import Dependencies
import Foundation
import SQLiteData

/// A Care Reminder: a notification for a Care Task, some days ahead so there's time to book the vet, or on its due date.
public struct CareReminder: Equatable, Identifiable, Sendable {
  public enum Kind: String, Sendable {
    case advance
    case due
  }

  /// When a Care Task's reminders fire, set in Settings.
  public struct Timing: Hashable, Sendable {
    /// How many days before the due date the advance reminder comes.
    public var daysBefore: Int
    /// The time of day both reminders fire, in minutes after midnight.
    public var minuteOfDay: Int
    /// When the owner last moved advance reminders further ahead, which can move one still to come into the past.
    public var lengthenedAt: Date?

    public init(daysBefore: Int, minuteOfDay: Int, lengthenedAt: Date? = nil) {
      self.daysBefore = daysBefore
      self.minuteOfDay = minuteOfDay
      self.lengthenedAt = lengthenedAt
    }

    public static let `default` = Timing(daysBefore: 3, minuteOfDay: 9 * 60)
  }

  public var kind: Kind
  /// When it fires.
  public var date: Date
  public var task: CareTask
  public var catName: String

  /// Stable for the same task, kind and time, so a reminder that didn't change keeps its identity.
  public var id: String { "care-\(kind.rawValue)-\(task.id)-\(Int(date.timeIntervalSince1970))" }

  /// How many days ahead, today included, the plan covers. Further than Meals': Care Tasks are few, so vet reminders
  /// keep coming for weeks even if the app isn't opened.
  public static let days = 30
}

/// Stored as "3 540", then the time it changed, so Settings can keep it under one key.
extension CareReminder.Timing: RawRepresentable {
  public init?(rawValue: String) {
    let parts = rawValue.split(separator: " ")
    guard parts.count == 2 || parts.count == 3, let daysBefore = Int(parts[0]), let minuteOfDay = Int(parts[1]) else {
      return nil
    }
    var lengthenedAt: Date?
    if parts.count == 3 {
      guard let seconds = Double(parts[2]) else { return nil }
      lengthenedAt = Date(timeIntervalSince1970: seconds)
    }
    self.init(daysBefore: daysBefore, minuteOfDay: minuteOfDay, lengthenedAt: lengthenedAt)
  }

  public var rawValue: String {
    "\(daysBefore) \(minuteOfDay)" + (lengthenedAt.map { " \($0.timeIntervalSince1970)" } ?? "")
  }
}

extension Database {
  /// The plan's Care Reminders: every one still to come over the next ``CareReminder/days`` days. Overdue tasks and
  /// done one-off tasks get none. A due date set, or advance reminders moved further ahead, after the advance reminder's
  /// time, e.g. a task added 2 days ahead, gets that reminder at the next reminder time instead, if that's still before
  /// the due date.
  // ponytail: changing the days before, a later time of day, or a due date moved back by deleting a Care Record, after
  // an advance reminder came can bring it again; noting which went out would stop that.
  func careReminders(timing: CareReminder.Timing) throws -> [CareReminder] {
    @Dependency(\.calendar) var calendar
    @Dependency(\.date.now) var now
    let cats = Dictionary(uniqueKeysWithValues: try Cat.inCare.fetchAll(self).map { ($0.id, $0) })
    let end = calendar.date(byAdding: .day, value: CareReminder.days, to: calendar.startOfDay(for: now))!
    let recorded = Set(try CareRecord.select(\.careTaskID).fetchAll(self))
    var reminders: [CareReminder] = []
    for task in try CareTask.all.fetchAll(self) {
      guard let cat = cats[task.catID], task.interval != nil || !recorded.contains(task.id) else { continue }
      let due = calendar.date(atMinuteOfDay: timing.minuteOfDay, on: task.dueDate)
      let advanceDay = calendar.date(byAdding: .day, value: -timing.daysBefore, to: task.dueDate)!
      let usual = calendar.date(atMinuteOfDay: timing.minuteOfDay, on: advanceDay)
      let setAt = [task.dueDateSetAt, timing.lengthenedAt].compactMap(\.self).max()
      let advance = setAt.map { usual <= $0 ? nextReminderTime(after: $0, timing: timing, calendar: calendar) : usual } ?? usual
      // On the due date itself, the due reminder covers it.
      let isAdvanceBeforeDueDate = calendar.startOfDay(for: advance) < calendar.startOfDay(for: task.dueDate)
      for (kind, date) in [(CareReminder.Kind.advance, advance), (.due, due)] {
        guard date > now, date < end, kind == .due || isAdvanceBeforeDueDate else { continue }
        reminders.append(CareReminder(kind: kind, date: date, task: task, catName: cat.name))
      }
    }
    return reminders
  }

  private func nextReminderTime(after date: Date, timing: CareReminder.Timing, calendar: Calendar) -> Date {
    let sameDay = calendar.date(atMinuteOfDay: timing.minuteOfDay, on: date)
    return sameDay > date
      ? sameDay : calendar.date(atMinuteOfDay: timing.minuteOfDay, on: calendar.date(byAdding: .day, value: 1, to: date)!)
  }
}
