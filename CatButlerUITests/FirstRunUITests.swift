import XCTest

final class FirstRunUITests: XCTestCase {
  @MainActor
  func testFirstRunAddsACatAndAFood() {
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

    // Step 2: a can labelled 90 kcal per 100 g, 85 g a can.
    let foodName = app.textFields["Name"]
    XCTAssertTrue(foodName.waitForExistence(timeout: 5))
    foodName.tap()
    foodName.typeText("Tuna pâté")
    app.buttons["Label states calories, Per can"].tap()
    app.buttons["Per 100 g"].tap()
    let kcal = app.textFields["Calories"]
    kcal.tap()
    kcal.typeText("90")
    let grams = app.textFields["Weight of one can"]
    grams.tap()
    grams.typeText("85")
    XCTAssertTrue(app.staticTexts["76.5 kcal per can"].exists)
    attachScreenshot("First Food", of: app)
    app.buttons["Save"].tap()

    XCTAssertTrue(app.staticTexts["Miso"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Kitten"].exists)
    XCTAssertTrue(app.staticTexts["9 lb"].exists)
    for tab in ["Today", "Cats", "Care", "Settings"] {
      XCTAssertTrue(app.tabBars.buttons[tab].exists, tab)
    }
    attachScreenshot("Today", of: app)

    app.tabBars.buttons["Settings"].tap()
    app.buttons["Foods"].tap()
    XCTAssertTrue(app.staticTexts["Tuna pâté"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["76.5 kcal per can"].exists)
    attachScreenshot("Foods", of: app)
  }

  @MainActor
  private func attachScreenshot(_ name: String, of app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
