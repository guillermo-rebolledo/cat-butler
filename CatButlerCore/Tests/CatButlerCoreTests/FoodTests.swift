import CatButlerCore
import Dependencies
import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

@Suite(
  .dependency(\.date.now, Date(timeIntervalSince1970: 1_800_000_000)),
  .dependency(\.uuid, .incrementing),
  .dependency(\.calendar, calendar(in: "America/New_York")),
  .dependencies { $0.defaultDatabase = try appDatabase() }
)
struct FoodTests {
  @Dependency(\.defaultDatabase) var database

  @Test func addedFoodsBelongToTheHousehold() throws {
    let (cat, food) = try database.write { db in
      (
        try db.addCat(name: "Miso", photo: nil, birthdate: .now, isNeutered: false, weight: Measurement(value: 4, unit: .kilograms)),
        try db.addFood(name: "Tuna pâté", servingUnit: .can, kcalPerUnit: 76.5, isTreat: true, isFreeFed: true)
      )
    }
    let stored = try database.read { try Food.find(food.id).fetchOne($0) }
    #expect(stored?.householdID == cat.householdID)
    #expect(stored?.name == "Tuna pâté")
    #expect(stored?.servingUnit == .can)
    #expect(stored?.kcalPerUnit == 76.5)
    #expect(stored?.isTreat == true)
    #expect(stored?.isFreeFed == true)
    #expect(stored?.isRetired == false)
  }

  @Test func retiredFoodsLeavePickersButKeepTheirDetails() throws {
    var kibble = try database.write { db in
      try db.addFood(name: "Kibble", servingUnit: .gram, kcalPerUnit: 3.8, isTreat: false, isFreeFed: true)
    }
    let treat = try database.write { db in
      try db.addFood(name: "Freeze-dried chicken", servingUnit: .gram, kcalPerUnit: 4.2, isTreat: true, isFreeFed: false)
    }
    kibble.isRetired = true
    try database.write { try Food.update(kibble).execute($0) }

    #expect(try database.read { try Food.active.fetchAll($0) } == [treat])
    #expect(try database.read { try Food.retired.fetchAll($0) } == [kibble])
    #expect(try database.read { try Food.find(kibble.id).fetchOne($0) } == kibble)
  }

  @Test func foodsAreListedAlphabeticallyIgnoringCase() throws {
    try database.write { db in
      for name in ["Zebra mix", "apple bites", "Mackerel"] {
        try db.addFood(name: name, servingUnit: .can, kcalPerUnit: 80, isTreat: false, isFreeFed: false)
      }
    }
    #expect(try database.read { try Food.active.fetchAll($0) }.map(\.name) == ["apple bites", "Mackerel", "Zebra mix"])
  }
}
