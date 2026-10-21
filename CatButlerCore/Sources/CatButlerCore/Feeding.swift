import Dependencies
import Foundation
import SQLiteData

/// A planned feeding on a Cat's schedule. The schedule is the same every day.
@Table
public nonisolated struct Meal: Hashable, Identifiable, Sendable {
  public let id: UUID
  public var catID: Cat.ID
  /// Wall-clock time in the device's time zone, in minutes after midnight (08:00 is 480).
  public var minuteOfDay: Int
  public var foodID: Food.ID
  /// In the Food's serving unit.
  public var amount: Double
  /// The Meal counts from here: a time whose window ended earlier isn't Missed. Set when the Meal is added or
  /// moved, unless it was Missed then.
  public internal(set) var startsAt: Date

  /// `startsAt` is set when the Meal is saved.
  public init(id: UUID, catID: Cat.ID, minuteOfDay: Int, foodID: Food.ID, amount: Double) {
    self.id = id
    self.catID = catID
    self.minuteOfDay = minuteOfDay
    self.foodID = foodID
    self.amount = amount
    startsAt = .distantPast
  }

  /// A Feeding fulfils a Meal up to this long before or after it.
  public static let window: TimeInterval = 2 * 60 * 60

  /// Meal times offered on first run: 3–4 small Meals for a Kitten, two for an older Cat.
  public static func suggestedMinutesOfDay(for lifeStage: LifeStage) -> [Int] {
    switch lifeStage {
    case .kitten: [7 * 60, 12 * 60, 17 * 60, 21 * 60]
    case .adult, .senior: [8 * 60, 18 * 60]
    }
  }

  /// This Meal on the local day containing `day`.
  public func time(on day: Date, calendar: Calendar) -> Date {
    calendar.date(atMinuteOfDay: minuteOfDay, on: day)
  }

  /// This Meal on whichever day puts it closest to `date`.
  func time(nearest date: Date, calendar: Calendar) -> Date {
    [-1, 0, 1].compactMap { calendar.date(byAdding: .day, value: $0, to: date) }
      .map { time(on: $0, calendar: calendar) }
      .min { Swift.abs($0.timeIntervalSince(date)) < Swift.abs($1.timeIntervalSince(date)) }!
  }
}

extension Calendar {
  /// `minuteOfDay` minutes after midnight on the local day containing `day`. On a daylight saving day a time that
  /// doesn't exist moves forward.
  public func date(atMinuteOfDay minuteOfDay: Int, on day: Date) -> Date {
    date(
      bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: day,
      matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward
    )!
  }

  /// Minutes after midnight of `date`'s local time, e.g. one picked in a DatePicker.
  public func minuteOfDay(of date: Date) -> Int {
    let parts = dateComponents([.hour, .minute], from: date)
    return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
  }
}

/// A record that food was given to a Cat.
@Table
public nonisolated struct Feeding: Hashable, Identifiable, Sendable {
  public let id: UUID
  public var catID: Cat.ID
  public var foodID: Food.ID
  /// In the Food's serving unit.
  public var amount: Double
  public var date: Date
  /// The Meal this Feeding fulfilled, or nil when it was off-schedule. Worked out from the times, never set by hand.
  public internal(set) var mealID: Meal.ID?
  /// Calories given, fixed when logged so that editing the Food later doesn't rewrite past Intake.
  public internal(set) var kcal: Double
  /// How much of it the Cat ate, from 0 to 1, set afterwards when food is left in the bowl. Nil means all of it.
  public var eatenFraction: Double?

  /// Calories eaten, which is what counts toward Intake.
  var eatenKcal: Double { kcal * (eatenFraction ?? 1) }

  /// Whether this Feeding fulfilled `meal` at `time`, that Meal on one day.
  func fulfils(_ meal: Meal, at time: Date) -> Bool {
    mealID == meal.id && Swift.abs(date.timeIntervalSince(time)) <= Meal.window
  }
}

public struct FoodUsedByMeal: Error {}
public struct InvalidEatenFraction: Error {}

/// Each Meal of one local day with its status, plus the day's other Feedings.
public struct FeedingDay: Equatable, Sendable {
  public enum State: Equatable, Sendable {
    case upcoming
    case missed
    /// Its window passed before the Meal was added or moved, so it counts from tomorrow.
    case startsTomorrow
    case done(Feeding)
  }

  public struct MealStatus: Equatable, Identifiable, Sendable {
    public var meal: Meal
    public var time: Date
    public var state: State
    public var id: Meal.ID { meal.id }
  }

  public var meals: [MealStatus] = []
  /// The day's Feedings that fulfilled none of the day's Meals: off-schedule ones, and any that
  /// fulfilled last night's Meal after midnight or were matched in another time zone.
  public var otherFeedings: [Feeding] = []
  public var intake = Intake()

  public init() {}

  /// The Meal a Feeding given at `now` fulfils: the nearest one still to come whose window is open.
  public func currentMeal(at now: Date) -> Meal? {
    meals.filter { $0.state == .upcoming && now >= $0.time.addingTimeInterval(-Meal.window) }
      .min { Swift.abs($0.time.timeIntervalSince(now)) < Swift.abs($1.time.timeIntervalSince(now)) }?.meal
  }
}

extension Database {
  /// Replaces a Cat's schedule with `meals`. New and moved Meals apply from now on; earlier days keep their
  /// Feedings' Meals. Feedings of a removed Meal become off-schedule, on every day.
  public func saveMeals(_ meals: [Meal], for catID: Cat.ID) throws {
    @Dependency(\.calendar) var calendar
    @Dependency(\.date.now) var now
    let ids = meals.map(\.id)
    let before = try feedingDay(for: catID).meals
    let removed = before.map(\.id).filter { !ids.contains($0) }
    try Feeding.where { $0.mealID.in(removed.map(Optional.some)) }.update { $0.mealID = #bind(nil) }.execute(self)
    try Meal.where { $0.id.in(removed) }.delete().execute(self)
    for var meal in meals {
      // New and moved Meals start now, but a Missed one keeps its start: editing or moving it mustn't hide the miss.
      // ponytail: each save only sees the state at that moment, so a Meal moved away and back, or moved after it was
      // fed and then unfed, shows From tomorrow rather than Missed for that day; record each day's misses if it matters.
      if let old = before.first(where: { $0.id == meal.id }), old.meal.minuteOfDay == meal.minuteOfDay || old.state == .missed {
        meal.startsAt = old.meal.startsAt
      } else {
        meal.startsAt = now
      }
      try Meal.upsert { meal }.execute(self)
    }
    try relinkFeedings(of: catID, from: calendar.startOfDay(for: now))
  }

  @discardableResult
  public func logFeeding(catID: Cat.ID, foodID: Food.ID, amount: Double, at date: Date) throws -> Feeding {
    @Dependency(\.uuid) var uuid
    let feeding = Feeding(
      id: uuid(), catID: catID, foodID: foodID, amount: amount, date: date, mealID: nil,
      kcal: amount * (try kcalPerUnit(of: foodID)), eatenFraction: nil
    )
    try Feeding.insert { feeding }.execute(self)
    try relinkFeedings(of: catID, from: date)
    return try Feeding.find(feeding.id).fetchOne(self) ?? feeding
  }

  /// Each Cat's current Meal, for Feed All. Cats with none get no entry.
  public func currentMeals() throws -> [Meal] {
    @Dependency(\.date.now) var now
    return try Cat.order(by: \.name).select(\.id).fetchAll(self).compactMap { try feedingDay(for: $0).currentMeal(at: now) }
  }

  /// Feed All: logs one Feeding now for each Cat with a current Meal, with that Meal's Food and amount.
  @discardableResult
  public func feedAll() throws -> [Feeding] {
    @Dependency(\.date.now) var now
    return try currentMeals().map { try logFeeding(catID: $0.catID, foodID: $0.foodID, amount: $0.amount, at: now) }
  }

  /// Saves a changed Food, amount, time or eaten fraction. Calories are recalculated only when the Food or amount changed.
  public func updateFeeding(_ feeding: Feeding) throws {
    if let fraction = feeding.eatenFraction, !(0...1).contains(fraction) { throw InvalidEatenFraction() }
    guard let old = try Feeding.find(feeding.id).fetchOne(self) else { throw NotFound() }
    var feeding = feeding
    feeding.mealID = old.mealID
    feeding.kcal =
      feeding.foodID == old.foodID && feeding.amount == old.amount
      ? old.kcal : feeding.amount * (try kcalPerUnit(of: feeding.foodID))
    try Feeding.update(feeding).execute(self)
    try relinkFeedings(of: feeding.catID, from: min(old.date, feeding.date))
  }

  /// Saves an edited Food. Making it free-fed, or no longer free-fed, rematches today's Feedings.
  /// A Food some Meal defaults to can't become free-fed, since its Feedings would never fulfil that Meal.
  public func updateFood(_ food: Food) throws {
    @Dependency(\.calendar) var calendar
    @Dependency(\.date.now) var now
    let wasFreeFed = try Food.find(food.id).select(\.isFreeFed).fetchOne(self)
    if food.isFreeFed, wasFreeFed == false, try Meal.where({ $0.foodID.eq(food.id) }).fetchCount(self) > 0 {
      throw FoodUsedByMeal()
    }
    try Food.update(food).execute(self)
    guard wasFreeFed != food.isFreeFed else { return }
    for catID in try Cat.where { $0.householdID.eq(food.householdID) }.select(\.id).fetchAll(self) {
      try relinkFeedings(of: catID, from: calendar.startOfDay(for: now))
    }
  }

  public func deleteFeeding(_ id: Feeding.ID) throws {
    guard let old = try Feeding.find(id).fetchOne(self) else { return }
    try Feeding.find(id).delete().execute(self)
    try relinkFeedings(of: old.catID, from: old.date)
  }

  /// Today, the device's local calendar day.
  public func feedingDay(for catID: Cat.ID) throws -> FeedingDay {
    @Dependency(\.calendar) var calendar
    @Dependency(\.date.now) var now
    let day = calendar.dateInterval(of: .day, for: now)!
    let (from, to) = (day.start.addingTimeInterval(-Meal.window), day.end.addingTimeInterval(Meal.window))
    let meals = try Meal.where { $0.catID.eq(catID) }.order(by: \.minuteOfDay).fetchAll(self)
    let feedings = try Feeding.where { $0.catID.eq(catID) && $0.date >= from && $0.date < to }
      .order(by: \.date).fetchAll(self)

    var result = FeedingDay()
    result.meals = meals.map { meal in
      let time = meal.time(on: now, calendar: calendar)
      let windowEnd = time.addingTimeInterval(Meal.window)
      let state: FeedingDay.State =
        if let feeding = feedings.first(where: { $0.fulfils(meal, at: time) }) {
          .done(feeding)
        } else if now > windowEnd {
          windowEnd < meal.startsAt ? .startsTomorrow : .missed
        } else {
          .upcoming
        }
      return FeedingDay.MealStatus(meal: meal, time: time, state: state)
    }
    let done = Set(result.meals.compactMap { if case .done(let feeding) = $0.state { feeding.id } else { nil } })
    let todays = feedings.filter { $0.date >= day.start && $0.date < day.end }
    result.otherFeedings = todays.filter { !done.contains($0.id) }
    result.intake = try intake(of: todays)
    return result
  }

  /// Treat and free-fed come from the Food as it is now, so re-flagging a Food relabels its past Feedings; only the
  /// calories are fixed when logged. Retired Foods keep their flags, so their Feedings still count the same.
  private func intake(of feedings: [Feeding]) throws -> Intake {
    let foods = try Food.where { $0.id.in(feedings.map(\.foodID)) }.fetchAll(self)
    let treats = Set(foods.filter(\.isTreat).map(\.id))
    let freeFed = Set(foods.filter(\.isFreeFed).map(\.id))
    return Intake(
      kcal: feedings.map(\.eatenKcal).reduce(0, +),
      treatKcal: feedings.filter { treats.contains($0.foodID) }.map(\.eatenKcal).reduce(0, +),
      isApproximate: feedings.contains { freeFed.contains($0.foodID) }
    )
  }

  private func kcalPerUnit(of foodID: Food.ID) throws -> Double {
    guard let food = try Food.find(foodID).fetchOne(self) else { throw NotFound() }
    return food.kcalPerUnit
  }

  /// Rematches the Cat's Feedings from `start` on, in time order: each fulfils the nearest Meal within the window
  /// that no earlier Feeding fulfilled. Feedings of free-fed Foods never fulfil a Meal.
  // ponytail: rematches every Feeding after `start`, so backdating far back rewrites that whole stretch; fine at a few Feedings a day.
  private func relinkFeedings(of catID: Cat.ID, from start: Date) throws {
    @Dependency(\.calendar) var calendar
    struct Occurrence: Hashable {
      var mealID: Meal.ID
      var time: Date
    }
    let meals = try Meal.where { $0.catID.eq(catID) }.fetchAll(self)
    let freeFed = Set(try Food.where(\.isFreeFed).select(\.id).fetchAll(self))

    // Feedings just before `start` keep their Meals, which are then taken.
    let earlier = start.addingTimeInterval(-2 * Meal.window)
    var fulfilled = Set<Occurrence>()
    for feeding in try Feeding.where({ $0.catID.eq(catID) && $0.date >= earlier && $0.date < start }).fetchAll(self) {
      guard let meal = meals.first(where: { $0.id == feeding.mealID }) else { continue }
      let time = meal.time(nearest: feeding.date, calendar: calendar)
      // A match made before the Meal moved may no longer be in its window; it doesn't take the new time.
      guard abs(time.timeIntervalSince(feeding.date)) <= Meal.window else { continue }
      fulfilled.insert(Occurrence(mealID: meal.id, time: time))
    }

    let feedings = try Feeding.where { $0.catID.eq(catID) && $0.date >= start }.order { ($0.date, $0.id) }.fetchAll(self)
    for var feeding in feedings {
      let distance = { (occurrence: Occurrence) in abs(occurrence.time.timeIntervalSince(feeding.date)) }
      let match =
        freeFed.contains(feeding.foodID)
        ? nil
        : meals.map { Occurrence(mealID: $0.id, time: $0.time(nearest: feeding.date, calendar: calendar)) }
          .filter { distance($0) <= Meal.window && !fulfilled.contains($0) }
          // Equally near: the earlier Meal.
          .min { (distance($0), $0.time) < (distance($1), $1.time) }
      if let match { fulfilled.insert(match) }
      guard feeding.mealID != match?.mealID else { continue }
      feeding.mealID = match?.mealID
      try Feeding.update(feeding).execute(self)
    }
  }
}
