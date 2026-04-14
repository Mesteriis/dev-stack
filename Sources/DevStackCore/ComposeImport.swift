import AppKit
import Foundation

struct ComposeImportRequest: Sendable {
    let composeURL: URL
    let targetProfileName: String
    let replaceServices: Bool
    let services: [ServiceDefinition]
    let composeContent: String
    let composeWorkingDirectory: String
    let composeProjectName: String
}

@MainActor
final class ComposeImportWindowController: NSWindowController, NSWindowDelegate {
    typealias ImportHandler = @MainActor (ComposeImportRequest) -> Void

    private let composeURL: URL
    private let composeContent: String
    private let importedServices: [ServiceDefinition]
    private let profiles: [String]
    private let currentProfileName: String?
    private let onImport: ImportHandler
    private let onClose: () -> Void

    private let targetProfileField = NSComboBox()
    private let replaceServicesCheckbox = NSButton(
        checkboxWithTitle: "Replace existing services in the target profile",
        target: nil,
        action: nil
    )
    private var serviceCheckboxes: [(ServiceDefinition, NSButton)] = []

    init(
        composeURL: URL,
        composeContent: String,
        importedServices: [ServiceDefinition],
        profiles: [String],
        currentProfileName: String?,
        onImport: @escaping ImportHandler,
        onClose: @escaping () -> Void
    ) {
        self.composeURL = composeURL
        self.composeContent = composeContent
        self.importedServices = importedServices
        self.profiles = profiles
        self.currentProfileName = currentProfileName
        self.onImport = onImport
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Import Docker Compose To DX"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self

        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    private func buildUI() {
        guard let contentView = window?.contentView else {
            return
        }

        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)

        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        let description = NSTextField(wrappingLabelWithString: "Choose which services from \(composeURL.lastPathComponent) should be imported into a DevStack profile.")
        description.maximumNumberOfLines = 3
        root.addArrangedSubview(description)

        let sourceLabel = NSTextField(labelWithString: composeURL.path)
        sourceLabel.textColor = .secondaryLabelColor
        sourceLabel.lineBreakMode = .byTruncatingMiddle
        root.addArrangedSubview(sourceLabel)

        targetProfileField.isEditable = true
        targetProfileField.usesDataSource = false
        targetProfileField.addItems(withObjectValues: profiles)
        targetProfileField.stringValue = currentProfileName
            ?? composeURL.deletingPathExtension().lastPathComponent
        root.addArrangedSubview(makeFormRow(label: "Target Profile", field: targetProfileField))

        replaceServicesCheckbox.state = profiles.contains(targetProfileField.stringValue) ? .on : .off
        root.addArrangedSubview(replaceServicesCheckbox)

        root.addArrangedSubview(sectionTitle("Detected Services"))
        root.addArrangedSubview(serviceChecklist())

        root.addArrangedSubview(buttonRow())
    }

    private func serviceChecklist() -> NSView {
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false

        for service in importedServices {
            let title = "\(service.name)  role=\(service.role)  local=\(service.localPort)  alias=\(service.aliasHost)"
            let checkbox = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            checkbox.state = .on
            serviceCheckboxes.append((service, checkbox))
            content.addArrangedSubview(checkbox)
        }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = content
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 560),
            scrollView.heightAnchor.constraint(equalToConstant: 300),
        ])

        return scrollView
    }

    private func buttonRow() -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelAction(_:)))
        let importButton = NSButton(title: "Open In Editor", target: self, action: #selector(importAction(_:)))
        importButton.keyEquivalent = "\r"

        let stack = NSStackView(views: [spacer, cancelButton, importButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    @objc private func cancelAction(_ sender: Any?) {
        close()
    }

    @objc private func importAction(_ sender: Any?) {
        let profileName = targetProfileField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !profileName.isEmpty else {
            showError("Target profile name is required.")
            return
        }

        let selectedServices = serviceCheckboxes
            .filter { $0.1.state == .on }
            .map(\.0)

        guard !selectedServices.isEmpty else {
            showError("Select at least one service to import.")
            return
        }

        let request = ComposeImportRequest(
            composeURL: composeURL,
            targetProfileName: profileName,
            replaceServices: replaceServicesCheckbox.state == .on,
            services: selectedServices,
            composeContent: composeContent,
            composeWorkingDirectory: composeURL.deletingLastPathComponent().path,
            composeProjectName: composeURL.deletingLastPathComponent().lastPathComponent
        )

        onImport(request)
        close()
    }

    private func makeFormRow(label text: String, field: NSView) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        field.translatesAutoresizingMaskIntoConstraints = false

        let grid = NSGridView(views: [[label, field]])
        grid.column(at: 0).width = 110
        grid.columnSpacing = 12
        grid.rowSpacing = 6
        return grid
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        return field
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Compose Import Error"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window ?? NSWindow(), completionHandler: nil)
    }
}
