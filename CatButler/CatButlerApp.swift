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
    MealNotifications.shared.start()
  }

  var body: some Scene {
    WindowGroup { RootView() }
  }
}

struct RootView: View {
  @FetchAll(Cat.order(by: \.name)) var cats
  @FetchAll var foods: [Food]
  @FetchAll var meals: [Meal]
  @Fetch var mealReminders: [MealReminder] = []
  @Environment(\.scenePhase) private var scenePhase
  @Dependency(\.date.now) var now

  var body: some View {
    content
      // On every return to the app, so the plan moves on with the clock, and on every change to the database.
      .task(id: scenePhase) {
        guard scenePhase == .active else { return }
        MealNotifications.shared.clearDelivered()
        await withErrorReporting { try await $mealReminders.load(MealRemindersRequest(refreshedAt: now)) }
        // Here too, not only on change: a plan that loads empty must still clear what's pending.
        MealNotifications.shared.schedule(mealReminders)
        if !meals.isEmpty { await MealNotifications.shared.requestPermission() }
      }
      .onChange(of: mealReminders) { MealNotifications.shared.schedule(mealReminders) }
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
            }
            .navigationTitle("Settings")
          }
        }
      }
    }
  }
}

private struct MealRemindersRequest: FetchKeyRequest {
  /// Only here so each return to the app is a new request.
  let refreshedAt: Date

  func fetch(_ db: Database) throws -> [MealReminder] {
    try db.mealReminders()
  }
}
