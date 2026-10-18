import CatButlerCore
import SQLiteData
import SwiftUI

@main
struct CatButlerApp: App {
  init() {
    prepareDependencies {
      // UI tests get a fresh temporary database on every launch.
      if ProcessInfo.processInfo.arguments.contains("-ui-testing") { $0.context = .preview }
      $0.defaultDatabase = try! appDatabase()
    }
  }

  var body: some Scene {
    WindowGroup { RootView() }
  }
}

struct RootView: View {
  @FetchAll var cats: [Cat]
  @FetchAll var foods: [Food]

  var body: some View {
    if cats.isEmpty {
      FirstRunView()
    } else if foods.isEmpty {
      // First-run step 2: the Food.
      NavigationStack { FoodEditor() }
    } else {
      TabView {
        Tab("Today", systemImage: "sun.max") { TodayView() }
        Tab("Cats", systemImage: "cat") { Text("Cats") }
        Tab("Care", systemImage: "cross.case") { Text("Care") }
        Tab("Settings", systemImage: "gear") {
          NavigationStack {
            List { NavigationLink("Foods") { FoodsView() } }.navigationTitle("Settings")
          }
        }
      }
    }
  }
}
