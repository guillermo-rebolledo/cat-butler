import CatButlerCore
import Dependencies
import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

@Suite(
  .dependency(\.date.now, Date(timeIntervalSince1970: 1_800_000_000)),
  .dependency(\.uuid, .incrementing),
  .dependencies { $0.defaultDatabase = try appDatabase() }
)
struct FirstRunTests {
  @Dependency(\.defaultDatabase) var database
  @Dependency(\.date.now) var now

  @Test func addingTheFirstCatCreatesAHouseholdAndFirstWeighIn() throws {
    let birthdate = Date(timeIntervalSince1970: 1_790_000_000)
    let cat = try database.write { db in
      try db.addCat(name: "Miso", photo: nil, birthdate: birthdate, isNeutered: false, weight: Measurement(value: 5, unit: .pounds))
    }

    let households = try database.read { try Household.fetchAll($0) }
    #expect(households.count == 1)
    #expect(cat.householdID == households.first?.id)
    #expect(cat.name == "Miso")
    #expect(cat.birthdate == birthdate)

    let weighIns = try database.read { try WeighIn.where { $0.catID.eq(cat.id) }.fetchAll($0) }
    #expect(weighIns.count == 1)
    #expect(abs(weighIns[0].kilograms - 2.268) < 0.001)
    #expect(weighIns.map(\.date) == [now])
  }

  @Test func laterCatsJoinTheSameHousehold() throws {
    let (first, second) = try database.write { db in
      (
        try db.addCat(name: "Miso", photo: nil, birthdate: now, isNeutered: false, weight: Measurement(value: 1, unit: .kilograms)),
        try db.addCat(name: "Tofu", photo: nil, birthdate: now, isNeutered: true, weight: Measurement(value: 8.8, unit: .pounds))
      )
    }
    #expect(first.householdID == second.householdID)
    #expect(try database.read { try Household.fetchCount($0) } == 1)
  }
}
