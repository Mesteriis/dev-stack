import AppKit
import Foundation
@MainActor
extension ProfileEditorWindowController {
    @objc func runtimeSelectionChanged(_ sender: Any?) {
        updateRuntimeDetails()
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
