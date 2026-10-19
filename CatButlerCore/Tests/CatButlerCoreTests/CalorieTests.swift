import CatButlerCore
import Dependencies
import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

@Suite(
  .dependency(\.date.now, instant("2026-10-19T12:00:00-04:00")),
  .dependency(\.uuid, .incrementing),
  .dependency(\.calendar, calendar(in: "America/New_York")),
  .dependencies { $0.defaultDatabase = try appDatabase() }
)
struct CalorieTests {
  @Dependency(\.defaultDatabase) var database

  func addCat(born birthdate: String, neutered: Bool = true, kilograms: Double) throws -> Cat {
    try database.write { db in
      try db.addCat(
        name: "Miso", photo: nil, birthdate: instant(birthdate), isNeutered: neutered,
        weight: Measurement(value: kilograms, unit: .kilograms)
      )
    }
  }

  func target(of cat: Cat) throws -> CalorieTarget? {
    try database.read { try $0.calorieTarget(for: cat.id) }
  }

  @Test func aFourKilogramNeuteredAdultNeedsAbout238Kcal() throws {
    let cat = try addCat(born: "2020-05-01T00:00:00-04:00", kilograms: 4)
    #expect(try target(of: cat)?.kcal.rounded() == 238)
    #expect(try target(of: cat)?.isOverride == false)
  }

  @Test(arguments: [true, false])
  func aTwoKilogramKittenNeedsAbout294KcalNeuteredOrNot(neutered: Bool) throws {
    let cat = try addCat(born: "2026-03-19T00:00:00-04:00", neutered: neutered, kilograms: 2)
    #expect(try target(of: cat)?.kcal.rounded() == 294)
  }

  @Test func anIntactAdultNeedsMoreThanANeuteredOne() throws {
    let cat = try addCat(born: "2020-05-01T00:00:00-04:00", neutered: false, kilograms: 4)
    // 70 × 4^0.75 × 1.4
    #expect(try target(of: cat)?.kcal.rounded() == 277)
  }

  @Test(arguments: [true, false])
  func aFourKilogramSeniorNeedsAbout238KcalNeuteredOrNot(neutered: Bool) throws {
    let cat = try addCat(born: "2015-05-01T00:00:00-04:00", neutered: neutered, kilograms: 4)
    #expect(try target(of: cat)?.kcal.rounded() == 238)
  }

  @Test func theTargetFollowsTheLatestWeighIn() throws {
    // First weighed in September.
    let cat = try withDependencies { $0.date.now = instant("2026-09-01T09:00:00-04:00") } operation: {
      try addCat(born: "2026-03-19T00:00:00-04:00", kilograms: 2)
    }
    #expect(try target(of: cat)?.kcal.rounded() == 294)
    try database.write { db in
      try db.recordWeighIn(Measurement(value: 2.5, unit: .kilograms), for: cat.id, on: instant("2026-10-19T09:00:00-04:00"))
      // Entered afterwards for an earlier date: not the latest.
      try db.recordWeighIn(Measurement(value: 1.8, unit: .kilograms), for: cat.id, on: instant("2026-10-01T09:00:00-04:00"))
    }
    // 70 × 2.5^0.75 × 2.5
    #expect(try target(of: cat)?.kcal.rounded() == 348)
  }

  @Test func theOwnersTargetReplacesTheCalculatedOneUntilCleared() throws {
    let cat = try addCat(born: "2020-05-01T00:00:00-04:00", kilograms: 4)
    try database.write { try $0.overrideCalorieTarget(210, for: cat.id) }
    #expect(try target(of: cat) == CalorieTarget(kcal: 210, isOverride: true))

    try database.write { try $0.overrideCalorieTarget(nil, for: cat.id) }
    #expect(try target(of: cat)?.kcal.rounded() == 238)
    #expect(try target(of: cat)?.isOverride == false)
  }

  @Test func theConverterShowsHowMuchOfAFoodMeetsTheTarget() throws {
    let cat = try addCat(born: "2020-05-01T00:00:00-04:00", kilograms: 4)
    try database.write { try $0.overrideCalorieTarget(240, for: cat.id) }
    let target = try #require(try target(of: cat))
    #expect(try addFood("Pâté", kcalPerUnit: 80).dailyAmount(toMeet: target) == 3)
    #expect(try addFood("Kibble", kcalPerUnit: 4, freeFed: true).dailyAmount(toMeet: target) == 60)
  }

  // MARK: Intake

  func addFood(_ name: String, kcalPerUnit: Double, treat: Bool = false, freeFed: Bool = false) throws -> Food {
    try database.write { try $0.addFood(name: name, servingUnit: .can, kcalPerUnit: kcalPerUnit, isTreat: treat, isFreeFed: freeFed) }
  }

  @discardableResult
  func log(_ amount: Double, of food: Food, for cat: Cat, at iso8601: String) throws -> Feeding {
    try database.write { try $0.logFeeding(catID: cat.id, foodID: food.id, amount: amount, at: instant(iso8601)) }
  }

  func intake(of cat: Cat) throws -> Intake {
    try database.read { try $0.feedingDay(for: cat.id).intake }
  }

  @Test func intakeAddsUpTodaysFeedings() throws {
    let cat = try addCat(born: "2026-03-19T00:00:00-04:00", kilograms: 2)
    let pate = try addFood("Pâté", kcalPerUnit: 80)
    try log(0.5, of: pate, for: cat, at: "2026-10-19T00:00:00-04:00")
    try log(1, of: pate, for: cat, at: "2026-10-19T11:00:00-04:00")
    // Either side of today, by the local clock.
    try log(1, of: pate, for: cat, at: "2026-10-18T23:59:00-04:00")
    try log(1, of: pate, for: cat, at: "2026-10-20T00:00:00-04:00")
    #expect(try intake(of: cat) == Intake(kcal: 120, treatKcal: 0, isApproximate: false))
  }

  @Test func treatsCountTowardIntakeAndAreSummedSeparately() throws {
    let cat = try addCat(born: "2026-03-19T00:00:00-04:00", kilograms: 2)
    try log(1, of: try addFood("Pâté", kcalPerUnit: 80), for: cat, at: "2026-10-19T08:00:00-04:00")
    try log(5, of: try addFood("Freeze-dried chicken", kcalPerUnit: 2, treat: true), for: cat, at: "2026-10-19T10:00:00-04:00")
    #expect(try intake(of: cat) == Intake(kcal: 90, treatKcal: 10, isApproximate: false))
  }

  @Test func anyFreeFedFeedingTodayMakesIntakeApproximate() throws {
    let cat = try addCat(born: "2026-03-19T00:00:00-04:00", kilograms: 2)
    let kibble = try addFood("Kibble", kcalPerUnit: 3.8, freeFed: true)
    // Yesterday's top-up doesn't make today approximate.
    try log(20, of: kibble, for: cat, at: "2026-10-18T20:00:00-04:00")
    try log(1, of: try addFood("Pâté", kcalPerUnit: 80), for: cat, at: "2026-10-19T08:00:00-04:00")
    #expect(try intake(of: cat).isApproximate == false)

    try log(10, of: kibble, for: cat, at: "2026-10-19T09:00:00-04:00")
    #expect(try intake(of: cat) == Intake(kcal: 118, treatKcal: 0, isApproximate: true))
  }

  @Test func feedingsOfARetiredFoodStillCount() throws {
    let cat = try addCat(born: "2026-03-19T00:00:00-04:00", kilograms: 2)
    var treat = try addFood("Freeze-dried chicken", kcalPerUnit: 2, treat: true)
    var kibble = try addFood("Kibble", kcalPerUnit: 3.8, freeFed: true)
    try log(5, of: treat, for: cat, at: "2026-10-19T08:00:00-04:00")
    try log(10, of: kibble, for: cat, at: "2026-10-19T09:00:00-04:00")
    treat.isRetired = true
    kibble.isRetired = true
    try database.write { db in
      try db.updateFood(treat)
      try db.updateFood(kibble)
    }
    #expect(try intake(of: cat) == Intake(kcal: 48, treatKcal: 10, isApproximate: true))
  }

  @Test func aFeedingAdjustedAfterwardsCountsOnlyWhatWasEaten() throws {
    let cat = try addCat(born: "2026-03-19T00:00:00-04:00", kilograms: 2)
    var meal = try log(1, of: try addFood("Pâté", kcalPerUnit: 80), for: cat, at: "2026-10-19T08:00:00-04:00")
    var treat = try log(5, of: try addFood("Freeze-dried chicken", kcalPerUnit: 2, treat: true), for: cat, at: "2026-10-19T10:00:00-04:00")
    #expect(meal.eatenFraction == nil)

    meal.eatenFraction = 0.5
    treat.eatenFraction = 0
    try database.write { db in
      try db.updateFeeding(meal)
      try db.updateFeeding(treat)
    }
    #expect(try intake(of: cat) == Intake(kcal: 40, treatKcal: 0, isApproximate: false))

    // A new amount keeps the fraction: ate about ½ of 2 cans.
    meal.amount = 2
    try database.write { try $0.updateFeeding(meal) }
    #expect(try intake(of: cat).kcal == 80)

    // Ate it all after all.
    meal.eatenFraction = nil
    try database.write { try $0.updateFeeding(meal) }
    #expect(try intake(of: cat).kcal == 160)
  }

  @Test(arguments: [-0.25, 1.5, Double.nan])
  func anEatenFractionIsBetweenNoneAndAll(fraction: Double) throws {
    let cat = try addCat(born: "2026-03-19T00:00:00-04:00", kilograms: 2)
    var feeding = try log(1, of: try addFood("Pâté", kcalPerUnit: 80), for: cat, at: "2026-10-19T08:00:00-04:00")
    feeding.eatenFraction = fraction
    #expect(throws: InvalidEatenFraction.self) { try database.write { try $0.updateFeeding(feeding) } }
    #expect(try intake(of: cat).kcal == 80)
  }

  @Test func treatAndFreeFedFollowTheFoodAsItIsNowButCaloriesDont() throws {
    let cat = try addCat(born: "2026-03-19T00:00:00-04:00", kilograms: 2)
    var bites = try addFood("Chicken bites", kcalPerUnit: 2)
    try log(5, of: bites, for: cat, at: "2026-10-19T08:00:00-04:00")
    bites.isTreat = true
    bites.isFreeFed = true
    bites.kcalPerUnit = 3
    try database.write { try $0.updateFood(bites) }
    #expect(try intake(of: cat) == Intake(kcal: 10, treatKcal: 10, isApproximate: true))
  }

  @Test func eachCatHasItsOwnIntake() throws {
    let miso = try addCat(born: "2026-03-19T00:00:00-04:00", kilograms: 2)
    let tofu = try addCat(born: "2026-03-19T00:00:00-04:00", kilograms: 2)
    let pate = try addFood("Pâté", kcalPerUnit: 80)
    try log(1, of: pate, for: tofu, at: "2026-10-19T08:00:00-04:00")
    #expect(try intake(of: miso).kcal == 0)
    #expect(try intake(of: tofu).kcal == 80)
  }

  @Test(arguments: [0, -50, Double.nan, .infinity])
  func anOverrideMustBeAPositiveNumber(kcal: Double) throws {
    let cat = try addCat(born: "2020-05-01T00:00:00-04:00", kilograms: 4)
    #expect(throws: InvalidCalorieTarget.self) { try database.write { try $0.overrideCalorieTarget(kcal, for: cat.id) } }
    #expect(try target(of: cat)?.isOverride == false)
  }
}
