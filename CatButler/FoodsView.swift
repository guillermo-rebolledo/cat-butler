import CatButlerCore
import SQLiteData
import SwiftUI

/// Lists the Household's Foods; reached from Settings after first run.
struct FoodsView: View {
  @FetchAll(Food.active) var active
  @FetchAll(Food.where(\.isRetired).order(by: \.name)) var retired
  @State private var isAdding = false

  var body: some View {
    List {
      Section { ForEach(active) { FoodRow(food: $0) } }
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
        FoodEditor { isAdding = false }
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
        Text("\(food.kcalPerUnit, format: .number.precision(.fractionLength(0...1))) kcal per \(food.servingUnit.rawValue)")
          .font(.subheadline).foregroundStyle(.secondary)
      }
    }
  }
}

/// Adds a new Food, or edits one when `food` is given. Used by first-run step 2 too.
struct FoodEditor: View {
  enum Basis: CaseIterable { case perUnit, per100g, perKilogram }

  var food: Food?
  var onSave: () -> Void = {}
  @Dependency(\.defaultDatabase) var database
  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var servingUnit: ServingUnit
  @State private var basis = Basis.perUnit
  @State private var kcal: Double?
  @State private var gramsPerUnit: Double?
  @State private var isTreat: Bool
  @State private var isFreeFed: Bool
  @State private var isRetired: Bool

  init(food: Food? = nil, onSave: @escaping () -> Void = {}) {
    self.food = food
    self.onSave = onSave
    _name = State(initialValue: food?.name ?? "")
    _servingUnit = State(initialValue: food?.servingUnit ?? .can)
    _kcal = State(initialValue: food?.kcalPerUnit)
    _isTreat = State(initialValue: food?.isTreat ?? false)
    _isFreeFed = State(initialValue: food?.isFreeFed ?? false)
    _isRetired = State(initialValue: food?.isRetired ?? false)
  }

  private var label: CalorieLabel? {
    guard let kcal, kcal > 0 else { return nil }
    switch basis {
    case .perUnit: return .perUnit(kcal)
    case .per100g: return .per100g(kcal)
    case .perKilogram: return .perKilogram(kcal)
    }
  }

  private var kcalPerUnit: Double? {
    label?.kcal(per: servingUnit, gramsPerUnit: (gramsPerUnit ?? 0) > 0 ? gramsPerUnit : nil)
  }

  var body: some View {
    Form {
      Section {
        TextField("Name", text: $name)
        Picker("Serving unit", selection: $servingUnit) {
          ForEach(ServingUnit.allCases, id: \.self) { Text($0.rawValue) }
        }
      }
      Section {
        Picker("Label states calories", selection: $basis) {
          ForEach(Basis.allCases, id: \.self) { Text($0.title(for: servingUnit)) }
        }
        LabeledContent("Calories") {
          HStack {
            TextField("kcal", value: $kcal, format: .number)
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
            Text("kcal")
          }
        }
        if label?.needsGramsPerUnit(for: servingUnit) == true {
          LabeledContent("Weight of one \(servingUnit.rawValue)") {
            HStack {
              TextField("grams", value: $gramsPerUnit, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
              Text("g")
            }
          }
        }
      } footer: {
        if let kcalPerUnit, basis != .perUnit {
          Text("\(kcalPerUnit, format: .number.precision(.fractionLength(0...1))) kcal per \(servingUnit.rawValue)")
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
    .navigationTitle(food == nil ? "Add Food" : "Edit Food")
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Save", action: save).disabled(name.isEmpty || kcalPerUnit == nil)
      }
    }
  }

  private func save() {
    guard let kcalPerUnit else { return }
    withErrorReporting {
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
    }
    if food != nil { dismiss() }
    onSave()
  }
}

extension FoodEditor.Basis {
  func title(for unit: ServingUnit) -> String {
    switch self {
    case .perUnit: "Per \(unit.rawValue)"
    case .per100g: "Per 100 g"
    case .perKilogram: "Per kg"
    }
  }
}
