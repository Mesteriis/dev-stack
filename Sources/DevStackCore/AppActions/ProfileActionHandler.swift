import AppKit
import Foundation
import UniformTypeIdentifiers

extension AppDelegate {
    @objc func switchProfileAction(_ sender: NSMenuItem) {
        guard let profile = sender.representedObject as? String else {
            return
        }
        runRuntimeAction(successMessage: "Profile switched to \(profile)") {
            try RuntimeController.activateProfile(named: profile, store: self.store)
        }
    }

    @objc func newProfileAction(_ sender: Any?) {
        openProfileEditor(profile: nil, beginWithAddService: false)
    }

    @objc func importComposeFileAction(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "yml") ?? .yaml,
            UTType(filenameExtension: "yaml") ?? .yaml,
        ]
        panel.message = "Choose a docker-compose file to import into DX."

        if panel.runModal() == .OK, let url = panel.url {
            beginComposeImport(from: url)
        }
    }

    @objc func editCurrentProfileAction(_ sender: Any?) {
        guard let profile = loadCurrentProfile() else {
            return
        }
        openProfileEditor(profile: profile, beginWithAddService: false)
    }

    @objc func addServiceToCurrentProfileAction(_ sender: Any?) {
        guard let profile = loadCurrentProfile() else {
            return
        }
        openProfileEditor(profile: profile, beginWithAddService: true)
    }

    @objc func manageSecretsAction(_ sender: Any?) {
        guard let profile = loadCurrentProfile() else {
            return
        }

        let controller = SecretManagerWindowController(
            store: store,
            profile: profile,
            onClose: { [weak self] in
                self?.editors.removeAll { $0.window == nil || !$0.window!.isVisible }
            }
        )
        editors.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func deleteCurrentProfileAction(_ sender: Any?) {
        guard let profile = loadCurrentProfile() else {
            return
        }

        let deleteOnlyPlan = try? RuntimeController.deletionPlan(profileName: profile.name, store: store, removeData: false)
        let deleteWithDataPlan = try? RuntimeController.deletionPlan(profileName: profile.name, store: store, removeData: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete profile '\(profile.name)'?"
        var lines = ["This will stop tunnels and bring down the compose stack for this profile."]
        if let plan = deleteOnlyPlan, !plan.runningServiceNames.isEmpty {
            lines.append("")
            lines.append("Running services:")
            lines.append(contentsOf: plan.runningServiceNames.map { "- \($0)" })
        }
        if let plan = deleteWithDataPlan {
            if !plan.volumes.isEmpty {
                lines.append("")
                lines.append("Delete + Data also removes volumes:")
                lines.append(contentsOf: plan.volumes.map { "- \($0)" })
            }
            if let localDataPath = plan.localDataPath {
                lines.append("")
                lines.append("Local data:")
                lines.append("- \(localDataPath)")
            }
            if let remoteProjectPath = plan.remoteProjectPath {
                lines.append("")
                lines.append("Remote project data:")
                lines.append("- \(remoteProjectPath)")
            }
        }
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: "Delete + Data")
        alert.addButton(withTitle: "Delete Profile")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            runRuntimeAction(successMessage: "Profile deleted with data cleanup") {
                try RuntimeController.deleteProfile(named: profile.name, store: self.store, removeData: true)
            }
        case .alertSecondButtonReturn:
            runRuntimeAction(successMessage: "Profile deleted") {
                try RuntimeController.deleteProfile(named: profile.name, store: self.store, removeData: false)
            }
        default:
            return
        }
    }
}
