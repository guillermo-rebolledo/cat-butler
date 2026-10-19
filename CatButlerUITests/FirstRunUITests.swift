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

    app.fillInFirstMeals()
    XCTAssertTrue(app.buttons["Save"].isEnabled)
    attachScreenshot("First Meals", of: app)
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
