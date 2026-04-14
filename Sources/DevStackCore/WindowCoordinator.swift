import AppKit
import Foundation

extension AppDelegate {
    func openProfileEditor(profile: ProfileDefinition?, beginWithAddService: Bool) {
        let controller = ProfileEditorWindowController(
            store: store,
            profile: profile,
            dockerContexts: dockerContexts,
            onSave: { [weak self] profile, originalName in
                try self?.persistProfile(profile, originalName: originalName)
            },
            onClose: { [weak self] in
                self?.editors.removeAll { $0.window == nil || !$0.window!.isVisible }
            }
        )

        editors.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)

        if beginWithAddService {
            Task {
                controller.beginAddService()
            }
        }
    }

    func beginComposeImport(from url: URL) {
        do {
            let imported = try ProfileImportService.importedServices(from: url)

            let controller = ComposeImportWindowController(
                composeURL: url,
                composeContent: imported.content,
                importedServices: imported.services,
                profiles: profiles,
                currentProfileName: selectedProfileName(),
                onImport: { [weak self] request in
                    self?.openImportedComposeInEditor(request)
                },
                onClose: { [weak self] in
                    self?.editors.removeAll { $0.window == nil || !$0.window!.isVisible }
                }
            )

            editors.append(controller)
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            showError(error.localizedDescription)
        }
    }

    func openImportedComposeInEditor(_ request: ComposeImportRequest) {
        do {
            let profile = try ProfileImportService.draftProfile(
                from: request,
                store: store,
                currentProfileName: selectedProfileName(),
                activeDockerContext: snapshot?.configuredDockerContext,
                dockerContexts: dockerContexts,
                runtimeTargets: runtimeTargets
            )
            openProfileEditor(profile: profile, beginWithAddService: false)
        } catch {
            showError(error.localizedDescription)
        }
    }

    func persistProfile(_ profile: ProfileDefinition, originalName: String?) throws {
        let previousProfile = originalName.flatMap { try? store.loadProfile(named: $0) }
        if !profile.runtimeName.isEmpty {
            _ = try store.loadRuntime(named: profile.runtimeName)
        }
        try store.saveProfile(profile, originalName: originalName)
        let current = snapshot?.profile ?? store.currentProfileName()
        let isUpdatingCurrent = current == originalName || current == profile.name

        if isUpdatingCurrent,
           let previousProfile,
           previousProfile.compose.configured,
           shouldResetComposeRuntime(previous: previousProfile, next: profile)
        {
            try? RuntimeController.cleanupRuntime(for: previousProfile, store: store, removeVolumes: false)
        }

        if isUpdatingCurrent {
            try RuntimeController.activateProfile(named: profile.name, store: store)
            lastMessage = "Profile saved and activated"
        } else {
            lastMessage = "Profile saved"
        }

        refreshSnapshot(force: true)
    }
}
