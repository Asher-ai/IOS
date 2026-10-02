import Foundation

@MainActor
struct RegisterStudySubjectUseCase {
    enum Failure: LocalizedError, Equatable {
        case missingCodeOrName, subjectAlreadyRegistered
        var errorDescription: String? {
            switch self {
            case .missingCodeOrName: return "Give this subject a code and a name so you can recognise its assessments."
            case .subjectAlreadyRegistered: return "That subject code is already in your planner. Choose the existing subject or use a different code."
            }
        }
    }
    let repository: any StudyRepository
    func execute(code: String, name: String) throws -> StudySubject {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, !name.isEmpty else { throw Failure.missingCodeOrName }
        guard try !repository.subjects().contains(where: { $0.code.caseInsensitiveCompare(code) == .orderedSame }) else {
            throw Failure.subjectAlreadyRegistered
        }
        let subject = StudySubject(id: UUID(), code: code, name: name)
        try repository.saveSubject(subject)
        return subject
    }
}

struct AssessmentDraft {
    var subjectID: UUID
    var title: String
    var dueAt: Date
    var timeZoneID: String
    var nextStep: String
    var notes: String = ""
    var sourceURL: String = ""
    var deadlineConfirmed: Bool
    var capturedReferenceID: UUID? = nil
}

@MainActor
struct PlanAssessmentUseCase {
    enum Failure: LocalizedError, Equatable {
        case missingTitle, missingNextStep, subjectMissing, deadlineNotConfirmed, invalidSourceLink, invalidTimeZone
        var errorDescription: String? {
            switch self {
            case .missingTitle: return "Name the assessment before saving it, for example 'Research report'."
            case .missingNextStep: return "Add one concrete next step, such as 'Read the marking criteria', to make this assessment actionable."
            case .subjectMissing: return "Choose a registered subject for this assessment. Add the subject in Subjects if it is missing."
            case .deadlineNotConfirmed: return "Check the deadline against your subject outline or assignment page, then confirm the date and time."
            case .invalidSourceLink: return "The assessment link must begin with https:// or http:// and include a website name. Correct it or leave the link empty."
            case .invalidTimeZone: return "Choose a valid time zone for the assessment deadline before saving."
            }
        }
    }
    let repository: any StudyRepository
    func execute(_ draft: AssessmentDraft, id: UUID = UUID()) throws -> AssessmentPlan {
        // Retrying a share import after an interrupted inbox cleanup must not duplicate work.
        if let referenceID = draft.capturedReferenceID,
           let existing = try repository.assessments().first(where: { $0.capturedReferenceID == referenceID }) { return existing }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let step = draft.nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw Failure.missingTitle }
        guard !step.isEmpty else { throw Failure.missingNextStep }
        guard try repository.subjects().contains(where: { $0.id == draft.subjectID }) else { throw Failure.subjectMissing }
        guard draft.deadlineConfirmed else { throw Failure.deadlineNotConfirmed }
        guard TimeZone(identifier: draft.timeZoneID) != nil else { throw Failure.invalidTimeZone }
        let link = draft.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard link.isEmpty || SharedLinkValidation.isWebURL(link) else { throw Failure.invalidSourceLink }
        // Past deadlines are deliberately allowed: students need to record overdue work too.
        let plan = AssessmentPlan(id: id, subjectID: draft.subjectID, title: title,
                                  dueAt: draft.dueAt, timeZoneID: draft.timeZoneID,
                                  nextStep: step, notes: draft.notes, sourceURL: link.isEmpty ? nil : URL(string: link),
                                  submittedAt: nil, capturedReferenceID: draft.capturedReferenceID)
        try repository.saveAssessment(plan)
        return plan
    }
}

@MainActor
struct RecordAssessmentSubmissionUseCase {
    enum Failure: LocalizedError, Equatable {
        case assessmentMissing, alreadySubmitted
        var errorDescription: String? {
            switch self {
            case .assessmentMissing: return "This assessment is no longer in your planner. Return to Deadlines and select another assessment."
            case .alreadySubmitted: return "This assessment is already marked submitted. Check its submission record in your planner."
            }
        }
    }
    let repository: any StudyRepository
    func execute(id: UUID, at date: Date = Date()) throws {
        guard var plan = try repository.assessment(id: id) else { throw Failure.assessmentMissing }
        guard !plan.isSubmitted else { throw Failure.alreadySubmitted }
        plan.submittedAt = date
        try repository.saveAssessment(plan)
    }
}

@MainActor
struct ReviseAssessmentPlanUseCase {
    enum Failure: LocalizedError, Equatable {
        case assessmentMissing, submittedAssessment, missingNextStep, deadlineNotConfirmed
        var errorDescription: String? {
            switch self {
            case .assessmentMissing: return "This assessment could not be found. Return to Deadlines and reopen it."
            case .submittedAssessment: return "This assessment is already submitted. Its deadline record is kept for your reference."
            case .missingNextStep: return "Write your next study step before updating this assessment."
            case .deadlineNotConfirmed: return "Confirm the revised deadline against your official assignment page before saving it."
            }
        }
    }
    let repository: any StudyRepository
    func execute(id: UUID, dueAt: Date, nextStep: String, notes: String, confirmed: Bool) throws {
        guard var plan = try repository.assessment(id: id) else { throw Failure.assessmentMissing }
        guard !plan.isSubmitted else { throw Failure.submittedAssessment }
        guard !nextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.missingNextStep }
        guard confirmed else { throw Failure.deadlineNotConfirmed }
        plan.dueAt = dueAt
        plan.timeZoneID = TimeZone.current.identifier
        plan.nextStep = nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.notes = notes
        try repository.saveAssessment(plan)
    }
}

@MainActor
struct ReviewStudyWorkloadUseCase {
    enum Failure: LocalizedError, Equatable {
        case invalidPlanningWindow
        var errorDescription: String? { "Choose a planning window between 1 and 31 days to review your upcoming assessments." }
    }
    let repository: any StudyRepository
    func overview() throws -> (subjects: [StudySubject], assessments: [AssessmentPlan], upcoming: [AssessmentPlan]) {
        (try repository.subjects(), try repository.assessments(), try execute())
    }
    func execute(now: Date = Date(), days: Int = 7, calendar: Calendar = .current) throws -> [AssessmentPlan] {
        guard (1...31).contains(days), let cutoff = calendar.date(byAdding: .day, value: days, to: now) else {
            throw Failure.invalidPlanningWindow
        }
        return try repository.outstandingAssessments(dueBefore: cutoff)
    }
}
