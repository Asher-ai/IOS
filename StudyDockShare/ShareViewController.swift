import UIKit
import UniformTypeIdentifiers

/// A short capture flow: retain the reference now, confirm its deadline in the main app.
final class ShareViewController: UIViewController {
    private let titleField = UITextField()
    private let preview = UILabel()
    private let status = UILabel()
    private let saveButton = UIButton(type: .system)
    private var sharedText = ""
    private var sharedURL: String?
    private var didFinish = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let heading = UILabel()
        heading.text = "Save to StudyDock"
        heading.font = .preferredFont(forTextStyle: .title2)
        heading.adjustsFontForContentSizeCategory = true
        let explanation = UILabel()
        explanation.text = "Keep this assessment reference. Choose its subject and confirm the deadline in your shared inbox later."
        explanation.font = .preferredFont(forTextStyle: .subheadline)
        explanation.textColor = .secondaryLabel
        explanation.numberOfLines = 0
        titleField.placeholder = "Assessment reference title"
        titleField.borderStyle = .roundedRect
        titleField.accessibilityIdentifier = "sharedReferenceTitle"
        titleField.accessibilityLabel = "Assessment reference title"
        preview.numberOfLines = 5
        preview.font = .preferredFont(forTextStyle: .footnote)
        preview.textColor = .secondaryLabel
        status.text = "Reading the shared reference…"
        status.numberOfLines = 0
        status.font = .preferredFont(forTextStyle: .footnote)
        status.accessibilityIdentifier = "shareStatus"
        saveButton.setTitle("Save reference", for: .normal)
        saveButton.configuration = .filled()
        saveButton.tintColor = UIColor(red: 0, green: 0.43, blue: 0.43, alpha: 1)
        saveButton.isEnabled = false
        saveButton.accessibilityIdentifier = "saveSharedReference"
        saveButton.addTarget(self, action: #selector(saveReference), for: .touchUpInside)
        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal)
        cancel.addTarget(self, action: #selector(cancelSharing), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [heading, explanation, titleField, preview, status, saveButton, cancel])
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)
        ])
        Task { await readReference() }
    }

    @MainActor
    private func readReference() async {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        var failure: String?
        for provider in providers {
            let type = provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) ? UTType.url.identifier : UTType.plainText.identifier
            guard provider.hasItemConformingToTypeIdentifier(type) else { continue }
            do {
                let value = try await load(provider, type: type)
                if let url = value as? URL { sharedURL = url.absoluteString }
                else if let text = value as? String {
                    if type == UTType.url.identifier { sharedURL = text }
                    else { sharedText = text }
                } else if let data = value as? Data, let text = String(data: data, encoding: .utf8) { sharedText = text }
            } catch { failure = "The source app could not provide this reference. Cancel and share the assignment link again." }
        }
        if sharedText.isEmpty { sharedText = items.compactMap { $0.attributedContentText?.string }.first ?? "" }
        if sharedURL == nil, SharedLinkValidation.isWebURL(sharedText) { sharedURL = sharedText }
        let suppliedTitle = items.compactMap { $0.attributedTitle?.string }.first
        titleField.text = suppliedTitle ?? String((sharedText.isEmpty ? (URL(string: sharedURL ?? "")?.host ?? "Shared assessment") : sharedText).prefix(100))
        preview.text = sharedURL ?? sharedText
        let hasContent = sharedURL != nil || !sharedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        status.text = hasContent ? "The deadline will be confirmed in StudyDock." : (failure ?? "No supported reference was found. Share a web link or assessment text.")
        saveButton.isEnabled = hasContent
    }

    private func load(_ provider: NSItemProvider, type: String) async throws -> NSSecureCoding? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: item) }
            }
        }
    }

    @objc private func saveReference() {
        guard !didFinish else { return }
        saveButton.isEnabled = false
        do {
            _ = try CaptureAssessmentReferenceUseCase(repository: FileShareInboxRepository()).execute(title: titleField.text ?? "", text: sharedText, sourceURL: sharedURL)
            didFinish = true
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        } catch {
            status.text = error.localizedDescription
            status.textColor = .systemRed
            saveButton.isEnabled = true
        }
    }
    @objc private func cancelSharing() {
        guard !didFinish else { return }
        didFinish = true
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }
}
