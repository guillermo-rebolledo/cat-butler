import CatButlerCore
import SQLiteData
import SwiftUI

/// Lists the Household's Foods; reached from Settings after first run.
struct FoodsView: View {
  @FetchAll(Food.active) var active
  @FetchAll(Food.retired) var retired
  @State private var isAdding = false

  var body: some View {
    List {
      Section {
        ForEach(active) { FoodRow(food: $0) }
        if active.isEmpty { Text("No Foods in use. Add one, or bring back a retired one.").foregroundStyle(.secondary) }
      }
      if !retired.isEmpty {
        Section("Retired") { ForEach(retired) { FoodRow(food: $0) } }
      }
    }
    .navigationTitle("Foods")
    .toolbar {
      Button("Add Food", systemImage: "plus") { isAdding = true }
    }
    .sheet(isPresented: $isAdding) {
      NavigationStack {
        FoodEditor()
          .toolbar { Button("Cancel") { isAdding = false } }
      }
    }
  }
}

private struct FoodRow: View {
  let food: Food

  var body: some View {
    NavigationLink {
      FoodEditor(food: food)
    } label: {
      VStack(alignment: .leading) {
        Text(food.name)
        Text(food.servingUnit.kcalText(food.kcalPerUnit))
          .font(.subheadline).foregroundStyle(.secondary)
      }
    }
  }
}

/// Adds a new Food, or edits one when `food` is given. Used by first-run step 2 too.
struct FoodEditor: View {
  var food: Food?
  @Dependency(\.defaultDatabase) var database
  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var servingUnit: ServingUnit
  @State private var basis = CalorieLabel.Basis.unit
  @State private var kcal: Double?
  @State private var gramsPerUnit: Double?
  @State private var isTreat: Bool
  @State private var isFreeFed: Bool
  @State private var isRetired: Bool

  init(food: Food? = nil) {
    self.food = food
    _name = State(initialValue: food?.name ?? "")
    _servingUnit = State(initialValue: food?.servingUnit ?? .can)
    _kcal = State(initialValue: food?.kcalPerUnit)
    _isTreat = State(initialValue: food?.isTreat ?? false)
    _isFreeFed = State(initialValue: food?.isFreeFed ?? false)
    _isRetired = State(initialValue: food?.isRetired ?? false)
  }

  private var label: CalorieLabel { CalorieLabel(kcal: kcal ?? 0, per: basis) }
  private var kcalPerUnit: Double? { label.kcal(per: servingUnit, gramsPerUnit: gramsPerUnit) }

  var body: some View {
    Form {
      Section {
        TextField("Name", text: $name)
        Picker("Serving unit", selection: $servingUnit) {
          ForEach(ServingUnit.allCases, id: \.self) { Text($0.title) }
        }
      }
      Section {
        Picker("Label states calories", selection: $basis) {
          ForEach(CalorieLabel.Basis.allCases, id: \.self) { Text($0.title(for: servingUnit)) }
        }
        NumberField("Calories", value: $kcal, unit: "kcal")
        if label.needsGramsPerUnit(for: servingUnit) {
          NumberField("Weight of one \(servingUnit.title)", value: $gramsPerUnit, unit: "g")
        }
      } footer: {
        if let kcalPerUnit, basis != .unit {
          Text(servingUnit.kcalText(kcalPerUnit))
        }
      }
      Section {
        Toggle("Treat", isOn: $isTreat)
        Toggle("Free-fed", isOn: $isFreeFed)
        if food != nil { Toggle("Retired", isOn: $isRetired) }
      } footer: {
        if food != nil { Text("Retired Foods stay in past records but leave the pickers.") }
      }
    }
    // An existing Food's kcal is per its old unit; make the owner re-enter it rather than silently reinterpret it.
    .onChange(of: servingUnit) { if food != nil { kcal = nil } }
    .onChange(of: basis) { if food != nil { kcal = nil } }
    .navigationTitle(food == nil ? "Add Food" : "Edit Food")
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Save", action: save).disabled(trimmedName.isEmpty || kcalPerUnit == nil)
      }
    }
  }

  private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

  private func save() {
    guard let kcalPerUnit else { return }
    let name = trimmedName
    let saved = withErrorReporting {
      try database.write { db in
        if var food {
          food.name = name
          food.servingUnit = servingUnit
          food.kcalPerUnit = kcalPerUnit
          food.isTreat = isTreat
          food.isFreeFed = isFreeFed
          food.isRetired = isRetired
          try Food.update(food).execute(db)
        } else {
          try db.addFood(name: name, servingUnit: servingUnit, kcalPerUnit: kcalPerUnit, isTreat: isTreat, isFreeFed: isFreeFed)
        }
      }
      return true
    }
    // Closes the add sheet or the edit screen; on first run RootView moves on by itself.
    if saved == true { dismiss() }
  }
}

extension ServingUnit {
  var title: String {
    switch self {
    case .can: String(localized: "can")
    case .pouch: String(localized: "pouch")
    case .gram: String(localized: "gram")
    case .cup: String(localized: "cup")
    }
  }

  /// "76.5 kcal per can"
  func kcalText(_ kcal: Double) -> String {
    String(localized: "\(kcal.formatted(.number.precision(.fractionLength(0...1)))) kcal per \(title)")
  }
}

extension CalorieLabel.Basis {
  func title(for unit: ServingUnit) -> String {
    switch self {
    case .unit: String(localized: "Per \(unit.title)")
    case .hundredGrams: String(localized: "Per 100 g")
    case .kilogram: String(localized: "Per kg")
    }
  }
}
