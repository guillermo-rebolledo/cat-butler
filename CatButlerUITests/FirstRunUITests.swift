import XCTest

final class FirstRunUITests: XCTestCase {
  @MainActor
  func testAddingTheFirstCatShowsItOnToday() {
    let app = XCUIApplication()
    // US units, so the weight round-trips lb → kg → lb.
    app.launchArguments = ["-ui-testing", "-AppleLocale", "en_US"]
    app.launch()
    attachScreenshot("First run", of: app)

    let name = app.textFields["Name"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    name.tap()
    name.typeText("Miso")

    let weight = app.textFields["0"]
    weight.tap()
    weight.typeText("9")

    attachScreenshot("First run filled in", of: app)
    app.buttons["Continue"].tap()

    XCTAssertTrue(app.staticTexts["Miso"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Kitten"].exists)
    XCTAssertTrue(app.staticTexts["9 lb"].exists)
    for tab in ["Today", "Cats", "Care", "Settings"] {
      XCTAssertTrue(app.tabBars.buttons[tab].exists, tab)
    }
    attachScreenshot("Today", of: app)
  }

  @MainActor
  private func attachScreenshot(_ name: String, of app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
