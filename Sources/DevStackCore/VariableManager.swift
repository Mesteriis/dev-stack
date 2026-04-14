import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class VariableManagerWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private let store: ProfileStore
    private let onClose: () -> Void

    private let summaryField = NSTextField(wrappingLabelWithString: "")
    private let tableView = NSTableView()
    private var variables: [ManagedVariableDefinition] = []

    init(store: ProfileStore, onClose: @escaping () -> Void) {
        self.store = store
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Global Variable Manager"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self

        buildUI()
        reloadVariables()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        variables.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < variables.count else {
            return nil
        }

        let variable = variables[row]
        let identifier = tableColumn?.identifier.rawValue ?? "name"
        let text: String
        switch identifier {
        case "value":
            text = variable.value
        case "profiles":
            text = variable.profileNames.joined(separator: ", ")
        default:
            text = variable.name
        }

        let viewIdentifier = NSUserInterfaceItemIdentifier("managed-var-\(identifier)")
        let label: NSTextField
        if let existing = tableView.makeView(withIdentifier: viewIdentifier, owner: self) as? NSTextField {
            label = existing
        } else {
            label = NSTextField(labelWithString: "")
            label.identifier = viewIdentifier
            label.lineBreakMode = .byTruncatingMiddle
        }
        label.stringValue = text
        return label
    }

    @objc private func addVariableAction(_ sender: Any?) {
        do {
            let profiles = try store.profileNames()
            if let variable = ManagedVariableEditorDialog.runModal(
                variable: nil,
                availableProfiles: profiles,
                parentWindow: window
            ) {
                try store.upsertManagedVariable(variable)
                reloadVariables(message: "Variable '\(variable.name)' saved")
            }
        } catch {
            presentError(error.localizedDescription)
        }
    }

    @objc private func editVariableAction(_ sender: Any?) {
        guard let current = selectedVariable() else {
            presentError("Select a variable first.")
            return
        }

        do {
            let profiles = try store.profileNames()
            if let updated = ManagedVariableEditorDialog.runModal(
                variable: current,
                availableProfiles: profiles,
                parentWindow: window
            ) {
                var values = try store.managedVariables().filter { $0.name != current.name }
                values.append(updated)
                try store.saveManagedVariables(values)
                reloadVariables(message: "Variable '\(updated.name)' updated")
            }
        } catch {
            presentError(error.localizedDescription)
        }
    }

    @objc private func deleteVariableAction(_ sender: Any?) {
        guard let current = selectedVariable() else {
            presentError("Select a variable first.")
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete variable '\(current.name)'?"
        alert.informativeText = "This removes the variable from all assigned profiles."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        do {
            try store.deleteManagedVariable(named: current.name)
            reloadVariables(message: "Variable '\(current.name)' deleted")
        } catch {
            presentError(error.localizedDescription)
        }
    }

    @objc private func importVariablesAction(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType.plainText,
            UTType(filenameExtension: "env") ?? .plainText,
        ]
        panel.message = "Choose a .env file to import into the variable manager."

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        let imported = ComposeSupport.parseEnvironmentFile(at: url)
        guard !imported.isEmpty else {
            presentError("No variables were found in \(url.lastPathComponent).")
            return
        }

        do {
            let profiles = try store.profileNames()
            let suggestedProfiles = suggestedProfileNames(for: url)
            guard let selection = ManagedVariableImportDialog.runModal(
                sourceURL: url,
                importedCount: imported.count,
                availableProfiles: profiles,
                suggestedProfiles: suggestedProfiles,
                parentWindow: window
            ) else {
                return
            }

            let summary = try importVariables(
                imported,
                assignedProfiles: selection.profileNames,
                overwriteExistingValues: selection.overwriteExistingValues
            )
            reloadVariables(
                message: "Imported \(summary.created) new and updated \(summary.updated) existing variable(s)"
            )
        } catch {
            presentError(error.localizedDescription)
        }
    }

    @objc private func refreshAction(_ sender: Any?) {
        reloadVariables()
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

        let title = NSTextField(labelWithString: "Managed env variables")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        root.addArrangedSubview(title)

        summaryField.maximumNumberOfLines = 4
        summaryField.textColor = .secondaryLabelColor
        root.addArrangedSubview(summaryField)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView

        tableView.headerView = NSTableHeaderView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 24
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(editVariableAction(_:))

        addColumn(id: "name", title: "Name", width: 180)
        addColumn(id: "value", title: "Value", width: 260)
        addColumn(id: "profiles", title: "Assigned Profiles", width: 360)

        NSLayoutConstraint.activate([
            scrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 800),
            scrollView.heightAnchor.constraint(equalToConstant: 380),
        ])
        root.addArrangedSubview(scrollView)

        let buttons = NSStackView(views: [
            button(title: "Add Variable…", action: #selector(addVariableAction(_:))),
            button(title: "Edit Variable…", action: #selector(editVariableAction(_:))),
            button(title: "Delete Variable", action: #selector(deleteVariableAction(_:))),
            button(title: "Import .env…", action: #selector(importVariablesAction(_:))),
            button(title: "Refresh", action: #selector(refreshAction(_:))),
        ])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8
        root.addArrangedSubview(buttons)
    }

    private func addColumn(id: String, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        column.resizingMask = .userResizingMask
        tableView.addTableColumn(column)
    }

    private func selectedVariable() -> ManagedVariableDefinition? {
        let row = tableView.selectedRow
        guard row >= 0, row < variables.count else {
            return nil
        }
        return variables[row]
    }

    private func reloadVariables(message: String? = nil) {
        do {
            variables = try store.managedVariables()
            let profiles = Set(variables.flatMap(\.profileNames))
            let lines = [
                "Resolution order: Variable Manager -> .env -> .env.local -> .env.devstack -> Keychain secrets",
                "Managed variables: \(variables.count)",
                "Profiles referenced: \(profiles.count)",
            ]
            summaryField.stringValue = ([message].compactMap { $0 } + [lines.joined(separator: "\n")]).joined(separator: "\n\n")
        } catch {
            variables = []
            summaryField.stringValue = error.localizedDescription
        }

        tableView.reloadData()
    }

    private func importVariables(
        _ imported: [String: String],
        assignedProfiles: [String],
        overwriteExistingValues: Bool
    ) throws -> (created: Int, updated: Int) {
        var currentValues = Dictionary(uniqueKeysWithValues: try store.managedVariables().map { ($0.name, $0) })
        var created = 0
        var updated = 0

        for (name, value) in imported.sorted(by: { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }) {
            if var existing = currentValues[name] {
                if overwriteExistingValues {
                    existing.value = value
                }
                existing.profileNames = Array(Set(existing.profileNames + assignedProfiles))
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                currentValues[name] = try existing.normalized()
                updated += 1
            } else {
                currentValues[name] = try ManagedVariableDefinition(
                    name: name,
                    value: value,
                    profileNames: assignedProfiles
                ).normalized()
                created += 1
            }
        }

        try store.saveManagedVariables(Array(currentValues.values))
        return (created, updated)
    }

    private func suggestedProfileNames(for envURL: URL) -> [String] {
        let envDirectory = envURL.deletingLastPathComponent().standardizedFileURL
        let envGit = GitProjectInspector.inspectProject(at: envDirectory)
        let profiles = (try? store.profileNames().compactMap { try? store.loadProfile(named: $0) }) ?? []

        return profiles.compactMap { profile in
            guard let projectDirectory = store.managedProjectDirectory(for: profile) else {
                return nil
            }
            if projectDirectory.standardizedFileURL.path == envDirectory.path {
                return profile.name
            }
            let profileGit = GitProjectInspector.inspectProject(at: projectDirectory)
            if envGit?.repositoryRoot == profileGit?.repositoryRoot, envGit?.repositoryRoot != nil {
                return profile.name
            }
            return nil
        }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Variable Manager Error"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window ?? NSWindow(), completionHandler: nil)
    }

    private func button(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }
}

@MainActor
private enum ManagedVariableEditorDialog {
    static func runModal(
        variable: ManagedVariableDefinition?,
        availableProfiles: [String],
        parentWindow: NSWindow?
    ) -> ManagedVariableDefinition? {
        let nameField = NSTextField(string: variable?.name ?? "")
        let valueField = NSTextField(string: variable?.value ?? "")
        let checkboxes = profileCheckboxes(
            availableProfiles: availableProfiles,
            selectedProfiles: Set(variable?.profileNames ?? [])
        )

        let accessory = NSStackView()
        accessory.orientation = .vertical
        accessory.alignment = .leading
        accessory.spacing = 8

        accessory.addArrangedSubview(formRow(label: "Name", field: nameField))
        accessory.addArrangedSubview(formRow(label: "Value", field: valueField))
        accessory.addArrangedSubview(sectionLabel("Assigned Profiles"))
        accessory.addArrangedSubview(profileChecklistContainer(checkboxes))

        let alert = NSAlert()
        alert.messageText = variable == nil ? "Add Variable" : "Edit Variable"
        alert.informativeText = "Managed variables are written before project .env files, so local env files can still override them."
        alert.accessoryView = accessory
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

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

            let selectedProfiles = checkboxes
                .filter { $0.state == .on }
                .map(\.title)

            do {
                return try ManagedVariableDefinition(
                    name: nameField.stringValue,
                    value: valueField.stringValue,
                    profileNames: selectedProfiles
                ).normalized()
            } catch {
                showSimpleError(error.localizedDescription)
            }
        }
    }

    private static func profileCheckboxes(
        availableProfiles: [String],
        selectedProfiles: Set<String>
    ) -> [NSButton] {
        availableProfiles.map { profileName in
            let checkbox = NSButton(checkboxWithTitle: profileName, target: nil, action: nil)
            checkbox.state = selectedProfiles.contains(profileName) ? .on : .off
            return checkbox
        }
    }

    static func profileChecklistContainer(_ checkboxes: [NSButton]) -> NSView {
        if checkboxes.isEmpty {
            return NSTextField(wrappingLabelWithString: "Create at least one profile before assigning managed variables.")
        }

        let content = NSStackView(views: checkboxes)
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 6

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = content
        scrollView.frame = NSRect(x: 0, y: 0, width: 420, height: 160)
        return scrollView
    }

    private static func formRow(label text: String, field: NSView) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        label.alignment = .right

        let grid = NSGridView(views: [[label, field]])
        grid.column(at: 0).width = 80
        grid.columnSpacing = 12
        return grid
    }

    private static func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        return label
    }

    private static func showSimpleError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Variable Error"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private struct ManagedVariableImportSelection {
    let profileNames: [String]
    let overwriteExistingValues: Bool
}

@MainActor
private enum ManagedVariableImportDialog {
    static func runModal(
        sourceURL: URL,
        importedCount: Int,
        availableProfiles: [String],
        suggestedProfiles: [String],
        parentWindow: NSWindow?
    ) -> ManagedVariableImportSelection? {
        let overwriteCheckbox = NSButton(
            checkboxWithTitle: "Overwrite values for variables that already exist",
            target: nil,
            action: nil
        )
        overwriteCheckbox.state = .on

        let checkboxes = availableProfiles.map { profileName in
            let checkbox = NSButton(checkboxWithTitle: profileName, target: nil, action: nil)
            checkbox.state = suggestedProfiles.contains(profileName) ? .on : .off
            return checkbox
        }

        let accessory = NSStackView()
        accessory.orientation = .vertical
        accessory.alignment = .leading
        accessory.spacing = 8

        let description = NSTextField(
            wrappingLabelWithString: "Import \(importedCount) variable(s) from \(sourceURL.lastPathComponent) and assign them to selected profiles."
        )
        description.maximumNumberOfLines = 3
        accessory.addArrangedSubview(description)

        if !suggestedProfiles.isEmpty {
            let suggested = NSTextField(
                wrappingLabelWithString: "Suggested profiles: \(suggestedProfiles.joined(separator: ", "))"
            )
            suggested.textColor = .secondaryLabelColor
            suggested.maximumNumberOfLines = 2
            accessory.addArrangedSubview(suggested)
        }

        accessory.addArrangedSubview(overwriteCheckbox)
        accessory.addArrangedSubview(ManagedVariableEditorDialog.profileChecklistContainer(checkboxes))

        let alert = NSAlert()
        alert.messageText = "Import .env Into Variable Manager"
        alert.informativeText = sourceURL.path
        alert.accessoryView = accessory
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")

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

            let selectedProfiles = checkboxes.filter { $0.state == .on }.map(\.title)
            if selectedProfiles.isEmpty {
                let error = NSAlert()
                error.alertStyle = .warning
                error.messageText = "Select at least one profile."
                error.runModal()
                continue
            }

            return ManagedVariableImportSelection(
                profileNames: selectedProfiles,
                overwriteExistingValues: overwriteCheckbox.state == .on
            )
        }
    }
}
