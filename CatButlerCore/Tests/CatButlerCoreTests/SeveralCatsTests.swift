import CatButlerCore
import Dependencies
import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

/// Miso and Tofu, each on its own schedule. Now is 12:00.
@Suite(
  .dependency(\.date.now, instant("2026-10-19T12:00:00-04:00")),
  .dependency(\.uuid, .incrementing),
  .dependency(\.calendar, calendar(in: "America/New_York")),
  .dependencies { $0.defaultDatabase = try appDatabase() }
)
struct SeveralCatsTests {
  @Dependency(\.defaultDatabase) var database
  let miso: Cat
  let tofu: Cat
  let pate: Food
  let kibble: Food

  init() throws {
    @Dependency(\.defaultDatabase) var database
    (miso, tofu, pate, kibble) = try database.write { db in
      (
        try db.addCat(name: "Miso", photo: nil, birthdate: instant("2026-06-01T00:00:00-04:00"), isNeutered: false, weight: Measurement(value: 2, unit: .kilograms)),
        try db.addCat(name: "Tofu", photo: nil, birthdate: instant("2020-01-01T00:00:00-05:00"), isNeutered: true, weight: Measurement(value: 4.5, unit: .kilograms)),
        try db.addFood(name: "Tuna pâté", servingUnit: .can, kcalPerUnit: 80, isTreat: false, isFreeFed: false),
        try db.addFood(name: "Dry kibble", servingUnit: .gram, kcalPerUnit: 4, isTreat: false, isFreeFed: false)
      )
    }
  }

  /// Saves `cat`'s Meals at the given minutes of the day, long ago, so none of them starts tomorrow.
  @discardableResult
  func schedule(_ cat: Cat, _ meals: [(minuteOfDay: Int, food: Food, amount: Double)]) throws -> [Meal] {
    @Dependency(\.uuid) var uuid
    let meals = meals.map { Meal(id: uuid(), catID: cat.id, minuteOfDay: $0.minuteOfDay, foodID: $0.food.id, amount: $0.amount) }
    try withDependencies { $0.date.now = instant("2026-01-01T00:00:00-05:00") } operation: {
      try database.write { try $0.saveMeals(meals, for: cat.id) }
    }
    return meals
  }

  func today(_ cat: Cat) throws -> FeedingDay {
    try database.read { try $0.feedingDay(for: cat.id) }
  }

  @Test func feedAllLogsEachCatsOwnMealWithItsDefaults() throws {
    let misoLunch = try schedule(miso, [(7 * 60, pate, 0.25), (12 * 60, pate, 0.25), (17 * 60, pate, 0.25)])[1]
    let tofuBrunch = try schedule(tofu, [(11 * 60, kibble, 30), (18 * 60, kibble, 30)])[0]

    let feedings = try database.write { try $0.feedAll() }

    #expect(feedings.count == 2)
    let misos = try #require(feedings.first { $0.catID == miso.id })
    #expect((misos.mealID, misos.foodID, misos.amount, misos.kcal) == (misoLunch.id, pate.id, 0.25, 20))
    let tofus = try #require(feedings.first { $0.catID == tofu.id })
    #expect((tofus.mealID, tofus.foodID, tofus.amount, tofus.kcal) == (tofuBrunch.id, kibble.id, 30, 120))
  }

  @Test func feedAllSkipsCatsWithNoMealDueNow() throws {
    try schedule(miso, [(12 * 60, pate, 0.25)])
    // Tofu's next Meal is more than 2 hours away.
    try schedule(tofu, [(18 * 60, kibble, 30)])

    let feedings = try database.write { try $0.feedAll() }

    #expect(feedings.map(\.catID) == [miso.id])
    #expect(try today(tofu).otherFeedings == [])
  }

  @Test func feedAllAgainLogsNothingMore() throws {
    try schedule(miso, [(12 * 60, pate, 0.25)])
    try schedule(tofu, [(11 * 60, kibble, 30)])
    try database.write { try $0.feedAll() }

    #expect(try database.write { try $0.feedAll() } == [])
    #expect(try today(miso).otherFeedings == [])
  }

  @Test func feedAllPicksTheNearestOpenMeal() throws {
    // 13:00 is an hour away, 10:30 an hour and a half: 13:00's amount is logged.
    let meals = try schedule(miso, [(10 * 60 + 30, pate, 0.25), (13 * 60, pate, 0.5)])
    let feedings = try database.write { try $0.feedAll() }
    #expect(feedings.map(\.mealID) == [meals[1].id])
    #expect(feedings.map(\.amount) == [0.5])
  }

  @Test func editingACatSavesItsDetails() throws {
    var edited = tofu
    edited.name = "Tofu Jr."
    edited.isNeutered = false
    try database.write { try $0.updateCat(edited) }
    #expect(try database.read { try Cat.find(tofu.id).fetchOne($0) } == edited)
  }

  @Test func editingACatKeepsATargetSetMeanwhile() throws {
    var edited = tofu
    edited.name = "Tofu Jr."
    try database.write { try $0.overrideCalorieTarget(200, for: tofu.id) }
    try database.write { try $0.updateCat(edited) }
    let saved = try database.read { try Cat.find(tofu.id).fetchOne($0) }
    #expect(saved?.name == "Tofu Jr.")
    #expect(saved?.calorieTargetOverride == 200)
  }

  /// A corrected birthdate isn't a birthday: a Kitten corrected to an Adult gets no turning-one notice, and an Adult
  /// corrected to a Kitten gets it when it turns one.
  @Test func correctingTheBirthdateResetsTheTurningOneNotice() throws {
    var miso = miso
    miso.birthdate = instant("2025-01-01T00:00:00-05:00")
    try database.write { try $0.updateCat(miso) }
    #expect(try database.read { try $0.turningOneNotice(for: miso.id) } == nil)

    var tofu = tofu
    tofu.birthdate = instant("2026-01-01T00:00:00-05:00")
    try database.write { try $0.updateCat(tofu) }
    let atOne = try withDependencies { $0.date.now = instant("2027-01-02T12:00:00-05:00") } operation: {
      try database.read { try $0.turningOneNotice(for: tofu.id) }
    }
    #expect(atOne != nil)
  }

  @Test func intakeAndMealStatusStaySeparatePerCat() throws {
    let misoLunch = try schedule(miso, [(12 * 60, pate, 0.25)])[0]
    try schedule(tofu, [(12 * 60, kibble, 30)])
    let feeding = try database.write {
      try $0.logFeeding(catID: miso.id, foodID: misoLunch.foodID, amount: misoLunch.amount, at: instant("2026-10-19T12:00:00-04:00"))
    }

    #expect(try today(miso).meals.map(\.state) == [.done(feeding)])
    #expect(try today(miso).intake.kcal == 20)
    #expect(try today(tofu).meals.map(\.state) == [.upcoming])
    #expect(try today(tofu).intake.kcal == 0)
  }
}
