import XCTest

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

  /// First-run step 3: ¼ can at each of the four Meals suggested for a Kitten.
  @MainActor
  func fillInFirstMeals() {
    XCTAssertTrue(navigationBars["Meals"].waitForExistence(timeout: 5))
    // The Form only builds the rows on screen, so fill the empty ones while scrolling down.
    let empty = textFields.matching(NSPredicate(format: "label == 'Amount' AND NOT (value CONTAINS '0.25')")).firstMatch
    var filled = 0
    for _ in 0..<12 where filled < 4 {
      let top = navigationBars["Meals"].frame.maxY
      let bottom = keyboards.firstMatch.exists ? keyboards.firstMatch.frame.minY : frame.maxY
      if empty.exists, empty.frame.minY > top, empty.frame.maxY < bottom {
        empty.tap()
        empty.typeText("0.25")
        filled += 1
      } else {
        collectionViews.firstMatch.swipeUp(velocity: .slow)
      }
    }
    XCTAssertEqual(filled, 4)
  }

  /// Finishes first run with Miso, Tuna pâté and four Meals.
  @MainActor
  func completeFirstRun() {
    addFirstCat()
    buttons["Continue"].tap()
    fillInFirstFood()
    buttons["Save"].tap()
    fillInFirstMeals()
    buttons["Save"].tap()
    XCTAssertTrue(tabBars.buttons["Today"].waitForExistence(timeout: 5))
  }

  /// Finishes first run, then opens Settings → Foods.
  @MainActor
  func completeFirstRunAndOpenFoods() {
    completeFirstRun()
    openFoods()
  }

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
    // At the top, over the title: a tap in the middle can land on a button under the popover, such as Delete.
    buttons["PopoverDismissRegion"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
  }

  @MainActor
  func openFoods() {
    XCTAssertTrue(tabBars.buttons["Settings"].waitForExistence(timeout: 5))
    tabBars.buttons["Settings"].tap()
    buttons["Foods"].tap()
    XCTAssertTrue(navigationBars["Foods"].waitForExistence(timeout: 5))
  }
}

extension XCUIElement {
  /// Replaces the field's value with `text`.
  @MainActor
  func clearAndType(_ text: String) {
    // At the right edge, so the caret lands after the current value.
    coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
    typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + text)
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
