import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
extension ProfileEditorWindowController {
    func configureFields(with profile: ProfileDefinition?) {
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

    @objc func localContainerModeChanged(_ sender: Any?) {
        updateLocalContainerModeDescription()
    }

    @objc func runtimeSelectionChanged(_ sender: Any?) {
        updateRuntimeDetails()
    }

    @objc func chooseComposeSourceAction(_ sender: Any?) {
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

    @objc func clearComposeSourceAction(_ sender: Any?) {
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

    @objc func openComposeSourceAction(_ sender: Any?) {
        let path = composeSourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: false))
    }

    @objc func addComposeOverlayAction(_ sender: Any?) {
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

    @objc func removeComposeOverlayAction(_ sender: Any?) {
        let selectedPath = selectedOverlayPath()
        guard let selectedPath else {
            return
        }
        composeAdditionalSourceFiles.removeAll { $0 == selectedPath }
        updateComposeOverlayDetails()
        reloadComposeEnvironmentOverview()
    }

    @objc func openComposeOverlayAction(_ sender: Any?) {
        guard let selectedPath = selectedOverlayPath() else {
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: selectedPath, isDirectory: false))
    }

    @objc func composeOverlaySelectionChanged(_ sender: Any?) {
        updateComposeOverlayDetails()
        updateEnvironmentDetails()
    }

    @objc func addRuntimeAction(_ sender: Any?) {
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

    @objc func editRuntimeAction(_ sender: Any?) {
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

    func selectedLocalContainerMode() -> LocalContainerMode {
        let selectedTitle = localContainerModeField.selectedItem?.title
        return LocalContainerMode.allCases.first(where: { $0.title == selectedTitle }) ?? .manual
    }

    func updateLocalContainerModeDescription() {
        localContainerModeDescription.stringValue = selectedLocalContainerMode().summary
    }

    func updateComposeSourceDetails() {
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

    func updateComposeOverlayDetails() {
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

    func selectedOverlayPath() -> String? {
        let title = composeOverlaysField.selectedItem?.title ?? ""
        guard !title.isEmpty, title != "No overlays" else {
            return nil
        }
        return title
    }

    func selectComposeURLs(allowsMultipleSelection: Bool) -> [URL] {
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

    func reloadRuntimeTargets(preferredName: String?) {
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

    func selectedRuntimeName() -> String? {
        let selected = runtimeField.selectedItem?.title ?? ""
        return selected.isEmpty ? nil : selected
    }

    func selectedRuntimeTarget() -> RemoteServerDefinition? {
        guard let selectedName = selectedRuntimeName() else {
            return nil
        }
        return runtimeTargets.first(where: { $0.name == selectedName })
    }

    func preferredRuntimeName(for profile: ProfileDefinition?) -> String? {
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

    func updateRuntimeDetails() {
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

    func upsertRuntimeTarget(_ server: RemoteServerDefinition) {
        removeRuntimeTarget(named: server.name)
        runtimeTargets.append(server)
    }

    func removeRuntimeTarget(named name: String) {
        runtimeTargets.removeAll { $0.name == name }
    }
}
