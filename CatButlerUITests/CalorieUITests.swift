import XCTest

/// Miso from first run is a 9 lb (4.08 kg) intact Kitten: 70 × 4.08^0.75 × 2.5 ≈ 503 kcal a day.
/// Tuna pâté is 76.5 kcal a can, and each Meal is ¼ can.
final class CalorieUITests: XCTestCase {
  @MainActor
  func testIntakeAgainstTheTargetFollowsFeedingsWhatWasEatenAndTheOwnersTarget() {
    let app = XCUIApplication.launchedForTesting()
    app.completeFirstRun()
    XCTAssertTrue(app.staticTexts["Intake, 0 of about 503 kcal/day"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["The Calorie Target is an estimate. Adjust it based on the weight trend and your vet."].exists)

    app.buttons["Fed"].firstMatch.tap()
    // 19.1 kcal
    XCTAssertTrue(app.staticTexts["Intake, 19 of about 503 kcal/day"].waitForExistence(timeout: 5))
    attachScreenshot("Intake", of: app)

    app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Fed at'")).firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Edit Feeding"].waitForExistence(timeout: 5))
    app.buttons["Ate, All of it"].tap()
    app.buttons["About ½"].tap()
    app.buttons["Save"].tap()
    // 9.6 kcal
    XCTAssertTrue(app.staticTexts["Intake, 10 of about 503 kcal/day"].waitForExistence(timeout: 5))

    app.staticTexts["Intake, 10 of about 503 kcal/day"].tap()
    XCTAssertTrue(app.navigationBars["Calorie Target"].waitForExistence(timeout: 5))
    // 503 / 76.5
    XCTAssertTrue(app.containing("6.57 can").exists)
    attachScreenshot("Calorie Target", of: app)
    let own = app.textFields["Your target"]
    own.tap()
    own.typeText("250")
    app.buttons["Save"].tap()

    XCTAssertTrue(app.staticTexts["Intake, 10 of about 250 kcal/day"].waitForExistence(timeout: 5))
    app.staticTexts["Intake, 10 of about 250 kcal/day"].tap()
    XCTAssertTrue(app.containing("3.27 can").waitForExistence(timeout: 5))
  }

  @MainActor
  func testTreatsAndFreeFedFoodShowOnIntake() {
    let app = XCUIApplication.launchedForTesting()
    app.completeFirstRunAndOpenFoods()
    app.addFood("Kibble", kcal: "4", freeFed: true)
    app.addFood("Chicken bites", kcal: "2", treat: true)
    app.tabBars.buttons["Today"].tap()

    for (food, amount) in [("Kibble", "10"), ("Chicken bites", "5")] {
      app.buttons["Log Feeding"].tap()
      XCTAssertTrue(app.navigationBars["Log Feeding"].waitForExistence(timeout: 5))
      app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Food,'")).firstMatch.tap()
      app.buttons[food].tap()
      let field = app.textFields["Amount"]
      // At the right edge, so the caret lands after the Meal's ¼, which is then replaced.
      field.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
      field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + amount)
      app.buttons["Save"].tap()
    }
    XCTAssertTrue(app.staticTexts["Intake, 50 of about 503 kcal/day"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.containing("Treats 10 kcal").exists)
    XCTAssertTrue(app.containing("Approximate: includes free-fed Food").exists)
    attachScreenshot("Treats and free-fed", of: app)
  }
}

extension XCUIApplication {
  /// Any element whose label contains `text`, such as a line inside a row's combined label.
  @MainActor
  func containing(_ text: String) -> XCUIElement {
    descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
  }

  /// Adds a Food from the Foods screen, labelled in kcal per can.
  @MainActor
  func addFood(_ name: String, kcal: String, treat: Bool = false, freeFed: Bool = false) {
    buttons["Add Food"].tap()
    let nameField = textFields["Name"]
    XCTAssertTrue(nameField.waitForExistence(timeout: 5))
    nameField.tap()
    nameField.typeText(name)
    let kcalField = textFields["Calories"]
    kcalField.tap()
    kcalField.typeText(kcal)
    if treat { switches["Treat"].switches.firstMatch.tap() }
    if freeFed { switches["Free-fed"].switches.firstMatch.tap() }
    buttons["Save"].tap()
    XCTAssertTrue(staticTexts[name].waitForExistence(timeout: 5))
  }
}
