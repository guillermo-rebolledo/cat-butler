import CatButlerCore
import Charts
import SQLiteData
import SwiftUI

/// A Cat's weight chart and its Weigh-ins, newest first, in the device's units.
struct WeightView: View {
  let cat: Cat
  @FetchAll var series: [WeighIn]
  @Dependency(\.defaultDatabase) var database
  @State private var editing: WeighIn?
  @State private var isAdding = false
  private let unit = UnitMass.catWeight()

  init(cat: Cat) {
    self.cat = cat
    _series = FetchAll(WeighIn.series(for: cat.id))
  }

  var body: some View {
    List {
      if !series.isEmpty {
        Section {
          Chart(series) { weighIn in
            let weight = weighIn.weight.converted(to: unit).value
            LineMark(x: .value("Date", weighIn.date), y: .value("Weight", weight))
            PointMark(x: .value("Date", weighIn.date), y: .value("Weight", weight))
          }
          .chartYScale(domain: .automatic(includesZero: false))
          .chartYAxis { AxisMarks(position: .leading) }
          // Dates centred on their marks, with room at both ends so the first and last aren't cut off.
          .chartXAxis { AxisMarks { AxisGridLine(); AxisValueLabel(anchor: .top) } }
          .chartXScale(range: .plotDimension(padding: 24))
          .chartYAxisLabel(unit.symbol)
          .frame(height: 220)
          .accessibilityLabel("Weight chart")
        }
      }
      Section("Weigh-ins") {
        ForEach(series.reversed()) { weighIn in
          Button { editing = weighIn } label: {
            LabeledContent(weighIn.date.formatted(date: .abbreviated, time: .omitted)) { Text(weighIn.weightText) }
          }
          .swipeActions { Button("Delete", role: .destructive) { delete(weighIn) } }
        }
        if series.isEmpty { Text("No Weigh-ins yet.").foregroundStyle(.secondary) }
      }
    }
    .navigationTitle("\(cat.name)'s Weight")
    .toolbar {
      Button("Add Weigh-in", systemImage: "plus") { isAdding = true }
    }
    .sheet(isPresented: $isAdding) {
      NavigationStack { WeighInEditor(catID: cat.id) }
    }
    .sheet(item: $editing) { weighIn in
      NavigationStack { WeighInEditor(catID: cat.id, weighIn: weighIn) }
    }
  }

  private func delete(_ weighIn: WeighIn) {
    withErrorReporting { try database.write { try $0.deleteWeighIn(weighIn.id) } }
  }
}

/// Records a Weigh-in, or corrects one when `weighIn` is given.
struct WeighInEditor: View {
  let catID: Cat.ID
  var weighIn: WeighIn?
  @Dependency(\.defaultDatabase) var database
  @Dependency(\.date.now) var now
  @Environment(\.dismiss) private var dismiss
  @State private var weight: Double?
  @State private var date: Date
  private let unit = UnitMass.catWeight()

  init(catID: Cat.ID, weighIn: WeighIn? = nil) {
    @Dependency(\.date.now) var now
    self.catID = catID
    self.weighIn = weighIn
    // To 0.01, as `weightText` shows it, rather than the long decimal a unit conversion leaves.
    _weight = State(initialValue: weighIn.map { ($0.weight.converted(to: .catWeight()).value * 100).rounded() / 100 })
    _date = State(initialValue: weighIn?.date ?? now)
  }

  var body: some View {
    Form {
      Section {
        NumberField("Weight", value: $weight, unit: unit.symbol)
        DatePicker("Date", selection: $date, in: ...now, displayedComponents: .date)
      }
      if weighIn != nil {
        Section { Button("Delete Weigh-in", role: .destructive, action: delete) }
      }
    }
    .navigationTitle(weighIn == nil ? "Add Weigh-in" : "Edit Weigh-in")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save", action: save).disabled(weight.map(WeighIn.isValid) != true)
      }
    }
  }

  private func save() {
    guard let weight else { return }
    let measurement = Measurement(value: weight, unit: unit)
    let saved = withErrorReporting {
      try database.write { db in
        if var weighIn {
          weighIn.weight = measurement
          weighIn.date = date
          try db.updateWeighIn(weighIn)
        } else {
          try db.recordWeighIn(measurement, for: catID, on: date)
        }
      }
      return true
    }
    if saved == true { dismiss() }
  }

  private func delete() {
    guard let weighIn else { return }
    let deleted = withErrorReporting {
      try database.write { try $0.deleteWeighIn(weighIn.id) }
      return true
    }
    if deleted == true { dismiss() }
  }
}

extension WeighIn {
  /// "9 lb" or "4.1 kg", in the device's units.
  var weightText: String {
    weight.converted(to: .catWeight())
      .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...2))))
  }
}
