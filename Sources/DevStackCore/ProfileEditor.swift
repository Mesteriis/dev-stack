import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ProfileEditorWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate, NSTextViewDelegate {
    typealias SaveHandler = @MainActor (_ profile: ProfileDefinition, _ originalName: String?) throws -> Void

    private let store: ProfileStore
    private let originalName: String?
    private let dockerContexts: [DockerContextEntry]
    private let onSave: SaveHandler
    private let onClose: () -> Void

    private let nameField = NSTextField()
    private let runtimeField = NSPopUpButton()
    private let runtimeDockerContextField = NSTextField(labelWithString: "")
    private let runtimeRemoteHostField = NSTextField(labelWithString: "")
    private let runtimeSummaryField = NSTextField(wrappingLabelWithString: "")
    private let composeProjectField = NSTextField()
    private let composeWorkingDirectoryField = NSTextField()
    private let composeSourceField = NSTextField(wrappingLabelWithString: "")
    private let composeOverlaysField = NSPopUpButton()
    private let composeOverlaysSummaryField = NSTextField(wrappingLabelWithString: "")
    private let localContainerModeField = NSPopUpButton()
    private let localContainerModeDescription = NSTextField(wrappingLabelWithString: "")
    private let shellExportsTextView = NSTextView()
    private let composeTextView = NSTextView()
    private let servicesTableView = NSTableView()
    private let environmentSummaryField = NSTextField(wrappingLabelWithString: "")
    private let environmentTableView = NSTableView()
    private let environmentKeyField = NSTextField(labelWithString: "No variable selected")
    private let environmentStatusField = NSTextField(wrappingLabelWithString: "")
    private let environmentValueField = NSTextField()
    private let environmentSensitiveCheckbox = NSButton(checkboxWithTitle: "Save in Keychain", target: nil, action: nil)
    private let environmentNoteField = NSTextField(wrappingLabelWithString: "")
    private let clipboardPreviewField = NSTextField(wrappingLabelWithString: "")
    private var environmentGenerateButton: NSButton?
    private var environmentSaveButton: NSButton?
    private var environmentIgnoreButton: NSButton?
    private var environmentExternalButton: NSButton?
    private var clipboardUseButton: NSButton?
    private var runtimeTargets: [RemoteServerDefinition]
    private var services: [ServiceDefinition]
    private var composeSourceFile = ""
    private var composeAdditionalSourceFiles: [String] = []
    private var environmentOverview: ComposeEnvironmentOverview?
    private var externalEnvironmentKeys: [String]
    private var ignoredEnvironmentKeys = Set<String>()
    private var environmentMessage: String?
    private var clipboardParseResult: ClipboardSmartParseResult?
    private var clipboardTimer: Timer?
    private var lastClipboardChangeCount = NSPasteboard.general.changeCount

    init(
        store: ProfileStore,
        profile: ProfileDefinition?,
        dockerContexts: [DockerContextEntry],
        onSave: @escaping SaveHandler,
        onClose: @escaping () -> Void
    ) {
        self.store = store
        self.originalName = profile?.name
        self.dockerContexts = dockerContexts
        self.onSave = onSave
        self.onClose = onClose
        self.runtimeTargets = (try? store.runtimeTargets().sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }) ?? []
        self.services = profile?.services ?? []
        self.externalEnvironmentKeys = profile?.externalEnvironmentKeys ?? []

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = profile == nil ? "New DevStack Profile" : "Edit DevStack Profile"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self

        configureFields(with: profile)
        buildUI()
        startClipboardObservation()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        clipboardTimer?.invalidate()
        onClose()
    }

    @objc func beginAddService() {
        addServiceAction(nil)
    }

    private func configureFields(with profile: ProfileDefinition?) {
        nameField.stringValue = profile?.name ?? ""
        nameField.target = self
        nameField.action = #selector(refreshComposeEnvironmentAction(_:))
        composeProjectField.stringValue = profile?.compose.projectName ?? ""
        composeWorkingDirectoryField.stringValue = profile?.compose.workingDirectory ?? ""
        composeWorkingDirectoryField.target = self
        composeWorkingDirectoryField.action = #selector(refreshComposeEnvironmentAction(_:))
        composeSourceFile = profile?.compose.sourceFile ?? ""
        composeAdditionalSourceFiles = profile?.compose.additionalSourceFiles ?? []
        shellExportsTextView.string = (profile?.shellExports ?? []).joined(separator: "\n")
        composeTextView.string = profile?.compose.content ?? ""
        composeTextView.delegate = self

        runtimeField.removeAllItems()
        runtimeField.target = self
        runtimeField.action = #selector(runtimeSelectionChanged(_:))
        reloadRuntimeTargets(preferredName: preferredRuntimeName(for: profile))
        runtimeSummaryField.textColor = .secondaryLabelColor
        runtimeSummaryField.maximumNumberOfLines = 0
        updateRuntimeDetails()

        localContainerModeField.removeAllItems()
        localContainerModeField.addItems(withTitles: LocalContainerMode.allCases.map(\.title))
        let selectedMode = profile?.compose.localContainerMode ?? .manual
        localContainerModeField.selectItem(withTitle: selectedMode.title)
        localContainerModeField.target = self
        localContainerModeField.action = #selector(localContainerModeChanged(_:))
        localContainerModeDescription.textColor = .secondaryLabelColor
        updateLocalContainerModeDescription()
        composeSourceField.textColor = .secondaryLabelColor
        composeSourceField.maximumNumberOfLines = 0
        composeOverlaysSummaryField.textColor = .secondaryLabelColor
        composeOverlaysSummaryField.maximumNumberOfLines = 0
        updateComposeSourceDetails()
        updateComposeOverlayDetails()
        configureEnvironmentFields()
        reloadComposeEnvironmentOverview()
    }

    private func buildUI() {
        guard let contentView = window?.contentView else {
            return
        }

        let rootScrollView = NSScrollView()
        rootScrollView.translatesAutoresizingMaskIntoConstraints = false
        rootScrollView.drawsBackground = false
        rootScrollView.hasVerticalScroller = true
        rootScrollView.hasHorizontalScroller = false
        rootScrollView.borderType = .noBorder

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        rootScrollView.documentView = documentView

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14

        documentView.addSubview(stack)
        contentView.addSubview(rootScrollView)

        NSLayoutConstraint.activate([
            rootScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rootScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rootScrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            rootScrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -18),
            stack.widthAnchor.constraint(equalTo: rootScrollView.contentView.widthAnchor, constant: -36),
        ])

        stack.addArrangedSubview(sectionTitle("Profile"))
        stack.addArrangedSubview(profileGrid())
        stack.addArrangedSubview(localContainerModeSection())

        stack.addArrangedSubview(sectionTitle("Services"))
        stack.addArrangedSubview(serviceTableSection())

        stack.addArrangedSubview(sectionTitle("Shell Exports"))
        stack.addArrangedSubview(textSection(shellExportsTextView, height: 90))

        stack.addArrangedSubview(sectionTitle("Docker Compose Contents"))
        stack.addArrangedSubview(textSection(composeTextView, height: 250))
        stack.addArrangedSubview(sectionTitle("Compose Environment"))
        stack.addArrangedSubview(composeEnvironmentSection())

        stack.addArrangedSubview(buttonRow())
    }

    private func profileGrid() -> NSGridView {
        let grid = NSGridView(views: [
            [label("Name"), nameField],
            [label("Runtime"), runtimeSelectionRow()],
            [label("Docker Context"), runtimeDockerContextField],
            [label("Remote Docker Runtime"), runtimeRemoteHostField],
            [NSView(), runtimeSummaryField],
            [label("Compose Project"), composeProjectField],
            [label("Compose Working Dir"), composeWorkingDirectoryField],
            [label("Source Compose"), composeSourceSelectionRow()],
            [NSView(), composeSourceField],
            [label("Compose Overlays"), composeOverlaySelectionRow()],
            [NSView(), composeOverlaysSummaryField],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        grid.xPlacement = .fill
        grid.yPlacement = .center
        grid.column(at: 0).width = 150
        return grid
    }

    private func runtimeSelectionRow() -> NSView {
        let addButton = button(title: "New Runtime…", action: #selector(addRuntimeAction(_:)))
        let editButton = button(title: "Edit…", action: #selector(editRuntimeAction(_:)))
        let stack = NSStackView(views: [runtimeField, addButton, editButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func composeSourceSelectionRow() -> NSView {
        let chooseButton = button(title: "Choose…", action: #selector(chooseComposeSourceAction(_:)))
        let clearButton = button(title: "Clear", action: #selector(clearComposeSourceAction(_:)))
        let openButton = button(title: "Open", action: #selector(openComposeSourceAction(_:)))
        let stack = NSStackView(views: [chooseButton, clearButton, openButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func composeOverlaySelectionRow() -> NSView {
        composeOverlaysField.target = self
        composeOverlaysField.action = #selector(composeOverlaySelectionChanged(_:))

        let addButton = button(title: "Add…", action: #selector(addComposeOverlayAction(_:)))
        let removeButton = button(title: "Remove", action: #selector(removeComposeOverlayAction(_:)))
        let openButton = button(title: "Open", action: #selector(openComposeOverlayAction(_:)))

        let stack = NSStackView(views: [composeOverlaysField, addButton, removeButton, openButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func localContainerModeSection() -> NSView {
        let modeLabel = label("Local Container Mode")
        let grid = NSGridView(views: [
            [modeLabel, localContainerModeField],
            [NSView(), localContainerModeDescription],
        ])
        grid.column(at: 0).width = 150
        grid.columnSpacing = 12
        grid.rowSpacing = 6

        let stack = NSStackView(views: [grid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        return stack
    }

    private func composeEnvironmentSection() -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 8
        container.translatesAutoresizingMaskIntoConstraints = false

        environmentSummaryField.maximumNumberOfLines = 4
        environmentSummaryField.textColor = .secondaryLabelColor
        container.addArrangedSubview(environmentSummaryField)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = environmentTableView

        environmentTableView.headerView = NSTableHeaderView()
        environmentTableView.usesAlternatingRowBackgroundColors = true
        environmentTableView.rowHeight = 24
        environmentTableView.delegate = self
        environmentTableView.dataSource = self
        environmentTableView.target = self
        environmentTableView.action = #selector(environmentSelectionChanged(_:))
        environmentTableView.allowsMultipleSelection = false

        addEnvironmentColumn(id: "key", title: "Variable", width: 220)
        addEnvironmentColumn(id: "status", title: "Status", width: 540)

        NSLayoutConstraint.activate([
            scrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 860),
            scrollView.heightAnchor.constraint(equalToConstant: 150),
        ])
        container.addArrangedSubview(scrollView)

        environmentStatusField.maximumNumberOfLines = 3
        environmentStatusField.textColor = .secondaryLabelColor
        environmentNoteField.maximumNumberOfLines = 3
        environmentNoteField.textColor = .secondaryLabelColor
        clipboardPreviewField.maximumNumberOfLines = 3
        clipboardPreviewField.textColor = .secondaryLabelColor

        let detailGrid = NSGridView(views: [
            [label("Selected"), environmentKeyField],
            [label("Value"), environmentValueField],
            [NSView(), environmentSensitiveCheckbox],
            [NSView(), environmentStatusField],
            [NSView(), environmentNoteField],
            [NSView(), clipboardPreviewRow()],
        ])
        detailGrid.column(at: 0).width = 150
        detailGrid.columnSpacing = 12
        detailGrid.rowSpacing = 6
        container.addArrangedSubview(detailGrid)

        let generateButton = button(title: "Generate…", action: #selector(generateEnvironmentValueAction(_:)))
        let saveButton = button(title: "Save Value", action: #selector(saveEnvironmentValueAction(_:)))
        let ignoreButton = button(title: "Ignore", action: #selector(ignoreEnvironmentVariableAction(_:)))
        let externalButton = button(title: "Mark as External", action: #selector(toggleExternalEnvironmentVariableAction(_:)))
        environmentGenerateButton = generateButton
        environmentSaveButton = saveButton
        environmentIgnoreButton = ignoreButton
        environmentExternalButton = externalButton
        let buttons = NSStackView(views: [
            generateButton,
            saveButton,
            ignoreButton,
            externalButton,
            button(title: "Refresh Env", action: #selector(refreshComposeEnvironmentAction(_:))),
        ])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8
        container.addArrangedSubview(buttons)

        return container
    }

    private func serviceTableSection() -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 8
        container.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = servicesTableView

        servicesTableView.headerView = NSTableHeaderView()
        servicesTableView.usesAlternatingRowBackgroundColors = true
        servicesTableView.rowHeight = 24
        servicesTableView.delegate = self
        servicesTableView.dataSource = self
        servicesTableView.target = self
        servicesTableView.doubleAction = #selector(editServiceAction(_:))
        servicesTableView.allowsMultipleSelection = false

        addColumn(id: "name", title: "Name", width: 150)
        addColumn(id: "role", title: "Role", width: 90)
        addColumn(id: "tunnelHost", title: "Server", width: 120)
        addColumn(id: "aliasHost", title: "Alias", width: 180)
        addColumn(id: "localPort", title: "Local", width: 70)
        addColumn(id: "remotePort", title: "Remote", width: 70)
        addColumn(id: "enabled", title: "On", width: 50)

        NSLayoutConstraint.activate([
            scrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 860),
            scrollView.heightAnchor.constraint(equalToConstant: 210),
        ])

        let buttons = NSStackView(views: [
            button(title: "Add Service", action: #selector(addServiceAction(_:))),
            button(title: "Edit Service", action: #selector(editServiceAction(_:))),
            button(title: "Remove Service", action: #selector(removeServiceAction(_:))),
            button(title: "Import From Compose", action: #selector(importServicesFromComposeAction(_:))),
        ])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8

        container.addArrangedSubview(scrollView)
        container.addArrangedSubview(buttons)
        return container
    }

    private func textSection(_ textView: NSTextView, height: CGFloat) -> NSView {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = true
        scrollView.documentView = textView
        textView.minSize = NSSize(width: 0, height: height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        NSLayoutConstraint.activate([
            scrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 860),
            scrollView.heightAnchor.constraint(equalToConstant: height),
        ])

        return scrollView
    }

    private func buttonRow() -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let saveButton = button(title: "Save Profile", action: #selector(saveAction(_:)))
        saveButton.keyEquivalent = "\r"

        let cancelButton = button(title: "Cancel", action: #selector(cancelAction(_:)))
        let stack = NSStackView(views: [spacer, cancelButton, saveButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func addColumn(id: String, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        column.resizingMask = .userResizingMask
        servicesTableView.addTableColumn(column)
    }

    private func addEnvironmentColumn(id: String, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        column.resizingMask = .userResizingMask
        environmentTableView.addTableColumn(column)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == environmentTableView {
            return environmentOverview?.entries.count ?? 0
        }
        return services.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView == environmentTableView {
            guard let entry = environmentOverview?.entries[row] else {
                return nil
            }

            let identifier = tableColumn?.identifier.rawValue ?? "status"
            let text = identifier == "key" ? entry.key : entry.statusText
            let cellIdentifier = NSUserInterfaceItemIdentifier("env-cell-\(identifier)")
            let labelField: NSTextField
            if let existing = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTextField {
                labelField = existing
            } else {
                labelField = NSTextField(labelWithString: "")
                labelField.identifier = cellIdentifier
                labelField.lineBreakMode = .byTruncatingMiddle
            }
            labelField.stringValue = text
            if identifier == "status", entry.isMissing || entry.isEmptyValue {
                labelField.textColor = .systemRed
            } else if identifier == "status", entry.isMarkedExternal {
                labelField.textColor = .systemOrange
            } else {
                labelField.textColor = .labelColor
            }
            return labelField
        }

        guard row >= 0, row < services.count else {
            return nil
        }

        let service = services[row]
        let identifier = tableColumn?.identifier.rawValue ?? "cell"
        let text: String

        switch identifier {
        case "name":
            text = service.name
        case "role":
            text = service.role
        case "tunnelHost":
            text = service.remoteServer.isEmpty ? "(profile default)" : service.remoteServer
        case "aliasHost":
            text = service.aliasHost
        case "localPort":
            text = service.localPort == 0 ? "" : "\(service.localPort)"
        case "remotePort":
            text = service.remotePort == 0 ? "" : "\(service.remotePort)"
        case "enabled":
            text = service.enabled ? "yes" : "no"
        default:
            text = ""
        }

        let cellIdentifier = NSUserInterfaceItemIdentifier("profile-cell-\(identifier)")
        let labelField: NSTextField
        if let existing = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTextField {
            labelField = existing
        } else {
            labelField = NSTextField(labelWithString: "")
            labelField.identifier = cellIdentifier
            labelField.lineBreakMode = .byTruncatingMiddle
        }
        labelField.stringValue = text
        return labelField
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView else {
            return
        }
        if tableView == environmentTableView {
            updateEnvironmentDetails()
        }
    }

    @objc private func addServiceAction(_ sender: Any?) {
        if let service = ServiceEditorDialog.runModal(service: nil, parentWindow: window) {
            services.append(service)
            servicesTableView.reloadData()
            servicesTableView.selectRowIndexes(IndexSet(integer: services.count - 1), byExtendingSelection: false)
        }
    }

    @objc private func editServiceAction(_ sender: Any?) {
        let row = servicesTableView.selectedRow
        guard row >= 0, row < services.count else {
            presentError("Select a service first.")
            return
        }

        if let updated = ServiceEditorDialog.runModal(service: services[row], parentWindow: window) {
            services[row] = updated
            servicesTableView.reloadData()
            servicesTableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

    @objc private func removeServiceAction(_ sender: Any?) {
        let row = servicesTableView.selectedRow
        guard row >= 0, row < services.count else {
            presentError("Select a service first.")
            return
        }
        services.remove(at: row)
        servicesTableView.reloadData()
    }

    @objc private func importServicesFromComposeAction(_ sender: Any?) {
        let workingDirectory = composeWorkingDirectoryField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let imported = ComposeSupport.importServices(
            from: composeTextView.string,
            workingDirectory: workingDirectory.isEmpty ? nil : URL(fileURLWithPath: workingDirectory, isDirectory: true)
        )
        guard !imported.isEmpty else {
            presentError("Could not infer any published ports from the docker-compose contents.")
            return
        }

        if services.isEmpty {
            services = imported
            servicesTableView.reloadData()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Import services from compose?"
        alert.informativeText = "Replace the current service list or append imported services."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Append")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            services = imported
        case .alertSecondButtonReturn:
            services.append(contentsOf: imported)
        default:
            return
        }

        servicesTableView.reloadData()
    }

    @objc private func saveAction(_ sender: Any?) {
        do {
            let profile = try buildProfile()
            try onSave(profile, originalName)
            close()
        } catch {
            presentError(error.localizedDescription)
        }
    }

    @objc private func cancelAction(_ sender: Any?) {
        close()
    }

    @objc private func localContainerModeChanged(_ sender: Any?) {
        updateLocalContainerModeDescription()
    }

    @objc private func runtimeSelectionChanged(_ sender: Any?) {
        updateRuntimeDetails()
    }

    @objc private func chooseComposeSourceAction(_ sender: Any?) {
        guard let url = selectComposeURLs(allowsMultipleSelection: false).first else {
            return
        }

        if !composeSourceFile.isEmpty, composeSourceFile != url.path, !composeAdditionalSourceFiles.contains(composeSourceFile) {
            composeAdditionalSourceFiles.insert(composeSourceFile, at: 0)
        }
        composeSourceFile = url.path
        composeAdditionalSourceFiles.removeAll { $0 == composeSourceFile }
        composeWorkingDirectoryField.stringValue = url.deletingLastPathComponent().path
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            composeTextView.string = content
        }
        updateComposeSourceDetails()
        updateComposeOverlayDetails()
        reloadComposeEnvironmentOverview()
    }

    @objc private func clearComposeSourceAction(_ sender: Any?) {
        if let replacement = composeAdditionalSourceFiles.first {
            composeSourceFile = replacement
            composeAdditionalSourceFiles.removeFirst()
        } else {
            composeSourceFile = ""
        }
        updateComposeSourceDetails()
        updateComposeOverlayDetails()
        reloadComposeEnvironmentOverview()
    }

    @objc private func openComposeSourceAction(_ sender: Any?) {
        let path = composeSourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: false))
    }

    @objc private func addComposeOverlayAction(_ sender: Any?) {
        let urls = selectComposeURLs(allowsMultipleSelection: true)
        guard !urls.isEmpty else {
            return
        }

        for url in urls {
            let path = url.path
            guard path != composeSourceFile, !composeAdditionalSourceFiles.contains(path) else {
                continue
            }
            composeAdditionalSourceFiles.append(path)
        }
        updateComposeOverlayDetails()
        reloadComposeEnvironmentOverview()
    }

    @objc private func removeComposeOverlayAction(_ sender: Any?) {
        let selectedPath = selectedOverlayPath()
        guard let selectedPath else {
            return
        }
        composeAdditionalSourceFiles.removeAll { $0 == selectedPath }
        updateComposeOverlayDetails()
        reloadComposeEnvironmentOverview()
    }

    @objc private func openComposeOverlayAction(_ sender: Any?) {
        guard let selectedPath = selectedOverlayPath() else {
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: selectedPath, isDirectory: false))
    }

    @objc private func composeOverlaySelectionChanged(_ sender: Any?) {
        updateComposeOverlayDetails()
        updateEnvironmentDetails()
    }

    @objc private func addRuntimeAction(_ sender: Any?) {
        let suggestedContext = dockerContexts.first(where: \.isCurrent)?.name ?? "default"
        if let server = ServerWizardWindowController.runModal(
            store: store,
            existingServer: nil,
            suggestedDockerContext: suggestedContext
        ) {
            upsertRuntimeTarget(server)
            reloadRuntimeTargets(preferredName: server.name)
            updateRuntimeDetails()
        }
    }

    @objc private func editRuntimeAction(_ sender: Any?) {
        guard let server = selectedRuntimeTarget() else {
            presentError("Create or select a runtime first.")
            return
        }

        let suggestedContext = dockerContexts.first(where: \.isCurrent)?.name ?? server.dockerContext
        let originalRuntimeName = server.name
        let updated = ServerWizardWindowController.runModal(
            store: store,
            existingServer: server,
            suggestedDockerContext: suggestedContext
        )

        if let updated {
            removeRuntimeTarget(named: originalRuntimeName)
            upsertRuntimeTarget(updated)
            reloadRuntimeTargets(preferredName: updated.name)
        } else {
            runtimeTargets = (try? store.runtimeTargets().sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }) ?? []
            reloadRuntimeTargets(preferredName: selectedRuntimeName() == originalRuntimeName ? nil : selectedRuntimeName())
        }

        updateRuntimeDetails()
    }

    private func buildProfile() throws -> ProfileDefinition {
        let selectedMode = selectedLocalContainerMode()
        guard let server = selectedRuntimeTarget() else {
            throw ValidationError("Choose or create a runtime target first.")
        }
        let profile = ProfileDefinition(
            name: nameField.stringValue,
            serverName: server.name,
            dockerContext: server.dockerContext,
            tunnelHost: server.remoteDockerServerDisplay,
            shellExports: splitLines(shellExportsTextView.string),
            externalEnvironmentKeys: externalEnvironmentKeys,
            services: services,
            compose: ComposeDefinition(
                projectName: composeProjectField.stringValue,
                workingDirectory: composeWorkingDirectoryField.stringValue,
                sourceFile: composeSourceFile,
                additionalSourceFiles: composeAdditionalSourceFiles,
                autoDownOnSwitch: selectedMode.autoDownOnSwitch,
                autoUpOnActivate: selectedMode.autoUpOnActivate,
                content: composeTextView.string
            )
        )

        return try profile.normalized()
    }

    private func splitLines(_ text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func textDidChange(_ notification: Notification) {
        guard let object = notification.object as? NSTextView, object == composeTextView else {
            return
        }
        reloadComposeEnvironmentOverview()
    }

    @objc private func environmentSelectionChanged(_ sender: Any?) {
        updateEnvironmentDetails()
    }

    @objc private func refreshComposeEnvironmentAction(_ sender: Any?) {
        reloadComposeEnvironmentOverview()
    }

    @objc private func generateEnvironmentValueAction(_ sender: Any?) {
        guard let entry = selectedEnvironmentEntry() else {
            presentError("Select a compose variable first.")
            return
        }
        guard entry.isMissing || entry.isEmptyValue else {
            presentError("Generation is only available for missing or empty compose variables.")
            return
        }

        guard let draftProfile = try? buildProfileDraftForUtilities() else {
            presentError("Complete the profile basics before generating environment values.")
            return
        }

        let canSaveToKeychain = entry.envFileURL == nil && !entry.isEmptyValue
        let defaultSensitive = canSaveToKeychain && ContextValueGenerator.looksSensitive(key: entry.key)
        let generatorField = NSPopUpButton()
        generatorField.addItems(withTitles: EnvironmentValueGeneratorKind.allCases.map(\.title))
        generatorField.selectItem(at: 0)

        let sensitiveCheckbox = NSButton(
            checkboxWithTitle: "Save in Keychain",
            target: nil,
            action: nil
        )
        sensitiveCheckbox.state = defaultSensitive ? .on : .off
        sensitiveCheckbox.isEnabled = canSaveToKeychain

        let destinationText: String
        if let envFileURL = entry.envFileURL {
            destinationText = "Compose already sees \(entry.key) in \(envFileURL.lastPathComponent), so generated values will update that file."
        } else if canSaveToKeychain {
            destinationText = "Missing values can be written to .env.devstack or stored in Keychain if sensitive."
        } else {
            destinationText = "Generated values will be written to .env.devstack for this profile."
        }

        let accessory = NSStackView()
        accessory.orientation = .vertical
        accessory.alignment = .leading
        accessory.spacing = 8
        accessory.addArrangedSubview(
            NSTextField(wrappingLabelWithString: destinationText)
        )
        accessory.addArrangedSubview(formRow(label: "Variable", field: NSTextField(labelWithString: entry.key)))
        accessory.addArrangedSubview(formRow(label: "Generator", field: generatorField))
        accessory.addArrangedSubview(sensitiveCheckbox)

        let alert = NSAlert()
        alert.messageText = "Generate value for \(entry.key)"
        alert.informativeText = "Choose the generator type and save target."
        alert.accessoryView = accessory
        alert.addButton(withTitle: "Generate")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let selectedKind = EnvironmentValueGeneratorKind.allCases[generatorField.indexOfSelectedItem]
        do {
            let value = try ContextValueGenerator.generate(kind: selectedKind)
            environmentValueField.stringValue = value
            let saveToKeychain = sensitiveCheckbox.state == .on && sensitiveCheckbox.isEnabled
            try persistEnvironmentValue(
                key: entry.key,
                value: value,
                saveToKeychain: saveToKeychain,
                draftProfile: draftProfile,
                entry: entry
            )
            let destinationName = (entry.envFileURL ?? environmentOverview?.profileEnvironmentFile)?.lastPathComponent ?? ".env.devstack"
            environmentMessage = saveToKeychain
                ? "Saved \(entry.key) in Keychain"
                : "Saved \(entry.key) to \(destinationName)"
            reloadComposeEnvironmentOverview(selecting: entry.key)
        } catch {
            presentError(error.localizedDescription)
        }
    }

    @objc private func saveEnvironmentValueAction(_ sender: Any?) {
        guard let entry = selectedEnvironmentEntry() else {
            presentError("Select a compose variable first.")
            return
        }

        let value = environmentValueField.stringValue
        guard !value.isEmpty else {
            presentError("Enter a value first.")
            return
        }

        guard let draftProfile = try? buildProfileDraftForUtilities() else {
            presentError("Complete the profile basics before saving environment values.")
            return
        }

        do {
            let saveToKeychain = environmentSensitiveCheckbox.state == .on && environmentSensitiveCheckbox.isEnabled
            try persistEnvironmentValue(
                key: entry.key,
                value: value,
                saveToKeychain: saveToKeychain,
                draftProfile: draftProfile,
                entry: entry
            )
            let destinationName = (entry.envFileURL ?? environmentOverview?.profileEnvironmentFile)?.lastPathComponent ?? ".env.devstack"
            environmentMessage = saveToKeychain
                ? "Saved \(entry.key) in Keychain"
                : "Saved \(entry.key) to \(destinationName)"
            reloadComposeEnvironmentOverview(selecting: entry.key)
        } catch {
            presentError(error.localizedDescription)
        }
    }

    @objc private func ignoreEnvironmentVariableAction(_ sender: Any?) {
        guard let entry = selectedEnvironmentEntry() else {
            presentError("Select a compose variable first.")
            return
        }
        ignoredEnvironmentKeys.insert(entry.key)
        environmentMessage = "Ignored \(entry.key) for this editor session"
        reloadComposeEnvironmentOverview()
    }

    @objc private func toggleExternalEnvironmentVariableAction(_ sender: Any?) {
        guard let entry = selectedEnvironmentEntry() else {
            presentError("Select a compose variable first.")
            return
        }
        guard entry.isMissing || entry.isMarkedExternal else {
            presentError("Only truly missing variables can be marked as external.")
            return
        }

        if externalEnvironmentKeys.contains(entry.key) {
            externalEnvironmentKeys.removeAll { $0 == entry.key }
            environmentMessage = "Removed external mark from \(entry.key)"
        } else {
            externalEnvironmentKeys.append(entry.key)
            environmentMessage = "Marked \(entry.key) as external"
        }
        ignoredEnvironmentKeys.remove(entry.key)
        reloadComposeEnvironmentOverview(selecting: entry.key)
    }

    @objc private func useClipboardResultAction(_ sender: Any?) {
        guard let value = clipboardParseResult?.value else {
            return
        }
        environmentValueField.stringValue = value
        updateEnvironmentDetails()
    }

    private func configureEnvironmentFields() {
        environmentValueField.placeholderString = "Selected variable value"
        environmentSensitiveCheckbox.target = self
        environmentSensitiveCheckbox.action = #selector(environmentSensitivityChanged(_:))
        environmentStatusField.stringValue = "Select a compose variable to inspect env resolution."
        environmentNoteField.stringValue = ""
        clipboardPreviewField.stringValue = ""
    }

    @objc private func environmentSensitivityChanged(_ sender: Any?) {
        updateEnvironmentDetails()
    }

    private func buildProfileDraftForUtilities() throws -> ProfileDefinition {
        let selectedMode = selectedLocalContainerMode()
        let runtime = selectedRuntimeTarget()
        let trimmedName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let draftName = trimmedName.isEmpty ? "unsaved-profile" : trimmedName
        return try ProfileDefinition(
            name: draftName,
            serverName: runtime?.name ?? "",
            dockerContext: runtime?.dockerContext ?? (dockerContexts.first(where: \.isCurrent)?.name ?? "default"),
            tunnelHost: runtime?.remoteDockerServerDisplay ?? "docker",
            shellExports: splitLines(shellExportsTextView.string),
            externalEnvironmentKeys: externalEnvironmentKeys,
            services: services,
            compose: ComposeDefinition(
                projectName: composeProjectField.stringValue,
                workingDirectory: composeWorkingDirectoryField.stringValue,
                sourceFile: composeSourceFile,
                additionalSourceFiles: composeAdditionalSourceFiles,
                autoDownOnSwitch: selectedMode.autoDownOnSwitch,
                autoUpOnActivate: selectedMode.autoUpOnActivate,
                content: composeTextView.string
            )
        ).normalized()
    }

    private func reloadComposeEnvironmentOverview(selecting preferredKey: String? = nil) {
        guard let profile = try? buildProfileDraftForUtilities() else {
            environmentOverview = nil
            environmentSummaryField.stringValue = "Compose environment utilities become available once the compose working directory and contents are valid."
            environmentTableView.reloadData()
            updateEnvironmentDetails()
            return
        }

        do {
            let overview = try ComposeSupport.environmentOverview(
                profile: profile,
                store: store,
                ignoredKeys: ignoredEnvironmentKeys
            )
            environmentOverview = overview
            let missingCount = overview.entries.filter { $0.isMissing || $0.isEmptyValue }.count
            let externalCount = overview.entries.filter(\.isMarkedExternal).count
            let summaryLines = [
                "Referenced: \(overview.referencedKeys.count)  |  Missing: \(missingCount)  |  External: \(externalCount)",
                "Editable env file: \(overview.profileEnvironmentFile.lastPathComponent) in \(overview.workingDirectory.path)",
            ]
            environmentSummaryField.stringValue = ([environmentMessage].compactMap { $0 } + [summaryLines.joined(separator: "\n")]).joined(separator: "\n\n")
            environmentMessage = nil
            environmentTableView.reloadData()
            selectEnvironmentKey(preferredKey)
        } catch {
            environmentOverview = nil
            environmentSummaryField.stringValue = error.localizedDescription
            environmentTableView.reloadData()
            updateEnvironmentDetails()
        }
    }

    private func selectEnvironmentKey(_ preferredKey: String?) {
        let row: Int
        if let preferredKey,
           let index = environmentOverview?.entries.firstIndex(where: { $0.key == preferredKey }) {
            row = index
        } else if let entries = environmentOverview?.entries, !entries.isEmpty {
            row = 0
        } else {
            updateEnvironmentDetails()
            return
        }
        environmentTableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        updateEnvironmentDetails()
    }

    private func selectedEnvironmentEntry() -> ComposeEnvironmentEntry? {
        let row = environmentTableView.selectedRow
        guard row >= 0, row < (environmentOverview?.entries.count ?? 0) else {
            return nil
        }
        return environmentOverview?.entries[row]
    }

    private func updateEnvironmentDetails() {
        guard let entry = selectedEnvironmentEntry() else {
            environmentKeyField.stringValue = "No variable selected"
            environmentStatusField.stringValue = "Select a compose variable to inspect env resolution."
            environmentValueField.stringValue = ""
            environmentValueField.isEnabled = false
            environmentSensitiveCheckbox.state = .off
            environmentSensitiveCheckbox.isEnabled = false
            environmentNoteField.stringValue = ""
            environmentGenerateButton?.isEnabled = false
            environmentSaveButton?.isEnabled = false
            environmentIgnoreButton?.isEnabled = false
            environmentExternalButton?.isEnabled = false
            environmentExternalButton?.title = "Mark as External"
            updateClipboardPreview()
            return
        }

        environmentKeyField.stringValue = entry.key
        environmentStatusField.stringValue = entry.statusText
        if let envFileValue = entry.envFileValue {
            environmentValueField.stringValue = envFileValue
        } else if entry.hasProfileKeychainValue || entry.hasProjectKeychainValue {
            environmentValueField.stringValue = ""
        }
        environmentValueField.isEnabled = entry.envFileURL != nil || entry.isMissing || entry.isEmptyValue || entry.isMarkedExternal

        let canSaveToKeychain = entry.envFileURL == nil && !entry.isEmptyValue
        if canSaveToKeychain {
            let shouldSuggestSensitive = ContextValueGenerator.looksSensitive(key: entry.key)
            if environmentSensitiveCheckbox.state == .off && shouldSuggestSensitive {
                environmentSensitiveCheckbox.state = .on
            }
        } else {
            environmentSensitiveCheckbox.state = .off
        }
        environmentSensitiveCheckbox.isEnabled = canSaveToKeychain

        if let envFileURL = entry.envFileURL {
            environmentNoteField.stringValue = "Saving updates \(envFileURL.lastPathComponent). Keychain is disabled because compose already resolves this key from a file."
        } else if entry.providedByManagedVariables {
            environmentNoteField.stringValue = "This key is already satisfied by Variable Manager."
        } else if entry.hasProfileKeychainValue || entry.hasProjectKeychainValue {
            environmentNoteField.stringValue = "Keychain-backed values are intentionally not displayed here."
        } else if entry.isMarkedExternal {
            environmentNoteField.stringValue = "This key is expected from the shell, CI or another external source."
        } else {
            environmentNoteField.stringValue = "Missing keys can be generated into .env.devstack or stored in Keychain if sensitive."
        }

        environmentGenerateButton?.isEnabled = entry.isMissing || entry.isEmptyValue
        environmentSaveButton?.isEnabled = environmentValueField.isEnabled
        environmentIgnoreButton?.isEnabled = entry.isMissing || entry.isEmptyValue
        environmentExternalButton?.isEnabled = entry.isMissing || entry.isMarkedExternal
        environmentExternalButton?.title = entry.isMarkedExternal ? "Unmark External" : "Mark as External"

        updateClipboardPreview()
    }

    private func persistEnvironmentValue(
        key: String,
        value: String,
        saveToKeychain: Bool,
        draftProfile: ProfileDefinition,
        entry: ComposeEnvironmentEntry
    ) throws {
        externalEnvironmentKeys.removeAll { $0 == key }
        if saveToKeychain {
            let actualProfileName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !actualProfileName.isEmpty else {
                throw ValidationError("Set the profile name before saving a Keychain value.")
            }
            var profileForSecrets = draftProfile
            profileForSecrets.name = actualProfileName
            try ComposeSupport.saveProfileSecret(key: key, value: value, profile: profileForSecrets)
            return
        }
        try ComposeSupport.saveEnvironmentValue(
            key: key,
            value: value,
            profile: draftProfile,
            store: store,
            fileURL: entry.suggestedWriteURL
        )
    }

    private func clipboardPreviewRow() -> NSView {
        let useButton = button(title: "Use Result", action: #selector(useClipboardResultAction(_:)))
        clipboardUseButton = useButton
        let stack = NSStackView(views: [clipboardPreviewField, useButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func startClipboardObservation() {
        clipboardTimer?.invalidate()
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollClipboard()
            }
        }
        pollClipboard()
    }

    private func pollClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastClipboardChangeCount else {
            return
        }
        lastClipboardChangeCount = pasteboard.changeCount
        let raw = pasteboard.string(forType: .string) ?? ""
        clipboardParseResult = ClipboardSmartParser.parse(raw)
        updateClipboardPreview()
    }

    private func updateClipboardPreview() {
        if let result = clipboardParseResult {
            clipboardPreviewField.stringValue = "\(result.title): \(result.preview)"
            clipboardUseButton?.isHidden = result.value == nil
            clipboardUseButton?.isEnabled = result.value != nil && selectedEnvironmentEntry() != nil
        } else {
            clipboardPreviewField.stringValue = "Clipboard helper watches timestamps, JSON and base64 while this editor is open."
            clipboardUseButton?.isHidden = true
            clipboardUseButton?.isEnabled = false
        }
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Profile Error"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window ?? NSWindow(), completionHandler: nil)
    }

    private func selectedLocalContainerMode() -> LocalContainerMode {
        let selectedTitle = localContainerModeField.selectedItem?.title
        return LocalContainerMode.allCases.first(where: { $0.title == selectedTitle }) ?? .manual
    }

    private func updateLocalContainerModeDescription() {
        localContainerModeDescription.stringValue = selectedLocalContainerMode().summary
    }

    private func updateComposeSourceDetails() {
        if composeSourceFile.isEmpty {
            composeSourceField.stringValue = "Manual compose contents. The working directory controls where ./data is materialized."
            composeWorkingDirectoryField.isEditable = true
            return
        }

        composeSourceField.stringValue = composeSourceFile
        composeWorkingDirectoryField.isEditable = false
        composeWorkingDirectoryField.stringValue = URL(fileURLWithPath: composeSourceFile, isDirectory: false)
            .deletingLastPathComponent()
            .path
    }

    private func updateComposeOverlayDetails() {
        composeOverlaysField.removeAllItems()
        if composeAdditionalSourceFiles.isEmpty {
            composeOverlaysField.addItem(withTitle: "No overlays")
            composeOverlaysField.isEnabled = false
            composeOverlaysSummaryField.stringValue = "Optional override files passed after the main compose file."
            return
        }

        composeOverlaysField.addItems(withTitles: composeAdditionalSourceFiles)
        composeOverlaysField.isEnabled = true
        if composeOverlaysField.indexOfSelectedItem < 0 {
            composeOverlaysField.selectItem(at: 0)
        }
        composeOverlaysSummaryField.stringValue = "\(composeAdditionalSourceFiles.count) overlay file(s) will be appended with `docker compose -f ...`."
    }

    private func selectedOverlayPath() -> String? {
        let title = composeOverlaysField.selectedItem?.title ?? ""
        guard !title.isEmpty, title != "No overlays" else {
            return nil
        }
        return title
    }

    private func selectComposeURLs(allowsMultipleSelection: Bool) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.allowedContentTypes = [
            UTType(filenameExtension: "yml") ?? .yaml,
            UTType(filenameExtension: "yaml") ?? .yaml,
        ]
        panel.directoryURL = composeSourceFile.isEmpty
            ? (
                composeWorkingDirectoryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : URL(fileURLWithPath: composeWorkingDirectoryField.stringValue, isDirectory: true)
            )
            : URL(fileURLWithPath: composeSourceFile, isDirectory: false).deletingLastPathComponent()

        guard panel.runModal() == .OK else {
            return []
        }
        return panel.urls
    }

    private func reloadRuntimeTargets(preferredName: String?) {
        runtimeTargets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        runtimeField.removeAllItems()
        runtimeField.addItems(withTitles: runtimeTargets.map(\.name))
        if let preferredName, runtimeField.indexOfItem(withTitle: preferredName) >= 0 {
            runtimeField.selectItem(withTitle: preferredName)
        } else if !runtimeTargets.isEmpty {
            runtimeField.selectItem(at: 0)
        }
        runtimeField.isEnabled = !runtimeTargets.isEmpty
    }

    private func selectedRuntimeName() -> String? {
        let selected = runtimeField.selectedItem?.title ?? ""
        return selected.isEmpty ? nil : selected
    }

    private func selectedRuntimeTarget() -> RemoteServerDefinition? {
        guard let selectedName = selectedRuntimeName() else {
            return nil
        }
        return runtimeTargets.first(where: { $0.name == selectedName })
    }

    private func preferredRuntimeName(for profile: ProfileDefinition?) -> String? {
        if let explicit = profile?.runtimeName, !explicit.isEmpty {
            return explicit
        }

        guard let profile else {
            return runtimeTargets.first?.name
        }

        if let matched = runtimeTargets.first(where: {
            $0.dockerContext == profile.dockerContext
                || $0.remoteDockerServerDisplay == profile.tunnelHost
                || $0.sshTarget == profile.tunnelHost
        }) {
            return matched.name
        }

        return runtimeTargets.first?.name
    }

    private func updateRuntimeDetails() {
        guard let server = selectedRuntimeTarget() else {
            runtimeDockerContextField.stringValue = "No runtime selected"
            runtimeRemoteHostField.stringValue = "No runtime selected"
            runtimeSummaryField.stringValue = "Profiles are bound to saved runtime targets. Create a local or SSH runtime first."
            return
        }

        runtimeDockerContextField.stringValue = server.dockerContext
        runtimeRemoteHostField.stringValue = server.remoteDockerServerDisplay
        runtimeSummaryField.stringValue = server.connectionSummary
    }

    private func upsertRuntimeTarget(_ server: RemoteServerDefinition) {
        removeRuntimeTarget(named: server.name)
        runtimeTargets.append(server)
    }

    private func removeRuntimeTarget(named name: String) {
        runtimeTargets.removeAll { $0.name == name }
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        field.alignment = .right
        return field
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        return field
    }

    private func formRow(label text: String, field: NSView) -> NSView {
        let labelField = NSTextField(labelWithString: text)
        labelField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        labelField.alignment = .right
        field.translatesAutoresizingMaskIntoConstraints = false

        let grid = NSGridView(views: [[labelField, field]])
        grid.column(at: 0).width = 90
        grid.columnSpacing = 12
        return grid
    }

    private func button(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }
}

@MainActor
enum ServiceEditorDialog {
    static func runModal(service: ServiceDefinition?, parentWindow: NSWindow?) -> ServiceDefinition? {
        let nameField = NSTextField(string: service?.name ?? "")
        let roleField = NSPopUpButton()
        roleField.addItems(withTitles: ["generic", "postgres", "redis", "http", "https", "minio"])
        roleField.selectItem(withTitle: service?.role ?? "generic")

        let aliasField = NSTextField(string: service?.aliasHost ?? "")
        let localPortField = NSTextField(string: service?.localPort == 0 ? "" : "\(service?.localPort ?? 0)")
        let remoteHostField = NSTextField(string: service?.remoteHost ?? "127.0.0.1")
        let remotePortField = NSTextField(string: service?.remotePort == 0 ? "" : "\(service?.remotePort ?? 0)")
        let remoteServerField = NSTextField(string: service?.remoteServer ?? "")
        let envPrefixField = NSTextField(string: service?.envPrefix ?? "")
        let enabledCheckbox = NSButton(
            checkboxWithTitle: "Enabled",
            target: nil,
            action: nil
        )
        enabledCheckbox.state = (service?.enabled ?? true) ? .on : .off

        let exportsTextView = NSTextView()
        exportsTextView.string = service?.extraExports.joined(separator: "\n") ?? ""
        exportsTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        let accessory = NSStackView()
        accessory.orientation = .vertical
        accessory.alignment = .leading
        accessory.spacing = 8
        accessory.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 0, right: 0)

        let grid = NSGridView(views: [
            [fieldLabel("Name"), nameField],
            [fieldLabel("Role"), roleField],
            [fieldLabel("Alias Host"), aliasField],
            [fieldLabel("Local Port"), localPortField],
            [fieldLabel("Remote Host"), remoteHostField],
            [fieldLabel("Remote Port"), remotePortField],
            [fieldLabel("Remote Server"), remoteServerField],
            [fieldLabel("Env Prefix"), envPrefixField],
            [fieldLabel(""), enabledCheckbox],
        ])
        grid.column(at: 0).width = 100
        grid.rowSpacing = 6
        grid.columnSpacing = 12

        accessory.addArrangedSubview(grid)
        accessory.addArrangedSubview(fieldLabel("Extra Export Lines"))
        accessory.addArrangedSubview(scrollContainer(for: exportsTextView, height: 90, width: 420))

        let alert = NSAlert()
        alert.messageText = service == nil ? "Add Service" : "Edit Service"
        alert.informativeText = "One profile can contain multiple databases and services."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = accessory

        while true {
            let response: NSApplication.ModalResponse
            if let parentWindow {
                response = alert.runModal()
                _ = parentWindow
            } else {
                response = alert.runModal()
            }

            guard response == .alertFirstButtonReturn else {
                return nil
            }

            let localPort = Int(localPortField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let remotePort = Int(remotePortField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let trimmedName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedName.isEmpty {
                showSimpleError("Service name is required.")
                continue
            }

            let built = ServiceDefinition(
                name: trimmedName,
                role: roleField.selectedItem?.title ?? "generic",
                aliasHost: aliasField.stringValue,
                localPort: localPort,
                remoteHost: remoteHostField.stringValue,
                remotePort: remotePort,
                tunnelHost: remoteServerField.stringValue,
                enabled: enabledCheckbox.state == .on,
                envPrefix: envPrefixField.stringValue,
                extraExports: exportsTextView.string
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )

            do {
                let validated = try ProfileDefinition(name: "validation", services: [built]).normalized().services[0]
                return validated
            } catch {
                showSimpleError(error.localizedDescription)
            }
        }
    }

    private static func fieldLabel(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        field.alignment = .right
        return field
    }

    private static func scrollContainer(for textView: NSTextView, height: CGFloat, width: CGFloat) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = textView
        textView.minSize = NSSize(width: width, height: height)
        textView.maxSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scrollView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        return scrollView
    }

    private static func showSimpleError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Service Error"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
