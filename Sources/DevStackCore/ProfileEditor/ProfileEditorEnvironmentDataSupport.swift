import Foundation

@MainActor
extension ProfileEditorWindowController {
    func buildProfileDraftForUtilities() throws -> ProfileDefinition {
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

    func reloadComposeEnvironmentOverview(selecting preferredKey: String? = nil) {
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

    func selectEnvironmentKey(_ preferredKey: String?) {
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

    func selectedEnvironmentEntry() -> ComposeEnvironmentEntry? {
        let row = environmentTableView.selectedRow
        guard row >= 0, row < (environmentOverview?.entries.count ?? 0) else {
            return nil
        }
        return environmentOverview?.entries[row]
    }

    func updateEnvironmentDetails() {
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

    func persistEnvironmentValue(
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
}
