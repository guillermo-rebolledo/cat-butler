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

  @MainActor
  func testACatCanBeArchivedThenDeleted() {
    let app = XCUIApplication.launchedForTesting()
    app.completeFirstRun()
    app.tabBars.buttons["Cats"].tap()
    app.buttons["Add Cat"].tap()
    app.fillInCat(named: "Tofu")
    app.buttons["Save"].tap()

    app.catRow("Tofu").tap()
    XCTAssertTrue(app.navigationBars["Edit Cat"].waitForExistence(timeout: 5))
    app.buttons["Archive Cat"].tap()
    XCTAssertTrue(app.staticTexts["Archived"].waitForExistence(timeout: 5))
    attachScreenshot("Archived", of: app)

    // Its history stays readable.
    app.catRow("Tofu").tap()
    app.buttons["Weight Chart"].tap()
    XCTAssertTrue(app.navigationBars["Tofu's Weight"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.containing("9 lb").exists)
    app.navigationBars.buttons.firstMatch.tap()

    // Only Miso is left in care: nothing to switch or feed all.
    app.tabBars.buttons["Today"].tap()
    XCTAssertTrue(app.staticTexts["Miso"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["Feed All"].exists)

    app.tabBars.buttons["Cats"].tap()
    // Below the history rows, so the Form builds it only once scrolled to.
    app.swipeUp()
    app.buttons["Delete Cat"].tap()
    app.buttons["Delete Tofu and Their History"].tap()
    XCTAssertTrue(app.catRow("Miso").waitForExistence(timeout: 5))
    XCTAssertFalse(app.catRow("Tofu").exists)
    XCTAssertFalse(app.staticTexts["Archived"].exists)

    // With every Cat archived, Today says so instead of starting first run over.
    app.catRow("Miso").tap()
    app.buttons["Archive Cat"].tap()
    XCTAssertTrue(app.staticTexts["Archived"].waitForExistence(timeout: 5))
    app.tabBars.buttons["Today"].tap()
    XCTAssertTrue(app.staticTexts["No Cats in Care"].waitForExistence(timeout: 5))
  }
}
