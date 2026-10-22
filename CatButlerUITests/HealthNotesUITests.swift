import XCTest

final class HealthNotesUITests: XCTestCase {
  @MainActor
  func testHealthNotesCanBeAddedFromTheCatsScreenEditedAndDeleted() {
    let app = XCUIApplication.launchedForTesting()
    app.completeFirstRun()
    app.tabBars.buttons["Cats"].tap()
    app.catRow("Miso").tap()
    XCTAssertTrue(app.navigationBars["Edit Cat"].waitForExistence(timeout: 5))

    // Quick entry, dated now.
    app.buttons["Add Health Note"].tap()
    app.fillInHealthNote("Vomited after breakfast")
    app.buttons["Health Notes"].tap()
    XCTAssertTrue(app.navigationBars["Miso's Health Notes"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.containing("Vomited after breakfast").waitForExistence(timeout: 5))

    // Noticed last month: listed after today's.
    app.navigationBars.buttons["Add Health Note"].tap()
    app.fillInHealthNote("Not using the litter box", monthsAgo: 1)
    let litterBox = app.containing("Not using the litter box")
    XCTAssertTrue(litterBox.waitForExistence(timeout: 5))
    XCTAssertLessThan(app.containing("Vomited after breakfast").frame.minY, litterBox.frame.minY)

    litterBox.tap()
    XCTAssertTrue(app.navigationBars["Edit Health Note"].waitForExistence(timeout: 5))
    // Labelled by its text once filled in.
    let field = app.textFields.firstMatch
    // At the right edge, so the caret lands after the text.
    field.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
    field.typeText(" at night")
    app.navigationBars["Edit Health Note"].buttons["Save"].tap()
    XCTAssertTrue(app.containing("Not using the litter box at night").waitForExistence(timeout: 5))
    attachScreenshot("Health Notes", of: app)

    app.containing("Vomited after breakfast").swipeLeft()
    app.buttons["Delete"].tap()
    XCTAssertFalse(app.containing("Vomited after breakfast").waitForExistence(timeout: 2))
  }
}
