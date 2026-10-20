import XCTest

final class CareUITests: XCTestCase {
  @MainActor
  func testAnOverdueVaccineShowsOnTodayUntilItsDone() {
    let app = XCUIApplication.launchedForTesting()
    app.completeFirstRun()
    app.tabBars.buttons["Care"].tap()

    app.buttons["Add Care Task"].tap()
    XCTAssertTrue(app.navigationBars["Add Care Task"].waitForExistence(timeout: 5))
    app.buttons["Vaccine"].tap()
    XCTAssertEqual(app.textFields["Title"].value as? String, "Vaccine")
    // The 15th of last month, so it's overdue whatever today's date is.
    app.pickDay15(monthsAgo: 1)
    app.buttons["Save"].tap()
    XCTAssertTrue(app.staticTexts["Overdue"].waitForExistence(timeout: 5))
    attachScreenshot("Care tab, overdue", of: app)

    app.tabBars.buttons["Today"].tap()
    app.swipeUp()
    XCTAssertTrue(app.staticTexts["Overdue"].waitForExistence(timeout: 5))
    attachScreenshot("Today, overdue", of: app)

    app.buttons["Mark Vaccine done"].tap()
    XCTAssertTrue(app.navigationBars["Vaccine"].waitForExistence(timeout: 5))
    let notes = app.textFields["Notes"]
    notes.tap()
    notes.typeText("Booster, left leg")
    app.buttons["Save"].tap()
    // Next due in a year, so it leaves Today.
    XCTAssertFalse(app.staticTexts["Overdue"].waitForExistence(timeout: 2))
    XCTAssertFalse(app.buttons["Mark Vaccine done"].exists)

    app.tabBars.buttons["Care"].tap()
    XCTAssertTrue(app.containing("Booster, left leg").waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Overdue"].exists)
    attachScreenshot("Care tab, done", of: app)
  }

  @MainActor
  func testAOneOffTaskIsDoneWithABackdatedCareRecord() {
    let app = XCUIApplication.launchedForTesting()
    app.completeFirstRun()
    app.tabBars.buttons["Care"].tap()

    app.buttons["Add Care Task"].tap()
    let title = app.textFields["Title"]
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    title.tap()
    title.typeText("Rabies vaccine")
    app.buttons["Save"].tap()

    // Given by the shelter before the app was installed.
    XCTAssertTrue(app.buttons["Mark Rabies vaccine done"].waitForExistence(timeout: 5))
    app.buttons["Mark Rabies vaccine done"].tap()
    XCTAssertTrue(app.navigationBars["Rabies vaccine"].waitForExistence(timeout: 5))
    app.pickDay15(monthsAgo: 2)
    app.textFields["Notes"].tap()
    app.textFields["Notes"].typeText("Given by the shelter")
    app.buttons["Save"].tap()

    XCTAssertTrue(app.containing("Given by the shelter").waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Done"].exists)
    XCTAssertFalse(app.buttons["Mark Rabies vaccine done"].exists)
    attachScreenshot("Backdated one-off", of: app)

    // Deleting the task takes its Care Records with it, so it asks first.
    app.staticTexts["Rabies vaccine"].firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Edit Care Task"].waitForExistence(timeout: 5))
    app.buttons["Delete Care Task"].tap()
    let confirm = app.buttons["Delete Care Task and Records"]
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    confirm.tap()
    XCTAssertTrue(app.staticTexts["No Care Records yet."].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["No Care Tasks yet."].exists)
  }
}
