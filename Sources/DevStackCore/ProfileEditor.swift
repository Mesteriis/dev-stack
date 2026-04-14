import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ProfileEditorWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    typealias SaveHandler = @MainActor (_ profile: ProfileDefinition, _ originalName: String?) throws -> Void

    private let store: ProfileStore
    private let originalName: String?
    private let dockerContexts: [DockerContextEntry]
    private let onSave: SaveHandler
    private let onClose: () -> Void

    private let nameField = NSTextField()
    private let serverField = NSPopUpButton()
    private let serverDockerContextField = NSTextField(labelWithString: "")
    private let serverRemoteHostField = NSTextField(labelWithString: "")
    private let serverSummaryField = NSTextField(wrappingLabelWithString: "")
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
    private var servers: [RemoteServerDefinition]
    private var services: [ServiceDefinition]
    private var composeSourceFile = ""
    private var composeAdditionalSourceFiles: [String] = []

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
        self.servers = (try? store.remoteServers().sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }) ?? []
        self.services = profile?.services ?? []

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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    @objc func beginAddService() {
        addServiceAction(nil)
    }

    private func configureFields(with profile: ProfileDefinition?) {
        nameField.stringValue = profile?.name ?? ""
        composeProjectField.stringValue = profile?.compose.projectName ?? ""
        composeWorkingDirectoryField.stringValue = profile?.compose.workingDirectory ?? ""
        composeSourceFile = profile?.compose.sourceFile ?? ""
        composeAdditionalSourceFiles = profile?.compose.additionalSourceFiles ?? []
        shellExportsTextView.string = (profile?.shellExports ?? []).joined(separator: "\n")
        composeTextView.string = profile?.compose.content ?? ""

        serverField.removeAllItems()
        serverField.target = self
        serverField.action = #selector(serverSelectionChanged(_:))
        reloadServers(preferredName: preferredServerName(for: profile))
        serverSummaryField.textColor = .secondaryLabelColor
        serverSummaryField.maximumNumberOfLines = 0
        updateServerDetails()

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

        stack.addArrangedSubview(buttonRow())
    }

    private func profileGrid() -> NSGridView {
        let grid = NSGridView(views: [
            [label("Name"), nameField],
            [label("Server"), serverSelectionRow()],
            [label("Docker Context"), serverDockerContextField],
            [label("Remote Docker Server"), serverRemoteHostField],
            [NSView(), serverSummaryField],
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

    private func serverSelectionRow() -> NSView {
        let addButton = button(title: "New Server…", action: #selector(addServerAction(_:)))
        let editButton = button(title: "Edit…", action: #selector(editServerAction(_:)))
        let stack = NSStackView(views: [serverField, addButton, editButton])
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

    func numberOfRows(in tableView: NSTableView) -> Int {
        services.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
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

    @objc private func serverSelectionChanged(_ sender: Any?) {
        updateServerDetails()
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
    }

    @objc private func removeComposeOverlayAction(_ sender: Any?) {
        let selectedPath = selectedOverlayPath()
        guard let selectedPath else {
            return
        }
        composeAdditionalSourceFiles.removeAll { $0 == selectedPath }
        updateComposeOverlayDetails()
    }

    @objc private func openComposeOverlayAction(_ sender: Any?) {
        guard let selectedPath = selectedOverlayPath() else {
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: selectedPath, isDirectory: false))
    }

    @objc private func composeOverlaySelectionChanged(_ sender: Any?) {
        updateComposeOverlayDetails()
    }

    @objc private func addServerAction(_ sender: Any?) {
        let suggestedContext = dockerContexts.first(where: \.isCurrent)?.name ?? "default"
        if let server = ServerWizardWindowController.runModal(
            store: store,
            existingServer: nil,
            suggestedDockerContext: suggestedContext
        ) {
            upsertServer(server)
            reloadServers(preferredName: server.name)
            updateServerDetails()
        }
    }

    @objc private func editServerAction(_ sender: Any?) {
        guard let server = selectedServer() else {
            presentError("Create or select a server first.")
            return
        }

        let suggestedContext = dockerContexts.first(where: \.isCurrent)?.name ?? server.dockerContext
        let originalServerName = server.name
        let updated = ServerWizardWindowController.runModal(
            store: store,
            existingServer: server,
            suggestedDockerContext: suggestedContext
        )

        if let updated {
            removeServer(named: originalServerName)
            upsertServer(updated)
            reloadServers(preferredName: updated.name)
        } else {
            servers = (try? store.remoteServers().sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }) ?? []
            reloadServers(preferredName: selectedServerName() == originalServerName ? nil : selectedServerName())
        }

        updateServerDetails()
    }

    private func buildProfile() throws -> ProfileDefinition {
        let selectedMode = selectedLocalContainerMode()
        guard let server = selectedServer() else {
            throw ValidationError("Choose or create a Docker server first.")
        }
        let profile = ProfileDefinition(
            name: nameField.stringValue,
            serverName: server.name,
            dockerContext: server.dockerContext,
            tunnelHost: server.remoteDockerServerDisplay,
            shellExports: splitLines(shellExportsTextView.string),
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

    private func reloadServers(preferredName: String?) {
        servers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        serverField.removeAllItems()
        serverField.addItems(withTitles: servers.map(\.name))
        if let preferredName, serverField.indexOfItem(withTitle: preferredName) >= 0 {
            serverField.selectItem(withTitle: preferredName)
        } else if !servers.isEmpty {
            serverField.selectItem(at: 0)
        }
        serverField.isEnabled = !servers.isEmpty
    }

    private func selectedServerName() -> String? {
        let selected = serverField.selectedItem?.title ?? ""
        return selected.isEmpty ? nil : selected
    }

    private func selectedServer() -> RemoteServerDefinition? {
        guard let selectedName = selectedServerName() else {
            return nil
        }
        return servers.first(where: { $0.name == selectedName })
    }

    private func preferredServerName(for profile: ProfileDefinition?) -> String? {
        if let explicit = profile?.serverName, !explicit.isEmpty {
            return explicit
        }

        guard let profile else {
            return servers.first?.name
        }

        if let matched = servers.first(where: {
            $0.dockerContext == profile.dockerContext
                || $0.remoteDockerServerDisplay == profile.tunnelHost
                || $0.sshTarget == profile.tunnelHost
        }) {
            return matched.name
        }

        return servers.first?.name
    }

    private func updateServerDetails() {
        guard let server = selectedServer() else {
            serverDockerContextField.stringValue = "No server selected"
            serverRemoteHostField.stringValue = "No server selected"
            serverSummaryField.stringValue = "Profiles are now bound to saved server definitions. Create a local or SSH server first."
            return
        }

        serverDockerContextField.stringValue = server.dockerContext
        serverRemoteHostField.stringValue = server.remoteDockerServerDisplay
        serverSummaryField.stringValue = server.connectionSummary
    }

    private func upsertServer(_ server: RemoteServerDefinition) {
        removeServer(named: server.name)
        servers.append(server)
    }

    private func removeServer(named name: String) {
        servers.removeAll { $0.name == name }
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
