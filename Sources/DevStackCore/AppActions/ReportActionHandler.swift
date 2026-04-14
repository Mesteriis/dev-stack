import AppKit
import Foundation

extension AppDelegate {
    @objc func refreshAction(_ sender: Any?) {
        refreshSnapshot(force: true)
    }

    @objc func copyShellExportsAction(_ sender: Any?) {
        guard let profileName = selectedProfileName() else {
            return
        }

        do {
            let exports = try RuntimeController.shellExports(profileName: profileName, store: store)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(exports, forType: .string)
            lastMessage = "Shell exports copied"
            rebuildMenu()
            updateStatusButton()
        } catch {
            showError(error.localizedDescription)
            return
        }
    }

    @objc func openProfilesFolderAction(_ sender: Any?) {
        NSWorkspace.shared.open(store.profilesDirectory)
    }

    @objc func openCurrentProfileDataFolderAction(_ sender: Any?) {
        guard let profile = loadCurrentProfile() else {
            return
        }

        do {
            try store.ensureRuntimeDirectories()
            let directory = store.profileDataDirectory(for: profile)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(directory)
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc func openRuntimesFolderAction(_ sender: Any?) {
        NSWorkspace.shared.open(store.runtimesDirectory)
    }

    @objc func openCurrentProjectFolderAction(_ sender: Any?) {
        guard let profile = loadCurrentProfile() else {
            return
        }

        guard let directory = store.managedProjectDirectory(for: profile) else {
            showError("Current profile is not linked to a project folder")
            return
        }

        NSWorkspace.shared.open(directory)
    }

    @objc func openAppSupportFolderAction(_ sender: Any?) {
        NSWorkspace.shared.open(store.rootDirectory)
    }

    @objc func openComposePreviewAction(_ sender: Any?) {
        guard let profileName = selectedProfileName() else {
            return
        }

        do {
            let preview = try RuntimeController.composePreview(profileName: profileName, store: store)
            let reportURL = store.generatedComposePlanURL(for: profileName)
            try ComposeSupport.writePlanReport(plan: preview.plan, to: reportURL)
            NSWorkspace.shared.open(reportURL)
            lastMessage = "Compose preview opened"
            rebuildMenu()
            updateStatusButton()
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc func openComposeLogsAction(_ sender: Any?) {
        guard let profileName = selectedProfileName() else {
            return
        }

        do {
            let url = try RuntimeController.writeComposeLogsSnapshot(profileName: profileName, store: store)
            NSWorkspace.shared.open(url)
            lastMessage = "Compose logs opened"
            rebuildMenu()
            updateStatusButton()
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc func openVolumeReportAction(_ sender: Any?) {
        guard let profileName = selectedProfileName() else {
            return
        }

        do {
            let url = try RuntimeController.writeVolumeReport(profileName: profileName, store: store)
            NSWorkspace.shared.open(url)
            lastMessage = "Volume report opened"
            rebuildMenu()
            updateStatusButton()
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc func removeCurrentVolumesAction(_ sender: Any?) {
        guard let profileName = selectedProfileName() else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remove compose volumes for '\(profileName)'?"
        alert.informativeText = "This deletes current Docker named volumes for the selected profile."
        alert.addButton(withTitle: "Remove Volumes")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        runRuntimeAction(successMessage: "Compose volumes removed") {
            _ = try RuntimeController.removeComposeVolumes(profileName: profileName, store: self.store)
        }
    }

    @objc func openMetricsReportAction(_ sender: Any?) {
        guard let profileName = selectedProfileName() else {
            return
        }

        do {
            let url = try RuntimeController.writeMetricsReport(profileName: profileName, store: store)
            NSWorkspace.shared.open(url)
            lastMessage = "Runtime metrics opened"
            rebuildMenu()
            updateStatusButton()
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc func openRemoteFilesAction(_ sender: Any?) {
        guard let profileName = selectedProfileName() else {
            return
        }

        do {
            let url = try RuntimeController.writeRemoteBrowseReport(profileName: profileName, store: store)
            NSWorkspace.shared.open(url)
            lastMessage = "Remote file report opened"
            rebuildMenu()
            updateStatusButton()
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc func openProjectEnvFilesAction(_ sender: Any?) {
        guard let profile = loadCurrentProfile(),
              let projectDirectory = store.managedProjectDirectory(for: profile)
        else {
            return
        }

        let candidates = [".env", ".env.local", ".env.devstack"].map {
            projectDirectory.appendingPathComponent($0, isDirectory: false)
        }

        if let firstExisting = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            NSWorkspace.shared.open(firstExisting)
        } else {
            NSWorkspace.shared.open(projectDirectory)
        }
    }

    @objc func manageVariablesAction(_ sender: Any?) {
        let controller = VariableManagerWindowController(
            store: store,
            onClose: { [weak self] in
                self?.editors.removeAll { $0.window == nil || !$0.window!.isVisible }
            }
        )
        editors.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func quitAction(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }

    @objc func supportProjectAction(_ sender: Any?) {
        guard let url = URL(string: "https://buymeacoffee.com/mesteriis") else {
            showError("Support link is invalid")
            return
        }
        NSWorkspace.shared.open(url)
    }
}
