import CatButlerCore
import SQLiteData
import SwiftUI

@main
struct CatButlerApp: App {
  init() {
    let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
    // Settings start fresh in UI tests too.
    if isUITesting { UserDefaults.standard.removeObject(forKey: CareReminder.Timing.key) }
    prepareDependencies {
      // UI tests get a fresh temporary database on every launch.
      if isUITesting {
        $0.context = .preview
        // Noon today, so Meal statuses don't depend on when the tests run.
        $0.date = .constant(Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!)
      }
      try! $0.bootstrapDatabase()
    }
    ReminderNotifications.shared.start()
  }

  var body: some Scene {
    WindowGroup { RootView() }
  }
}

struct RootView: View {
  /// Archived Cats too: with every Cat archived, first run doesn't start over and their history stays on the Cats tab.
  @FetchAll(Cat.order(by: \.name)) var cats
  @FetchAll(Cat.inCare) var catsInCare
  @FetchAll var foods: [Food]
  @FetchAll var meals: [Meal]
  @Fetch var reminders: [Reminder] = []
  @AppStorage(CareReminder.Timing.key) private var careTiming = CareReminder.Timing.default
  @Environment(\.scenePhase) private var scenePhase
  @Dependency(\.date.now) var now
  /// The Cat Today and Care show, shared so switching on one switches both.
  @State private var catID: Cat.ID?

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

  private func loadReminders() async {
    await withErrorReporting { try await $reminders.load(RemindersRequest(careTiming: careTiming, refreshedAt: now)) }
  }

  @ViewBuilder private var content: some View {
    if cats.isEmpty {
      NavigationStack { CatEditor(isFirstRun: true) }
    } else if foods.isEmpty {
      // First-run step 2: the Food.
      NavigationStack { FoodEditor() }
    } else if meals.isEmpty, let cat = catsInCare.first {
      // First-run step 3: the Meals.
      NavigationStack { MealScheduleEditor(cat: cat, isFirstRun: true) }
    } else {
      TabView {
        Tab("Today", systemImage: "sun.max") { TodayView(catID: $catID) }
        Tab("Cats", systemImage: "cat") { CatsView() }
        Tab("Care", systemImage: "cross.case") { CareView(catID: $catID) }
        Tab("Settings", systemImage: "gear") {
          NavigationStack {
            List {
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
