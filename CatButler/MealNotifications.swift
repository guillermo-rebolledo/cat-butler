import CatButlerCore
import SQLiteData
import UserNotifications

/// Keeps iOS's pending notifications in line with the core's reminder plan, and logs a Feeding on "Fed ✓".
final class MealNotifications: NSObject, UNUserNotificationCenterDelegate, Sendable {
  static let shared = MealNotifications()
  private static let category = "meal"
  private static let fedAction = "fed"
  private static let mealIDKey = "mealID"
  private static let mealTimeKey = "mealTime"
  /// iOS keeps at most this many pending notifications per app.
  private static let limit = 64

  /// At launch, before the app finishes launching, so "Fed ✓" reaches us when it launches the app in the background.
  func start() {
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    center.setNotificationCategories([
      UNNotificationCategory(
        identifier: Self.category, actions: [UNNotificationAction(identifier: Self.fedAction, title: String(localized: "Fed ✓"))],
        intentIdentifiers: []
      )
    ])
  }

  /// First-run step 3, and at launch for a schedule made before reminders existed. Asks once; afterwards iOS answers
  /// with the owner's choice.
  func requestPermission() async {
    // UI tests can't dismiss the system alert.
    guard !ProcessInfo.processInfo.arguments.contains("-ui-testing") else { return }
    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
  }

  /// Replaces every pending notification with the plan's. On the main actor, so two syncs can't interleave.
  // ponytail: replaces all of them on each change; diff against the pending ones if that ever shows up as churn.
  @MainActor func schedule(_ plan: [MealReminder]) {
    let center = UNUserNotificationCenter.current()
    center.removeAllPendingNotificationRequests()
    for reminder in plan.prefix(Self.limit) {
      center.add(request(for: reminder), withCompletionHandler: nil)
    }
  }

  /// Opening the app shows where every Meal stands, so reminders already on screen go.
  func clearDelivered() {
    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
  }

  /// Rereads the plan, for when no screen is watching the database: "Fed ✓" in the background.
  @MainActor func reschedule() {
    @Dependency(\.defaultDatabase) var database
    withErrorReporting { schedule(try database.read { try $0.mealReminders() }) }
  }

  private func request(for reminder: MealReminder) -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    let amount = reminder.food.amountText(reminder.meal.amount)
    switch reminder.kind {
    case .due:
      content.title = String(localized: "Time to feed \(reminder.catName)")
      content.body = amount
    case .followUp:
      content.title = String(localized: "Has \(reminder.catName) been fed?")
      let time = reminder.mealTime.formatted(date: .omitted, time: .shortened)
      content.body = String(localized: "The \(time) Meal isn't logged yet: \(amount).")
    }
    content.sound = .default
    content.categoryIdentifier = Self.category
    content.userInfo = [Self.mealIDKey: reminder.meal.id.uuidString, Self.mealTimeKey: reminder.mealTime.timeIntervalSince1970]
    @Dependency(\.calendar) var calendar
    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.date)
    return UNNotificationRequest(
      identifier: reminder.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    )
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
    guard response.actionIdentifier == Self.fedAction,
      let id = response.notification.request.content.userInfo[Self.mealIDKey] as? String,
      let mealID = UUID(uuidString: id),
      let mealTime = response.notification.request.content.userInfo[Self.mealTimeKey] as? TimeInterval
    else { return }
    @Dependency(\.defaultDatabase) var database
    await withErrorReporting {
      try await database.write { try $0.logFeeding(forMeal: mealID, at: Date(timeIntervalSince1970: mealTime)) }
    }
    await reschedule()
  }

  /// Shows reminders while the app is open too.
  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
    -> UNNotificationPresentationOptions
  {
    [.banner, .list, .sound]
  }
}
