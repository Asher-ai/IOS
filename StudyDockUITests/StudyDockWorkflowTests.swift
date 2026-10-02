import XCTest

/// Run on a dedicated clean simulator: these tests create real, clearly labelled test records.
final class StudyDockWorkflowTests: XCTestCase {
    func testStudentCanPlanAnAssessmentRelaunchAndRecordSubmission() throws {
        let app = XCUIApplication()
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
        app.swipeDown()
        app.switches["confirmDeadline"].tap()
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
