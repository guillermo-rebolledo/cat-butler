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

  /// How many days ahead, today included, the plan covers.
  // ponytail: the plan only moves on when the app opens or Fed ✓ runs, so reminders stop if the app isn't opened for
  // this long (less with many Meals, as iOS keeps 64); a background app refresh task would keep it going.
  public static let days = 7
  /// iOS keeps at most this many pending notifications per app.
  public static let limit = 64
}

extension Database {
  /// The reminder plan: Meal and Care Reminders over the next ``Reminder/days`` days, soonest first, cut to the
  /// ``Reminder/limit`` iOS keeps.
  public func reminders(careTiming: CareReminder.Timing) throws -> [Reminder] {
    let all = try mealReminders().map(Reminder.meal) + careReminders(timing: careTiming).map(Reminder.care)
    return Array(all.sorted { $0.date < $1.date }.prefix(Reminder.limit))
  }
}
