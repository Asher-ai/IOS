import XCTest
@testable import StudyDock

@MainActor
final class MockStudyRepository: StudyRepository {
    var storedSubjects: [StudySubject] = []
    var storedAssessments: [AssessmentPlan] = []
    var shouldFailSave = false
    var lastQueryCutoff: Date?
    func subjects() throws -> [StudySubject] { storedSubjects }
    func saveSubject(_ subject: StudySubject) throws {
        if shouldFailSave { throw StudyStorageError.saveFailed }
        storedSubjects.removeAll { $0.id == subject.id }; storedSubjects.append(subject)
    }
    func assessments() throws -> [AssessmentPlan] { storedAssessments.sorted { $0.dueAt < $1.dueAt } }
    func assessment(id: UUID) throws -> AssessmentPlan? { storedAssessments.first { $0.id == id } }
    func outstandingAssessments(dueBefore cutoff: Date) throws -> [AssessmentPlan] {
        lastQueryCutoff = cutoff
        return storedAssessments.filter { !$0.isSubmitted && $0.dueAt <= cutoff }.sorted { $0.dueAt < $1.dueAt }
    }
    func saveAssessment(_ assessment: AssessmentPlan) throws {
        if shouldFailSave { throw StudyStorageError.saveFailed }
        storedAssessments.removeAll { $0.id == assessment.id }; storedAssessments.append(assessment)
    }
}

final class MockShareInboxRepository: ShareInboxRepository {
    var references: [SharedAssessmentReference] = []
    func contents() throws -> ShareInboxContents { ShareInboxContents(references: references) }
    func save(_ reference: SharedAssessmentReference) throws { references.append(reference) }
    func remove(id: UUID) throws { references.removeAll { $0.id == id } }
}

final class StudyUseCaseTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_900_000)
    @MainActor private func setupPlanner() throws -> (MockStudyRepository, StudySubject) {
        let repository = MockStudyRepository()
        let subject = try RegisterStudySubjectUseCase(repository: repository).execute(code: "IOS101", name: "iOS Development")
        return (repository, subject)
    }
    private func draft(_ subject: StudySubject) -> AssessmentDraft {
        AssessmentDraft(subjectID: subject.id, title: "Platform project", dueAt: now.addingTimeInterval(3_600), timeZoneID: "Australia/Sydney", nextStep: "Read the rubric", deadlineConfirmed: true)
    }

    @MainActor func testRegisteringSubjectTrimsAndNormalisesItsCode() throws {
        let repository = MockStudyRepository()
        let subject = try RegisterStudySubjectUseCase(repository: repository).execute(code: " ios101 ", name: " iOS Development ")
        XCTAssertEqual(subject.code, "IOS101"); XCTAssertEqual(subject.name, "iOS Development")
        XCTAssertEqual(try repository.subjects(), [subject])
    }
    @MainActor func testASecondSubjectCannotReuseTheSameCodeWithDifferentCase() throws {
        let (repository, _) = try setupPlanner()
        XCTAssertThrowsError(try RegisterStudySubjectUseCase(repository: repository).execute(code: "ios101", name: "Other subject")) {
            XCTAssertEqual($0 as? RegisterStudySubjectUseCase.Failure, .subjectAlreadyRegistered)
        }
        XCTAssertEqual(repository.storedSubjects.count, 1)
    }
    @MainActor func testSubjectWithoutNameIsNotRegistered() {
        let repository = MockStudyRepository()
        XCTAssertThrowsError(try RegisterStudySubjectUseCase(repository: repository).execute(code: "IOS101", name: "  ")) {
            XCTAssertEqual($0 as? RegisterStudySubjectUseCase.Failure, .missingCodeOrName)
        }
        XCTAssertTrue(repository.storedSubjects.isEmpty)
    }
    @MainActor func testConfirmedAssessmentIsSavedUnderItsSubject() throws {
        let (repository, subject) = try setupPlanner()
        let plan = try PlanAssessmentUseCase(repository: repository).execute(draft(subject))
        XCTAssertEqual(try repository.assessment(id: plan.id), plan)
        XCTAssertEqual(plan.subjectID, subject.id); XCTAssertFalse(plan.isSubmitted)
    }
    @MainActor func testUnconfirmedDeadlineCannotEnterThePlanner() throws {
        let (repository, subject) = try setupPlanner()
        var request = draft(subject); request.deadlineConfirmed = false
        XCTAssertThrowsError(try PlanAssessmentUseCase(repository: repository).execute(request)) {
            XCTAssertEqual($0 as? PlanAssessmentUseCase.Failure, .deadlineNotConfirmed)
        }
        XCTAssertTrue(repository.storedAssessments.isEmpty)
    }
    @MainActor func testAssessmentNeedsAConcreteNextStudyStep() throws {
        let (repository, subject) = try setupPlanner()
        var request = draft(subject); request.nextStep = " \n "
        XCTAssertThrowsError(try PlanAssessmentUseCase(repository: repository).execute(request)) {
            XCTAssertEqual($0 as? PlanAssessmentUseCase.Failure, .missingNextStep)
        }
    }
    @MainActor func testAssessmentCannotBelongToAnUnknownSubject() throws {
        let (repository, subject) = try setupPlanner()
        var request = draft(subject); request.subjectID = UUID()
        XCTAssertThrowsError(try PlanAssessmentUseCase(repository: repository).execute(request)) {
            XCTAssertEqual($0 as? PlanAssessmentUseCase.Failure, .subjectMissing)
        }
    }
    @MainActor func testBlankAssessmentTitleIsRejected() throws {
        let (repository, subject) = try setupPlanner()
        var request = draft(subject); request.title = " "
        XCTAssertThrowsError(try PlanAssessmentUseCase(repository: repository).execute(request)) {
            XCTAssertEqual($0 as? PlanAssessmentUseCase.Failure, .missingTitle)
        }
    }
    @MainActor func testNonWebAssignmentLinksAreRejected() throws {
        let (repository, subject) = try setupPlanner()
        var request = draft(subject); request.sourceURL = "javascript:alert(1)"
        XCTAssertThrowsError(try PlanAssessmentUseCase(repository: repository).execute(request)) {
            XCTAssertEqual($0 as? PlanAssessmentUseCase.Failure, .invalidSourceLink)
        }
    }
    @MainActor func testOverdueAssessmentCanBeRecordedInsteadOfHidden() throws {
        let (repository, subject) = try setupPlanner()
        var request = draft(subject); request.dueAt = now.addingTimeInterval(-1)
        let plan = try PlanAssessmentUseCase(repository: repository).execute(request)
        XCTAssertTrue(plan.isOverdue(at: now))
    }
    @MainActor func testRetryingASharedReferenceReusesTheSavedAssessment() throws {
        let (repository, subject) = try setupPlanner()
        var request = draft(subject); request.capturedReferenceID = UUID()
        let first = try PlanAssessmentUseCase(repository: repository).execute(request)
        let retry = try PlanAssessmentUseCase(repository: repository).execute(request)
        XCTAssertEqual(first.id, retry.id); XCTAssertEqual(repository.storedAssessments.count, 1)
    }
    @MainActor func testRecordingSubmissionPersistsItsTimestamp() throws {
        let (repository, subject) = try setupPlanner()
        let plan = try PlanAssessmentUseCase(repository: repository).execute(draft(subject))
        try RecordAssessmentSubmissionUseCase(repository: repository).execute(id: plan.id, at: now)
        XCTAssertEqual(try repository.assessment(id: plan.id)?.submittedAt, now)
    }
    @MainActor func testAnAssessmentCannotBeMarkedSubmittedTwice() throws {
        let (repository, subject) = try setupPlanner()
        let plan = try PlanAssessmentUseCase(repository: repository).execute(draft(subject))
        let useCase = RecordAssessmentSubmissionUseCase(repository: repository)
        try useCase.execute(id: plan.id, at: now)
        XCTAssertThrowsError(try useCase.execute(id: plan.id, at: now)) { XCTAssertEqual($0 as? RecordAssessmentSubmissionUseCase.Failure, .alreadySubmitted) }
    }
    @MainActor func testMissingAssessmentCannotBeMarkedSubmitted() throws {
        XCTAssertThrowsError(try RecordAssessmentSubmissionUseCase(repository: MockStudyRepository()).execute(id: UUID())) {
            XCTAssertEqual($0 as? RecordAssessmentSubmissionUseCase.Failure, .assessmentMissing)
        }
    }
    @MainActor func testWorkloadIncludesTheCutoffAndOverdueButExcludesSubmittedAndLaterWork() throws {
        let (repository, subject) = try setupPlanner()
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let cutoff = calendar.date(byAdding: .day, value: 7, to: now)!
        var ids: [UUID] = []
        for date in [now.addingTimeInterval(-100), cutoff, cutoff.addingTimeInterval(1), now] {
            var request = draft(subject); request.dueAt = date
            ids.append(try PlanAssessmentUseCase(repository: repository).execute(request).id)
        }
        try RecordAssessmentSubmissionUseCase(repository: repository).execute(id: ids[3], at: now)
        let result = try ReviewStudyWorkloadUseCase(repository: repository).execute(now: now, days: 7, calendar: calendar)
        XCTAssertEqual(result.map(\.id), Array(ids.prefix(2)))
        XCTAssertEqual(repository.lastQueryCutoff, cutoff)
    }
    @MainActor func testZeroDayWorkloadWindowIsRejected() {
        XCTAssertThrowsError(try ReviewStudyWorkloadUseCase(repository: MockStudyRepository()).execute(now: now, days: 0)) {
            XCTAssertEqual($0 as? ReviewStudyWorkloadUseCase.Failure, .invalidPlanningWindow)
        }
    }
    @MainActor func testRevisedDeadlineAndNextStepAreSavedTogether() throws {
        let (repository, subject) = try setupPlanner()
        let plan = try PlanAssessmentUseCase(repository: repository).execute(draft(subject))
        try ReviseAssessmentPlanUseCase(repository: repository).execute(id: plan.id, dueAt: now, nextStep: "Write the introduction", notes: "Extension confirmed", confirmed: true)
        let saved = try XCTUnwrap(repository.assessment(id: plan.id))
        XCTAssertEqual(saved.dueAt, now); XCTAssertEqual(saved.nextStep, "Write the introduction"); XCTAssertEqual(saved.notes, "Extension confirmed")
    }
    @MainActor func testDeadlineRevisionRequiresFreshConfirmation() throws {
        let (repository, subject) = try setupPlanner()
        let plan = try PlanAssessmentUseCase(repository: repository).execute(draft(subject))
        XCTAssertThrowsError(try ReviseAssessmentPlanUseCase(repository: repository).execute(id: plan.id, dueAt: now, nextStep: "Draft", notes: "", confirmed: false)) {
            XCTAssertEqual($0 as? ReviseAssessmentPlanUseCase.Failure, .deadlineNotConfirmed)
        }
        XCTAssertEqual(try repository.assessment(id: plan.id), plan)
    }
    @MainActor func testSubmittedAssessmentCannotBeRevised() throws {
        let (repository, subject) = try setupPlanner()
        let plan = try PlanAssessmentUseCase(repository: repository).execute(draft(subject))
        try RecordAssessmentSubmissionUseCase(repository: repository).execute(id: plan.id)
        XCTAssertThrowsError(try ReviseAssessmentPlanUseCase(repository: repository).execute(id: plan.id, dueAt: now, nextStep: "Draft", notes: "", confirmed: true)) {
            XCTAssertEqual($0 as? ReviseAssessmentPlanUseCase.Failure, .submittedAssessment)
        }
    }
    @MainActor func testRepositorySaveFailureDoesNotCreateAnAssessment() throws {
        let (repository, subject) = try setupPlanner(); repository.shouldFailSave = true
        XCTAssertThrowsError(try PlanAssessmentUseCase(repository: repository).execute(draft(subject)))
        XCTAssertTrue(repository.storedAssessments.isEmpty)
    }
    func testWebReferenceIsCapturedWithItsOriginalSource() throws {
        let repository = MockShareInboxRepository()
        let reference = try CaptureAssessmentReferenceUseCase(repository: repository).execute(title: "Research brief", text: "", sourceURL: "https://canvas.uts.edu.au/", now: now)
        XCTAssertEqual(repository.references, [reference]); XCTAssertEqual(reference.capturedAt, now)
        XCTAssertEqual(reference.sourceURL, "https://canvas.uts.edu.au/")
    }
    func testPlainTextReferenceCanBeCapturedWithoutALink() throws {
        let repository = MockShareInboxRepository()
        let reference = try CaptureAssessmentReferenceUseCase(repository: repository).execute(title: "", text: "Prepare the research proposal", sourceURL: nil)
        XCTAssertNil(reference.sourceURL); XCTAssertEqual(reference.title, "Shared assessment")
        XCTAssertEqual(repository.references.count, 1)
    }
    func testEmptySharedReferenceIsRejected() {
        XCTAssertThrowsError(try CaptureAssessmentReferenceUseCase(repository: MockShareInboxRepository()).execute(title: "Title only", text: " ", sourceURL: nil)) {
            XCTAssertEqual($0 as? CaptureAssessmentReferenceUseCase.Failure, .emptyReference)
        }
    }
    func testNonWebSharedLinkIsRejected() {
        XCTAssertThrowsError(try CaptureAssessmentReferenceUseCase(repository: MockShareInboxRepository()).execute(title: "Brief", text: "", sourceURL: "file:///private/brief.pdf")) {
            XCTAssertEqual($0 as? CaptureAssessmentReferenceUseCase.Failure, .unsupportedLink)
        }
    }
    func testEightThousandCharacterReferenceIsAcceptedAtTheBoundary() throws {
        let repository = MockShareInboxRepository()
        _ = try CaptureAssessmentReferenceUseCase(repository: repository).execute(title: "Brief", text: String(repeating: "a", count: 8_000), sourceURL: nil)
        XCTAssertEqual(repository.references.count, 1)
    }
    func testOversizedReferenceIsRejectedWithoutSaving() {
        let repository = MockShareInboxRepository()
        XCTAssertThrowsError(try CaptureAssessmentReferenceUseCase(repository: repository).execute(title: "Brief", text: String(repeating: "a", count: 8_001), sourceURL: nil)) {
            XCTAssertEqual($0 as? CaptureAssessmentReferenceUseCase.Failure, .referenceTooLong)
        }
        XCTAssertTrue(repository.references.isEmpty)
    }
}
