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
    try addTask(due: "2026-10-24T00:00:00-04:00")
    #expect(try plan() == [
      reminder(.advance, "2026-10-21T09:00:00-04:00"), reminder(.due, "2026-10-24T09:00:00-04:00"),
    ])
  }

  /// Both stay at 09:00 across the end of daylight saving time on November 1.
  @Test func remindersKeepTheirTimeOfDayAcrossADaylightSavingChange() throws {
    try withDependencies { $0.date.now = instant("2026-10-28T12:00:00-04:00") } operation: {
      try addTask(due: "2026-11-02T00:00:00-05:00")
      let reminders = try plan()
      #expect(reminders == [
        reminder(.advance, "2026-10-30T09:00:00-04:00"), reminder(.due, "2026-11-02T09:00:00-05:00"),
      ])
    }
  }

  @Test func settingsChangeBothTimings() throws {
    try addTask(due: "2026-10-25T00:00:00-04:00")
    #expect(try plan(CareReminder.Timing(daysBefore: 5, minuteOfDay: 18 * 60 + 30)) == [
      reminder(.advance, "2026-10-20T18:30:00-04:00"), reminder(.due, "2026-10-25T18:30:00-04:00"),
    ])
  }

  /// 30 days ahead, today included, until the 17th of November; later ones join as the plan moves on.
  @Test func thePlanCoversAMonthOfCareReminders() throws {
    try addTask(due: "2026-11-20T00:00:00-05:00")
    #expect(try plan() == [reminder(.advance, "2026-11-17T09:00:00-05:00")])
    try withDependencies { $0.date.now = instant("2026-10-22T12:00:00-04:00") } operation: {
      let later = try plan()
      #expect(later == [reminder(.advance, "2026-11-17T09:00:00-05:00"), reminder(.due, "2026-11-20T09:00:00-05:00")])
    }
  }

  /// Overdue from the day after its due date: the badge shows it, no notification does.
  @Test func overdueCareTasksProduceNoReminders() throws {
    try addTask(due: "2026-10-18T00:00:00-04:00")
    try addTask(due: "2026-10-01T00:00:00-04:00", interval: CareInterval(count: 1, unit: .month))
    #expect(try plan() == [])
  }

  /// Noon on the due date: 09:00 has passed, so none is left. Added just now, it's in front of the owner on Today.
  @Test func aCareTaskDueTodayAfterItsReminderTimeGetsNoMore() throws {
    try addTask(due: "2026-10-19T00:00:00-04:00")
    #expect(try plan() == [])
  }

  /// Added 2 days ahead, after its advance reminder's time: that comes at the next reminder time instead, and only
  /// once.
  @Test func aCareTaskAddedLateGetsItsAdvanceReminderAtTheNextReminderTime() throws {
    try addTask(due: "2026-10-21T00:00:00-04:00")
    #expect(try plan() == [reminder(.advance, "2026-10-20T09:00:00-04:00"), reminder(.due, "2026-10-21T09:00:00-04:00")])
    try withDependencies { $0.date.now = instant("2026-10-20T10:00:00-04:00") } operation: {
      let later = try plan()
      #expect(later == [reminder(.due, "2026-10-21T09:00:00-04:00")])
    }
  }

  /// Added the day before, the next reminder time is the due date's own.
  @Test func aCareTaskAddedTheDayBeforeGetsOnlyItsDueDateReminder() throws {
    try addTask(due: "2026-10-20T00:00:00-04:00")
    #expect(try plan() == [reminder(.due, "2026-10-20T09:00:00-04:00")])
  }

  /// Added weeks ago, its advance reminder already came on the 18th.
  @Test func aCareTaskSetEarlierGetsNoSecondAdvanceReminder() throws {
    let task = try withDependencies { $0.date.now = instant("2026-10-01T12:00:00-04:00") } operation: {
      try addTask(due: "2026-10-21T00:00:00-04:00")
    }
    #expect(try plan() == [reminder(.due, "2026-10-21T09:00:00-04:00")])
    // Renaming it, or picking a time on the same day, doesn't change the day it's due.
    var renamed = task
    renamed.title = "Rabies vaccine"
    renamed.dueDate = instant("2026-10-21T15:00:00-04:00")
    try database.write { try $0.updateCareTask(renamed) }
    #expect(try plan() == [reminder(.due, "2026-10-21T09:00:00-04:00")])
  }

  /// Set weeks ago, due on the 25th: its advance reminder was coming on the 22nd. Moved to 7 days before today, the
  /// 18th has passed, so it comes at the next reminder time instead of not at all.
  @Test func aLongerTimingCatchesUpInsteadOfDroppingTheAdvanceReminder() throws {
    try withDependencies { $0.date.now = instant("2026-10-01T12:00:00-04:00") } operation: {
      try addTask(due: "2026-10-25T00:00:00-04:00")
    }
    let timing = CareReminder.Timing(daysBefore: 7, minuteOfDay: 9 * 60, lengthenedAt: instant("2026-10-19T11:00:00-04:00"))
    #expect(try plan(timing) == [reminder(.advance, "2026-10-20T09:00:00-04:00"), reminder(.due, "2026-10-25T09:00:00-04:00")])
  }

  /// Moved from December to the 21st, e.g. the vet's booster date: the advance reminder catches up.
  @Test func aDueDateMovedCloserCountsAsSetNow() throws {
    var task = try withDependencies { $0.date.now = instant("2026-10-01T12:00:00-04:00") } operation: {
      try addTask(due: "2026-12-01T00:00:00-05:00")
    }
    task.dueDate = instant("2026-10-21T00:00:00-04:00")
    try database.write { try $0.updateCareTask(task) }
    #expect(try plan() == [reminder(.advance, "2026-10-20T09:00:00-04:00"), reminder(.due, "2026-10-21T09:00:00-04:00")])
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
    #expect(try plan() == [])
    try withDependencies { $0.date.now = instant("2027-01-15T12:00:00-05:00") } operation: {
      let later = try plan()
      #expect(later == [reminder(.advance, "2027-01-16T09:00:00-05:00"), reminder(.due, "2027-01-19T09:00:00-05:00")])
    }
  }

  /// Six Meals a day make 84 Meal Reminders over the week, more than iOS keeps, so the plan keeps the soonest 64:
  /// the Flea treatment's Care Reminders, but not the Checkup's.
  @Test func thePlanNeverExceeds64AndKeepsTheSoonest() throws {
    @Dependency(\.uuid) var uuid
    let pate = try database.write { try $0.addFood(name: "Tuna pâté", servingUnit: .can, kcalPerUnit: 80, isTreat: false, isFreeFed: false) }
    let meals = [7, 10, 13, 16, 19, 22].map { Meal(id: uuid(), catID: cat.id, minuteOfDay: $0 * 60, foodID: pate.id, amount: 0.5) }
    try database.write { try $0.saveMeals(meals, for: cat.id) }
    try addTask("Flea treatment", due: "2026-10-21T00:00:00-04:00")
    // Inside the window, but past the cut.
    try addTask("Checkup", due: "2026-11-10T00:00:00-05:00")

    let reminders = try database.read { try $0.reminders(careTiming: .default) }
    #expect(reminders.count == Reminder.limit)
    #expect(reminders.map(\.date) == reminders.map(\.date).sorted())
    #expect(try plan() == [reminder(.advance, "2026-10-20T09:00:00-04:00"), reminder(.due, "2026-10-21T09:00:00-04:00")])
    // 8 left today, 12 a day on the 20th–23rd and the Flea treatment's 2 make 58; the 24th's first 6 end at 13:30.
    #expect(reminders.last?.date == instant("2026-10-24T13:30:00-04:00"))
  }

  /// Settings keeps the timing under one key.
  @Test func aTimingSurvivesBeingStored() {
    let timing = CareReminder.Timing(daysBefore: 7, minuteOfDay: 18 * 60 + 30)
    #expect(timing.rawValue == "7 1110")
    #expect(CareReminder.Timing(rawValue: "7 1110") == timing)
    let changed = CareReminder.Timing(daysBefore: 7, minuteOfDay: 18 * 60 + 30, lengthenedAt: instant("2026-10-19T11:00:00-04:00"))
    #expect(changed.rawValue == "7 1110 1792422000.0")
    #expect(CareReminder.Timing(rawValue: "7 1110 1792422000.0") == changed)
    #expect(CareReminder.Timing(rawValue: "") == nil)
    #expect(CareReminder.Timing(rawValue: "3.5 540") == nil)
    #expect(CareReminder.Timing(rawValue: "3 540 soon") == nil)
  }
}
