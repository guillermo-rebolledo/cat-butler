import Dependencies
import Foundation
import SQLiteData

/// A Meal Reminder: a notification for one Meal on one day, at its time or as the follow-up if it's still unfulfilled.
public struct MealReminder: Equatable, Identifiable, Sendable {
  public enum Kind: String, Sendable {
    case due
    case followUp
  }

  public var kind: Kind
  /// When it fires.
  public var date: Date
  /// The Meal on that day, which "Fed ✓" logs.
  public var mealTime: Date
  public var meal: Meal
  public var catName: String
  public var food: Food

  /// Stable for the same Meal, day and kind, so a reminder that didn't change keeps its identity.
  public var id: String { "\(kind.rawValue)-\(meal.id)-\(Int(date.timeIntervalSince1970))" }

  /// A follow-up comes this long after its Meal, unless the Meal was fulfilled by then.
  public static let followUpDelay: TimeInterval = 30 * 60
  /// How many days ahead, today included, the plan covers.
  // ponytail: the plan only moves on when the app opens or Fed ✓ runs, so reminders stop if the app isn't opened for
  // this long (less with many Meals, as iOS keeps 64); a background app refresh task would keep it going.
  public static let days = 7
}

extension Database {
  /// The plan's Meal Reminders: every one still to come, soonest first, over the next ``MealReminder/days`` days.
  /// Meals already fulfilled, and Meals of free-fed Foods, get none.
  public func mealReminders() throws -> [MealReminder] {
    @Dependency(\.calendar) var calendar
    @Dependency(\.date.now) var now
    let cats = Dictionary(uniqueKeysWithValues: try Cat.all.fetchAll(self).map { ($0.id, $0) })
    let foods = Dictionary(uniqueKeysWithValues: try Food.all.fetchAll(self).map { ($0.id, $0) })
    // The earliest Meal with a reminder left is a follow-up away; Feedings before its window can't fulfil it.
    let earliest = now.addingTimeInterval(-MealReminder.followUpDelay - Meal.window)
    let feedings = try Feeding.where { $0.mealID.isNot(nil) && $0.date >= earliest }.fetchAll(self)
    var reminders: [MealReminder] = []
    for meal in try Meal.all.fetchAll(self) {
      guard let cat = cats[meal.catID], let food = foods[meal.foodID], !food.isFreeFed else { continue }
      // From yesterday: last night's late Meal can still have its follow-up to come after midnight.
      for offset in -1..<MealReminder.days {
        let time = meal.time(on: calendar.date(byAdding: .day, value: offset, to: now)!, calendar: calendar)
        guard !feedings.contains(where: { $0.fulfils(meal, at: time) }) else { continue }
        for (kind, date) in [(MealReminder.Kind.due, time), (.followUp, time.addingTimeInterval(MealReminder.followUpDelay))]
        where date > now {
          reminders.append(MealReminder(kind: kind, date: date, mealTime: time, meal: meal, catName: cat.name, food: food))
        }
      }
    }
    return reminders.sorted { $0.date < $1.date }
  }

  /// "Fed ✓" on the reminder for `mealTime`, the Meal on one day: logs the Meal's default Feeding now, or at the Meal's
  /// time once its window has passed, since it was fed and only not logged. Nil, logging nothing, when the Meal is
  /// gone or that day's is already fulfilled, such as Fed ✓ tapped again on a follow-up still on screen.
  @discardableResult
  public func logFeeding(forMeal mealID: Meal.ID, at mealTime: Date) throws -> Feeding? {
    @Dependency(\.date.now) var now
    guard let meal = try Meal.find(mealID).fetchOne(self) else { return nil }
    let window = mealTime.addingTimeInterval(-Meal.window)...mealTime.addingTimeInterval(Meal.window)
    let feedings = try Feeding.where { $0.mealID.eq(mealID) && $0.date >= window.lowerBound }.fetchAll(self)
    guard !feedings.contains(where: { $0.fulfils(meal, at: mealTime) }) else { return nil }
    return try logFeeding(catID: meal.catID, foodID: meal.foodID, amount: meal.amount, at: window.contains(now) ? now : mealTime)
  }
}
