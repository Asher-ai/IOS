import Foundation
import Combine
import WidgetKit

@MainActor
final class StudyPlannerViewModel: ObservableObject {
    @Published private(set) var subjects: [StudySubject] = []
    @Published private(set) var assessments: [AssessmentPlan] = []
    @Published private(set) var upcoming: [AssessmentPlan] = []
    @Published private(set) var inbox: [SharedAssessmentReference] = []
    @Published var message: String?
    @Published var integrationNotice: String?
    @Published var selectedTab = 0
    @Published var routedAssessmentID: UUID?
    private let repository: any StudyRepository
    private let inboxRepository: any ShareInboxRepository

    init(repository: any StudyRepository, inboxRepository: any ShareInboxRepository = FileShareInboxRepository()) {
        self.repository = repository
        self.inboxRepository = inboxRepository
        refresh()
    }

    func refresh() {
        do {
            let overview = try ReviewStudyWorkloadUseCase(repository: repository).overview()
            subjects = overview.subjects
            assessments = overview.assessments
            upcoming = overview.upcoming
        } catch { message = error.localizedDescription; return }
        integrationNotice = nil
        do {
            let contents = try inboxRepository.contents()
            inbox = contents.references
            if contents.unreadableCount > 0 {
                integrationNotice = "\(contents.unreadableCount) shared reference(s) could not be read. They have been kept. Share the original content again to recover it."
            }
            let items = assessments.filter { !$0.isSubmitted }.prefix(12).map {
                DeadlineWidgetItem(id: $0.id, title: $0.title, subjectCode: subject(for: $0)?.code ?? "Subject", dueAt: $0.dueAt, nextStep: $0.nextStep)
            }
            try WidgetSnapshotRepository().save(DeadlineWidgetSnapshot(generatedAt: Date(), items: items))
            WidgetCenter.shared.reloadTimelines(ofKind: SharedGroup.widgetKind)
        } catch {
            // The primary save has succeeded; do not tell the student to create a duplicate.
            integrationNotice = "Your planner is saved. The shared inbox or widget needs attention: " + error.localizedDescription
        }
    }

    func registerSubject(code: String, name: String) -> Bool {
        perform { _ = try RegisterStudySubjectUseCase(repository: repository).execute(code: code, name: name) }
    }
    func plan(_ draft: AssessmentDraft) -> Bool {
        do {
            _ = try PlanAssessmentUseCase(repository: repository).execute(draft)
            var cleanupFailed = false
            if let id = draft.capturedReferenceID {
                do { try inboxRepository.remove(id: id) } catch { cleanupFailed = true }
            }
            refresh()
            if cleanupFailed { integrationNotice = "The assessment is saved, but its shared reference is still in the inbox. Reviewing it again will reuse the saved assessment." }
            return true
        } catch { message = error.localizedDescription; return false }
    }
    func recordSubmission(id: UUID) {
        _ = perform { try RecordAssessmentSubmissionUseCase(repository: repository).execute(id: id) }
    }
    func revise(id: UUID, dueAt: Date, nextStep: String, notes: String, confirmed: Bool) -> Bool {
        perform { try ReviseAssessmentPlanUseCase(repository: repository).execute(id: id, dueAt: dueAt, nextStep: nextStep, notes: notes, confirmed: confirmed) }
    }
    func discardReference(id: UUID) {
        _ = perform { try inboxRepository.remove(id: id) }
    }
    func subject(for plan: AssessmentPlan) -> StudySubject? { subjects.first { $0.id == plan.subjectID } }
    func open(_ url: URL) {
        guard url.scheme == "studydock" else { return }
        selectedTab = 0
        if url.host == "assessment", let id = UUID(uuidString: url.lastPathComponent) {
            refresh()
            if assessments.contains(where: { $0.id == id }) { routedAssessmentID = id }
            else { message = "This widget assessment is no longer available. Your current deadlines are shown in the planner." }
        }
    }

    func loadExampleSemester() {
        guard subjects.isEmpty, assessments.isEmpty else {
            message = "Example data is available only in an empty planner, so it cannot mix with your real assessments."
            return
        }
        _ = perform {
            let register = RegisterStudySubjectUseCase(repository: repository)
            let design = try register.execute(code: "DEMO 101", name: "Interaction Design (example)")
            let research = try register.execute(code: "DEMO 202", name: "Research Methods (example)")
            for (subject, title, hours, step) in [
                (design, "Prototype review", 18.0, "Test the first screen with a classmate"),
                (research, "Literature review", 64.0, "Compare three recent papers"),
                (design, "Design reflection", 140.0, "Outline the main design trade-off"),
                (research, "Research proposal", -8.0, "Check the late submission instructions")
            ] {
                _ = try PlanAssessmentUseCase(repository: repository).execute(AssessmentDraft(subjectID: subject.id, title: title,
                    dueAt: Date().addingTimeInterval(hours * 3_600), timeZoneID: TimeZone.current.identifier,
                    nextStep: step, notes: "Example assessment for demonstrating StudyDock. Not a real university deadline.",
                    sourceURL: "https://www.uts.edu.au", deadlineConfirmed: true))
            }
        }
    }

    private func perform(_ operation: () throws -> Void) -> Bool {
        do { try operation(); refresh(); return true }
        catch { message = error.localizedDescription; return false }
    }
}
