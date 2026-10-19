import XCTest

/// Miso from first run was weighed today at 9 lb, so no Weigh-in is due yet.
final class WeighInUITests: XCTestCase {
  @MainActor
  func testWeighInsCanBeAddedEditedAndDeletedOnTheWeightChart() {
    let app = XCUIApplication.launchedForTesting()
    app.completeFirstRun()
    app.openWeightChart()
    XCTAssertTrue(app.containing(", 9 lb").exists)

    app.buttons["Add Weigh-in"].tap()
    app.fillInWeighIn("7", monthsAgo: 2)
    app.buttons["Add Weigh-in"].tap()
    app.fillInWeighIn("8", monthsAgo: 1)
    XCTAssertTrue(app.containing(", 8 lb").waitForExistence(timeout: 5))

    app.containing(", 8 lb").tap()
    XCTAssertTrue(app.navigationBars["Edit Weigh-in"].waitForExistence(timeout: 5))
    app.textFields["Weight"].clearAndType("7.9")
    app.buttons["Save"].tap()
    XCTAssertTrue(app.containing(", 7.9 lb").waitForExistence(timeout: 5))
    XCTAssertFalse(app.containing(", 8 lb").exists)

    // Entered by mistake.
    app.buttons["Add Weigh-in"].tap()
    app.fillInWeighIn("90")
    XCTAssertTrue(app.containing(", 90 lb").waitForExistence(timeout: 5))
    app.containing(", 90 lb").swipeLeft()
    app.buttons["Delete"].tap()
    XCTAssertFalse(app.containing(", 90 lb").waitForExistence(timeout: 2))

    XCTAssertTrue(app.containing("Weight chart").exists)
    attachScreenshot("Weight chart", of: app)
  }

  @MainActor
  func testTheTodayViewPromptsForAWeighInOnceOneIsDue() {
    let app = XCUIApplication.launchedForTesting()
    app.completeFirstRun()
    app.swipeUp()
    XCTAssertTrue(app.buttons["Weight Chart"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.containing("Time for a Weigh-in").exists)

    // A Kitten weighed on the 15th of last month, at least 14 days ago, is due.
    app.buttons["Weight Chart"].tap()
    app.containing(", 9 lb").tap()
    XCTAssertTrue(app.navigationBars["Edit Weigh-in"].waitForExistence(timeout: 5))
    app.pickDay15(monthsAgo: 1)
    app.buttons["Save"].tap()
    XCTAssertTrue(app.containing(" 15, ").waitForExistence(timeout: 5))
    app.navigationBars.buttons["Today"].tap()

    app.swipeUp()
    XCTAssertTrue(app.containing("Time for a Weigh-in").waitForExistence(timeout: 5))
    attachScreenshot("Weigh-in due", of: app)

    app.buttons["Weigh"].tap()
    app.fillInWeighIn("9.4")
    XCTAssertTrue(app.staticTexts["9.4 lb"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.containing("Time for a Weigh-in").exists)
    app.swipeDown()
    attachScreenshot("Weigh-in recorded", of: app)
  }
}

extension XCUIApplication {
  @MainActor
  func openWeightChart() {
    swipeUp()
    buttons["Weight Chart"].tap()
    XCTAssertTrue(navigationBars["Miso's Weight"].waitForExistence(timeout: 5))
  }

  /// Fills in and saves the open Weigh-in editor, dated the 15th `monthsAgo` months back, or today when nil.
  @MainActor
  func fillInWeighIn(_ pounds: String, monthsAgo: Int? = nil) {
    XCTAssertTrue(navigationBars["Add Weigh-in"].waitForExistence(timeout: 5))
    let weight = textFields["Weight"]
    weight.tap()
    weight.typeText(pounds)
    if let monthsAgo { pickDay15(monthsAgo: monthsAgo) }
    buttons["Save"].tap()
  }

  /// The 15th exists in every month, so this works whatever today's date is.
  @MainActor
  func pickDay15(monthsAgo: Int) {
    datePickers.firstMatch.tap()
    let previous = buttons["Previous Month"]
    XCTAssertTrue(previous.waitForExistence(timeout: 5))
    for _ in 0..<monthsAgo { previous.tap() }
    // By the month's name, so the tap waits out the page animation instead of landing on the month going away.
    let month = Calendar.current.date(byAdding: .month, value: -monthsAgo, to: .now)!.formatted(.dateTime.month(.wide))
    let day = buttons.matching(NSPredicate(format: "label ENDSWITH %@", "\(month) 15")).firstMatch
    XCTAssertTrue(day.waitForExistence(timeout: 5))
    day.tap()
    buttons["PopoverDismissRegion"].tap()
  }
}

extension XCUIElement {
  @MainActor
  func clearAndType(_ text: String) {
    // At the right edge, so the caret lands after the current value.
    coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
    typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + text)
  }
}
