import CoreData
import Foundation

/// Core Data never escapes this implementation. Domain code sees value types only.
@MainActor
final class CoreDataStudyRepository: StudyRepository {
    private let container: NSPersistentContainer
    private var context: NSManagedObjectContext { container.viewContext }

    init(storeURL: URL? = nil) throws {
        guard let modelURL = Bundle.main.url(forResource: "StudyDock", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else { throw StudyStorageError.unavailable }
        container = NSPersistentContainer(name: "StudyDock", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        if let storeURL { description.url = storeURL }
        else {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            description.url = directory.appendingPathComponent("StudyDock.sqlite")
        }
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(FileProtectionType.completeUntilFirstUserAuthentication as NSObject, forKey: NSPersistentStoreFileProtectionKey)
        container.persistentStoreDescriptions = [description]
        var loadingError: Swift.Error?
        container.loadPersistentStores { _, error in loadingError = error }
        if loadingError != nil { throw StudyStorageError.unavailable }
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func subjects() throws -> [StudySubject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "StudySubjectRecord")
        request.sortDescriptors = [NSSortDescriptor(key: "code", ascending: true)]
        return try fetch(request).map {
            guard let id = $0.value(forKey: "id") as? UUID, let code = $0.value(forKey: "code") as? String,
                  let name = $0.value(forKey: "name") as? String else { throw StudyStorageError.invalidRecord }
            return StudySubject(id: id, code: code, name: name)
        }
    }

    func saveSubject(_ subject: StudySubject) throws {
        let object = try object(entity: "StudySubjectRecord", id: subject.id) ?? NSEntityDescription.insertNewObject(forEntityName: "StudySubjectRecord", into: context)
        object.setValue(subject.id, forKey: "id")
        object.setValue(subject.code, forKey: "code")
        object.setValue(subject.name, forKey: "name")
        try persist()
    }

    func assessments() throws -> [AssessmentPlan] { try fetchPlans(predicate: nil) }
    func assessment(id: UUID) throws -> AssessmentPlan? {
        try object(entity: "AssessmentRecord", id: id).map(plan)
    }
    func outstandingAssessments(dueBefore cutoff: Date) throws -> [AssessmentPlan] {
        try fetchPlans(predicate: NSPredicate(format: "submittedAt == nil AND dueAt <= %@", cutoff as NSDate))
    }

    func saveAssessment(_ assessment: AssessmentPlan) throws {
        guard let subject = try object(entity: "StudySubjectRecord", id: assessment.subjectID) else { throw StudyStorageError.invalidRecord }
        let object = try object(entity: "AssessmentRecord", id: assessment.id) ?? NSEntityDescription.insertNewObject(forEntityName: "AssessmentRecord", into: context)
        object.setValue(assessment.id, forKey: "id")
        object.setValue(subject, forKey: "subject")
        object.setValue(assessment.title, forKey: "title")
        object.setValue(assessment.dueAt, forKey: "dueAt")
        object.setValue(assessment.timeZoneID, forKey: "timeZoneID")
        object.setValue(assessment.nextStep, forKey: "nextStep")
        object.setValue(assessment.notes, forKey: "notes")
        object.setValue(assessment.sourceURL?.absoluteString, forKey: "sourceURL")
        object.setValue(assessment.submittedAt, forKey: "submittedAt")
        object.setValue(assessment.capturedReferenceID, forKey: "capturedReferenceID")
        try persist()
    }

    private func persist() throws {
        do { try context.save() }
        catch { context.rollback(); throw StudyStorageError.saveFailed }
    }
    private func fetch(_ request: NSFetchRequest<NSManagedObject>) throws -> [NSManagedObject] {
        do { return try context.fetch(request) }
        catch { throw StudyStorageError.unavailable }
    }
    private func object(entity: String, id: UUID) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        return try fetch(request).first
    }
    private func fetchPlans(predicate: NSPredicate?) throws -> [AssessmentPlan] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "AssessmentRecord")
        request.predicate = predicate
        request.sortDescriptors = [NSSortDescriptor(key: "dueAt", ascending: true), NSSortDescriptor(key: "title", ascending: true)]
        return try fetch(request).map(plan)
    }
    private func plan(_ object: NSManagedObject) throws -> AssessmentPlan {
        guard let id = object.value(forKey: "id") as? UUID,
              let subject = object.value(forKey: "subject") as? NSManagedObject,
              let subjectID = subject.value(forKey: "id") as? UUID,
              let title = object.value(forKey: "title") as? String,
              let dueAt = object.value(forKey: "dueAt") as? Date,
              let timeZoneID = object.value(forKey: "timeZoneID") as? String,
              let nextStep = object.value(forKey: "nextStep") as? String else { throw StudyStorageError.invalidRecord }
        return AssessmentPlan(id: id, subjectID: subjectID, title: title, dueAt: dueAt, timeZoneID: timeZoneID,
                              nextStep: nextStep, notes: object.value(forKey: "notes") as? String ?? "",
                              sourceURL: (object.value(forKey: "sourceURL") as? String).flatMap(URL.init(string:)),
                              submittedAt: object.value(forKey: "submittedAt") as? Date,
                              capturedReferenceID: object.value(forKey: "capturedReferenceID") as? UUID)
    }
}
