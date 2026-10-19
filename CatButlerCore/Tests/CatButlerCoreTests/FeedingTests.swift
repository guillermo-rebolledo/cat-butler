import CatButlerCore
import Dependencies
import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

/// "2026-10-19T08:00:00-04:00" → that instant.
func instant(_ iso8601: String) -> Date {
  try! Date(iso8601, strategy: .iso8601)
}

func calendar(in timeZone: String) -> Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: timeZone)!
  return calendar
}

@Suite(
  .dependency(\.date.now, instant("2026-10-19T12:00:00-04:00")),
  .dependency(\.uuid, .incrementing),
  .dependency(\.calendar, calendar(in: "America/New_York")),
  .dependencies { $0.defaultDatabase = try appDatabase() }
)
struct FeedingTests {
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

  /// Saves Meals for Miso at the given "HH:mm" times, each ½ can of pâté.
  @discardableResult
  func schedule(_ times: String...) throws -> [Meal] {
    @Dependency(\.uuid) var uuid
    let meals = times.map { time in
      let parts = time.split(separator: ":").map { Int($0)! }
      return Meal(id: uuid(), catID: cat.id, minuteOfDay: parts[0] * 60 + parts[1], foodID: pate.id, amount: 0.5)
    }
    try database.write { try $0.saveMeals(meals, for: cat.id) }
    return meals
  }

  @discardableResult
  func log(at iso8601: String, food: Food? = nil) throws -> Feeding {
    try database.write { try $0.logFeeding(catID: cat.id, foodID: (food ?? pate).id, amount: 0.5, at: instant(iso8601)) }
  }

  func today() throws -> FeedingDay {
    try database.read { try $0.feedingDay(for: cat.id) }
  }

  @Test func aFeedingNearAMealFulfilsIt() throws {
    let breakfast = try schedule("08:00")[0]
    let feeding = try log(at: "2026-10-19T08:10:00-04:00")
    #expect(feeding.mealID == breakfast.id)
    #expect(try today().meals.map(\.state) == [.done(feeding)])
    #expect(try today().offSchedule == [])
  }

  @Test(arguments: ["2026-10-19T06:00:00-04:00", "2026-10-19T10:00:00-04:00"])
  func exactlyTwoHoursAwayStillFulfils(_ time: String) throws {
    let breakfast = try schedule("08:00")[0]
    #expect(try log(at: time).mealID == breakfast.id)
  }

  @Test(arguments: ["2026-10-19T05:59:59-04:00", "2026-10-19T10:00:01-04:00"])
  func moreThanTwoHoursAwayIsOffSchedule(_ time: String) throws {
    try schedule("08:00")
    let feeding = try log(at: time)
    #expect(feeding.mealID == nil)
    #expect(try today().offSchedule == [feeding])
  }

  @Test func twoNearbyMealsCompeteForOneFeeding() throws {
    let meals = try schedule("08:00", "09:00")
    // 20 minutes from 09:00 beats 40 from 08:00.
    let first = try log(at: "2026-10-19T08:40:00-04:00")
    #expect(first.mealID == meals[1].id)
    // 09:00 is taken, so the next Feeding fulfils 08:00 even though 09:00 is nearer.
    let second = try log(at: "2026-10-19T08:50:00-04:00")
    #expect(second.mealID == meals[0].id)
    // Nothing is left to fulfil.
    #expect(try log(at: "2026-10-19T08:55:00-04:00").mealID == nil)
  }

  @Test func equallyNearMealsGoToTheEarlierOne() throws {
    let meals = try schedule("09:00", "08:00")
    #expect(try log(at: "2026-10-19T08:30:00-04:00").mealID == meals[1].id)
  }

  @Test func backdatingAnEarlierFeedingRematchesLaterOnes() throws {
    let meals = try schedule("08:00", "09:00")
    let later = try log(at: "2026-10-19T08:50:00-04:00")
    #expect(later.mealID == meals[1].id)

    // Logged afterwards but given earlier: it is matched first and takes 09:00 as the nearer Meal.
    let backdated = try log(at: "2026-10-19T08:40:00-04:00")
    #expect(backdated.mealID == meals[1].id)
    #expect(try database.read { try Feeding.find(later.id).fetchOne($0) }?.mealID == meals[0].id)
  }

  @Test func aMealIsMissedOnceItsWindowPasses() throws {
    try schedule("10:00", "11:00")
    // Now is 12:00: 10:00's window closed exactly now, 11:00's is still open.
    #expect(try today().meals.map(\.state) == [.upcoming, .upcoming])
    let aSecondLater = try withDependencies { $0.date.now = instant("2026-10-19T12:00:01-04:00") } operation: { try today() }
    #expect(aSecondLater.meals.map(\.state) == [.missed, .upcoming])
  }

  @Test func aLateFeedingStopsAMealBeingMissed() throws {
    try schedule("09:00")
    #expect(try today().meals.map(\.state) == [.missed])
    let feeding = try log(at: "2026-10-19T09:30:00-04:00")
    #expect(try today().meals.map(\.state) == [.done(feeding)])
  }

  @Test func freeFedFoodsNeverFulfilMeals() throws {
    try schedule("08:00")
    let kibble = try database.write { try $0.addFood(name: "Kibble", servingUnit: .gram, kcalPerUnit: 3.8, isTreat: false, isFreeFed: true) }
    let feeding = try log(at: "2026-10-19T08:00:00-04:00", food: kibble)
    #expect(feeding.mealID == nil)
    #expect(try today().meals.map(\.state) == [.missed])
    #expect(try today().offSchedule == [feeding])
  }

  @Test func movingAFeedingOutOfTheWindowUnfulfilsItsMeal() throws {
    try schedule("11:00")
    var feeding = try log(at: "2026-10-19T11:00:00-04:00")
    feeding.date = instant("2026-10-19T08:00:00-04:00")
    try database.write { try $0.updateFeeding(feeding) }
    let moved = try database.read { try Feeding.find(feeding.id).fetchOne($0) }!
    #expect(moved.mealID == nil)
    #expect(try today().meals.map(\.state) == [.upcoming])
    #expect(try today().offSchedule == [moved])
  }

  @Test func movingAFeedingLaterFreesItsMealForOthers() throws {
    let meals = try schedule("08:00", "09:00")
    var first = try log(at: "2026-10-19T08:40:00-04:00")
    let second = try log(at: "2026-10-19T08:50:00-04:00")
    first.date = instant("2026-10-19T11:30:00-04:00")
    try database.write { try $0.updateFeeding(first) }
    #expect(try database.read { try Feeding.find(second.id).fetchOne($0) }?.mealID == meals[1].id)
  }

  @Test func deletingAFeedingFreesItsMealForOthers() throws {
    let meals = try schedule("08:00", "09:00")
    let first = try log(at: "2026-10-19T08:40:00-04:00")
    let second = try log(at: "2026-10-19T08:50:00-04:00")
    #expect([first.mealID, second.mealID] == [meals[1].id, meals[0].id])

    try database.write { try $0.deleteFeeding(first.id) }
    let rematched = try database.read { try Feeding.find(second.id).fetchOne($0) }!
    #expect(rematched.mealID == meals[1].id)
    #expect(try today().meals.map(\.state) == [.missed, .done(rematched)])
  }

  @Test func aFeedingKeepsTheCaloriesItWasLoggedWith() throws {
    // ½ can at 80 kcal per can.
    var feeding = try log(at: "2026-10-19T08:00:00-04:00")
    #expect(feeding.kcal == 40)

    var pate = pate
    pate.kcalPerUnit = 100
    try database.write { try Food.update(pate).execute($0) }
    feeding.date = instant("2026-10-19T08:30:00-04:00")
    try database.write { try $0.updateFeeding(feeding) }
    #expect(try database.read { try Feeding.find(feeding.id).fetchOne($0) }?.kcal == 40)

    // A new amount is worth the Food's current calories.
    feeding.amount = 1
    try database.write { try $0.updateFeeding(feeding) }
    #expect(try database.read { try Feeding.find(feeding.id).fetchOne($0) }?.kcal == 100)
  }

  @Test func changingTheScheduleRematchesTodayButNotEarlierDays() throws {
    var breakfast = try schedule("08:00")[0]
    let yesterday = try log(at: "2026-10-18T08:00:00-04:00")
    let today = try log(at: "2026-10-19T10:30:00-04:00")
    #expect([yesterday.mealID, today.mealID] == [breakfast.id, nil])

    breakfast.minuteOfDay = 11 * 60
    try database.write { try $0.saveMeals([breakfast], for: cat.id) }
    let stored = try database.read { try Feeding.order(by: \.date).fetchAll($0) }.map(\.mealID)
    #expect(stored == [breakfast.id, breakfast.id])

    // Removing the Meal leaves its Feedings off-schedule.
    try database.write { try $0.saveMeals([], for: cat.id) }
    #expect(try self.today().offSchedule.map(\.id) == [today.id])
  }

  @Test func dayMeansTheLocalCalendarDay() throws {
    let lateMeal = try schedule("23:30")[0]
    let yesterday = try log(at: "2026-10-18T21:00:00-04:00")
    // Just after midnight: fulfils last night's 23:30, not tonight's.
    let afterMidnight = try log(at: "2026-10-19T00:30:00-04:00")
    let earlyToday = try log(at: "2026-10-19T03:00:00-04:00")
    #expect([yesterday.mealID, afterMidnight.mealID, earlyToday.mealID] == [nil, lateMeal.id, nil])
    // Off-schedule Feedings either side of midnight belong to their own day.
    let kibble = try database.write { try $0.addFood(name: "Kibble", servingUnit: .gram, kcalPerUnit: 3.8, isTreat: false, isFreeFed: true) }
    try log(at: "2026-10-18T23:00:00-04:00", food: kibble)
    let lastThingToday = try log(at: "2026-10-19T23:59:00-04:00", food: kibble)
    try log(at: "2026-10-20T00:00:00-04:00", food: kibble)
    #expect(try today().meals.map(\.state) == [.upcoming])
    #expect(try today().offSchedule == [earlyToday, lastThingToday])
  }

  @Test(arguments: [
    // Clocks went forward at 02:00 on 8 March 2026 and back at 02:00 on 1 November.
    ("2026-03-08T10:00:00-04:00", "2026-03-08T10:00:01-04:00"),
    ("2026-11-01T10:00:00-05:00", "2026-11-01T10:00:01-05:00"),
  ])
  func mealsKeepTheirWallClockTimeOverDaylightSavingChanges(lastUpcoming: String, firstMissed: String) throws {
    try schedule("08:00")
    let states = try [lastUpcoming, firstMissed].map { now in
      try withDependencies { $0.date.now = instant(now) } operation: { try today().meals.map(\.state) }
    }
    #expect(states == [[.upcoming], [.missed]])
  }

  @Test func afterATimeZoneChangeMealsFollowTheNewLocalTime() throws {
    let breakfast = try schedule("08:00")[0]
    #expect(try log(at: "2026-10-19T08:00:00-04:00").mealID == breakfast.id)

    // 12:00 in New York is 01:00 the next day in Tokyo.
    try withDependencies { $0.calendar = calendar(in: "Asia/Tokyo") } operation: {
      let day = try today()
      #expect(day.meals.map(\.time) == [instant("2026-10-20T08:00:00+09:00")])
      #expect(day.meals.map(\.state) == [.upcoming])
      #expect(day.offSchedule == [])
      #expect(try log(at: "2026-10-20T08:05:00+09:00").mealID == breakfast.id)
    }
  }

  @Test func kittensAreOfferedFourMealsAndOlderCatsTwo() {
    #expect(Meal.suggestedMinutesOfDay(for: .kitten).count == 4)
    #expect(Meal.suggestedMinutesOfDay(for: .adult) == [8 * 60, 18 * 60])
    #expect(Meal.suggestedMinutesOfDay(for: .senior) == [8 * 60, 18 * 60])
  }
}
