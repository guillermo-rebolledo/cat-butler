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
  }

  var body: some Scene {
    WindowGroup { RootView() }
  }
}

struct RootView: View {
  @FetchAll(Cat.order(by: \.name)) var cats
  @FetchAll var foods: [Food]
  @FetchAll var meals: [Meal]

  var body: some View {
    if cats.isEmpty {
      FirstRunView()
    } else if foods.isEmpty {
      // First-run step 2: the Food.
      NavigationStack { FoodEditor() }
    } else if meals.isEmpty, let cat = cats.first {
      // First-run step 3: the Meals.
      NavigationStack { MealScheduleEditor(cat: cat) }
    } else {
      TabView {
        Tab("Today", systemImage: "sun.max") { TodayView() }
        Tab("Cats", systemImage: "cat") { Text("Cats") }
        Tab("Care", systemImage: "cross.case") { Text("Care") }
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
