import XCTest

/// Run on a dedicated clean simulator: these tests create real, clearly labelled test records.
final class StudyDockWorkflowTests: XCTestCase {
    /// Run after loading the example semester; also prompts the installed widget to reload.
    func testSubmittingOverdueAssessmentRemovesItFromActiveWorkload() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let proposal = app.staticTexts["Research proposal"]
        try XCTSkipIf(!proposal.waitForExistence(timeout: 5), "Load the example semester before this scenario.")
        proposal.tap()
        app.swipeUp()
        app.buttons["markSubmitted"].tap()
        app.buttons["Yes, record submission"].tap()
        XCTAssertTrue(app.staticTexts["Submitted"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertFalse(app.staticTexts["Research proposal"].exists)
        XCUIDevice.shared.press(.home)
    }

    /// Precondition: share a test URL from Safari into StudyDock on the dedicated simulator.
    func testSharedSafariReferenceCanBeConfirmedAndRemovedFromInbox() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Shared inbox"].tap()
        let review = app.buttons.containing(.staticText, identifier: "Review & confirm deadline").firstMatch
        try XCTSkipIf(!review.waitForExistence(timeout: 5), "Share a URL from Safari before this integration scenario.")
        review.tap()
        let title = app.textFields["assessmentTitle"]
        let importedTitle = try XCTUnwrap(title.value as? String)
        XCTAssertFalse(importedTitle.isEmpty)
        let step = app.textFields["nextStep"]
        step.tap(); step.typeText("Verify the official assignment instructions")
        app.buttons["confirmDeadline"].tap()
        app.buttons["saveAssessment"].tap()
        XCTAssertTrue(app.staticTexts["Nothing waiting to be planned"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Deadlines"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts[importedTitle].waitForExistence(timeout: 5))
        app.staticTexts[importedTitle].tap()
        XCTAssertTrue(app.buttons["Open official assignment page"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Safari reference persisted as confirmed assessment"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testExampleSemesterDisplaysUpcomingAndOverdueAssessments() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Guide"].tap()
        let examples = app.buttons["loadExamples"]
        app.swipeUp()
        if examples.isEnabled { examples.tap() }
        else { app.tabBars.buttons["Deadlines"].tap() }
        XCTAssertTrue(app.staticTexts["Research proposal"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Overdue"].exists)
        XCTAssertTrue(app.staticTexts["Prototype review"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Example semester with overdue and upcoming work"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testStudentCanPlanAnAssessmentRelaunchAndRecordSubmission() throws {
        let app = XCUIApplication()
        continueAfterFailure = false
        app.launch()
        let suffix = String(UUID().uuidString.prefix(6))
        app.tabBars.buttons["Subjects"].tap()
        app.buttons["addSubject"].tap()
        app.textFields["subjectCode"].tap(); app.textFields["subjectCode"].typeText("TEST-" + suffix)
        app.textFields["subjectName"].tap(); app.textFields["subjectName"].typeText("Workflow test subject")
        app.buttons["saveSubject"].tap()
        app.tabBars.buttons["Deadlines"].tap()
        app.buttons["planAssessment"].tap()
        app.textFields["assessmentTitle"].tap(); app.textFields["assessmentTitle"].typeText("UI assessment " + suffix)
        let nextStep = app.textViews["nextStep"]
        if nextStep.exists { nextStep.tap(); nextStep.typeText("Read the assignment brief") }
        else { app.textFields["nextStep"].tap(); app.textFields["nextStep"].typeText("Read the assignment brief") }
        let confirmation = app.buttons["confirmDeadline"]
        confirmation.tap()
        XCTAssertEqual(confirmation.value as? String, "Confirmed", "The student explicitly confirmed the deadline")
        app.buttons["saveAssessment"].tap()
        XCTAssertTrue(app.staticTexts["UI assessment " + suffix].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["UI assessment " + suffix].waitForExistence(timeout: 5))
        app.staticTexts["UI assessment " + suffix].tap()
        app.swipeUp()
        app.buttons["markSubmitted"].tap()
        app.buttons["Yes, record submission"].tap()
        XCTAssertTrue(app.staticTexts["Submitted"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Assessment submission persisted"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
