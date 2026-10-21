import Foundation
import SQLiteData

/// One notification in the reminder plan: a Meal Reminder or a Care Reminder.
public enum Reminder: Equatable, Identifiable, Sendable {
  case meal(MealReminder)
  case care(CareReminder)

  public var date: Date {
    switch self {
    case .meal(let reminder): reminder.date
    case .care(let reminder): reminder.date
    }
  }

  public var id: String {
    switch self {
    case .meal(let reminder): reminder.id
    case .care(let reminder): reminder.id
    }
  }

  /// iOS keeps at most this many pending notifications per app.
  // ponytail: with many Meals the cut can drop a Care Reminder weeks ahead until the plan moves on, which takes the
  // app being opened; see ``MealReminder/days``.
  public static let limit = 64
}

extension Database {
  /// The reminder plan: Meal Reminders over the next ``MealReminder/days`` days and every Care Reminder to come,
  /// soonest first, cut to the ``Reminder/limit`` iOS keeps.
  public func reminders(careTiming: CareReminder.Timing) throws -> [Reminder] {
    let all = try mealReminders().map(Reminder.meal) + careReminders(timing: careTiming).map(Reminder.care)
    return Array(all.sorted { $0.date < $1.date }.prefix(Reminder.limit))
  }
}
