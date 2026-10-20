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
struct CareReminderTests {
  @Dependency(\.defaultDatabase) var database
  let cat: Cat

  init() throws {
    @Dependency(\.defaultDatabase) var database
    cat = try database.write { db in
      try db.addCat(name: "Miso", photo: nil, birthdate: instant("2026-06-01T00:00:00-04:00"), isNeutered: false, weight: Measurement(value: 2, unit: .kilograms))
    }
  }

  @discardableResult
  func addTask(_ title: String = "Vaccine", due iso8601: String, interval: CareInterval? = nil) throws -> CareTask {
    try database.write { try $0.addCareTask(for: cat.id, title: title, dueDate: instant(iso8601), interval: interval) }
  }

  /// The Care Task part of the plan, as "kind instant".
  func plan(_ timing: CareReminder.Timing = .default) throws -> [String] {
    try database.read { try $0.reminders(careTiming: timing) }
      .compactMap { if case .care(let reminder) = $0 { "\(reminder.kind) \(reminder.date)" } else { nil } }
  }

  func reminder(_ kind: CareReminder.Kind, _ iso8601: String) -> String {
    "\(kind) \(instant(iso8601))"
  }

  @Test func aCareTaskGetsAReminderThreeDaysBeforeAndAt9OnItsDueDate() throws {
    try addTask(due: "2026-11-02T00:00:00-05:00")
    #expect(try plan() == [
      reminder(.advance, "2026-10-30T09:00:00-04:00"), reminder(.due, "2026-11-02T09:00:00-05:00"),
    ])
  }

  @Test func settingsChangeBothTimings() throws {
    try addTask(due: "2026-11-02T00:00:00-05:00")
    #expect(try plan(CareReminder.Timing(daysBefore: 7, minuteOfDay: 18 * 60 + 30)) == [
      reminder(.advance, "2026-10-26T18:30:00-04:00"), reminder(.due, "2026-11-02T18:30:00-05:00"),
    ])
  }

  /// Overdue from the day after its due date: the badge shows it, no notification does.
  @Test func overdueCareTasksProduceNoReminders() throws {
    try addTask(due: "2026-10-18T00:00:00-04:00")
    try addTask(due: "2026-10-01T00:00:00-04:00", interval: CareInterval(count: 1, unit: .month))
    #expect(try plan() == [])
  }

  /// Noon on the due date: 09:00 has passed, so it's already been reminded.
  @Test func aCareTaskDueTodayAfterItsReminderTimeGetsNoMore() throws {
    try addTask(due: "2026-10-19T00:00:00-04:00")
    #expect(try plan() == [])
  }

  /// Within 3 days of its due date, only the due-date reminder is left.
  @Test func aCareTaskDueInTwoDaysGetsOnlyItsDueDateReminder() throws {
    try addTask(due: "2026-10-21T00:00:00-04:00")
    #expect(try plan() == [reminder(.due, "2026-10-21T09:00:00-04:00")])
  }

  @Test func aDoneOneOffCareTaskProducesNoReminders() throws {
    let task = try addTask("Spay", due: "2026-11-02T00:00:00-05:00")
    try database.write { _ = try $0.addCareRecord(for: task.id, on: instant("2026-10-19T10:00:00-04:00"), notes: "", photo: nil) }
    #expect(try plan() == [])
  }

  /// Done today, a recurring task's reminders move with its next due date.
  @Test func aDoneRecurringCareTaskIsRemindedAtItsNextDueDate() throws {
    let task = try addTask("Deworming", due: "2026-10-22T00:00:00-04:00", interval: CareInterval(count: 3, unit: .month))
    try database.write { _ = try $0.addCareRecord(for: task.id, on: instant("2026-10-19T10:00:00-04:00"), notes: "", photo: nil) }
    #expect(try plan() == [
      reminder(.advance, "2027-01-16T09:00:00-05:00"), reminder(.due, "2027-01-19T09:00:00-05:00"),
    ])
  }

  /// Six Meals a day make 84 Meal Reminders over the week, more than iOS keeps, so the plan keeps the soonest 64,
  /// Care Reminders among them.
  @Test func thePlanNeverExceeds64AndKeepsTheSoonest() throws {
    @Dependency(\.uuid) var uuid
    let pate = try database.write { try $0.addFood(name: "Tuna pâté", servingUnit: .can, kcalPerUnit: 80, isTreat: false, isFreeFed: false) }
    let meals = [7, 10, 13, 16, 19, 22].map { Meal(id: uuid(), catID: cat.id, minuteOfDay: $0 * 60, foodID: pate.id, amount: 0.5) }
    try database.write { try $0.saveMeals(meals, for: cat.id) }
    try addTask("Flea treatment", due: "2026-10-21T00:00:00-04:00")
    try addTask(due: "2027-06-01T00:00:00-04:00")

    let reminders = try database.read { try $0.reminders(careTiming: .default) }
    #expect(reminders.count == Reminder.limit)
    #expect(reminders.map(\.date) == reminders.map(\.date).sorted())
    #expect(try plan() == [reminder(.due, "2026-10-21T09:00:00-04:00")])
    // 8 left today, 12 a day on the 20th–23rd and the Flea treatment make 57; the 24th's first 7 end at 16:00.
    #expect(reminders.last?.date == instant("2026-10-24T16:00:00-04:00"))
  }
}
