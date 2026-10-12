import XCTest

/// iPhone-only UI cases. Every launch explicitly uses invented records and no school network calls.
final class GrademaxxingUITests: XCTestCase {
  @MainActor private func launchDemo() -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["--demo"]
    app.launch()
    XCTAssertTrue(app.buttons["course.math"].waitForExistence(timeout: 15))
    return app
  }

  /// Polls an element until its label contains `value`, without reading properties of an element
  /// that is not there. A vanished element reports `"<missing>"` rather than raising a snapshot error.
  @MainActor private func label(
    of element: XCUIElement, containing value: String, timeout: TimeInterval = 10
  ) -> String {
    let deadline = Date().addingTimeInterval(timeout)
    var seen = element.exists ? element.label : "<missing>"
    while !seen.contains(value), Date() < deadline {
      _ = XCTWaiter.wait(for: [XCTestExpectation(description: "poll")], timeout: 0.25)
      seen = element.exists ? element.label : "<missing>"
    }
    return seen
  }

  /// Scrolls a lazy form until the element sits fully between the navigation bar and the tab bar, so
  /// a tap cannot land on the tab bar instead of the row. `furtherDown` starts the search in the
  /// direction the row lies in, since an unrealized row is absent from the tree either way.
  @MainActor private func bringIntoView(
    _ element: XCUIElement, in app: XCUIApplication, furtherDown: Bool = true
  ) {
    for _ in 0..<12 {
      guard element.exists else {
        if furtherDown { app.swipeUp() } else { app.swipeDown() }
        continue
      }
      let top = app.navigationBars.firstMatch.frame.maxY
      let bottom = app.tabBars.firstMatch.frame.minY
      if element.frame.minY >= top, element.frame.maxY <= bottom { return }
      if element.frame.maxY > bottom { app.swipeUp() } else { app.swipeDown() }
    }
  }

  @MainActor func testWhatIfLeavesOfficialGradeUnchanged() {
    let app = launchDemo()
    app.buttons["course.math"].tap()
    let official = app.staticTexts["course.officialPercent"]
    XCTAssertTrue(official.waitForExistence(timeout: 5))
    let original = official.label
    app.buttons["course.whatif"].tap()
    let projection = app.staticTexts["whatif.projectedPercent"]
    XCTAssertTrue(projection.waitForExistence(timeout: 5))
    let originalProjection = projection.label
    let score = app.textFields["whatif.earned"]
    score.tap()
    let current = score.value as? String ?? ""
    score.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + "100")
    XCTAssertNotEqual(projection.label, originalProjection)
    app.buttons["Done"].tap()
    XCTAssertEqual(official.label, original)
  }

  @MainActor func testPeriodSwitchAndAssignmentSearch() {
    let app = launchDemo()
    app.buttons["grades.period"].tap()
    app.buttons["Semester 2"].tap()
    app.buttons["course.english"].tap()
    XCTAssertEqual(app.staticTexts["course.officialPercent"].label, "91%")
    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 5))
    search.tap()
    // Submitting dismisses the keyboard so the filtered rows are on screen.
    search.typeText("Upcoming\n")
    let upcoming = app.buttons["assignment.english-3"]
    for _ in 0..<3 where !upcoming.exists { app.swipeUp() }
    XCTAssertTrue(upcoming.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["assignment.english-1"].exists)
  }

  @MainActor func testAssignmentEditsAndResetPreserveOfficialMark() {
    let app = launchDemo()
    app.buttons["course.math"].tap()
    let official = app.staticTexts["course.officialPercent"]
    XCTAssertTrue(official.waitForExistence(timeout: 5))
    let officialMark = official.label
    let planner = app.buttons["course.assignmentPlanner"]
    for _ in 0..<3 where !planner.isHittable { app.swipeUp() }
    planner.tap()
    let estimate = app.staticTexts["simulation.projected"]
    XCTAssertTrue(estimate.waitForExistence(timeout: 5))
    let original = estimate.label
    app.buttons["simulation.assignment.math-1"].tap()
    let score = app.textFields["simulation.earned"]
    XCTAssertTrue(score.waitForExistence(timeout: 5))
    score.tap()
    let current = score.value as? String ?? ""
    score.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + "25")
    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertNotEqual(estimate.label, original)
    let reset = app.buttons["simulation.reset"]
    for _ in 0..<5 where !reset.isHittable { app.swipeUp() }
    reset.tap()
    for _ in 0..<5 where !estimate.isHittable { app.swipeDown() }
    XCTAssertEqual(estimate.label, original)
    app.buttons["Done"].tap()
    for _ in 0..<5 where !official.isHittable { app.swipeDown() }
    XCTAssertEqual(official.label, officialMark)
  }

  @MainActor func testSchoolRecordsAndCalendarMonthNavigation() {
    let app = launchDemo()
    app.tabBars.buttons["School"].tap()
    app.buttons["school.attendance"].tap()
    XCTAssertTrue(app.buttons["attendance.record.2026-10-08"].waitForExistence(timeout: 5))
    app.buttons["attendance.record.2026-10-08"].tap()
    XCTAssertTrue(app.staticTexts["Synthetic excused appointment"].exists)
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["school.calendar"].tap()
    let month = app.staticTexts["calendar.month"]
    XCTAssertTrue(month.waitForExistence(timeout: 5))
    let originalMonth = month.label
    app.buttons["calendar.nextMonth"].tap()
    XCTAssertNotEqual(month.label, originalMonth)
    app.buttons["calendar.previousMonth"].tap()
    XCTAssertEqual(month.label, originalMonth)
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["school.schedule"].tap()
    XCTAssertTrue(app.staticTexts["AP Calculus"].waitForExistence(timeout: 5))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["school.profile"].tap()
    XCTAssertTrue(app.staticTexts["Demo Student"].firstMatch.waitForExistence(timeout: 5))
  }

  @MainActor func testLeavingDemoReturnsToSignInAndClearsRecords() {
    let app = launchDemo()
    app.tabBars.buttons["Account"].tap()
    app.buttons["account.signout"].tap()
    app.sheets.buttons["Leave demo"].tap()
    XCTAssertTrue(app.buttons["login.submit"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["course.math"].exists)
  }
  @MainActor func testPlannerInclusionChangesEstimateAndResetRestoresIt() {
    let app = launchDemo()
    app.tabBars.buttons["Planner"].tap()
    let weighted = app.staticTexts["planner.weighted"]
    XCTAssertTrue(weighted.waitForExistence(timeout: 10))
    // Demo data weights AP Calculus 5.0, English Honors 3.5, Chemistry 4.0, World History 3.0,
    // and Studio Art 4.0 across five credits each.
    bringIntoView(weighted, in: app, furtherDown: false)
    let initial = label(of: weighted, containing: "3.90")
    XCTAssertTrue(initial.contains("3.90"), "Expected weighted GPA 3.90, saw \(initial)")
    let include = app.switches["planner.include.math|1"].firstMatch
    bringIntoView(include, in: app)
    XCTAssertTrue(include.exists, "Expected the math inclusion switch")
    XCTAssertEqual(include.value as? String, "1")
    // The switch element covers the whole row and the row's text area does not move the control, so
    // tap the trailing edge of a fully visible row. Assert the estimate rather than the switch
    // again: after the control moves, runtimes differ on whether the row stays queryable.
    include.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    XCTAssertTrue(
      app.tabBars.buttons["Planner"].isSelected,
      "The inclusion tap left the Planner tab; app state \(app.state)")
    bringIntoView(weighted, in: app, furtherDown: false)
    // Excluding math leaves 14.5 quality points over four credits: 3.625, shown as 3.63.
    let excluded = label(of: weighted, containing: "3.63")
    XCTAssertTrue(excluded.contains("3.63"), "Expected weighted GPA 3.63, saw \(excluded)")
    let reset = app.buttons["planner.reset"]
    bringIntoView(reset, in: app)
    XCTAssertTrue(reset.exists, "Expected the planner reset button")
    reset.tap()
    bringIntoView(weighted, in: app, furtherDown: false)
    let restored = label(of: weighted, containing: "3.90")
    XCTAssertTrue(
      restored.contains("3.90"), "Expected weighted GPA 3.90 after reset, saw \(restored)")
  }
  @MainActor func testDocumentsAndReadOnlyMailAttachmentPreview() {
    let app = launchDemo()
    app.tabBars.buttons["School"].tap()
    app.buttons["school.documents"].tap()
    XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
    let document = app.buttons["document.c3ludGhldGljLWRvY3VtZW50"]
    XCTAssertTrue(document.waitForExistence(timeout: 5))
    document.tap()
    XCTAssertTrue(app.navigationBars["Synthetic document.pdf"].waitForExistence(timeout: 5))
    app.buttons["preview.close"].tap()
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["school.mail"].tap()
    XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
    let message = app.buttons["mail.message.11111111-2222-4333-8444-555555555555"]
    XCTAssertTrue(message.waitForExistence(timeout: 5))
    message.tap()
    XCTAssertTrue(app.staticTexts["mail.body"].waitForExistence(timeout: 5))
    let attachment = app.buttons["attachment.22222222-3333-4444-8555-666666666666"]
    XCTAssertTrue(attachment.exists)
    attachment.tap()
    XCTAssertTrue(app.navigationBars["Synthetic document.pdf"].waitForExistence(timeout: 5))
    app.buttons["preview.close"].tap()
    XCTAssertTrue(app.staticTexts["mail.body"].exists)
  }
}
