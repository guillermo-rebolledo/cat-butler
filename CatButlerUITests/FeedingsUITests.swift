import XCTest

/// The app runs at noon in UI tests: the 07:00 Meal is missed, 12:00 is due, 17:00 and 21:00 aren't yet.
final class FeedingsUITests: XCTestCase {
  @MainActor
  func testOneTapFeedingFulfilsTheMealAndCanBeDeleted() {
    let app = XCUIApplication.launchedForTesting()
    app.completeFirstRun()
    XCTAssertTrue(app.staticTexts["Missed"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons.matching(identifier: "Fed").count, 1)
    attachScreenshot("Today", of: app)

    app.buttons["Fed"].firstMatch.tap()
    // The time has a narrow no-break space before PM.
    let fed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Fed at 12:00'")).firstMatch
    XCTAssertTrue(fed.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Fed"].exists)
    attachScreenshot("Fed", of: app)

    fed.tap()
    XCTAssertTrue(app.navigationBars["Edit Feeding"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.textFields["Amount"].value as? String, "0.25")
    app.buttons["Delete Feeding"].tap()
    XCTAssertTrue(app.buttons["Fed"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons.matching(identifier: "Fed").count, 1)
  }

  @MainActor
  func testLoggingAMissedMealBackdatesItToTheMealTime() {
    let app = XCUIApplication.launchedForTesting()
    app.completeFirstRun()
    XCTAssertTrue(app.buttons["Log"].waitForExistence(timeout: 5))
    app.buttons["Log"].tap()
    XCTAssertTrue(app.navigationBars["Log Feeding"].waitForExistence(timeout: 5))
    app.buttons["Save"].tap()

    XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Fed at 7:00'")).firstMatch.waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Missed"].exists)
  }

  @MainActor
  func testTheScheduleCanBeEditedFromSettings() {
    let app = XCUIApplication.launchedForTesting()
    app.completeFirstRun()
    app.tabBars.buttons["Settings"].tap()
    app.buttons["Meals"].tap()
    XCTAssertTrue(app.navigationBars["Meals"].waitForExistence(timeout: 5))
    app.buttons["Remove Meal"].firstMatch.tap()
    app.buttons["Save"].tap()

    app.tabBars.buttons["Today"].tap()
    // 07:00 is gone, so nothing is missed.
    XCTAssertTrue(app.buttons["Fed"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Missed"].exists)
  }

  @MainActor
  func testMealsCantUseAFreeFedFood() {
    let app = XCUIApplication.launchedForTesting()
    app.completeFirstRunAndOpenFoods()
    app.buttons["Add Food"].tap()
    let name = app.textFields["Name"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    name.tap()
    name.typeText("Kibble")
    let kcal = app.textFields["Calories"]
    kcal.tap()
    kcal.typeText("4")
    app.switches["Free-fed"].switches.firstMatch.tap()
    app.buttons["Save"].tap()
    XCTAssertTrue(app.staticTexts["Kibble"].waitForExistence(timeout: 5))

    app.navigationBars.buttons.firstMatch.tap()
    app.buttons["Meals"].tap()
    app.buttons["Food, Tuna pâté"].firstMatch.tap()
    XCTAssertTrue(app.buttons["Tuna pâté"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Kibble"].exists)
  }

  @MainActor
  func testAFoodAMealUsesCantBecomeFreeFed() {
    let app = XCUIApplication.launchedForTesting()
    app.completeFirstRunAndOpenFoods()
    app.staticTexts["Tuna pâté"].tap()
    XCTAssertTrue(app.staticTexts["A Meal uses this Food, so it can't be free-fed. Retired Foods stay in past Feedings but leave the pickers."].waitForExistence(timeout: 5))
    XCTAssertFalse(app.switches["Free-fed"].isEnabled)
  }
}
