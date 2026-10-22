import CatButlerCore
import Dependencies
import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

/// Miso, still at home, and Tofu, rehomed. Now is 12:00.
@Suite(
  .dependency(\.date.now, instant("2026-10-19T12:00:00-04:00")),
  .dependency(\.uuid, .incrementing),
  .dependency(\.calendar, calendar(in: "America/New_York")),
  .dependencies { $0.defaultDatabase = try appDatabase() }
)
struct ArchiveCatTests {
  @Dependency(\.defaultDatabase) var database
  let miso: Cat
  let tofu: Cat
  let pate: Food

  init() throws {
    @Dependency(\.defaultDatabase) var database
    (miso, tofu, pate) = try database.write { db in
      (
        try db.addCat(name: "Miso", photo: nil, birthdate: instant("2026-06-01T00:00:00-04:00"), isNeutered: false, weight: Measurement(value: 2, unit: .kilograms)),
        try db.addCat(name: "Tofu", photo: nil, birthdate: instant("2020-01-01T00:00:00-05:00"), isNeutered: true, weight: Measurement(value: 4.5, unit: .kilograms)),
        try db.addFood(name: "Tuna pâté", servingUnit: .can, kcalPerUnit: 80, isTreat: false, isFreeFed: false)
      )
    }
  }

  /// Gives `cat` a 12:30 Meal, set long ago, and a Care Task due in 5 days.
  func care(for cat: Cat) throws {
    @Dependency(\.uuid) var uuid
    let meal = Meal(id: uuid(), catID: cat.id, minuteOfDay: 12 * 60 + 30, foodID: pate.id, amount: 0.25)
    try withDependencies { $0.date.now = instant("2026-01-01T00:00:00-05:00") } operation: {
      try database.write { try $0.saveMeals([meal], for: cat.id) }
    }
    try database.write { try $0.addCareTask(for: cat.id, title: "Vaccine", dueDate: instant("2026-10-24T00:00:00-04:00"), interval: nil) }
  }

  /// The plan's Cats, one entry per reminder.
  func remindedCats() throws -> Set<String> {
    Set(try database.read { try $0.reminders(careTiming: .default) }.map {
      switch $0 {
      case .meal(let reminder): reminder.catName
      case .care(let reminder): reminder.catName
      }
    })
  }

  @Test func anArchivedCatGetsNoReminders() throws {
    try care(for: miso)
    try care(for: tofu)

    try database.write { try $0.archiveCat(tofu.id) }

    #expect(try remindedCats() == ["Miso"])
  }

  @Test func anArchivedCatLeavesCareAndKeepsItsHistory() throws {
    let vaccine = try database.write { try $0.addCareTask(for: tofu.id, title: "Vaccine", dueDate: instant("2026-10-24T00:00:00-04:00"), interval: nil) }
    try database.write { db in
      _ = try db.addCareRecord(for: vaccine.id, on: instant("2026-10-18T10:00:00-04:00"), notes: "All good", photo: nil)
      try db.logFeeding(catID: tofu.id, foodID: pate.id, amount: 0.25, at: instant("2026-10-19T11:00:00-04:00"))
    }

    try database.write { try $0.archiveCat(tofu.id) }

    #expect(try database.read { try Cat.inCare.fetchAll($0) }.map(\.name) == ["Miso"])
    #expect(try database.read { try Cat.archived.fetchAll($0) }.map(\.name) == ["Tofu"])
    #expect(try database.read { try WeighIn.series(for: tofu.id).fetchAll($0) }.map(\.kilograms) == [4.5])
    #expect(try database.read { try CareRecord.history(for: tofu.id).fetchAll($0) }.map(\.notes) == ["All good"])
    #expect(try database.read { try $0.feedingDay(for: tofu.id) }.intake.kcal == 20)
  }

  @Test func anUnarchivedCatIsBackInCare() throws {
    try care(for: tofu)
    try database.write { try $0.archiveCat(tofu.id) }

    try database.write { try $0.unarchiveCat(tofu.id) }

    #expect(try database.read { try Cat.inCare.fetchAll($0) }.map(\.name) == ["Miso", "Tofu"])
    #expect(try remindedCats() == ["Tofu"])
  }

  @Test func feedAllSkipsAnArchivedCat() throws {
    try care(for: miso)
    try care(for: tofu)
    try database.write { try $0.archiveCat(tofu.id) }

    #expect(try database.write { try $0.feedAll() }.map(\.catID) == [miso.id])
  }

  @Test func deletingACatRemovesEverythingRecordedAboutIt() throws {
    try care(for: miso)
    try care(for: tofu)
    for cat in [miso, tofu] {
      let task = try database.read { try CareTask.where { $0.catID.eq(cat.id) }.fetchOne($0) }!
      try database.write { db in
        _ = try db.addCareRecord(for: task.id, on: instant("2026-10-18T10:00:00-04:00"), notes: "", photo: nil)
        try db.logFeeding(catID: cat.id, foodID: pate.id, amount: 0.25, at: instant("2026-10-19T11:00:00-04:00"))
      }
    }

    try database.write { try $0.deleteCat(tofu.id) }

    let left = try database.read { db in
      (
        cats: try Cat.all.fetchAll(db).map(\.name),
        meals: try Meal.all.fetchAll(db).map(\.catID),
        feedings: try Feeding.all.fetchAll(db).map(\.catID),
        weighIns: try WeighIn.all.fetchAll(db).map(\.catID),
        careTasks: try CareTask.all.fetchAll(db).map(\.catID),
        careRecords: try CareRecord.all.fetchCount(db)
      )
    }
    #expect(left.cats == ["Miso"])
    #expect(left.meals == [miso.id])
    #expect(left.feedings == [miso.id])
    #expect(left.weighIns == [miso.id])
    #expect(left.careTasks == [miso.id])
    #expect(left.careRecords == 1)
  }
}
