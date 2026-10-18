import XCTest

final class FoodsUITests: XCTestCase {
  @MainActor
  func testChangingAFoodsServingUnitAsksForItsCaloriesAgain() {
    let app = XCUIApplication.launchedForTesting()
    app.completeFirstRunAndOpenFoods()
    app.staticTexts["Tuna pâté"].tap()

    app.buttons["Serving unit, can"].tap()
    app.buttons["gram"].tap()
    // The old 76.5 kcal was per can; it must not quietly become 76.5 kcal per gram.
    XCTAssertEqual(app.textFields["Calories"].value as? String, "0")
    XCTAssertFalse(app.buttons["Save"].isEnabled)
    attachScreenshot("Unit changed", of: app)

    let kcal = app.textFields["Calories"]
    kcal.tap()
    kcal.typeText("0.9")
    app.buttons["Save"].tap()
    XCTAssertTrue(app.staticTexts["0.9 kcal per gram"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testAFoodNeedsANameThatIsNotJustSpaces() {
    let app = XCUIApplication.launchedForTesting()
    app.completeFirstRunAndOpenFoods()
    app.buttons["Add Food"].tap()

    let name = app.textFields["Name"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    name.tap()
    name.typeText("   ")
    let kcal = app.textFields["Calories"]
    kcal.tap()
    kcal.typeText("85")
    XCTAssertFalse(app.buttons["Save"].isEnabled)

    name.tap()
    name.typeText("Chicken")
    app.buttons["Save"].tap()
    XCTAssertTrue(app.staticTexts["Chicken"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testRetiringAFoodMovesItToRetiredAndBack() {
    let app = XCUIApplication.launchedForTesting()
    app.completeFirstRunAndOpenFoods()
    XCTAssertFalse(app.staticTexts["Retired"].exists)

    app.staticTexts["Tuna pâté"].tap()
    app.switches["Retired"].switches.firstMatch.tap()
    app.buttons["Save"].tap()
    XCTAssertTrue(app.staticTexts["Retired"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Tuna pâté"].exists)
    XCTAssertTrue(app.staticTexts["No Foods in use. Add one, or bring back a retired one."].exists)
    attachScreenshot("Retired", of: app)

    app.staticTexts["Tuna pâté"].tap()
    app.switches["Retired"].switches.firstMatch.tap()
    app.buttons["Save"].tap()
    XCTAssertTrue(app.navigationBars["Foods"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Retired"].exists)
    XCTAssertFalse(app.staticTexts["No Foods in use. Add one, or bring back a retired one."].exists)
    XCTAssertTrue(app.staticTexts["Tuna pâté"].exists)
  }
}
