import XCTest

final class FirstRunUITests: XCTestCase {
  @MainActor
  func testAddingTheFirstCatShowsItOnToday() {
    let app = XCUIApplication()
    // US units, so the weight round-trips lb → kg → lb.
    app.launchArguments = ["-ui-testing", "-AppleLocale", "en_US"]
    app.launch()

    let name = app.textFields["Name"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    name.tap()
    name.typeText("Miso")

    let weight = app.textFields["0"]
    weight.tap()
    weight.typeText("9")

    app.buttons["Continue"].tap()

    XCTAssertTrue(app.staticTexts["Miso"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Kitten"].exists)
    XCTAssertTrue(app.staticTexts["9 lb"].exists)
    for tab in ["Today", "Cats", "Care", "Settings"] {
      XCTAssertTrue(app.tabBars.buttons[tab].exists, tab)
    }
  }
}
