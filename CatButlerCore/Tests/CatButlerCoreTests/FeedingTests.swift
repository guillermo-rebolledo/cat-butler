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

  /// Saves Meals for Miso at the given "HH:mm" times, each ½ can of pâté. By default they were saved
  /// long ago, so today's earlier times can be Missed.
  @discardableResult
  func schedule(_ times: String..., savedAt: String = "2026-01-01T00:00:00-05:00") throws -> [Meal] {
    @Dependency(\.uuid) var uuid
    let meals = times.map { time in
      let parts = time.split(separator: ":").map { Int($0)! }
      return Meal(id: uuid(), catID: cat.id, minuteOfDay: parts[0] * 60 + parts[1], foodID: pate.id, amount: 0.5)
    }
    try save(meals, at: savedAt)
    return meals
  }

  func save(_ meals: [Meal], at iso8601: String) throws {
    try withDependencies { $0.date.now = instant(iso8601) } operation: {
      try database.write { try $0.saveMeals(meals, for: cat.id) }
    }
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
    #expect(try today().otherFeedings == [])
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
    #expect(try today().otherFeedings == [feeding])
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

  @Test func aMealAddedAfterItsWindowPassedIsntMissedUntilTomorrow() throws {
    try schedule("08:00", "11:00", savedAt: "2026-10-19T12:00:00-04:00")
    #expect(try today().meals.map(\.state) == [.startsTomorrow, .upcoming])
    let tomorrow = try withDependencies { $0.date.now = instant("2026-10-20T13:00:01-04:00") } operation: { try today() }
    #expect(tomorrow.meals.map(\.state) == [.missed, .missed])
  }

  @Test(arguments: ["2026-10-19T06:00:00-04:00", "2026-10-19T12:00:00-04:00"])
  func aMealAddedBeforeItsWindowEndsCanBeMissed(savedAt: String) throws {
    try schedule("11:00", savedAt: savedAt)
    let afterTheWindow = try withDependencies { $0.date.now = instant("2026-10-19T13:00:01-04:00") } operation: { try today() }
    #expect(afterTheWindow.meals.map(\.state) == [.missed])
  }

  @Test func aBackdatedFeedingStillFulfilsAMealAddedLater() throws {
    try schedule("08:00", savedAt: "2026-10-19T12:00:00-04:00")
    let feeding = try log(at: "2026-10-19T08:00:00-04:00")
    #expect(try today().meals.map(\.state) == [.done(feeding)])
  }

  @Test func movingAMealThatWasntDueYetStartsItAgain() throws {
    var meals = try schedule("08:00", "09:00", "18:00")
    meals[0].amount = 1
    // 09:00 was already Missed: nudging it doesn't hide that.
    meals[1].minuteOfDay = 9 * 60 + 15
    meals[2].minuteOfDay = 9 * 60 + 30
    try save(meals, at: "2026-10-19T12:00:00-04:00")
    #expect(try today().meals.map(\.state) == [.missed, .missed, .startsTomorrow])
  }

  @Test func aMealStartingTomorrowStillDoesWhenMovedToAnotherPassedTime() throws {
    var meal = try schedule("08:00", savedAt: "2026-10-19T12:00:00-04:00")[0]
    meal.minuteOfDay = 10 * 60 + 30
    try save([meal], at: "2026-10-19T12:45:00-04:00")
    let day = try withDependencies { $0.date.now = instant("2026-10-19T12:45:00-04:00") } operation: { try today() }
    #expect(day.meals.map(\.state) == [.startsTomorrow])
  }

  @Test func aFedMealMovedAwayFromItsFeedingIsntMissed() throws {
    var meal = try schedule("07:00")[0]
    try log(at: "2026-10-19T07:00:00-04:00")
    meal.minuteOfDay = 10 * 60
    try save([meal], at: "2026-10-19T12:45:00-04:00")
    let day = try withDependencies { $0.date.now = instant("2026-10-19T12:45:00-04:00") } operation: { try today() }
    #expect(day.meals.map(\.state) == [.startsTomorrow])
  }

  @Test func savingTheScheduleDoesntRestartMealsThatDidntMove() throws {
    let meals = try schedule("08:00")
    let feeding = try log(at: "2026-10-19T08:05:00-04:00")
    try save(meals, at: "2026-10-19T12:00:00-04:00")
    // Logged by mistake: the Meal was Missed after all.
    try database.write { try $0.deleteFeeding(feeding.id) }
    #expect(try today().meals.map(\.state) == [.missed])
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
    #expect(try today().otherFeedings == [feeding])
  }

  @Test func movingAFeedingOutOfTheWindowUnfulfilsItsMeal() throws {
    try schedule("11:00")
    var feeding = try log(at: "2026-10-19T11:00:00-04:00")
    feeding.date = instant("2026-10-19T08:00:00-04:00")
    try database.write { try $0.updateFeeding(feeding) }
    let moved = try database.read { try Feeding.find(feeding.id).fetchOne($0) }!
    #expect(moved.mealID == nil)
    #expect(try today().meals.map(\.state) == [.upcoming])
    #expect(try today().otherFeedings == [moved])
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
    try save([breakfast], at: "2026-10-19T12:00:00-04:00")
    let stored = try database.read { try Feeding.order(by: \.date).fetchAll($0) }.map(\.mealID)
    #expect(stored == [breakfast.id, breakfast.id])

    // Removing the Meal leaves all its Feedings off-schedule.
    try database.write { try $0.saveMeals([], for: cat.id) }
    #expect(try database.read { try Feeding.fetchAll($0) }.map(\.mealID) == [nil, nil])
    #expect(try self.today().otherFeedings.map(\.id) == [today.id])
  }

  @Test func dayMeansTheLocalCalendarDay() throws {
    let lateMeal = try schedule("23:30")[0]
    let yesterday = try log(at: "2026-10-18T21:00:00-04:00")
    // Just after midnight: fulfils last night's 23:30, not tonight's.
    let afterMidnight = try log(at: "2026-10-19T00:30:00-04:00")
    let earlyToday = try log(at: "2026-10-19T03:00:00-04:00")
    #expect([yesterday.mealID, afterMidnight.mealID, earlyToday.mealID] == [nil, lateMeal.id, nil])
    // Feedings either side of midnight belong to their own day.
    let kibble = try database.write { try $0.addFood(name: "Kibble", servingUnit: .gram, kcalPerUnit: 3.8, isTreat: false, isFreeFed: true) }
    try log(at: "2026-10-18T23:00:00-04:00", food: kibble)
    let lastThingToday = try log(at: "2026-10-19T23:59:00-04:00", food: kibble)
    try log(at: "2026-10-20T00:00:00-04:00", food: kibble)
    #expect(try today().meals.map(\.state) == [.upcoming])
    // Last night's Meal isn't on today's list, so its Feeding shows with the others.
    #expect(try today().otherFeedings == [afterMidnight, earlyToday, lastThingToday])
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
      #expect(day.otherFeedings == [])
      #expect(try log(at: "2026-10-20T08:05:00+09:00").mealID == breakfast.id)
    }
  }

  @Test func kittensAreOfferedFourMealsAndOlderCatsTwo() {
    #expect(Meal.suggestedMinutesOfDay(for: .kitten).count == 4)
    #expect(Meal.suggestedMinutesOfDay(for: .adult) == [8 * 60, 18 * 60])
    #expect(Meal.suggestedMinutesOfDay(for: .senior) == [8 * 60, 18 * 60])
  }

  @Test func aFeedingMatchedBeforeATimeZoneChangeStillShowsToday() throws {
    try schedule("08:00")
    let feeding = try log(at: "2026-10-19T08:00:00-04:00")
    // 12:00 in New York is 17:00 in London: London's 08:00 breakfast was at 03:00 New York time.
    let day = try withDependencies { $0.calendar = calendar(in: "Europe/London") } operation: { try today() }
    #expect(day.meals.map(\.state) == [.missed])
    #expect(day.otherFeedings == [feeding])
  }

  @Test func aFoodUsedByAMealCantBecomeFreeFed() throws {
    try schedule("08:00")
    var pate = pate
    pate.isFreeFed = true
    #expect(throws: FoodUsedByMeal.self) { try database.write { try $0.updateFood(pate) } }
    #expect(try database.read { try Food.find(pate.id).fetchOne($0) }?.isFreeFed == false)
  }

  @Test func makingAFoodFreeFedRematchesTodaysFeedings() throws {
    // Breakfast is chicken, but pâté given at 08:00 still fulfils it.
    let chicken = try database.write { try $0.addFood(name: "Chicken", servingUnit: .pouch, kcalPerUnit: 70, isTreat: false, isFreeFed: false) }
    let breakfast = Meal(id: UUID(), catID: cat.id, minuteOfDay: 8 * 60, foodID: chicken.id, amount: 1)
    try database.write { try $0.saveMeals([breakfast], for: cat.id) }
    let feeding = try log(at: "2026-10-19T08:00:00-04:00")
    #expect(feeding.mealID == breakfast.id)
    var pate = pate
    pate.isFreeFed = true
    try database.write { try $0.updateFood(pate) }
    #expect(try database.read { try Feeding.find(feeding.id).fetchOne($0) }?.mealID == nil)
    #expect(try database.read { try Food.find(pate.id).fetchOne($0) }?.isFreeFed == true)

    pate.isFreeFed = false
    try database.write { try $0.updateFood(pate) }
    #expect(try database.read { try Feeding.find(feeding.id).fetchOne($0) }?.mealID == breakfast.id)
  }

  @Test func aStaleMatchFromBeforeAScheduleChangeDoesNotBlockToday() throws {
    var lateMeal = try schedule("21:00")[0]
    try log(at: "2026-10-18T21:00:00-04:00")
    lateMeal.minuteOfDay = 60
    try database.write { try $0.saveMeals([lateMeal], for: cat.id) }
    // Last night's Feeding kept its Meal, but it is 4 hours from 01:00, so 01:00 is still free.
    #expect(try log(at: "2026-10-19T01:00:00-04:00").mealID == lateMeal.id)
  }

  @Test func timesSkippedOrRepeatedByDaylightSavingResolveToOneInstant() {
    let newYork = calendar(in: "America/New_York")
    let skipped = Meal(id: UUID(), catID: cat.id, minuteOfDay: 2 * 60 + 30, foodID: pate.id, amount: 1)
    #expect(skipped.time(on: instant("2026-03-08T12:00:00-04:00"), calendar: newYork) == instant("2026-03-08T03:00:00-04:00"))
    let repeated = Meal(id: UUID(), catID: cat.id, minuteOfDay: 90, foodID: pate.id, amount: 1)
    #expect(repeated.time(on: instant("2026-11-01T12:00:00-05:00"), calendar: newYork) == instant("2026-11-01T01:30:00-04:00"))
  }

  @Test func theWindowIsRealTimeAcrossAClockChange() throws {
    try schedule("03:00")
    // 00:59 EST to 03:00 EDT is 1 h 1 min, though the clock moves 2 h 1 min.
    let feeding = try withDependencies { $0.date.now = instant("2026-03-08T12:00:00-04:00") } operation: {
      try log(at: "2026-03-08T00:59:00-05:00")
    }
    #expect(feeding.mealID != nil)
  }
}
