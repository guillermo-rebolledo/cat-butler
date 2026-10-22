import XCTest

/// The app runs at noon, so both Cats' 12:00 Meals are due.
final class SeveralCatsUITests: XCTestCase {
  @MainActor
  func testASecondCatGetsItsOwnMealsAndFeedAllFeedsBoth() {
    let app = XCUIApplication.launchedForTesting()
    app.completeFirstRun()
    // One Cat: nothing to switch or feed all.
    XCTAssertFalse(app.buttons["Feed All"].exists)

    app.tabBars.buttons["Cats"].tap()
    app.buttons["Add Cat"].tap()
    XCTAssertTrue(app.navigationBars["Add Cat"].waitForExistence(timeout: 5))
    app.fillInCat(named: "Tofu")
    app.buttons["Save"].tap()
    XCTAssertTrue(app.catRow("Tofu").waitForExistence(timeout: 5))
    attachScreenshot("Cats", of: app)

    app.openMeals(of: "Tofu")
    app.fillInFirstMeals()
    app.buttons["Save"].tap()
    XCTAssertTrue(app.navigationBars["Edit Cat"].waitForExistence(timeout: 5))
    // Its weight is the first Weigh-in; after that it's on the chart.
    XCTAssertFalse(app.textFields["Weight"].exists)

    app.tabBars.buttons["Today"].tap()
    XCTAssertTrue(app.staticTexts["Miso"].waitForExistence(timeout: 5))
    app.buttons["Feed All"].tap()
    let fed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Fed at 12:00'")).firstMatch
    XCTAssertTrue(fed.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Feed All"].isEnabled)
    attachScreenshot("Fed all", of: app)

    app.switchCat(to: "Tofu")
    XCTAssertTrue(app.staticTexts["Tofu"].waitForExistence(timeout: 5))
    XCTAssertTrue(fed.waitForExistence(timeout: 5))
    attachScreenshot("Tofu", of: app)
  }

  @MainActor
  func testACatCanBeRenamed() {
    let app = XCUIApplication.launchedForTesting()
    app.completeFirstRun()
    app.tabBars.buttons["Cats"].tap()
    app.catRow("Miso").tap()
    XCTAssertTrue(app.navigationBars["Edit Cat"].waitForExistence(timeout: 5))
    app.textFields["Name"].clearAndType("Mochi")
    app.buttons["Save"].tap()
    XCTAssertTrue(app.catRow("Mochi").waitForExistence(timeout: 5))

    app.tabBars.buttons["Today"].tap()
    XCTAssertTrue(app.staticTexts["Mochi"].waitForExistence(timeout: 5))
  }
}
