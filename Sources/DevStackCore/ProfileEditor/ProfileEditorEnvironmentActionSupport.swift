import AppKit

@MainActor
extension ProfileEditorWindowController {
    @objc func environmentSelectionChanged(_ sender: Any?) {
        updateEnvironmentDetails()
    }

    @objc func refreshComposeEnvironmentAction(_ sender: Any?) {
        reloadComposeEnvironmentOverview()
    }

    @objc func generateEnvironmentValueAction(_ sender: Any?) {
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
        accessory.addArrangedSubview(NSTextField(wrappingLabelWithString: destinationText))
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

    @objc func saveEnvironmentValueAction(_ sender: Any?) {
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

    @objc func ignoreEnvironmentVariableAction(_ sender: Any?) {
        guard let entry = selectedEnvironmentEntry() else {
            presentError("Select a compose variable first.")
            return
        }
        ignoredEnvironmentKeys.insert(entry.key)
        environmentMessage = "Ignored \(entry.key) for this editor session"
        reloadComposeEnvironmentOverview()
    }

    @objc func toggleExternalEnvironmentVariableAction(_ sender: Any?) {
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

    @objc func useClipboardResultAction(_ sender: Any?) {
        guard let value = clipboardParseResult?.value else {
            return
        }
        environmentValueField.stringValue = value
        updateEnvironmentDetails()
    }

    func configureEnvironmentFields() {
        environmentValueField.placeholderString = "Selected variable value"
        environmentSensitiveCheckbox.target = self
        environmentSensitiveCheckbox.action = #selector(environmentSensitivityChanged(_:))
        environmentStatusField.stringValue = "Select a compose variable to inspect env resolution."
        environmentNoteField.stringValue = ""
        clipboardPreviewField.stringValue = ""
    }

    @objc func environmentSensitivityChanged(_ sender: Any?) {
        updateEnvironmentDetails()
    }

    func clipboardPreviewRow() -> NSView {
        let useButton = button(title: "Use Result", action: #selector(useClipboardResultAction(_:)))
        clipboardUseButton = useButton
        let stack = NSStackView(views: [clipboardPreviewField, useButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    func startClipboardObservation() {
        clipboardTimer?.invalidate()
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollClipboard()
            }
        }
        pollClipboard()
    }

    func pollClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastClipboardChangeCount else {
            return
        }
        lastClipboardChangeCount = pasteboard.changeCount
        let raw = pasteboard.string(forType: .string) ?? ""
        clipboardParseResult = ClipboardSmartParser.parse(raw)
        updateClipboardPreview()
    }

    func updateClipboardPreview() {
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
}
