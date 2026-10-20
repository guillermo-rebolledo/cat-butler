import CatButlerCore
import SQLiteData
import SwiftUI

/// A Cat's daily Meals. First-run step 3, and Settings → Meals.
struct MealScheduleEditor: View {
  let cat: Cat
  var isFirstRun = false
  @Dependency(\.defaultDatabase) var database
  @Dependency(\.uuid) var uuid
  @Dependency(\.date.now) var now
  @Environment(\.dismiss) private var dismiss
  // Free-fed Foods never fulfil a Meal, so a Meal can't default to one.
  @FetchAll(Food.active.where { !$0.isFreeFed }) var foods
  @FetchAll var allFoods: [Food]
  @State private var meals: [Meal] = []

  var body: some View {
    Form {
      ForEach($meals) { $meal in
        Section {
          DatePicker("Time", selection: $meal.timeToday, displayedComponents: .hourAndMinute)
          FoodPicker(selection: $meal.foodID, allowsFreeFed: false)
          NumberField("Amount", value: $meal.enteredAmount, unit: allFoods.unitTitle(of: meal.foodID))
          Button("Remove Meal", role: .destructive) { meals.removeAll { $0.id == meal.id } }
        }
      }
      Section {
        Button("Add Meal", systemImage: "plus", action: addMeal).disabled(foods.isEmpty)
      } footer: {
        if foods.isEmpty {
          Text("Meals need a Food that isn't free-fed. Add one in Settings → Foods.")
        } else {
          Text("Meals are the same every day. A Feeding within 2 hours of a Meal counts for it.")
        }
      }
      if isFirstRun {
        Section {
          Text("Cat Butler reminds you at each Meal, and once more 30 minutes later if it isn't logged. Tap Fed ✓ on the reminder to log it without opening the app.")
        } header: {
          Text("Reminders")
        } footer: {
          Text("After you save, iOS asks to allow notifications.")
        }
      }
    }
    .navigationTitle("Meals")
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Save", action: save).disabled(meals.isEmpty || meals.contains { $0.amount <= 0 })
      }
    }
    .task {
      withErrorReporting {
        meals = try database.read { db in
          let saved = try Meal.where { $0.catID.eq(cat.id) }.order(by: \.minuteOfDay).fetchAll(db)
          guard saved.isEmpty else { return saved }
          // First run: suggest times; the owner enters the amounts.
          let food =
            try Food.active.where { !$0.isTreat && !$0.isFreeFed }.fetchOne(db)
            ?? Food.active.where { !$0.isFreeFed }.fetchOne(db)
          guard let food else { return [] }
          return Meal.suggestedMinutesOfDay(for: cat.lifeStage(on: now)).map {
            Meal(id: uuid(), catID: cat.id, minuteOfDay: $0, foodID: food.id, amount: 0)
          }
        }
      }
    }
  }

  private func addMeal() {
    guard let foodID = meals.last?.foodID ?? foods.first?.id else { return }
    meals.append(Meal(id: uuid(), catID: cat.id, minuteOfDay: 12 * 60, foodID: foodID, amount: meals.last?.amount ?? 0))
  }

  private func save() {
    // First run: the explanation stays on screen behind iOS's permission alert.
    guard !isFirstRun else {
      Task {
        await ReminderNotifications.shared.requestPermission()
        write()
      }
      return
    }
    write()
  }

  private func write() {
    let saved = withErrorReporting {
      try database.write { try $0.saveMeals(meals, for: cat.id) }
      return true
    }
    // Leaves Settings → Meals; on first run RootView moves on by itself.
    if saved == true { dismiss() }
  }
}

/// Picks from the Household's active Foods, keeping a retired one if it's already chosen.
struct FoodPicker: View {
  @Binding var selection: Food.ID
  var allowsFreeFed = true
  @FetchAll(Food.order { $0.name.collate(.nocase) }) var foods

  var body: some View {
    Picker("Food", selection: $selection) {
      ForEach(foods.filter { ($0.id == selection || !$0.isRetired && (allowsFreeFed || !$0.isFreeFed)) }) {
        Text($0.name).tag($0.id)
      }
    }
  }
}

extension Meal {
  /// This Meal's time today, for a DatePicker.
  var timeToday: Date {
    get {
      @Dependency(\.calendar) var calendar
      @Dependency(\.date.now) var now
      return time(on: now, calendar: calendar)
    }
    set {
      @Dependency(\.calendar) var calendar
      let parts = calendar.dateComponents([.hour, .minute], from: newValue)
      minuteOfDay = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
  }

  /// The amount, or nil while it hasn't been entered.
  var enteredAmount: Double? {
    get { amount > 0 ? amount : nil }
    set { amount = newValue ?? 0 }
  }
}

extension [Food] {
  /// "can", for an amount field.
  func unitTitle(of id: Food.ID) -> String {
    first { $0.id == id }?.servingUnit.title ?? ""
  }
}

extension Food {
  /// "0.5 can Tuna pâté"
  func amountText(_ amount: Double) -> String {
    "\(amount.formatted(.number.precision(.fractionLength(0...2)))) \(servingUnit.title) \(name)"
  }
}
