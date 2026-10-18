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

    // Same for changing how the label states calories: 0.9 per gram isn't 0.9 per 100 g.
    app.staticTexts["Tuna pâté"].tap()
    app.buttons["Label states calories, Per gram"].tap()
    app.buttons["Per 100 g"].tap()
    XCTAssertFalse(app.buttons["Save"].isEnabled)
  }

  @MainActor
  func testAddingAFoodNeedsARealNameAndKeepsItsFlags() {
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
    app.switches["Treat"].switches.firstMatch.tap()
    app.switches["Free-fed"].switches.firstMatch.tap()
    app.buttons["Save"].tap()
    XCTAssertTrue(app.staticTexts["Chicken"].waitForExistence(timeout: 5))

    // Treat and free-fed are kept with the Food.
    app.staticTexts["Chicken"].tap()
    XCTAssertEqual(app.switches["Treat"].value as? String, "1")
    XCTAssertEqual(app.switches["Free-fed"].value as? String, "1")
    XCTAssertEqual(app.switches["Retired"].value as? String, "0")
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
