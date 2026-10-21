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

    public init(daysBefore: Int, minuteOfDay: Int) {
      self.daysBefore = daysBefore
      self.minuteOfDay = minuteOfDay
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
}

/// Stored as "3 540", so Settings can keep it under one key.
extension CareReminder.Timing: RawRepresentable {
  public init?(rawValue: String) {
    let parts = rawValue.split(separator: " ").compactMap { Int($0) }
    guard parts.count == 2 else { return nil }
    self.init(daysBefore: parts[0], minuteOfDay: parts[1])
  }

  public var rawValue: String { "\(daysBefore) \(minuteOfDay)" }
}

extension Database {
  /// The plan's Care Reminders: every one still to come over the next ``Reminder/days`` days. Overdue tasks and done
  /// one-off tasks get none. A due date set after its advance reminder's time, e.g. 2 days ahead, gets that reminder at
  /// the next reminder time instead, if that's still before the due date.
  func careReminders(timing: CareReminder.Timing) throws -> [CareReminder] {
    @Dependency(\.calendar) var calendar
    @Dependency(\.date.now) var now
    let cats = Dictionary(uniqueKeysWithValues: try Cat.all.fetchAll(self).map { ($0.id, $0) })
    let end = calendar.date(byAdding: .day, value: Reminder.days, to: calendar.startOfDay(for: now))!
    let recorded = Set(try CareRecord.select(\.careTaskID).fetchAll(self))
    var reminders: [CareReminder] = []
    for task in try CareTask.all.fetchAll(self) {
      guard let cat = cats[task.catID], task.interval != nil || !recorded.contains(task.id) else { continue }
      let due = calendar.date(atMinuteOfDay: timing.minuteOfDay, on: task.dueDate)
      var advance = calendar.date(byAdding: .day, value: -timing.daysBefore, to: due)!
      if let setAt = task.dueDateSetAt, advance <= setAt {
        advance = calendar.date(atMinuteOfDay: timing.minuteOfDay, on: setAt)
        if advance <= setAt { advance = calendar.date(byAdding: .day, value: 1, to: advance)! }
      }
      // On the due date itself, the due reminder covers it.
      let isAdvanceBeforeDueDate = calendar.startOfDay(for: advance) < calendar.startOfDay(for: task.dueDate)
      for (kind, date) in [(CareReminder.Kind.advance, advance), (.due, due)] {
        guard date > now, date < end, kind == .due || isAdvanceBeforeDueDate else { continue }
        reminders.append(CareReminder(kind: kind, date: date, task: task, catName: cat.name))
      }
    }
    return reminders
  }
}
