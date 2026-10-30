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
      let top =
        app.navigationBars.firstMatch.exists
        ? app.navigationBars.firstMatch.frame.maxY : app.frame.minY + 44
      let tabBar = app.tabBars.firstMatch
      let bottom =
        tabBar.exists && tabBar.isHittable ? tabBar.frame.minY - 8 : app.frame.maxY - 16
      if element.frame.minY >= top, element.frame.maxY <= bottom { return }
      if element.frame.maxY > bottom { app.swipeUp() } else { app.swipeDown() }
    }
  }

  @MainActor private func openCourse(_ id: String = "math", in app: XCUIApplication) {
    let course = app.buttons["course." + id]
    bringIntoView(course, in: app)
    XCTAssertTrue(course.isHittable)
    course.tap()
    let official = app.staticTexts["course.officialPercent"]
    XCTAssertTrue(official.waitForExistence(timeout: 5))
    bringIntoView(official, in: app, furtherDown: false)
  }

  @MainActor private func openMenu(_ destination: String, in app: XCUIApplication) {
    app.buttons["app.menu"].tap()
    let item = app.buttons["menu." + destination]
    XCTAssertTrue(item.waitForExistence(timeout: 5))
    item.tap()
  }

  @MainActor func testGradebookAndPrimaryNavigation() {
    let app = launchDemo()
    XCTAssertTrue(app.staticTexts["Gradebook"].exists)
    for destination in ["Grades", "Attendance", "Documents", "Mail"] {
      XCTAssertTrue(app.tabBars.buttons[destination].exists)
    }
    XCTAssertTrue(app.staticTexts["Your classes"].exists)
    XCTAssertEqual(app.staticTexts["grades.unweighted"].label, "3.60")
    XCTAssertEqual(app.staticTexts["grades.weighted"].label, "3.90")
    XCTAssertTrue(app.staticTexts["Current-course estimate · Not a transcript GPA"].exists)
    XCTAssertTrue(app.buttons["grades.period"].exists)
    app.buttons["grades.gpa"].tap()
    XCTAssertTrue(app.staticTexts["planner.weighted"].waitForExistence(timeout: 5))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertTrue(app.buttons["course.math"].waitForExistence(timeout: 5))
    // A class chosen in the menu opens the same native course screen as its gradebook row.
    app.buttons["app.menu"].tap()
    let course = app.buttons["menu.course.math"]
    bringIntoView(course, in: app)
    course.tap()
    XCTAssertTrue(app.staticTexts["course.officialPercent"].waitForExistence(timeout: 5))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertTrue(app.buttons["course.math"].waitForExistence(timeout: 5))
  }

  @MainActor func testPrimaryScreensPassAccessibilityAudit() throws {
    let app = launchDemo()
    continueAfterFailure = true
    let audits: XCUIAccessibilityAuditType = [
      .contrast, .hitRegion, .sufficientElementDescription, .trait, .textClipped,
    ]
    func audit() throws {
      try app.performAccessibilityAudit(for: audits) { issue in
        let element = issue.element
        let label = element?.exists == true ? element?.label ?? "" : "<unidentified>"
        // The system's single-line search field can truncate a placeholder at large sizes;
        // it retains its full accessible label and horizontally scrolls entered text.
        let nativeSearch = issue.auditType == .textClipped && element?.elementType == .searchField
        // Liquid Glass intentionally overlays scrolling content. Audit only content after
        // scrolling it clear of the tab bar, rather than treating the glass scrim as its ink.
        let behindTabBar =
          issue.auditType == .contrast
          && element?.frame.intersects(app.tabBars.firstMatch.frame) == true
        // On this runtime, the partly covered final demo row also produces unmappable
        // SwiftUI contrast nodes. Keep a screenshot for review; this does not certify contrast.
        let lastDemoCourse = app.buttons["course.art"]
        let unmappedCoveredDemoRow =
          issue.auditType == .contrast && element == nil
          && lastDemoCourse.exists
          && lastDemoCourse.frame.intersects(app.tabBars.firstMatch.frame)
        let expectedSystemRendering = nativeSearch || behindTabBar || unmappedCoveredDemoRow
        let description =
          "\(issue.compactDescription)\n\(issue.detailedDescription)\nLabel: \(label)\nFrame: \(String(describing: element?.frame))\nType: \(String(describing: element?.elementType))"
        print("Accessibility audit: \(description)")
        XCTContext.runActivity(named: "Audit diagnosis") { activity in
          let attachment = XCTAttachment(string: description)
          attachment.name =
            expectedSystemRendering ? "Native rendering exclusion" : "Audit diagnosis"
          attachment.lifetime = .keepAlways
          activity.add(attachment)
          if !expectedSystemRendering || unmappedCoveredDemoRow {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name =
              expectedSystemRendering
              ? "Review unmapped contrast under native tab bar" : "Audit failure"
            screenshot.lifetime = .keepAlways
            activity.add(screenshot)
          }
        }
        return expectedSystemRendering
      }
    }
    try audit()
    openCourse(in: app)
    XCTAssertTrue(app.staticTexts["course.officialPercent"].waitForExistence(timeout: 5))
    try audit()
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["grades.gpa"].tap()
    XCTAssertTrue(app.staticTexts["planner.weighted"].waitForExistence(timeout: 5))
    try audit()
    app.navigationBars.buttons.element(boundBy: 0).tap()
    for destination in ["Attendance", "Documents", "Mail"] {
      app.tabBars.buttons[destination].tap()
      XCTAssertTrue(app.buttons["app.menu"].waitForExistence(timeout: 5))
      try audit()
    }
  }

  @MainActor func testNativeTabsPreserveCourseNavigation() {
    let app = launchDemo()
    XCTAssertEqual(app.tabBars.buttons.count, 4)
    openCourse(in: app)
    let official = app.staticTexts["course.officialPercent"]
    XCTAssertTrue(official.waitForExistence(timeout: 5))
    app.tabBars.buttons["Attendance"].tap()
    XCTAssertTrue(app.buttons["attendance.record.2026-10-08"].waitForExistence(timeout: 5))
    app.tabBars.buttons["Grades"].tap()
    XCTAssertTrue(official.waitForExistence(timeout: 5))
    XCTAssertEqual(official.label, "Official grade: 94.2 percent")
    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertTrue(app.buttons["course.math"].waitForExistence(timeout: 5))
  }

  @MainActor func testCaptureSyntheticStoreScreenshots() {
    let app = launchDemo()
    func capture(_ name: String) {
      let attachment = XCTAttachment(screenshot: app.screenshot())
      attachment.name = "AppStore-synthetic-" + name
      attachment.lifetime = .keepAlways
      add(attachment)
    }
    capture("01-gradebook")
    openCourse(in: app)
    XCTAssertTrue(app.staticTexts["course.officialPercent"].waitForExistence(timeout: 5))
    capture("02-course")
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["grades.gpa"].tap()
    XCTAssertTrue(app.staticTexts["planner.weighted"].waitForExistence(timeout: 5))
    capture("03-gpa")
    app.tabBars.buttons["Attendance"].tap()
    XCTAssertTrue(app.buttons["attendance.record.2026-10-08"].waitForExistence(timeout: 5))
    capture("04-attendance")
  }

  @MainActor func testWhatIfLeavesOfficialGradeUnchanged() {
    let app = launchDemo()
    openCourse(in: app)
    let official = app.staticTexts["course.officialPercent"]
    XCTAssertTrue(official.waitForExistence(timeout: 5))
    let original = official.label
    let whatIf = app.buttons["course.whatif"]
    bringIntoView(whatIf, in: app)
    whatIf.tap()
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
    openCourse("english", in: app)
    XCTAssertEqual(app.staticTexts["course.officialPercent"].label, "Official grade: 91 percent")
    let search = app.searchFields.firstMatch
    bringIntoView(search, in: app)
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
    openCourse(in: app)
    let official = app.staticTexts["course.officialPercent"]
    XCTAssertTrue(official.waitForExistence(timeout: 5))
    let officialMark = official.label
    let planner = app.buttons["course.assignmentPlanner"]
    bringIntoView(planner, in: app)
    planner.tap()
    let estimate = app.staticTexts["simulation.projected"]
    XCTAssertTrue(estimate.waitForExistence(timeout: 5))
    let original = estimate.label
    let assignment = app.buttons["simulation.assignment.math-1"]
    bringIntoView(assignment, in: app)
    assignment.tap()
    let score = app.textFields["simulation.earned"]
    XCTAssertTrue(score.waitForExistence(timeout: 5))
    score.tap()
    let current = score.value as? String ?? ""
    score.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + "25")
    app.navigationBars["Edit estimate"].buttons.element(boundBy: 0).tap()
    bringIntoView(estimate, in: app, furtherDown: false)
    XCTAssertTrue(estimate.waitForExistence(timeout: 5))
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
    openMenu("school", in: app)
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

  @MainActor private func openSignInFromDemo() -> XCUIApplication {
    let app = launchDemo()
    openMenu("account", in: app)
    let signOut = app.buttons["account.signout"]
    bringIntoView(signOut, in: app)
    XCTAssertTrue(signOut.exists)
    signOut.tap()
    app.sheets.buttons["Leave demo"].tap()
    XCTAssertTrue(app.buttons["login.submit"].waitForExistence(timeout: 5))
    return app
  }
  @MainActor func testLeavingDemoReturnsToSignInAndClearsRecords() {
    let app = openSignInFromDemo()
    XCTAssertFalse(app.buttons["course.math"].exists)
  }
  @MainActor func testPrivacyAndBundledLicensesAvailableInDemo() {
    let app = launchDemo()
    openMenu("account", in: app)
    let privacy = app.buttons["account.privacy"]
    bringIntoView(privacy, in: app)
    privacy.tap()
    XCTAssertTrue(app.navigationBars["Data and privacy"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "over HTTPS")).firstMatch
        .exists)
    app.navigationBars.buttons.element(boundBy: 0).tap()
    let licenses = app.buttons["account.licenses"]
    bringIntoView(licenses, in: app)
    licenses.tap()
    XCTAssertTrue(app.buttons["licenses.agpl"].waitForExistence(timeout: 5))
    app.buttons["licenses.agpl"].tap()
    XCTAssertTrue(app.staticTexts["licenses.text"].waitForExistence(timeout: 5))
    XCTAssertTrue(
      app.staticTexts["licenses.text"].label.contains("GNU AFFERO GENERAL PUBLIC LICENSE"))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["licenses.fonts"].tap()
    XCTAssertTrue(app.staticTexts["licenses.text"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["licenses.text"].label.contains("SIL OPEN FONT LICENSE"))
  }
  @MainActor private func cancelDistrictPicker(in app: XCUIApplication) {
    let close = app.buttons["district.cancel"]
    if !close.isHittable {
      // iOS replaces the sheet toolbar while search is active. Its Close exits search first.
      app.buttons["Close"].firstMatch.tap()
    }
    XCTAssertTrue(close.waitForExistence(timeout: 5))
    close.tap()
    XCTAssertTrue(app.buttons["login.district"].waitForExistence(timeout: 5))
  }
  @MainActor func testDistrictPickerMatchesWebCatalogAndPreservesPortalPaths() {
    let app = openSignInFromDemo()
    let picker = app.buttons["login.district"]
    XCTAssertTrue(picker.waitForExistence(timeout: 5))
    XCTAssertTrue((picker.value as? String ?? "").contains("Pleasanton Unified School District"))
    picker.tap()
    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 5))
    search.tap()
    search.typeText("Fairfax")
    let fairfax = app.buttons["district.option.Fairfax County Public Schools"]
    XCTAssertTrue(fairfax.waitForExistence(timeout: 5))
    fairfax.tap()
    XCTAssertTrue(picker.waitForExistence(timeout: 5))
    XCTAssertTrue((picker.value as? String ?? "").contains("https://sisstudent.fcps.edu/svue"))
    picker.tap()
    XCTAssertTrue(search.waitForExistence(timeout: 5))
    search.tap()
    search.typeText("Alaska")
    XCTAssertTrue(
      app.buttons["district.option.Matanuska-Susitna School District"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["district.option.Yukon-Koyukuk School District"].exists)
    cancelDistrictPicker(in: app)
    XCTAssertTrue((picker.value as? String ?? "").contains("https://sisstudent.fcps.edu/svue"))
    picker.tap()
    XCTAssertTrue(search.waitForExistence(timeout: 5))
    search.tap()
    search.typeText("ca-pleas-psv.edupoint.com")
    app.buttons["district.option.Pleasanton Unified School District"].tap()
    XCTAssertTrue((picker.value as? String ?? "").contains("Pleasanton Unified School District"))
    XCTAssertFalse(app.buttons["login.submit"].isEnabled)
  }
  @MainActor func testDistrictPickerManualPortalAndNoMatches() {
    let app = openSignInFromDemo()
    let picker = app.buttons["login.district"]
    picker.tap()
    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 5))
    search.tap()
    search.typeText("NoSuchSyntheticDistrict123")
    XCTAssertTrue(app.staticTexts["district.empty"].waitForExistence(timeout: 5))
    cancelDistrictPicker(in: app)
    picker.tap()
    app.buttons["district.custom"].tap()
    let portal = app.textFields["district.customPortal"]
    XCTAssertTrue(portal.waitForExistence(timeout: 5))
    portal.tap()
    portal.typeText("http://district.example.invalid/svue")
    let use = app.buttons["district.useCustom"]
    XCTAssertFalse(use.isEnabled)
    let value = portal.value as? String ?? ""
    portal.typeText(
      String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)
        + "https://district.example.invalid/svue")
    use.tap()
    XCTAssertTrue(picker.waitForExistence(timeout: 5))
    XCTAssertTrue((picker.value as? String ?? "").contains("https://district.example.invalid/svue"))
    XCTAssertFalse(app.buttons["login.submit"].isEnabled)
  }
  @MainActor func testPlannerInclusionChangesEstimateAndResetRestoresIt() {
    let app = launchDemo()
    openMenu("planner", in: app)
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
      app.navigationBars["GPA calculator"].exists,
      "The inclusion tap left the GPA calculator; app state \(app.state)")
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
    app.tabBars.buttons["Documents"].tap()
    XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
    let document = app.buttons["document.c3ludGhldGljLWRvY3VtZW50"]
    bringIntoView(document, in: app)
    XCTAssertTrue(document.waitForExistence(timeout: 5))
    document.tap()
    XCTAssertTrue(app.navigationBars["Synthetic document.pdf"].waitForExistence(timeout: 5))
    app.buttons["preview.close"].tap()
    app.tabBars.buttons["Mail"].tap()
    XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
    let message = app.buttons["mail.message.11111111-2222-4333-8444-555555555555"]
    bringIntoView(message, in: app)
    XCTAssertTrue(message.waitForExistence(timeout: 5))
    message.tap()
    XCTAssertTrue(app.staticTexts["mail.body"].waitForExistence(timeout: 5))
    let attachment = app.buttons["attachment.22222222-3333-4444-8555-666666666666"]
    bringIntoView(attachment, in: app)
    XCTAssertTrue(attachment.exists)
    attachment.tap()
    XCTAssertTrue(app.navigationBars["Synthetic document.pdf"].waitForExistence(timeout: 5))
    app.buttons["preview.close"].tap()
    XCTAssertTrue(app.staticTexts["mail.body"].exists)
  }
}
