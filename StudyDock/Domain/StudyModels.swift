import Foundation

struct StudySubject: Identifiable, Equatable {
    let id: UUID
    var code: String
    var name: String
}

struct AssessmentPlan: Identifiable, Equatable {
    let id: UUID
    let subjectID: UUID
    var title: String
    var dueAt: Date
    var timeZoneID: String
    var nextStep: String
    var notes: String
    var sourceURL: URL?
    var submittedAt: Date?
    let capturedReferenceID: UUID?

    var isSubmitted: Bool { submittedAt != nil }
    func isOverdue(at now: Date) -> Bool { !isSubmitted && dueAt <= now }
}

@MainActor
protocol StudyRepository {
    func subjects() throws -> [StudySubject]
    func saveSubject(_ subject: StudySubject) throws
    func assessments() throws -> [AssessmentPlan]
    func assessment(id: UUID) throws -> AssessmentPlan?
    /// Includes overdue work so missed deadlines cannot silently disappear.
    func outstandingAssessments(dueBefore cutoff: Date) throws -> [AssessmentPlan]
    func saveAssessment(_ assessment: AssessmentPlan) throws
}

enum StudyStorageError: LocalizedError {
    case unavailable, saveFailed, invalidRecord, sharedContainerUnavailable
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Your study planner could not be opened. Close and reopen StudyDock; keep the app installed so your saved work is preserved."
        case .saveFailed: return "This change could not be saved to your study planner. Check available device storage, then try again."
        case .invalidRecord: return "A saved assessment could not be read. Keep the app installed and restore your device backup if the problem continues."
        case .sharedContainerUnavailable: return "StudyDock cannot reach its shared inbox. Check that the app and both extensions use the same App Group in Xcode, then reinstall this development build."
        }
    }
}
