import Dependencies
import Foundation
import SQLiteData

/// A notification the owner should get for one Meal on one day: at its time, then once more if it's still unfed.
public struct MealReminder: Equatable, Identifiable, Sendable {
  public enum Kind: String, Sendable {
    case due
    case followUp
  }

  public var kind: Kind
  public var date: Date
  public var meal: Meal
  public var catName: String
  public var food: Food

  /// Stable for the same Meal, day and kind, so a reminder that didn't change keeps its identity.
  public var id: String { "\(kind.rawValue)-\(meal.id)-\(Int(date.timeIntervalSince1970))" }

  /// A follow-up comes this long after its Meal, unless the Meal was fulfilled by then.
  public static let followUpDelay: TimeInterval = 30 * 60
  /// How many days ahead, today included, the plan covers.
  public static let days = 7
}

extension Database {
  /// The reminder plan: every reminder still to come, soonest first, over the next ``MealReminder/days`` days.
  /// Meals already fulfilled, and Meals of free-fed Foods, get none.
  public func mealReminders() throws -> [MealReminder] {
    @Dependency(\.calendar) var calendar
    @Dependency(\.date.now) var now
    let cats = Dictionary(uniqueKeysWithValues: try Cat.all.fetchAll(self).map { ($0.id, $0) })
    let foods = Dictionary(uniqueKeysWithValues: try Food.all.fetchAll(self).map { ($0.id, $0) })
    let feedings = try Feeding.where { $0.mealID.isNot(nil) && $0.date >= now.addingTimeInterval(-2 * Meal.window) }
      .fetchAll(self)
    var reminders: [MealReminder] = []
    for meal in try Meal.all.fetchAll(self) {
      guard let cat = cats[meal.catID], let food = foods[meal.foodID], !food.isFreeFed else { continue }
      for offset in 0..<MealReminder.days {
        let time = meal.time(on: calendar.date(byAdding: .day, value: offset, to: now)!, calendar: calendar)
        guard !feedings.contains(where: { $0.fulfils(meal, at: time) }) else { continue }
        for (kind, date) in [(MealReminder.Kind.due, time), (.followUp, time.addingTimeInterval(MealReminder.followUpDelay))]
        where date > now {
          reminders.append(MealReminder(kind: kind, date: date, meal: meal, catName: cat.name, food: food))
        }
      }
    }
    return reminders.sorted { $0.date < $1.date }
  }

  /// "Fed ✓" on a reminder: logs the Meal's default Feeding now. Nil, logging nothing, when the Meal is gone or
  /// already fulfilled, such as Fed ✓ tapped again on a follow-up still on screen.
  @discardableResult
  public func logFeeding(forMeal mealID: Meal.ID) throws -> Feeding? {
    @Dependency(\.calendar) var calendar
    @Dependency(\.date.now) var now
    guard let meal = try Meal.find(mealID).fetchOne(self) else { return nil }
    let time = meal.time(nearest: now, calendar: calendar)
    let window = (time.addingTimeInterval(-Meal.window), time.addingTimeInterval(Meal.window))
    let fulfilled = try Feeding.where { $0.mealID.eq(mealID) && $0.date >= window.0 && $0.date <= window.1 }.fetchCount(self) > 0
    guard !fulfilled else { return nil }
    return try logFeeding(catID: meal.catID, foodID: meal.foodID, amount: meal.amount, at: now)
  }
}
