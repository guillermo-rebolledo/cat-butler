import CatButlerCore
import SQLiteData
import SwiftUI

@main
struct CatButlerApp: App {
  init() {
    prepareDependencies {
      // UI tests get a fresh temporary database on every launch.
      if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
        $0.context = .preview
        // Noon today, so Meal statuses don't depend on when the tests run.
        $0.date = .constant(Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!)
      }
      $0.defaultDatabase = try! appDatabase()
    }
    ReminderNotifications.shared.start()
  }

  var body: some Scene {
    WindowGroup { RootView() }
  }
}

struct RootView: View {
  @FetchAll(Cat.order(by: \.name)) var cats
  @FetchAll var foods: [Food]
  @FetchAll var meals: [Meal]
  @Fetch var reminders: [Reminder] = []
  @AppStorage(CareReminder.Timing.daysBeforeKey) private var careDaysBefore = CareReminder.Timing.default.daysBefore
  @AppStorage(CareReminder.Timing.minuteOfDayKey) private var careMinuteOfDay = CareReminder.Timing.default.minuteOfDay
  @Environment(\.scenePhase) private var scenePhase
  @Dependency(\.date.now) var now

  var body: some View {
    content
      // On every return to the app, so the plan moves on with the clock, and on every change to the database.
      .task(id: scenePhase) {
        guard scenePhase == .active else { return }
        ReminderNotifications.shared.clearDelivered()
        await loadReminders()
        // Here too, not only on change: a plan that loads empty must still clear what's pending.
        ReminderNotifications.shared.schedule(reminders)
        if !meals.isEmpty { await ReminderNotifications.shared.requestPermission() }
      }
      // A changed timing in Settings → Care Reminders.
      .onChange(of: careTiming) { Task { await loadReminders() } }
      .onChange(of: reminders) { ReminderNotifications.shared.schedule(reminders) }
  }

  private var careTiming: CareReminder.Timing {
    CareReminder.Timing(daysBefore: careDaysBefore, minuteOfDay: careMinuteOfDay)
  }

  private func loadReminders() async {
    await withErrorReporting { try await $reminders.load(RemindersRequest(careTiming: careTiming, refreshedAt: now)) }
  }

  @ViewBuilder private var content: some View {
    if cats.isEmpty {
      FirstRunView()
    } else if foods.isEmpty {
      // First-run step 2: the Food.
      NavigationStack { FoodEditor() }
    } else if meals.isEmpty, let cat = cats.first {
      // First-run step 3: the Meals.
      NavigationStack { MealScheduleEditor(cat: cat, isFirstRun: true) }
    } else {
      TabView {
        Tab("Today", systemImage: "sun.max") { TodayView() }
        Tab("Cats", systemImage: "cat") { Text("Cats") }
        Tab("Care", systemImage: "cross.case") { CareView() }
        Tab("Settings", systemImage: "gear") {
          NavigationStack {
            List {
              // ponytail: the first Cat's Meals only, like Today; per-Cat settings come with multi-Cat support.
              if let cat = cats.first { NavigationLink("Meals") { MealScheduleEditor(cat: cat) } }
              NavigationLink("Foods") { FoodsView() }
              NavigationLink("Care Reminders") { CareReminderSettings() }
            }
            .navigationTitle("Settings")
          }
        }
      }
    }
  }
}

private struct RemindersRequest: FetchKeyRequest {
  let careTiming: CareReminder.Timing
  /// Only here so each return to the app is a new request.
  let refreshedAt: Date

  func fetch(_ db: Database) throws -> [Reminder] {
    try db.reminders(careTiming: careTiming)
  }
}
