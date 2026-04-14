import AppKit
import Foundation

@MainActor
final class ServerWizardWindowController: NSWindowController, NSWindowDelegate {
    private let store: ProfileStore
    private let originalName: String?
    private let suggestedDockerContext: String

    private let nameField = NSTextField()
    private let transportField = NSPopUpButton()
    private let dockerContextField = NSTextField()
    private let sshHostField = NSTextField()
    private let sshUserField = NSTextField()
    private let sshPortField = NSTextField()
    private let remoteDataRootField = NSTextField()
    private let bootstrapCheckbox = NSButton(checkboxWithTitle: "Bootstrap Docker if missing", target: nil, action: nil)
    private let transportDescription = NSTextField(wrappingLabelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private var saveButton: NSButton?
    private var deleteButton: NSButton?
    private var cancelButton: NSButton?
    private var savedServer: RemoteServerDefinition?
    private var modalResponse: NSApplication.ModalResponse = .cancel
    private var isSubmitting = false

    init(
        store: ProfileStore,
        existingServer: RemoteServerDefinition?,
        suggestedDockerContext: String
    ) {
        self.store = store
        self.originalName = existingServer?.name
        self.suggestedDockerContext = suggestedDockerContext

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = existingServer == nil ? "New Runtime Target" : "Edit Runtime Target"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self

        configureFields(with: existingServer)
        buildUI()
        updateTransportUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func runModal(
        store: ProfileStore,
        existingServer: RemoteServerDefinition?,
        suggestedDockerContext: String
    ) -> RemoteServerDefinition? {
        let controller = ServerWizardWindowController(
            store: store,
            existingServer: existingServer,
            suggestedDockerContext: suggestedDockerContext
        )

        guard let window = controller.window else {
            return nil
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: window)
        window.orderOut(nil)
        return controller.modalResponse == .OK ? controller.savedServer : nil
    }

    func windowWillClose(_ notification: Notification) {
        if modalResponse != .OK {
            modalResponse = .cancel
        }
        NSApp.stopModal(withCode: modalResponse)
    }

    private func configureFields(with existingServer: RemoteServerDefinition?) {
        let normalized = existingServer.flatMap { try? $0.normalized() }
        nameField.stringValue = normalized?.name ?? ""
        dockerContextField.stringValue = normalized?.dockerContext ?? suggestedDockerContext
        sshHostField.stringValue = normalized?.sshHost ?? ""
        sshUserField.stringValue = normalized?.sshUser ?? "root"
        sshPortField.stringValue = "\(normalized?.sshPort ?? 22)"
        remoteDataRootField.stringValue = normalized?.remoteDataRoot ?? "/var/lib/devstackmenu"

        transportField.removeAllItems()
        transportField.addItems(withTitles: RemoteServerTransport.allCases.map(\.title))
        let selectedTransport = normalized?.transport ?? .ssh
        transportField.selectItem(withTitle: selectedTransport.title)
        transportField.target = self
        transportField.action = #selector(transportChanged(_:))

        bootstrapCheckbox.state = selectedTransport == .ssh ? .on : .off
        transportDescription.textColor = .secondaryLabelColor
        transportDescription.maximumNumberOfLines = 0
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 0
        statusLabel.stringValue = existingServer == nil
            ? "The wizard will verify connectivity, create or validate the Docker context, and optionally bootstrap Docker on the host."
            : "Save to re-check connectivity and refresh this managed runtime target."
    }

    private func buildUI() {
        guard let contentView = window?.contentView else {
            return
        }

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14

        let grid = NSGridView(views: [
            [label("Name"), nameField],
            [label("Runtime Type"), transportField],
            [label("Docker Context"), dockerContextField],
            [label("SSH Host"), sshHostField],
            [label("SSH User"), sshUserField],
            [label("SSH Port"), sshPortField],
            [label("Remote Data Root"), remoteDataRootField],
            [NSView(), bootstrapCheckbox],
            [NSView(), transportDescription],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.column(at: 0).width = 140
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        grid.xPlacement = .fill

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .regular
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.stopAnimation(nil)

        let statusRow = NSStackView(views: [progressIndicator, statusLabel])
        statusRow.orientation = .horizontal
        statusRow.alignment = .top
        statusRow.spacing = 8

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let cancelButton = button(title: "Cancel", action: #selector(cancelAction(_:)))
        let saveButton = button(title: "Check and Save", action: #selector(saveAction(_:)))
        saveButton.keyEquivalent = "\r"
        self.cancelButton = cancelButton
        self.saveButton = saveButton

        let buttons = NSStackView(views: [spacer, cancelButton, saveButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8

        if originalName != nil {
            let deleteButton = button(title: "Delete", action: #selector(deleteAction(_:)))
            buttons.insertArrangedSubview(deleteButton, at: 1)
            self.deleteButton = deleteButton
        }

        stack.addArrangedSubview(grid)
        stack.addArrangedSubview(statusRow)
        stack.addArrangedSubview(buttons)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -18),
            nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
            dockerContextField.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
            sshHostField.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
            sshUserField.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            sshPortField.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            remoteDataRootField.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
        ])
    }

    @objc private func transportChanged(_ sender: Any?) {
        updateTransportUI()
    }

    @objc private func saveAction(_ sender: Any?) {
        guard !isSubmitting else {
            return
        }

        do {
            let draft = try ServerWizardService.buildServer(from: .init(
                name: nameField.stringValue,
                transport: selectedTransport(),
                dockerContext: dockerContextField.stringValue,
                sshHost: sshHostField.stringValue,
                sshPortText: sshPortField.stringValue,
                sshUser: sshUserField.stringValue,
                remoteDataRoot: remoteDataRootField.stringValue
            ))
            let store = self.store
            let bootstrapIfNeeded = self.bootstrapCheckbox.state == .on
            setSubmitting(true, message: ServerWizardService.initialProgressMessage(for: draft))

            Task {
                let result = await Task.detached(priority: .userInitiated) { () -> Result<RemoteServerPreparationResult, Error> in
                    do {
                        return .success(
                            try ServerWizardService.prepareServer(
                                draft,
                                store: store,
                                bootstrapIfNeeded: bootstrapIfNeeded
                            )
                        )
                    } catch {
                        return .failure(error)
                    }
                }.value

                switch result {
                case let .success(prepared):
                    do {
                        try ServerWizardService.savePreparedServer(
                            prepared.server,
                            originalName: self.originalName,
                            store: self.store
                        )
                        self.savedServer = prepared.server
                        self.modalResponse = .OK
                        self.statusLabel.stringValue = "Ready: \(prepared.server.connectionSummary) on \(prepared.remoteOS), Docker \(prepared.serverVersion)."
                        self.close()
                    } catch {
                        self.setSubmitting(false, message: error.localizedDescription, isError: true)
                    }
                case let .failure(error):
                    self.setSubmitting(false, message: error.localizedDescription, isError: true)
                }
            }
        } catch {
            setSubmitting(false, message: error.localizedDescription, isError: true)
        }
    }

    @objc private func deleteAction(_ sender: Any?) {
        guard let originalName else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete runtime '\(originalName)'?"
        alert.informativeText = "Profiles that still reference this runtime will stop working until you update them."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        do {
            try ServerWizardService.deleteRuntime(named: originalName, store: store)
            savedServer = nil
            modalResponse = .cancel
            close()
        } catch {
            setSubmitting(false, message: error.localizedDescription, isError: true)
        }
    }

    @objc private func cancelAction(_ sender: Any?) {
        modalResponse = .cancel
        close()
    }

    private func selectedTransport() -> RemoteServerTransport {
        ServerWizardService.parseTransport(title: transportField.selectedItem?.title)
    }

    private func updateTransportUI() {
        let transport = selectedTransport()
        let isLocal = transport == .local
        sshHostField.isEnabled = !isLocal
        sshUserField.isEnabled = !isLocal
        sshPortField.isEnabled = !isLocal
        remoteDataRootField.isEnabled = !isLocal
        bootstrapCheckbox.isEnabled = !isLocal
        if isLocal {
            bootstrapCheckbox.state = .off
            remoteDataRootField.stringValue = ""
        } else if remoteDataRootField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            remoteDataRootField.stringValue = "/var/lib/devstackmenu"
        }
        transportDescription.stringValue = transport.summary
        if dockerContextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dockerContextField.stringValue = transport == .local ? suggestedDockerContext : "srv-\(slugify(nameField.stringValue))"
        }
    }

    private func setSubmitting(_ submitting: Bool, message: String, isError: Bool = false) {
        isSubmitting = submitting
        nameField.isEnabled = !submitting
        transportField.isEnabled = !submitting
        dockerContextField.isEnabled = !submitting
        sshHostField.isEnabled = !submitting && selectedTransport() == .ssh
        sshUserField.isEnabled = !submitting && selectedTransport() == .ssh
        sshPortField.isEnabled = !submitting && selectedTransport() == .ssh
        remoteDataRootField.isEnabled = !submitting && selectedTransport() == .ssh
        bootstrapCheckbox.isEnabled = !submitting && selectedTransport() == .ssh
        saveButton?.isEnabled = !submitting
        cancelButton?.isEnabled = !submitting
        deleteButton?.isEnabled = !submitting
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
        statusLabel.stringValue = message

        if submitting {
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
        }
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        field.alignment = .right
        return field
    }

    private func button(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }
}
