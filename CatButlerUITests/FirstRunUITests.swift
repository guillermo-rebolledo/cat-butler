import XCTest

final class FirstRunUITests: XCTestCase {
  @MainActor
  func testFirstRunAddsACatAndAFood() {
    let app = XCUIApplication.launchedForTesting()
    attachScreenshot("First run", of: app)

    app.addFirstCat()
    attachScreenshot("First run filled in", of: app)
    app.buttons["Continue"].tap()

    app.fillInFirstFood()
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

    app.openFoods()
    XCTAssertTrue(app.staticTexts["Tuna pâté"].exists)
    XCTAssertTrue(app.staticTexts["76.5 kcal per can"].exists)
    attachScreenshot("Foods", of: app)
  }
}

extension XCUIApplication {
  @MainActor
  static func launchedForTesting() -> XCUIApplication {
    let app = XCUIApplication()
    // US units, so the weight round-trips lb → kg → lb.
    app.launchArguments = ["-ui-testing", "-AppleLocale", "en_US"]
    app.launch()
    return app
  }

  /// First-run step 1: Miso, 9 lb.
  @MainActor
  func addFirstCat() {
    let name = textFields["Name"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    name.tap()
    name.typeText("Miso")
    let weight = textFields["Weight"]
    weight.tap()
    weight.typeText("9")
  }

  /// First-run step 2: a can labelled 90 kcal per 100 g, 85 g a can.
  @MainActor
  func fillInFirstFood() {
    let name = textFields["Name"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    name.tap()
    name.typeText("Tuna pâté")
    buttons["Label states calories, Per can"].tap()
    buttons["Per 100 g"].tap()
    let kcal = textFields["Calories"]
    kcal.tap()
    kcal.typeText("90")
    let grams = textFields["Weight of one can"]
    grams.tap()
    grams.typeText("85")
  }

  /// Finishes first run with Miso and Tuna pâté, then opens Settings → Foods.
  @MainActor
  func completeFirstRunAndOpenFoods() {
    addFirstCat()
    buttons["Continue"].tap()
    fillInFirstFood()
    buttons["Save"].tap()
    openFoods()
  }

  @MainActor
  func openFoods() {
    XCTAssertTrue(tabBars.buttons["Settings"].waitForExistence(timeout: 5))
    tabBars.buttons["Settings"].tap()
    buttons["Foods"].tap()
    XCTAssertTrue(navigationBars["Foods"].waitForExistence(timeout: 5))
  }
}

extension XCTestCase {
  @MainActor
  func attachScreenshot(_ name: String, of app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
