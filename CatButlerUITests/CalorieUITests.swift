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
      app.textFields["Amount"].clearAndType(amount)
      app.buttons["Save"].tap()
    }
    XCTAssertTrue(app.staticTexts["Intake, 50 of about 503 kcal/day"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.containing("Treats 10 kcal").exists)
    XCTAssertTrue(app.containing("Approximate: includes free-fed Food").exists)
    attachScreenshot("Treats and free-fed", of: app)
  }
}
