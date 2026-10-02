import Foundation

enum SharedLinkValidation {
    static func isWebURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), let host = url.host, !host.isEmpty else { return false }
        return !value.contains(where: { $0.isWhitespace })
    }
}

enum SharedGroup {
    static let identifier = Bundle.main.object(forInfoDictionaryKey: "StudyDockAppGroup") as? String ?? "group.au.edu.studydock.shared"
    static let widgetKind = "StudyDockDeadlines"
    static func containerURL() throws -> URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw SharedFileError.unavailable
        }
        return url
    }
}

enum SharedFileError: LocalizedError {
    case unavailable, cannotSave, cannotRead
    var errorDescription: String? {
        switch self {
        case .unavailable: return "StudyDock's shared inbox is unavailable. Open StudyDock once and check the App Group setup before sharing again."
        case .cannotSave: return "Your reference could not be saved. Check free device storage, then share it again."
        case .cannotRead: return "Some shared study information could not be read. Reopen StudyDock and try again; your original reference has been kept."
        }
    }
}

struct SharedAssessmentReference: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let text: String
    let sourceURL: String?
    let capturedAt: Date
}

struct ShareInboxContents {
    var references: [SharedAssessmentReference]
    var unreadableCount: Int = 0
}

protocol ShareInboxRepository {
    func contents() throws -> ShareInboxContents
    func save(_ reference: SharedAssessmentReference) throws
    func remove(id: UUID) throws
}

/// One atomic file per capture avoids cross-process read-modify-write races.
struct FileShareInboxRepository: ShareInboxRepository {
    var rootURL: URL? = nil
    private func directory() throws -> URL {
        let directory = try (rootURL ?? SharedGroup.containerURL()).appendingPathComponent("ShareInbox", isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { throw SharedFileError.cannotSave }
        return directory
    }
    func contents() throws -> ShareInboxContents {
        let directory = try directory()
        var result = ShareInboxContents(references: [])
        let files: [URL]
        do { files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) }
        catch { throw SharedFileError.cannotRead }
        for url in files where url.pathExtension == "json" {
            do { result.references.append(try JSONDecoder().decode(SharedAssessmentReference.self, from: Data(contentsOf: url))) }
            catch { result.unreadableCount += 1 } // Keep damaged captures; do not silently delete them.
        }
        result.references.sort { $0.capturedAt > $1.capturedAt }
        return result
    }
    func save(_ reference: SharedAssessmentReference) throws {
        let file = try directory().appendingPathComponent(reference.id.uuidString + ".json")
        do { try JSONEncoder().encode(reference).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        catch { throw SharedFileError.cannotSave }
    }
    func remove(id: UUID) throws {
        let file = try directory().appendingPathComponent(id.uuidString + ".json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do { try FileManager.default.removeItem(at: file) }
        catch { throw SharedFileError.cannotSave }
    }
}

struct CaptureAssessmentReferenceUseCase {
    enum Failure: LocalizedError, Equatable {
        case emptyReference, unsupportedLink, referenceTooLong
        var errorDescription: String? {
            switch self {
            case .emptyReference: return "Share an assignment web link or some assessment text, then try again."
            case .unsupportedLink: return "This link is not a web page. Share an http or https assignment link, or share its text instead."
            case .referenceTooLong: return "This reference is too long. Share a shorter excerpt (up to 8,000 characters) or the assignment link."
            }
        }
    }
    let repository: any ShareInboxRepository
    func execute(title: String, text: String, sourceURL: String?, now: Date = Date()) throws -> SharedAssessmentReference {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !(link ?? "").isEmpty else { throw Failure.emptyReference }
        if let link, !SharedLinkValidation.isWebURL(link) { throw Failure.unsupportedLink }
        guard text.count <= 8_000, (link?.count ?? 0) <= 2_048 else { throw Failure.referenceTooLong }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let reference = SharedAssessmentReference(id: UUID(), title: String((cleanTitle.isEmpty ? "Shared assessment" : cleanTitle).prefix(160)), text: text, sourceURL: link, capturedAt: now)
        try repository.save(reference)
        return reference
    }
}

struct DeadlineWidgetItem: Codable, Identifiable {
    let id: UUID
    let title: String
    let subjectCode: String
    let dueAt: Date
    let nextStep: String
}

struct DeadlineWidgetSnapshot: Codable {
    let generatedAt: Date
    let items: [DeadlineWidgetItem]
}

struct WidgetSnapshotRepository {
    var rootURL: URL? = nil
    private func file() throws -> URL {
        try (rootURL ?? SharedGroup.containerURL()).appendingPathComponent("deadline-snapshot.json")
    }
    func save(_ snapshot: DeadlineWidgetSnapshot) throws {
        do { try JSONEncoder().encode(snapshot).write(to: file(), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        catch { throw SharedFileError.cannotSave }
    }
    func load() throws -> DeadlineWidgetSnapshot? {
        let url = try file()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do { return try JSONDecoder().decode(DeadlineWidgetSnapshot.self, from: Data(contentsOf: url)) }
        catch { throw SharedFileError.cannotRead }
    }
}
