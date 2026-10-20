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
struct MealReminderTests {
  @Dependency(\.defaultDatabase) var database
  let cat: Cat
  let pate: Food

  init() throws {
    @Dependency(\.defaultDatabase) var database
    (cat, pate) = try database.write { db in
      (
        try db.addCat(name: "Miso", photo: nil, birthdate: instant("2026-06-01T00:00:00-04:00"), isNeutered: false, weight: Measurement(value: 2, unit: .kilograms)),
        try db.addFood(name: "Tuna pâté", servingUnit: .can, kcalPerUnit: 80, isTreat: false, isFreeFed: false)
      )
    }
  }

  func meal(at minuteOfDay: Int, food: Food? = nil) -> Meal {
    @Dependency(\.uuid) var uuid
    return Meal(id: uuid(), catID: cat.id, minuteOfDay: minuteOfDay, foodID: (food ?? pate).id, amount: 0.5)
  }

  func save(_ meals: Meal...) throws {
    try database.write { try $0.saveMeals(meals, for: cat.id) }
  }

  /// The plan up to the end of tomorrow, as "kind instant".
  func plan() throws -> [String] {
    try database.read { try $0.mealReminders() }
      .filter { $0.date < instant("2026-10-21T00:00:00-04:00") }
      .map { "\($0.kind) \($0.date)" }
  }

  func reminder(_ kind: MealReminder.Kind, _ iso8601: String) -> String {
    "\(kind) \(instant(iso8601))"
  }

  @Test func eachMealGetsAReminderAndAFollowUpHalfAnHourLater() throws {
    try save(meal(at: 18 * 60))
    #expect(try plan() == [
      reminder(.due, "2026-10-19T18:00:00-04:00"), reminder(.followUp, "2026-10-19T18:30:00-04:00"),
      reminder(.due, "2026-10-20T18:00:00-04:00"), reminder(.followUp, "2026-10-20T18:30:00-04:00"),
    ])
  }

  @Test func loggingAFeedingRemovesThatMealsFollowUp() throws {
    let dinner = meal(at: 18 * 60)
    try save(dinner)
    try withDependencies { $0.date.now = instant("2026-10-19T18:10:00-04:00") } operation: {
      #expect(try plan().first == reminder(.followUp, "2026-10-19T18:30:00-04:00"))
      try database.write { _ = try $0.logFeeding(catID: cat.id, foodID: pate.id, amount: 0.5, at: instant("2026-10-19T18:10:00-04:00")) }
      #expect(try plan() == [reminder(.due, "2026-10-20T18:00:00-04:00"), reminder(.followUp, "2026-10-20T18:30:00-04:00")])
    }
  }

  @Test func freeFedFoodsProduceNoReminders() throws {
    let kibble = try database.write { try $0.addFood(name: "Kibble", servingUnit: .gram, kcalPerUnit: 3.8, isTreat: false, isFreeFed: true) }
    try save(meal(at: 18 * 60, food: kibble))
    try database.write { _ = try $0.logFeeding(catID: cat.id, foodID: kibble.id, amount: 20, at: instant("2026-10-19T11:00:00-04:00")) }
    #expect(try plan() == [])
  }

  @Test func editingAMealsTimeMovesItsReminder() throws {
    var dinner = meal(at: 18 * 60)
    try save(dinner)
    dinner.minuteOfDay = 19 * 60
    try save(dinner)
    #expect(try plan() == [
      reminder(.due, "2026-10-19T19:00:00-04:00"), reminder(.followUp, "2026-10-19T19:30:00-04:00"),
      reminder(.due, "2026-10-20T19:00:00-04:00"), reminder(.followUp, "2026-10-20T19:30:00-04:00"),
    ])
  }

  @Test func aMealJustPastStillGetsItsFollowUp() throws {
    try save(meal(at: 11 * 60 + 45))
    #expect(try plan() == [
      reminder(.followUp, "2026-10-19T12:15:00-04:00"),
      reminder(.due, "2026-10-20T11:45:00-04:00"), reminder(.followUp, "2026-10-20T12:15:00-04:00"),
    ])
  }

  @Test func thePlanCoversAWeek() throws {
    try save(meal(at: 18 * 60))
    let reminders = try database.read { try $0.mealReminders() }
    #expect(reminders.count == 2 * MealReminder.days)
    #expect(reminders.last?.date == instant("2026-10-25T18:30:00-04:00"))
  }

  @Test func fedLogsTheMealsDefaultFeedingNow() throws {
    let dinner = meal(at: 18 * 60)
    try save(dinner)
    try withDependencies { $0.date.now = instant("2026-10-19T18:05:00-04:00") } operation: {
      let feeding = try database.write { try $0.logFeeding(forMeal: dinner.id, at: instant("2026-10-19T18:00:00-04:00")) }
      #expect(feeding?.mealID == dinner.id)
      #expect(feeding?.foodID == pate.id)
      #expect(feeding?.amount == 0.5)
      #expect(feeding?.date == instant("2026-10-19T18:05:00-04:00"))
    }
  }

  /// Fed ✓ on the reminder, then again on a follow-up still on screen, logs one Feeding.
  @Test func fedTwiceLogsOneFeeding() throws {
    let dinner = meal(at: 18 * 60)
    try save(dinner)
    try withDependencies { $0.date.now = instant("2026-10-19T18:35:00-04:00") } operation: {
      try database.write { _ = try $0.logFeeding(forMeal: dinner.id, at: instant("2026-10-19T18:00:00-04:00")) }
      #expect(try database.write { try $0.logFeeding(forMeal: dinner.id, at: instant("2026-10-19T18:00:00-04:00")) } == nil)
      #expect(try database.read { try Feeding.fetchCount($0) } == 1)
    }
  }

  /// Fed ✓ tapped long after the reminder, from Notification Center: the Meal was fed, just not logged.
  @Test func fedAfterTheWindowLogsAtTheMealsTime() throws {
    let dinner = meal(at: 18 * 60)
    try save(dinner)
    try withDependencies { $0.date.now = instant("2026-10-20T00:30:00-04:00") } operation: {
      let feeding = try database.write { try $0.logFeeding(forMeal: dinner.id, at: instant("2026-10-19T18:00:00-04:00")) }
      #expect(feeding?.date == instant("2026-10-19T18:00:00-04:00"))
      #expect(feeding?.mealID == dinner.id)
    }
  }
}
