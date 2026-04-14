import AppKit

@MainActor
enum ManagedVariableEditorDialog {
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
            if parentWindow != nil {
                response = alert.runModal()
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

struct ManagedVariableImportSelection {
    let profileNames: [String]
    let overwriteExistingValues: Bool
}

@MainActor
enum ManagedVariableImportDialog {
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
            if parentWindow != nil {
                response = alert.runModal()
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
