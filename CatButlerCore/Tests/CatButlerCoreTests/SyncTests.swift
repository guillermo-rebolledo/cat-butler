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
  .dependencies { try $0.bootstrapDatabase() }
)
struct SyncTests {
  @Dependency(\.defaultDatabase) var database
  @Dependency(\.date.now) var now

  /// Fails when a new table isn't added to the sync: add it in `bootstrapDatabase`, and a row of it here.
  @Test func everyTableSyncsToICloud() throws {
    try database.write { db in
      let cat = try db.addCat(name: "Miso", photo: nil, birthdate: now, isNeutered: false, weight: Measurement(value: 2, unit: .kilograms))
      let food = try db.addFood(name: "Tuna pâté", servingUnit: .can, kcalPerUnit: 80, isTreat: false, isFreeFed: false)
      @Dependency(\.uuid) var uuid
      try db.saveMeals([Meal(id: uuid(), catID: cat.id, minuteOfDay: 8 * 60, foodID: food.id, amount: 1)], for: cat.id)
      try db.logFeeding(catID: cat.id, foodID: food.id, amount: 1, at: now)
      let task = try db.addCareTask(for: cat.id, title: "Rabies vaccine", dueDate: now, interval: nil)
      try db.addCareRecord(for: task.id, on: now, notes: "", photo: nil)
    }

    let (tables, syncedTables) = try database.read { db in
      (
        try Set(String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'")),
        try Set(SyncMetadata.select(\.recordType).fetchAll(db))
      )
    }
    #expect(tables.count == 8)
    #expect(syncedTables == tables)
  }
}
