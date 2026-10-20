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
struct CareTaskTests {
  @Dependency(\.defaultDatabase) var database
  let cat: Cat

  init() throws {
    @Dependency(\.defaultDatabase) var database
    cat = try database.write { db in
      try db.addCat(
        name: "Miso", photo: nil, birthdate: instant("2025-03-19T00:00:00-04:00"), isNeutered: true,
        weight: Measurement(value: 4, unit: .kilograms)
      )
    }
  }

  func addTask(_ title: String = "Deworming", due: String, every interval: CareInterval?) throws -> CareTask {
    try database.write { try $0.addCareTask(for: cat.id, title: title, dueDate: instant(due), interval: interval) }
  }

  func record(_ task: CareTask, on iso8601: String, notes: String = "") throws {
    try database.write { try $0.addCareRecord(for: task.id, on: instant(iso8601), notes: notes, photo: nil) }
  }

  func status(of task: CareTask, at iso8601: String = "2026-10-19T12:00:00-04:00") throws -> CareTaskStatus {
    try withDependencies { $0.date.now = instant(iso8601) } operation: {
      try #require(try database.read { try $0.careTasks(for: cat.id) }.first { $0.id == task.id })
    }
  }

  @Test func aRecurringTaskDoneLateIsNextDueAnIntervalAfterItWasDone() throws {
    let task = try addTask(due: "2026-10-01T09:00:00-04:00", every: CareInterval(count: 3, unit: .month))
    try record(task, on: "2026-10-10T18:00:00-04:00")
    #expect(try status(of: task).task.dueDate == instant("2027-01-10T18:00:00-05:00"))
  }

  @Test func aRecurringTaskDoneEarlyIsNextDueAnIntervalAfterItWasDone() throws {
    let task = try addTask(due: "2026-11-01T09:00:00-04:00", every: CareInterval(count: 1, unit: .month))
    try record(task, on: "2026-10-19T08:00:00-04:00")
    #expect(try status(of: task).task.dueDate == instant("2026-11-19T08:00:00-05:00"))
  }

  @Test func aFirstRecordBackdatedFromTheShelterCountsTheNextDueDateFromThen() throws {
    let task = try addTask("Vaccine", due: "2026-12-01T09:00:00-05:00", every: CareInterval(count: 1, unit: .year))
    try record(task, on: "2025-09-20T09:00:00-04:00", notes: "Given by the shelter")
    #expect(try status(of: task).task.dueDate == instant("2026-09-20T09:00:00-04:00"))
    #expect(try status(of: task).state == .overdue)
  }

  @Test func aRecordBackdatedBeforeTheLatestLeavesTheDueDate() throws {
    let task = try addTask(due: "2026-10-01T09:00:00-04:00", every: CareInterval(count: 1, unit: .year))
    try record(task, on: "2026-10-15T09:00:00-04:00")
    // The shelter's dose, entered afterwards.
    try record(task, on: "2025-11-20T09:00:00-05:00")
    #expect(try status(of: task).task.dueDate == instant("2027-10-15T09:00:00-04:00"))
  }

  @Test func aTaskIsDueSoonForAWeekAndOverdueFromTheDayAfterItsDueDate() throws {
    let task = try addTask(due: "2026-10-26T18:00:00-04:00", every: nil)
    #expect(try status(of: task, at: "2026-10-18T23:59:00-04:00").state == .later)
    // A week ahead, by local day rather than the hour it's due.
    #expect(try status(of: task, at: "2026-10-19T00:00:00-04:00").state == .dueSoon)
    #expect(try status(of: task, at: "2026-10-26T23:59:00-04:00").state == .dueSoon)
    #expect(try status(of: task, at: "2026-10-27T00:00:00-04:00").state == .overdue)
    // Today shows the due-soon and overdue ones only.
    #expect(try ["2026-10-18T23:59:00-04:00", "2026-10-19T00:00:00-04:00", "2026-10-27T00:00:00-04:00"].map { try status(of: task, at: $0).isDue } == [false, true, true])
  }

  @Test func aOneOffTaskIsDoneOnceItHasACareRecordAndKeepsItsDueDate() throws {
    let task = try addTask("Microchip check", due: "2026-10-12T09:00:00-04:00", every: nil)
    #expect(try status(of: task).state == .overdue)
    try record(task, on: "2026-10-19T10:00:00-04:00")
    #expect(try status(of: task).state == .done)
    #expect(try status(of: task).isDue == false)
    #expect(try status(of: task, at: "2027-06-01T09:00:00-04:00").state == .done)
    #expect(try status(of: task).task.dueDate == instant("2026-10-12T09:00:00-04:00"))
  }

  @Test func eachCatsHistoryListsItsCareRecordsNewestFirstIncludingBackdatedOnes() throws {
    let vaccine = try addTask("Vaccine", due: "2026-10-01T09:00:00-04:00", every: CareInterval(count: 1, unit: .year))
    let deworming = try addTask(due: "2026-10-01T09:00:00-04:00", every: CareInterval(count: 3, unit: .month))
    try record(vaccine, on: "2026-10-15T09:00:00-04:00", notes: "Booster, left leg")
    try record(deworming, on: "2026-10-16T09:00:00-04:00")
    try record(vaccine, on: "2025-11-20T09:00:00-05:00", notes: "Given by the shelter")
    let other = try database.write { db in
      try db.addCat(
        name: "Tofu", photo: nil, birthdate: instant("2024-01-01T00:00:00-05:00"), isNeutered: true,
        weight: Measurement(value: 5, unit: .kilograms)
      )
    }
    try database.write { db in
      let task = try db.addCareTask(for: other.id, title: "Checkup", dueDate: instant("2026-10-01T09:00:00-04:00"), interval: nil)
      try db.addCareRecord(for: task.id, on: instant("2026-10-17T09:00:00-04:00"), notes: "", photo: nil)
    }

    let history = try database.read { try CareRecord.history(for: cat.id).fetchAll($0) }
    #expect(history.map(\.careTaskID) == [deworming.id, vaccine.id, vaccine.id])
    #expect(history.map(\.notes) == ["", "Booster, left leg", "Given by the shelter"])
  }

  @Test func theOwnerCanMoveTheDueDateByHandAndDeleteATask() throws {
    var task = try addTask("Vaccine", due: "2026-10-01T09:00:00-04:00", every: CareInterval(count: 1, unit: .year))
    try record(task, on: "2026-10-15T09:00:00-04:00")
    // The vet card says the booster lasts three years.
    task = try status(of: task).task
    task.dueDate = instant("2029-10-15T09:00:00-04:00")
    task.interval = CareInterval(count: 3, unit: .year)
    try database.write { try $0.updateCareTask(task) }
    #expect(try status(of: task).task == task)
    #expect(try status(of: task).state == .later)

    try database.write { try $0.deleteCareTask(task.id) }
    #expect(try database.read { try $0.careTasks(for: cat.id) }.isEmpty)
    #expect(try database.read { try CareRecord.history(for: cat.id).fetchAll($0) }.isEmpty)
  }

  @Test(arguments: [("", 1), ("  ", 1), ("Vaccine", 0), ("Vaccine", -1)])
  func aTaskNeedsATitleAndARepeatOfAtLeastOne(title: String, count: Int) throws {
    #expect(throws: InvalidCareTask.self) {
      try addTask(title, due: "2026-10-01T09:00:00-04:00", every: CareInterval(count: count, unit: .month))
    }
    var task = try addTask(due: "2026-10-01T09:00:00-04:00", every: nil)
    task.title = title
    task.interval = CareInterval(count: count, unit: .month)
    #expect(throws: InvalidCareTask.self) { try database.write { try $0.updateCareTask(task) } }
    #expect(try database.read { try $0.careTasks(for: cat.id) }.map(\.task.title) == ["Deworming"])
  }
}
