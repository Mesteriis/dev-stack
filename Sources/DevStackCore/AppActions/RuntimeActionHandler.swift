import AppKit
import Foundation

extension AppDelegate {
    @objc func tunnelUpAction(_ sender: Any?) {
        guard let profileName = selectedProfileName() else {
            return
        }
        if let profile = try? store.loadProfile(named: profileName),
           profile.compose.autoUpOnActivate,
           !confirmComposeUpPreview(profileName: profileName)
        {
            return
        }
        runRuntimeAction(successMessage: "Profile activated") {
            try RuntimeController.activateProfile(named: profileName, store: self.store)
        }
    }

    @objc func tunnelDownAction(_ sender: Any?) {
        guard let profileName = selectedProfileName() else {
            return
        }
        runRuntimeAction(successMessage: "Tunnels stopped") {
            try RuntimeController.stopProfile(named: profileName, store: self.store)
        }
    }

    @objc func tunnelRestartAction(_ sender: Any?) {
        guard let profileName = selectedProfileName() else {
            return
        }
        runRuntimeAction(successMessage: "Tunnels restarted") {
            try RuntimeController.restartProfile(named: profileName, store: self.store)
        }
    }

    @objc func composeUpAction(_ sender: Any?) {
        guard let profileName = selectedProfileName() else {
            return
        }
        guard confirmComposeUpPreview(profileName: profileName) else {
            return
        }
        runRuntimeAction(successMessage: "Compose stack started") {
            try RuntimeController.composeUp(profileName: profileName, store: self.store)
        }
    }

    @objc func composeDownAction(_ sender: Any?) {
        guard let profileName = selectedProfileName() else {
            return
        }
        runRuntimeAction(successMessage: "Compose stack stopped") {
            try RuntimeController.composeDown(profileName: profileName, store: self.store)
        }
    }

    @objc func composeRestartAction(_ sender: Any?) {
        guard let profileName = selectedProfileName() else {
            return
        }
        runRuntimeAction(successMessage: "Compose stack restarted") {
            try RuntimeController.composeRestart(profileName: profileName, store: self.store)
        }
    }

    @objc func switchDockerContextAction(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? String else {
            return
        }
        guard let dockerPath = ToolPaths.docker else {
            showError("docker not found")
            return
        }

        runRuntimeAction(successMessage: "Docker context switched to \(context)") {
            let result = Shell.run(dockerPath, arguments: ["context", "use", context])
            guard result.exitCode == 0 else {
                throw ValidationError(RuntimeSharedSupport.nonEmpty(result.stderr) ?? RuntimeSharedSupport.nonEmpty(result.stdout) ?? "Failed to switch docker context")
            }
        }
    }

    @objc func newRuntimeAction(_ sender: Any?) {
        let suggestedContext = dockerContexts.first(where: \.isCurrent)?.name ?? "default"
        if let server = ServerWizardWindowController.runModal(
            store: store,
            existingServer: nil,
            suggestedDockerContext: suggestedContext
        ) {
            lastMessage = "Runtime '\(server.name)' saved"
            refreshSnapshot(force: true)
        }
    }

    @objc func editCurrentRuntimeAction(_ sender: Any?) {
        guard let server = loadCurrentServer() else {
            showError("No runtime selected for the current profile")
            return
        }

        let suggestedContext = dockerContexts.first(where: \.isCurrent)?.name ?? server.dockerContext
        if let updated = ServerWizardWindowController.runModal(
            store: store,
            existingServer: server,
            suggestedDockerContext: suggestedContext
        ) {
            lastMessage = "Runtime '\(updated.name)' updated"
            refreshSnapshot(force: true)
        } else {
            refreshSnapshot(force: true)
        }
    }

    @objc func editRuntimeAction(_ sender: NSMenuItem) {
        guard let serverName = sender.representedObject as? String else {
            return
        }

        do {
            let server = try store.loadRuntime(named: serverName)
            let suggestedContext = dockerContexts.first(where: \.isCurrent)?.name ?? server.dockerContext
            if let updated = ServerWizardWindowController.runModal(
                store: store,
                existingServer: server,
                suggestedDockerContext: suggestedContext
            ) {
                lastMessage = "Runtime '\(updated.name)' updated"
            }
            refreshSnapshot(force: true)
        } catch {
            showError(error.localizedDescription)
        }
    }
}
