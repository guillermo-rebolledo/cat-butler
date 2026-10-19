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
struct WeighInTests {
  @Dependency(\.defaultDatabase) var database

  /// A Cat first weighed at `weighedAt`, at 2 kg.
  func addCat(born birthdate: String, weighedAt iso8601: String) throws -> Cat {
    try withDependencies { $0.date.now = instant(iso8601) } operation: {
      try database.write { db in
        try db.addCat(
          name: "Miso", photo: nil, birthdate: instant(birthdate), isNeutered: true,
          weight: Measurement(value: 2, unit: .kilograms)
        )
      }
    }
  }

  func isDue(_ cat: Cat, at iso8601: String) throws -> Bool {
    try withDependencies { $0.date.now = instant(iso8601) } operation: {
      try database.read { try $0.isWeighInDue(for: cat.id) }
    }
  }

  @Test func aKittensWeighInFallsDueOnTheFourteenthDay() throws {
    let cat = try addCat(born: "2026-03-19T00:00:00-04:00", weighedAt: "2026-10-05T18:00:00-04:00")
    #expect(try isDue(cat, at: "2026-10-06T09:00:00-04:00") == false)
    #expect(try isDue(cat, at: "2026-10-18T23:59:00-04:00") == false)
    // From the start of the local day, not the hour it was weighed.
    #expect(try isDue(cat, at: "2026-10-19T00:00:00-04:00") == true)
    #expect(try isDue(cat, at: "2026-11-30T09:00:00-05:00") == true)
  }

  @Test(arguments: [
    "2020-05-01T00:00:00-04:00",  // Adult
    "2015-05-01T00:00:00-04:00",  // Senior
  ])
  func anAdultOrSeniorsWeighInFallsDueOnTheThirtiethDay(born birthdate: String) throws {
    let cat = try addCat(born: birthdate, weighedAt: "2026-10-05T18:00:00-04:00")
    #expect(try isDue(cat, at: "2026-10-19T09:00:00-04:00") == false)
    #expect(try isDue(cat, at: "2026-11-03T23:59:00-05:00") == false)
    #expect(try isDue(cat, at: "2026-11-04T00:00:00-05:00") == true)
  }

  func series(of cat: Cat) throws -> [WeighIn] {
    try database.read { try WeighIn.series(for: cat.id).fetchAll($0) }
  }

  @Test func weighInsAreStoredInKilogramsAndChartedInDateOrder() throws {
    let cat = try addCat(born: "2026-03-19T00:00:00-04:00", weighedAt: "2026-09-01T09:00:00-04:00")
    let other = try addCat(born: "2026-03-19T00:00:00-04:00", weighedAt: "2026-09-01T09:00:00-04:00")
    try database.write { db in
      try db.recordWeighIn(Measurement(value: 5.5, unit: .pounds), for: cat.id, on: instant("2026-10-15T09:00:00-04:00"))
      // Entered afterwards for an earlier date.
      try db.recordWeighIn(Measurement(value: 2200, unit: .grams), for: cat.id, on: instant("2026-09-20T09:00:00-04:00"))
    }
    #expect(try series(of: cat).map(\.date) == ["2026-09-01T09:00:00-04:00", "2026-09-20T09:00:00-04:00", "2026-10-15T09:00:00-04:00"].map(instant))
    // 5.5 lb is 2.495 kg.
    #expect(try series(of: cat).map { ($0.kilograms * 1000).rounded() / 1000 } == [2, 2.2, 2.495])
    #expect(try series(of: other).count == 1)
  }

  func target(of cat: Cat) throws -> Double? {
    try database.read { try $0.calorieTarget(for: cat.id)?.kcal.rounded() }
  }

  @Test func anEditedWeighInMovesTheChartTheTargetAndTheNextPrompt() throws {
    let cat = try addCat(born: "2026-03-19T00:00:00-04:00", weighedAt: "2026-09-01T09:00:00-04:00")
    var weighIn = try database.write { db in
      try db.recordWeighIn(Measurement(value: 25, unit: .kilograms), for: cat.id, on: instant("2026-09-10T09:00:00-04:00"))
    }
    // Meant 2.5 kg, two days ago.
    weighIn.weight = Measurement(value: 2.5, unit: .kilograms)
    weighIn.date = instant("2026-10-17T09:00:00-04:00")
    try database.write { try $0.updateWeighIn(weighIn) }

    #expect(try series(of: cat).map(\.kilograms) == [2, 2.5])
    // 70 × 2.5^0.75 × 2.5
    #expect(try target(of: cat) == 348)
    #expect(try isDue(cat, at: "2026-10-19T12:00:00-04:00") == false)
    #expect(try isDue(cat, at: "2026-10-31T00:00:00-04:00") == true)
  }

  @Test func deletingTheLatestWeighInFallsBackToTheOneBefore() throws {
    let cat = try addCat(born: "2026-03-19T00:00:00-04:00", weighedAt: "2026-09-01T09:00:00-04:00")
    let mistake = try database.write { db in
      try db.recordWeighIn(Measurement(value: 2.5, unit: .kilograms), for: cat.id, on: instant("2026-10-18T09:00:00-04:00"))
    }
    #expect(try isDue(cat, at: "2026-10-19T12:00:00-04:00") == false)

    try database.write { try $0.deleteWeighIn(mistake.id) }
    #expect(try series(of: cat).map(\.kilograms) == [2])
    // 70 × 2^0.75 × 2.5
    #expect(try target(of: cat) == 294)
    #expect(try isDue(cat, at: "2026-10-19T12:00:00-04:00") == true)
  }

  @Test func aCatWithNoWeighInsHasOnlyTheOwnersTargetAndIsDueOne() throws {
    let cat = try addCat(born: "2026-03-19T00:00:00-04:00", weighedAt: "2026-10-19T09:00:00-04:00")
    try database.write { db in
      for weighIn in try WeighIn.series(for: cat.id).fetchAll(db) { try db.deleteWeighIn(weighIn.id) }
    }
    #expect(try series(of: cat).isEmpty)
    #expect(try target(of: cat) == nil)
    #expect(try isDue(cat, at: "2026-10-19T12:00:00-04:00") == true)

    try database.write { try $0.overrideCalorieTarget(210, for: cat.id) }
    #expect(try target(of: cat) == 210)
  }

  @Test(arguments: [0, -2, Double.nan, .infinity])
  func aWeightMustBeAPositiveNumber(kilograms: Double) throws {
    let cat = try addCat(born: "2026-03-19T00:00:00-04:00", weighedAt: "2026-10-19T09:00:00-04:00")
    let weight = Measurement(value: kilograms, unit: UnitMass.kilograms)
    #expect(throws: InvalidWeight.self) {
      try database.write { try $0.recordWeighIn(weight, for: cat.id, on: instant("2026-10-19T10:00:00-04:00")) }
    }
    var weighIn = try #require(try series(of: cat).first)
    weighIn.weight = weight
    #expect(throws: InvalidWeight.self) { try database.write { try $0.updateWeighIn(weighIn) } }
    #expect(try series(of: cat).map(\.kilograms) == [2])
  }

  @Test func aNewWeighInEndsThePromptButOneBackdatedBeforeTheLastDoesNot() throws {
    let cat = try addCat(born: "2026-03-19T00:00:00-04:00", weighedAt: "2026-09-01T09:00:00-04:00")
    #expect(try isDue(cat, at: "2026-10-19T12:00:00-04:00") == true)

    try database.write { db in
      try db.recordWeighIn(Measurement(value: 2.4, unit: .kilograms), for: cat.id, on: instant("2026-08-20T09:00:00-04:00"))
    }
    #expect(try isDue(cat, at: "2026-10-19T12:00:00-04:00") == true)

    try database.write { db in
      try db.recordWeighIn(Measurement(value: 2.6, unit: .kilograms), for: cat.id, on: instant("2026-10-19T08:00:00-04:00"))
    }
    #expect(try isDue(cat, at: "2026-10-19T12:00:00-04:00") == false)
    #expect(try isDue(cat, at: "2026-11-02T00:00:00-05:00") == true)
  }

  @Test func aWeighInDueBeforeTheFirstBirthdayStaysDueAfterIt() throws {
    let cat = try addCat(born: "2025-10-25T00:00:00-04:00", weighedAt: "2026-10-05T18:00:00-04:00")
    #expect(try isDue(cat, at: "2026-10-19T09:00:00-04:00") == true)
    #expect(try isDue(cat, at: "2026-10-26T09:00:00-04:00") == true)
  }

  @Test func aKittenThatTurnsOneBeforeItsNextWeighInWaitsThirtyDays() throws {
    let cat = try addCat(born: "2025-10-25T00:00:00-04:00", weighedAt: "2026-10-20T18:00:00-04:00")
    #expect(try isDue(cat, at: "2026-11-03T09:00:00-05:00") == false)
    #expect(try isDue(cat, at: "2026-11-18T23:59:00-05:00") == false)
    #expect(try isDue(cat, at: "2026-11-19T00:00:00-05:00") == true)
  }
}
