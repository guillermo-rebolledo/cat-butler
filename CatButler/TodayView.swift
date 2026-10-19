import CatButlerCore
import SQLiteData
import SwiftUI

struct TodayView: View {
  // ponytail: shows the first Cat only; Cat switching comes with multi-Cat support.
  @FetchOne(Cat.order(by: \.name)) var cat: Cat?

  var body: some View {
    NavigationStack {
      Group {
        if let cat { FeedingsToday(cat: cat) } else { List {} }
      }
      .navigationTitle("Today")
    }
  }
}

/// The Cat, today's Meals as done, upcoming or missed, then the day's other Feedings.
struct FeedingsToday: View {
  let cat: Cat
  @Dependency(\.defaultDatabase) var database
  @Dependency(\.date.now) var now
  @Fetch var day = FeedingDay()
  @FetchAll var foods: [Food]
  @State private var draft: FeedingDraft?

  var body: some View {
    List {
      CatSummary(cat: cat)
      meals
      otherFeedings
    }
    .sheet(item: $draft) { draft in
      NavigationStack { FeedingEditor(draft: draft) }
    }
    .task(id: cat.id) {
      // Reload every minute so Meals turn Missed on time and Today rolls over at midnight.
      while !Task.isCancelled {
        await withErrorReporting { try await $day.load(FeedingDayRequest(catID: cat.id, refreshedAt: now)) }
        try? await Task.sleep(for: .seconds(60))
      }
    }
  }

  private var meals: some View {
    Section("Meals") {
      ForEach(day.meals) { status in
        HStack {
          VStack(alignment: .leading) {
            Text(status.time, style: .time).font(.headline)
            Text(text(status.meal.amount, of: status.meal.foodID)).foregroundStyle(.secondary)
          }
          Spacer()
          switch status.state {
          // Only once the window opens: logged any earlier, it couldn't fulfil this Meal.
          case .upcoming where now >= status.time.addingTimeInterval(-Meal.window):
            Button("Fed") { logNow(status.meal) }.buttonStyle(.borderedProminent)
          case .upcoming:
            EmptyView()
          case .missed:
            Text("Missed").foregroundStyle(.red)
            logButton(status)
          case .startsTomorrow:
            Text("From tomorrow").foregroundStyle(.secondary)
            logButton(status)
          case .done(let feeding):
            Button { draft = FeedingDraft(feeding) } label: {
              Label { Text(feeding.date, style: .time) } icon: { Image(systemName: "checkmark.circle.fill") }
            }
            .buttonStyle(.bordered).tint(.green)
            .accessibilityLabel(Text("Fed at \(feeding.date.formatted(date: .omitted, time: .shortened))"))
          }
        }
      }
    }
  }

  /// Backdates a Feeding to the Meal's time, for one given but not logged.
  private func logButton(_ status: FeedingDay.MealStatus) -> some View {
    Button("Log") { draft = FeedingDraft(catID: cat.id, meal: status.meal, date: status.time) }
      .buttonStyle(.bordered)
  }

  private var otherFeedings: some View {
    Section("Other Feedings") {
      ForEach(day.otherFeedings) { feeding in
        Button { draft = FeedingDraft(feeding) } label: {
          LabeledContent(text(feeding.amount, of: feeding.foodID)) { Text(feeding.date, style: .time) }
        }
        .swipeActions { Button("Delete", role: .destructive) { delete(feeding) } }
      }
      Button("Log Feeding", systemImage: "plus") {
        let meal = day.meals.first { $0.state == .upcoming }?.meal ?? day.meals.first?.meal
        draft = FeedingDraft(catID: cat.id, meal: meal, date: now)
      }
    }
  }

  private func text(_ amount: Double, of foodID: Food.ID) -> String {
    foods.first { $0.id == foodID }?.amountText(amount) ?? ""
  }

  private func logNow(_ meal: Meal) {
    withErrorReporting {
      try database.write { try $0.logFeeding(catID: cat.id, foodID: meal.foodID, amount: meal.amount, at: now) }
    }
  }

  private func delete(_ feeding: Feeding) {
    withErrorReporting { try database.write { try $0.deleteFeeding(feeding.id) } }
  }
}

private struct FeedingDayRequest: FetchKeyRequest {
  let catID: Cat.ID
  /// Only here so each minute's reload is a new request.
  let refreshedAt: Date

  func fetch(_ db: Database) throws -> FeedingDay {
    try db.feedingDay(for: catID)
  }
}

/// A Feeding being logged or edited.
struct FeedingDraft: Identifiable {
  let id = UUID()
  var feeding: Feeding?
  var catID: Cat.ID
  var foodID: Food.ID?
  var amount: Double?
  var date: Date

  init(_ feeding: Feeding) {
    self.feeding = feeding
    catID = feeding.catID
    foodID = feeding.foodID
    amount = feeding.amount
    date = feeding.date
  }

  /// A new Feeding with the Meal's defaults.
  init(catID: Cat.ID, meal: Meal?, date: Date) {
    self.catID = catID
    foodID = meal?.foodID
    amount = meal?.amount
    self.date = date
  }
}

struct FeedingEditor: View {
  @State var draft: FeedingDraft
  @Dependency(\.defaultDatabase) var database
  @Dependency(\.date.now) var now
  @Environment(\.dismiss) private var dismiss
  @FetchAll(Food.active) var activeFoods
  @FetchAll var foods: [Food]

  var body: some View {
    Form {
      Section {
        if let foodID = Binding($draft.foodID) {
          FoodPicker(selection: foodID)
          NumberField("Amount", value: $draft.amount, unit: foods.unitTitle(of: foodID.wrappedValue))
        }
        DatePicker("Time", selection: $draft.date, in: ...now)
      }
      if draft.feeding != nil {
        Section { Button("Delete Feeding", role: .destructive, action: delete) }
      }
    }
    .navigationTitle(draft.feeding == nil ? "Log Feeding" : "Edit Feeding")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save", action: save).disabled(draft.foodID == nil || (draft.amount ?? 0) <= 0)
      }
    }
    // No Meal to copy: start from the first Food in use.
    .onChange(of: activeFoods, initial: true) { if draft.foodID == nil { draft.foodID = activeFoods.first?.id } }
  }

  private func save() {
    guard let foodID = draft.foodID, let amount = draft.amount else { return }
    let saved = withErrorReporting {
      try database.write { db in
        if var feeding = draft.feeding {
          feeding.foodID = foodID
          feeding.amount = amount
          feeding.date = draft.date
          try db.updateFeeding(feeding)
        } else {
          try db.logFeeding(catID: draft.catID, foodID: foodID, amount: amount, at: draft.date)
        }
      }
      return true
    }
    if saved == true { dismiss() }
  }

  private func delete() {
    guard let feeding = draft.feeding else { return }
    let deleted = withErrorReporting {
      try database.write { try $0.deleteFeeding(feeding.id) }
      return true
    }
    if deleted == true { dismiss() }
  }
}

struct CatSummary: View {
  let cat: Cat
  @FetchOne var latestWeighIn: WeighIn?
  @Dependency(\.date.now) var now

  init(cat: Cat) {
    self.cat = cat
    _latestWeighIn = FetchOne(wrappedValue: nil, WeighIn.latest(for: cat.id))
  }

  var body: some View {
    HStack(spacing: 16) {
      CatPhoto(data: cat.photo).frame(width: 64, height: 64)
      VStack(alignment: .leading) {
        Text(cat.name).font(.title2.bold())
        Text(cat.lifeStage(on: now).title).foregroundStyle(.secondary)
        if let latestWeighIn {
          Text(
            latestWeighIn.weight.converted(to: .catWeight())
              .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1))))
          )
          .foregroundStyle(.secondary)
        }
      }
    }
  }
}

extension LifeStage {
  var title: LocalizedStringKey {
    switch self {
    case .kitten: "Kitten"
    case .adult: "Adult"
    case .senior: "Senior"
    }
  }
}
