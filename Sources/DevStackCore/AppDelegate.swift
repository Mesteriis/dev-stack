import AppKit
import Foundation
import UniformTypeIdentifiers
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store = ProfileStore()
    private let projectWatchCoordinator = ProjectWatchCoordinator()

    private var refreshTimer: Timer?
    private var snapshot: AppSnapshot?
    private var profiles: [String] = []
    private var activeProfiles: [String] = []
    private var runtimeTargets: [RemoteServerDefinition] = []
    private var dockerContexts: [DockerContextEntry] = []
    private var errorMessage: String?
    private var isRefreshing = false
    private var lastMessage: String?
    private var editors: [NSWindowController] = []
    private var aiToolSnapshots: [AIToolQuotaSnapshot] = []
    private var currentGitProjectInfo: GitProjectInfo?
    private var currentMetricsSnapshot: CompactMetricsSnapshot?
    private var ideActivationPromptShown = false
    private var pendingWatchRefresh: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if #available(macOS 13.0, *) {
            statusItem.behavior = [.removalAllowed]
        }

        do {
            try store.ensureRuntimeDirectories()
        } catch {
            errorMessage = error.localizedDescription
        }

        updateStatusButton()
        rebuildMenu()
        refreshSnapshot(force: true)

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSnapshot()
            }
        }

        handleLaunchArguments()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        projectWatchCoordinator.stop()
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let first = filenames.first else {
            return
        }
        beginComposeImport(from: URL(fileURLWithPath: first))
        sender.reply(toOpenOrPrint: .success)
    }

    @objc private func refreshAction(_ sender: Any?) {
        refreshSnapshot(force: true)
    }

    @objc private func tunnelUpAction(_ sender: Any?) {
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

    @objc private func tunnelDownAction(_ sender: Any?) {
        guard let profileName = selectedProfileName() else {
            return
        }
        runRuntimeAction(successMessage: "Tunnels stopped") {
            try RuntimeController.stopProfile(named: profileName, store: self.store)
        }
    }

    @objc private func tunnelRestartAction(_ sender: Any?) {
        guard let profileName = selectedProfileName() else {
            return
        }
        runRuntimeAction(successMessage: "Tunnels restarted") {
            try RuntimeController.restartProfile(named: profileName, store: self.store)
        }
    }

    @objc private func composeUpAction(_ sender: Any?) {
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

    @objc private func composeDownAction(_ sender: Any?) {
        guard let profileName = selectedProfileName() else {
            return
        }
        runRuntimeAction(successMessage: "Compose stack stopped") {
            try RuntimeController.composeDown(profileName: profileName, store: self.store)
        }
    }

    @objc private func composeRestartAction(_ sender: Any?) {
        guard let profileName = selectedProfileName() else {
            return
        }
        runRuntimeAction(successMessage: "Compose stack restarted") {
            try RuntimeController.composeRestart(profileName: profileName, store: self.store)
        }
    }

    @objc private func switchProfileAction(_ sender: NSMenuItem) {
        guard let profile = sender.representedObject as? String else {
            return
        }
        runRuntimeAction(successMessage: "Profile switched to \(profile)") {
            try RuntimeController.activateProfile(named: profile, store: self.store)
        }
    }

    @objc private func switchDockerContextAction(_ sender: NSMenuItem) {
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
                throw ValidationError(Self.nonEmpty(result.stderr) ?? Self.nonEmpty(result.stdout) ?? "Failed to switch docker context")
            }
        }
    }

    @objc private func copyShellExportsAction(_ sender: Any?) {
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

    @objc private func newProfileAction(_ sender: Any?) {
        openProfileEditor(profile: nil, beginWithAddService: false)
    }

    @objc private func newRuntimeAction(_ sender: Any?) {
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

    @objc private func editCurrentRuntimeAction(_ sender: Any?) {
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

    @objc private func editRuntimeAction(_ sender: NSMenuItem) {
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

    @objc private func importComposeFileAction(_ sender: Any?) {
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

    @objc private func editCurrentProfileAction(_ sender: Any?) {
        guard let profile = loadCurrentProfile() else {
            return
        }
        openProfileEditor(profile: profile, beginWithAddService: false)
    }

    @objc private func addServiceToCurrentProfileAction(_ sender: Any?) {
        guard let profile = loadCurrentProfile() else {
            return
        }
        openProfileEditor(profile: profile, beginWithAddService: true)
    }

    @objc private func openProfilesFolderAction(_ sender: Any?) {
        NSWorkspace.shared.open(store.profilesDirectory)
    }

    @objc private func openCurrentProfileDataFolderAction(_ sender: Any?) {
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

    @objc private func openRuntimesFolderAction(_ sender: Any?) {
        NSWorkspace.shared.open(store.runtimesDirectory)
    }

    @objc private func openCurrentProjectFolderAction(_ sender: Any?) {
        guard let profile = loadCurrentProfile() else {
            return
        }

        guard let directory = store.managedProjectDirectory(for: profile) else {
            showError("Current profile is not linked to a project folder")
            return
        }

        NSWorkspace.shared.open(directory)
    }

    @objc private func openAppSupportFolderAction(_ sender: Any?) {
        NSWorkspace.shared.open(store.rootDirectory)
    }

    @objc private func openComposePreviewAction(_ sender: Any?) {
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

    @objc private func openComposeLogsAction(_ sender: Any?) {
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

    @objc private func openVolumeReportAction(_ sender: Any?) {
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

    @objc private func removeCurrentVolumesAction(_ sender: Any?) {
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

    @objc private func openMetricsReportAction(_ sender: Any?) {
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

    @objc private func openRemoteFilesAction(_ sender: Any?) {
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

    @objc private func openProjectEnvFilesAction(_ sender: Any?) {
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

    @objc private func manageSecretsAction(_ sender: Any?) {
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

    @objc private func manageVariablesAction(_ sender: Any?) {
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

    @objc private func deleteCurrentProfileAction(_ sender: Any?) {
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

    @objc private func quitAction(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }

    @objc private func aiToolHelpAction(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let kind = AIToolKind(rawValue: rawValue),
              let snapshot = aiToolSnapshots.first(where: { $0.kind == kind })
        else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "\(snapshot.kind.title) Setup"
        var informativeText = snapshot.helpMessage
        if let helpCommand = snapshot.helpCommand {
            informativeText += "\n\nCommand:\n\(helpCommand)"
            alert.addButton(withTitle: "Copy Command")
        }
        alert.informativeText = informativeText
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn, let helpCommand = snapshot.helpCommand {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(helpCommand, forType: .string)
            lastMessage = "\(snapshot.kind.title) auth command copied"
            rebuildMenu()
            updateStatusButton()
        }
    }

    @objc private func supportProjectAction(_ sender: Any?) {
        guard let url = URL(string: "https://buymeacoffee.com/mesteriis") else {
            showError("Support link is invalid")
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func refreshSnapshot(force: Bool = false) {
        if isRefreshing && !force {
            return
        }

        if force {
            AIToolQuotaInspector.invalidateCache()
        }

        isRefreshing = true
        updateStatusButton()
        rebuildMenu()

        let store = store

        Task {
            let snapshotResult = await Task.detached(priority: .utility) {
                AppDelegate.collectState(store: store)
            }.value

            self.snapshot = snapshotResult.snapshot
            self.profiles = snapshotResult.profiles
            self.activeProfiles = snapshotResult.activeProfiles
            self.runtimeTargets = snapshotResult.runtimeTargets
            self.dockerContexts = snapshotResult.dockerContexts
            self.aiToolSnapshots = snapshotResult.aiToolSnapshots
            self.currentGitProjectInfo = snapshotResult.gitProjectInfo
            self.currentMetricsSnapshot = snapshotResult.metricsSnapshot
            self.errorMessage = snapshotResult.errorMessage
            if let cleanupMessage = snapshotResult.cleanupMessage {
                self.lastMessage = cleanupMessage
            }
            self.isRefreshing = false
            self.configureProjectWatchers()
            self.maybePromptForOpenIDEProjects()
            Task {
                await AILimitAlertManager.process(snapshots: self.aiToolSnapshots)
            }
            self.rebuildMenu()
            self.updateStatusButton()
        }
    }

    nonisolated private static func collectState(
        store: ProfileStore
    ) -> (
        snapshot: AppSnapshot?,
        profiles: [String],
        runtimeTargets: [RemoteServerDefinition],
        dockerContexts: [DockerContextEntry],
        aiToolSnapshots: [AIToolQuotaSnapshot],
        activeProfiles: [String],
        gitProjectInfo: GitProjectInfo?,
        metricsSnapshot: CompactMetricsSnapshot?,
        errorMessage: String?,
        cleanupMessage: String?
    ) {
        var snapshot: AppSnapshot?
        var profiles: [String] = []
        var activeProfiles: [String] = []
        var runtimeTargets: [RemoteServerDefinition] = []
        var dockerContexts: [DockerContextEntry] = []
        var aiToolSnapshots: [AIToolQuotaSnapshot] = []
        var gitProjectInfo: GitProjectInfo?
        var metricsSnapshot: CompactMetricsSnapshot?
        var errorMessage: String?
        var cleanupMessage: String?

        do {
            let removedProfiles = try RuntimeController.cleanupProfilesWithMissingComposeSources(store: store)
            if !removedProfiles.isEmpty {
                let sorted = removedProfiles.sorted()
                if sorted.count == 1 {
                    cleanupMessage = "Profile '\(sorted[0])' was removed because its compose file no longer exists"
                } else {
                    cleanupMessage = "Removed stale profiles: \(sorted.joined(separator: ", "))"
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        do {
            profiles = try store.profileNames()
            activeProfiles = store.activeProfileNames().filter { profiles.contains($0) }
        } catch {
            errorMessage = error.localizedDescription
        }

        do {
            dockerContexts = try RuntimeController.dockerContexts()
        } catch {
            if errorMessage == nil {
                errorMessage = error.localizedDescription
            }
        }

        do {
            runtimeTargets = try RuntimeController.remoteServers(store: store)
        } catch {
            if errorMessage == nil {
                errorMessage = error.localizedDescription
            }
        }

        aiToolSnapshots = AIToolQuotaInspector.collectAll(forceRefresh: false)

        let selectedProfileName = resolveCurrentProfileName(
            storedProfileName: store.currentProfileName(),
            profiles: profiles
        )

        if let selectedProfileName {
            do {
                snapshot = try RuntimeController.statusSnapshot(store: store, profileName: selectedProfileName)
                if let profile = try? store.loadProfile(named: selectedProfileName),
                   let projectDirectory = store.managedProjectDirectory(for: profile)
                {
                    gitProjectInfo = GitProjectInspector.inspectProject(at: projectDirectory)
                }
                if snapshot?.compose.runningServices.isEmpty == false {
                    metricsSnapshot = try? RuntimeController.compactMetrics(profileName: selectedProfileName, store: store)
                }
            } catch {
                if errorMessage == nil {
                    errorMessage = error.localizedDescription
                }
            }
        }

        return (snapshot, profiles, runtimeTargets, dockerContexts, aiToolSnapshots, activeProfiles, gitProjectInfo, metricsSnapshot, errorMessage, cleanupMessage)
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let currentProfileDefinition = selectedProfileName().flatMap { try? store.loadProfile(named: $0) }
        if let errorMessage {
            menu.addItem(disabledItem(title: "Error: \(errorMessage)", symbolName: "exclamationmark.triangle"))
        } else if let message = lastMessage {
            menu.addItem(
                disabledItem(
                    title: message,
                    symbolName: isRefreshing ? "hourglass" : "checkmark.circle"
                )
            )
        }

        let hasCurrentProfile = selectedProfileName() != nil

        menu.addItem(makeOverviewMenu(currentProfileDefinition: currentProfileDefinition))
        menu.addItem(makeProfileMenu(currentProfileDefinition: currentProfileDefinition, isEnabled: hasCurrentProfile))
        menu.addItem(makeRuntimesMenu())
        menu.addItem(makeVariablesMenu())
        menu.addItem(makeAILimitsMenu())

        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Buy Me a Coffee", action: #selector(supportProjectAction(_:)), symbolName: "cup.and.saucer"))
        menu.addItem(actionItem(title: "Refresh", action: #selector(refreshAction(_:)), symbolName: "arrow.clockwise"))
        menu.addItem(actionItem(title: "Quit", action: #selector(quitAction(_:)), symbolName: "power"))

        statusItem.menu = menu
    }

    private func makeOverviewMenu(currentProfileDefinition: ProfileDefinition?) -> NSMenuItem {
        let currentProfile = currentProfileDisplayName()
        let item = submenuItem(title: "Status", symbolName: "info.circle")
        let submenu = NSMenu()

        submenu.addItem(disabledItem(title: "Profile: \(currentProfile)", symbolName: "person.crop.rectangle"))
        submenu.addItem(disabledItem(title: "Active Profiles: \(activeProfiles.count)", symbolName: "square.stack.3d.down.right"))
        submenu.addItem(disabledItem(title: "Docker: \(snapshot?.activeDockerContext ?? "unknown")", symbolName: "shippingbox"))
        if let currentProfileDefinition {
            submenu.addItem(disabledItem(title: "Runtime: \(serverDisplayText(for: currentProfileDefinition))", symbolName: "network"))
        }
        if let currentGitProjectInfo {
            let branchText = currentGitProjectInfo.currentBranch ?? "detached"
            submenu.addItem(disabledItem(title: "Git: \(URL(fileURLWithPath: currentGitProjectInfo.repositoryRoot).lastPathComponent) @ \(branchText)", symbolName: "arrow.triangle.branch"))
        }
        submenu.addItem(disabledItem(title: "Tunnel: \(snapshot?.tunnelLoaded == true ? "loaded" : "stopped")", symbolName: "point.topleft.down.curvedto.point.bottomright.up"))
        if let currentMetricsSnapshot {
            submenu.addItem(disabledItem(title: "Metrics: \(currentMetricsSnapshot.summaryLine)", symbolName: "gauge"))
        }

        if let snapshot, snapshot.compose.configured {
            submenu.addItem(
                disabledItem(
                    title: "Compose: \(snapshot.compose.projectName) (\(snapshot.compose.runningServices.count) running)",
                    symbolName: "square.stack.3d.up"
                )
            )
            submenu.addItem(disabledItem(title: "Local Containers: \(snapshot.compose.localContainerMode.title)", symbolName: "switch.2"))
        }

        if let errorMessage {
            submenu.addItem(.separator())
            submenu.addItem(disabledItem(title: "Error: \(errorMessage)", symbolName: "exclamationmark.triangle"))
        } else if let message = lastMessage {
            submenu.addItem(.separator())
            submenu.addItem(disabledItem(title: message, symbolName: isRefreshing ? "hourglass" : "checkmark.circle"))
        }

        if let snapshot, !snapshot.compose.runningServices.isEmpty {
            submenu.addItem(.separator())
            submenu.addItem(disabledItem(title: "Compose Services", symbolName: "square.stack.3d.up"))
            for service in snapshot.compose.runningServices {
                submenu.addItem(disabledItem(title: "\(service.displayName)  \(service.displayStatus)", symbolName: "circle.fill"))
            }
        }

        if let snapshot, !snapshot.services.isEmpty {
            submenu.addItem(.separator())
            submenu.addItem(disabledItem(title: "Forwarded Services", symbolName: "point.topleft.down.curvedto.point.bottomright.up"))
            for service in snapshot.services {
                let line = "\(service.name)  \(service.aliasHost):\(service.localPort)  via \(service.tunnelHost)"
                submenu.addItem(disabledItem(title: line, symbolName: "arrow.left.arrow.right"))
            }
        }

        item.submenu = submenu
        return item
    }

    private func makeProfileMenu(currentProfileDefinition: ProfileDefinition?, isEnabled: Bool) -> NSMenuItem {
        let item = submenuItem(title: profileMenuTitle(), symbolName: "person.crop.rectangle")
        let submenu = NSMenu()

        if !isEnabled {
            populateProfileSelectionItems(into: submenu, includeFolders: true)
            item.submenu = submenu
            item.isEnabled = true
            return item
        }

        if let currentProfileDefinition {
            submenu.addItem(disabledItem(title: "Runtime: \(serverDisplayText(for: currentProfileDefinition))", symbolName: "network"))
            submenu.addItem(.separator())
        }

        submenu.addItem(actionItem(title: "Activate Profile", action: #selector(tunnelUpAction(_:)), isEnabled: isEnabled, symbolName: "play.circle"))
        submenu.addItem(actionItem(title: "Stop Tunnels", action: #selector(tunnelDownAction(_:)), isEnabled: isEnabled, symbolName: "stop.circle"))
        submenu.addItem(actionItem(title: "Restart Tunnels", action: #selector(tunnelRestartAction(_:)), isEnabled: isEnabled, symbolName: "arrow.clockwise.circle"))

        if snapshot?.compose.configured == true {
            submenu.addItem(.separator())
            submenu.addItem(actionItem(title: "Preview Compose Changes…", action: #selector(openComposePreviewAction(_:)), isEnabled: isEnabled, symbolName: "doc.text.magnifyingglass"))
            submenu.addItem(actionItem(title: "Compose Up", action: #selector(composeUpAction(_:)), isEnabled: isEnabled, symbolName: "play.square"))
            submenu.addItem(actionItem(title: "Compose Down", action: #selector(composeDownAction(_:)), isEnabled: isEnabled, symbolName: "stop.square"))
            submenu.addItem(actionItem(title: "Compose Restart", action: #selector(composeRestartAction(_:)), isEnabled: isEnabled, symbolName: "arrow.clockwise.square"))
            submenu.addItem(actionItem(title: "Open Compose Logs", action: #selector(openComposeLogsAction(_:)), isEnabled: isEnabled, symbolName: "doc.text"))
            submenu.addItem(actionItem(title: "Open Volume Report", action: #selector(openVolumeReportAction(_:)), isEnabled: isEnabled, symbolName: "shippingbox"))
            submenu.addItem(actionItem(title: "Open Metrics Report", action: #selector(openMetricsReportAction(_:)), isEnabled: isEnabled, symbolName: "chart.bar"))
            submenu.addItem(actionItem(title: "Open Remote Files", action: #selector(openRemoteFilesAction(_:)), isEnabled: isEnabled, symbolName: "externaldrive"))
            submenu.addItem(actionItem(title: "Remove Current Volumes…", action: #selector(removeCurrentVolumesAction(_:)), isEnabled: isEnabled, symbolName: "trash"))
        }

        submenu.addItem(.separator())
        submenu.addItem(actionItem(title: "Copy Shell Exports", action: #selector(copyShellExportsAction(_:)), isEnabled: isEnabled, symbolName: "document.on.document"))
        submenu.addItem(actionItem(title: "Manage Secrets…", action: #selector(manageSecretsAction(_:)), isEnabled: isEnabled, symbolName: "key"))
        submenu.addItem(actionItem(title: "Open Project Env Files", action: #selector(openProjectEnvFilesAction(_:)), isEnabled: isEnabled, symbolName: "doc.plaintext"))
        submenu.addItem(actionItem(title: "Open Compose Project Folder", action: #selector(openCurrentProjectFolderAction(_:)), isEnabled: isEnabled, symbolName: "folder"))
        submenu.addItem(actionItem(title: "Open Profile Data Folder", action: #selector(openCurrentProfileDataFolderAction(_:)), isEnabled: isEnabled, symbolName: "folder"))

        submenu.addItem(.separator())
        submenu.addItem(actionItem(title: "Edit Current Profile…", action: #selector(editCurrentProfileAction(_:)), isEnabled: isEnabled, symbolName: "pencil"))
        submenu.addItem(actionItem(title: "Add Service To Current Profile…", action: #selector(addServiceToCurrentProfileAction(_:)), isEnabled: isEnabled, symbolName: "plus"))
        submenu.addItem(actionItem(title: "Edit Current Runtime…", action: #selector(editCurrentRuntimeAction(_:)), isEnabled: isEnabled, symbolName: "server.rack"))

        submenu.addItem(.separator())
        submenu.addItem(makeProfileSwitcherMenu())
        submenu.addItem(.separator())
        submenu.addItem(actionItem(title: "Delete Current Profile…", action: #selector(deleteCurrentProfileAction(_:)), isEnabled: isEnabled, symbolName: "trash"))

        item.submenu = submenu
        item.isEnabled = true
        return item
    }

    private func makeProfileSwitcherMenu() -> NSMenuItem {
        let item = submenuItem(title: "Switch Profile", symbolName: "arrow.left.arrow.right")
        let submenu = NSMenu()
        populateProfileSelectionItems(into: submenu, includeFolders: true)

        item.submenu = submenu
        return item
    }

    private func populateProfileSelectionItems(into menu: NSMenu, includeFolders: Bool) {
        let currentProfile = selectedProfileName()

        if profiles.isEmpty {
            menu.addItem(disabledItem(title: "No profiles"))
        } else {
            for profile in profiles {
                let menuItem = actionItem(title: profile, action: #selector(switchProfileAction(_:)))
                menuItem.representedObject = profile
                if profile == currentProfile {
                    menuItem.state = .on
                } else if activeProfiles.contains(profile) {
                    menuItem.state = .mixed
                } else {
                    menuItem.state = .off
                }
                menu.addItem(menuItem)
            }
        }

        menu.addItem(.separator())
        menu.addItem(actionItem(title: "New Profile…", action: #selector(newProfileAction(_:)), symbolName: "plus.circle"))
        menu.addItem(actionItem(title: "Import Compose File…", action: #selector(importComposeFileAction(_:)), symbolName: "square.and.arrow.down"))
        if includeFolders {
            menu.addItem(actionItem(title: "Open Profiles Folder", action: #selector(openProfilesFolderAction(_:)), symbolName: "folder"))
        }
    }

    private func makeDockerContextsMenu(title: String = "Available Docker Contexts") -> NSMenuItem {
        let item = submenuItem(title: title, symbolName: "shippingbox")
        let submenu = NSMenu()

        if dockerContexts.isEmpty {
            submenu.addItem(disabledItem(title: "No docker contexts"))
        } else {
            for context in dockerContexts {
                let menuItem = actionItem(
                    title: "\(context.name)  \(context.endpoint)",
                    action: #selector(switchDockerContextAction(_:))
                )
                menuItem.representedObject = context.name
                menuItem.state = context.isCurrent ? .on : .off
                submenu.addItem(menuItem)
            }
        }

        item.submenu = submenu
        return item
    }

    private func makeAILimitsMenu() -> NSMenuItem {
        let item = submenuItem(title: "AI CLI Limits", symbolName: "gauge.with.dots.needle.50percent")
        let submenu = NSMenu()

        if aiToolSnapshots.isEmpty {
            submenu.addItem(disabledItem(title: "No tool data yet"))
        } else {
            for snapshot in aiToolSnapshots {
                let toolItem = submenuItem(title: snapshot.kind.title, symbolName: snapshot.statusSymbolName)
                let toolMenu = NSMenu()
                if !snapshot.progressMetrics.isEmpty || !snapshot.highlightLines.isEmpty {
                    toolMenu.addItem(aiQuotaSummaryItem(for: snapshot))
                    toolMenu.addItem(.separator())
                }
                toolMenu.addItem(disabledItem(title: "CLI: \(snapshot.cliStatus)", symbolName: "terminal"))
                toolMenu.addItem(disabledItem(title: "Auth: \(snapshot.authStatus)", symbolName: "lock"))
                toolMenu.addItem(disabledItem(title: "Quota: \(snapshot.quotaStatus)", symbolName: "chart.bar"))

                if !snapshot.detailLines.isEmpty {
                    toolMenu.addItem(.separator())
                    for line in snapshot.detailLines {
                        toolMenu.addItem(disabledItem(title: line, symbolName: "info.circle"))
                    }
                }

                toolMenu.addItem(.separator())
                let helpItem = actionItem(title: "Setup / Auth Help…", action: #selector(aiToolHelpAction(_:)), symbolName: "questionmark.circle")
                helpItem.representedObject = snapshot.kind.rawValue
                toolMenu.addItem(helpItem)
                toolItem.submenu = toolMenu
                submenu.addItem(toolItem)
            }
        }

        item.submenu = submenu
        return item
    }

    private func aiQuotaSummaryItem(for snapshot: AIToolQuotaSnapshot) -> NSMenuItem {
        let item = NSMenuItem()
        let view = makeAIQuotaSummaryView(for: snapshot)
        item.isEnabled = true
        item.view = view
        return item
    }

    private func makeAIQuotaSummaryView(for snapshot: AIToolQuotaSnapshot) -> NSView {
        let preferredWidth: CGFloat = 310
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: snapshot.kind.title)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(title)

        let quota = NSTextField(labelWithString: snapshot.quotaStatus)
        quota.textColor = .secondaryLabelColor
        quota.font = .systemFont(ofSize: 11)
        quota.lineBreakMode = .byTruncatingTail
        stack.addArrangedSubview(quota)

        for highlight in snapshot.highlightLines.prefix(3) {
            let label = NSTextField(labelWithString: highlight)
            label.textColor = .secondaryLabelColor
            label.font = .systemFont(ofSize: 11)
            label.lineBreakMode = .byTruncatingTail
            stack.addArrangedSubview(label)
        }

        for metric in snapshot.progressMetrics {
            stack.addArrangedSubview(aiQuotaMetricRow(metric))
        }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: preferredWidth, height: 1))
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: preferredWidth),
        ])

        container.layoutSubtreeIfNeeded()
        let fittingHeight = max(44, stack.fittingSize.height)
        container.frame = NSRect(x: 0, y: 0, width: preferredWidth, height: fittingHeight)

        return container
    }

    private func aiQuotaMetricRow(_ metric: AIToolProgressMetric) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: metric.summary)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        header.addArrangedSubview(label)

        let remainingPercent = max(0, min(100, Int(((1 - metric.usedPercent) * 100).rounded())))
        let remainingLabel = NSTextField(labelWithString: "\(remainingPercent)% left")
        remainingLabel.textColor = .systemGreen
        remainingLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        remainingLabel.alignment = .right
        remainingLabel.setContentHuggingPriority(.required, for: .horizontal)
        remainingLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        header.addArrangedSubview(remainingLabel)
        stack.addArrangedSubview(header)

        let remainingBar = AIQuotaRemainingBarView(remainingFraction: 1 - metric.usedPercent)
        remainingBar.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(remainingBar)

        if let forecast = metric.forecastExhaustionAt, let resetAt = metric.resetAt, forecast < resetAt {
            let forecastLabel = NSTextField(labelWithString: "Forecast: ends around \(formattedForecast(forecast))")
            forecastLabel.textColor = .systemOrange
            forecastLabel.font = .systemFont(ofSize: 10)
            forecastLabel.lineBreakMode = .byTruncatingTail
            stack.addArrangedSubview(forecastLabel)
        }

        NSLayoutConstraint.activate([
            remainingBar.widthAnchor.constraint(equalToConstant: 280),
        ])

        return stack
    }

    private func formattedForecast(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func makeRuntimesMenu() -> NSMenuItem {
        let item = submenuItem(title: "Runtimes", symbolName: "server.rack")
        let submenu = NSMenu()
        let currentServerName = selectedProfileName()
            .flatMap { try? store.loadProfile(named: $0).runtimeName }

        submenu.addItem(disabledItem(title: "Current Docker Context: \(snapshot?.activeDockerContext ?? "unknown")", symbolName: "shippingbox"))

        submenu.addItem(.separator())

        if runtimeTargets.isEmpty {
            submenu.addItem(disabledItem(title: "No saved runtimes"))
        } else {
            for server in runtimeTargets {
                let menuItem = actionItem(
                    title: "\(server.name)  \(server.connectionSummary)",
                    action: #selector(editRuntimeAction(_:)),
                    symbolName: server.isLocal ? "desktopcomputer" : "network"
                )
                menuItem.representedObject = server.name
                menuItem.state = server.name == currentServerName ? .on : .off
                submenu.addItem(menuItem)
            }
        }

        submenu.addItem(.separator())
        submenu.addItem(makeDockerContextsMenu())
        submenu.addItem(.separator())
        submenu.addItem(actionItem(title: "New Runtime…", action: #selector(newRuntimeAction(_:)), symbolName: "plus.circle"))
        submenu.addItem(actionItem(title: "Open Runtimes Folder", action: #selector(openRuntimesFolderAction(_:)), symbolName: "folder"))

        item.submenu = submenu
        return item
    }

    private func makeVariablesMenu() -> NSMenuItem {
        let item = submenuItem(title: "Variables", symbolName: "slider.horizontal.below.square.and.square.filled")
        let submenu = NSMenu()
        let allVariables = (try? store.managedVariables()) ?? []

        submenu.addItem(disabledItem(title: "Managed vars: \(allVariables.count)", symbolName: "text.badge.plus"))
        if let currentProfileName = selectedProfileName() {
            let assignedCount = allVariables.filter { $0.applies(to: currentProfileName) }.count
            submenu.addItem(disabledItem(title: "Assigned to \(currentProfileName): \(assignedCount)", symbolName: "person.crop.rectangle"))
        }
        submenu.addItem(.separator())
        submenu.addItem(actionItem(title: "Manage Variables…", action: #selector(manageVariablesAction(_:)), symbolName: "slider.horizontal.3"))

        item.submenu = submenu
        return item
    }

    private func openProfileEditor(profile: ProfileDefinition?, beginWithAddService: Bool) {
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

    private func beginComposeImport(from url: URL) {
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

    private func openImportedComposeInEditor(_ request: ComposeImportRequest) {
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

    private func persistProfile(_ profile: ProfileDefinition, originalName: String?) throws {
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

    private func loadCurrentProfile() -> ProfileDefinition? {
        guard let name = selectedProfileName() else {
            return nil
        }
        do {
            return try store.loadProfile(named: name)
        } catch {
            showError(error.localizedDescription)
            return nil
        }
    }

    private func loadCurrentServer() -> RemoteServerDefinition? {
        guard let profile = loadCurrentProfile(), !profile.runtimeName.isEmpty else {
            return nil
        }
        return try? store.loadRuntime(named: profile.runtimeName)
    }

    private func serverDisplayText(for profile: ProfileDefinition) -> String {
        if !profile.runtimeName.isEmpty, let server = try? store.loadRuntime(named: profile.runtimeName) {
            return "\(server.name)  \(server.remoteDockerServerDisplay)"
        }
        return profile.remoteDockerServer
    }

    private func selectedProfileName() -> String? {
        Self.resolveCurrentProfileName(
            storedProfileName: snapshot?.profile ?? store.currentProfileName(),
            profiles: profiles
        )
    }

    private func shouldResetComposeRuntime(previous: ProfileDefinition, next: ProfileDefinition) -> Bool {
        guard previous.compose.configured else {
            return false
        }
        if !next.compose.configured {
            return true
        }
        return previous.name != next.name
            || previous.runtimeName != next.runtimeName
            || previous.dockerContext != next.dockerContext
            || previous.compose.projectName != next.compose.projectName
            || previous.compose.workingDirectory != next.compose.workingDirectory
            || previous.compose.sourceFile != next.compose.sourceFile
            || previous.compose.additionalSourceFiles != next.compose.additionalSourceFiles
    }

    private func handleLaunchArguments() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--import-compose"), index + 1 < arguments.count else {
            return
        }
        let path = arguments[index + 1]
        beginComposeImport(from: URL(fileURLWithPath: path))
    }

    private func actionItem(title: String, action: Selector, isEnabled: Bool = true, symbolName: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = isEnabled
        configureSymbol(symbolName, for: item)
        return item
    }

    private func disabledItem(title: String, symbolName: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        configureSymbol(symbolName, for: item)
        return item
    }

    private func submenuItem(title: String, symbolName: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        configureSymbol(symbolName, for: item)
        return item
    }

    private func configureSymbol(_ symbolName: String?, for item: NSMenuItem) {
        guard let symbolName, let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            return
        }
        image.isTemplate = true
        image.size = NSSize(width: 14, height: 14)
        item.image = image
    }

    private func runRuntimeAction(
        successMessage: String,
        operation: @escaping @Sendable () throws -> Void
    ) {
        isRefreshing = true
        lastMessage = "Working…"
        rebuildMenu()
        updateStatusButton()

        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<Void, Error> in
                do {
                    try operation()
                    return .success(())
                } catch {
                    return .failure(error)
                }
            }.value

            self.isRefreshing = false

            switch result {
            case .success:
                self.lastMessage = successMessage
            case let .failure(error):
                self.lastMessage = error.localizedDescription
                NSSound.beep()
            }

            self.refreshSnapshot(force: true)
        }
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else {
            return
        }

        let hasSelectedProfile = selectedProfileName() != nil
        let isHealthy = errorMessage == nil && (
            !hasSelectedProfile
                || snapshot == nil
                || snapshot?.tunnelLoaded == true
                || snapshot?.services.isEmpty == true
        )
        let title = isRefreshing ? "DX…" : (isHealthy ? "DX" : "DX!")
        button.title = title

        var tooltip = "DevStack"
        tooltip += "\nProfile: \(currentProfileDisplayName())"
        tooltip += "\nActive profiles: \(activeProfiles.count)"
        tooltip += "\nDocker: \(snapshot?.activeDockerContext ?? "unknown")"
        tooltip += "\nTunnel: \(snapshot?.tunnelLoaded == true ? "loaded" : "stopped")"

        if let snapshot, snapshot.compose.configured {
            tooltip += "\nCompose: \(snapshot.compose.projectName) (\(snapshot.compose.runningServices.count) running)"
        }

        if let currentGitProjectInfo {
            tooltip += "\nGit: \(URL(fileURLWithPath: currentGitProjectInfo.repositoryRoot).lastPathComponent)"
            if let branch = currentGitProjectInfo.currentBranch {
                tooltip += " @ \(branch)"
            }
        }

        if let currentMetricsSnapshot {
            tooltip += "\n\(currentMetricsSnapshot.summaryLine)"
        }

        if let message = lastMessage {
            tooltip += "\n\(message)"
        }

        if let errorMessage {
            tooltip += "\nError: \(errorMessage)"
        }

        button.toolTip = tooltip
    }

    private func showError(_ message: String) {
        lastMessage = message
        rebuildMenu()
        updateStatusButton()
        NSSound.beep()
    }

    private func currentProfileDisplayName() -> String {
        selectedProfileName() ?? "none"
    }

    private func profileMenuTitle() -> String {
        selectedProfileName() ?? "Select Profile"
    }

    private func configureProjectWatchers() {
        var watchPaths: [URL] = [
            store.rootDirectory,
            store.profilesDirectory,
            store.runtimesDirectory,
        ]

        for profileName in profiles {
            guard let profile = try? store.loadProfile(named: profileName) else {
                continue
            }
            if let projectDirectory = store.managedProjectDirectory(for: profile) {
                watchPaths.append(projectDirectory)
                watchPaths.append(projectDirectory.appendingPathComponent(".devstackmenu", isDirectory: true))
            }
            for sourceURL in store.sourceComposeURLs(for: profile) {
                watchPaths.append(sourceURL.deletingLastPathComponent())
            }
        }

        watchPaths.append(contentsOf: IDEProjectDetector.watchRoots())
        projectWatchCoordinator.reconfigure(paths: watchPaths) { [weak self] in
            DispatchQueue.main.async {
                self?.scheduleWatchedRefresh()
            }
        }
    }

    private func scheduleWatchedRefresh() {
        pendingWatchRefresh?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.refreshSnapshot(force: true)
        }
        pendingWatchRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
    }

    private func maybePromptForOpenIDEProjects() {
        guard !ideActivationPromptShown, selectedProfileName() == nil else {
            return
        }

        let ideProjects = IDEProjectDetector.activeProjects()
        guard !ideProjects.isEmpty else {
            return
        }

        let loadedProfiles = profiles.compactMap { try? store.loadProfile(named: $0) }
        for context in ideProjects {
            let normalizedProjectPath = URL(fileURLWithPath: context.projectPath).standardizedFileURL.path
            let matchedProfile = loadedProfiles.first { profile in
                guard let projectDirectory = store.managedProjectDirectory(for: profile) else {
                    return false
                }
                let profilePath = projectDirectory.standardizedFileURL.path
                if profilePath == normalizedProjectPath {
                    return true
                }
                let ideGit = GitProjectInspector.inspectProject(at: URL(fileURLWithPath: normalizedProjectPath))
                let profileGit = GitProjectInspector.inspectProject(at: projectDirectory)
                return ideGit?.repositoryRoot == profileGit?.repositoryRoot && ideGit?.repositoryRoot != nil
            }

            guard let matchedProfile else {
                continue
            }

            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Activate profile '\(matchedProfile.name)'?"
            alert.informativeText = "\(context.ideName) currently has project '\(URL(fileURLWithPath: context.projectPath).lastPathComponent)' open."
            alert.addButton(withTitle: "Activate")
            alert.addButton(withTitle: "Not Now")
            ideActivationPromptShown = true

            if alert.runModal() == .alertFirstButtonReturn {
                runRuntimeAction(successMessage: "Profile switched to \(matchedProfile.name)") {
                    try RuntimeController.activateProfile(named: matchedProfile.name, store: self.store)
                }
            }
            return
        }
    }

    private func confirmComposeUpPreview(profileName: String) -> Bool {
        guard let preview = try? RuntimeController.composePreview(profileName: profileName, store: store) else {
            return true
        }

        let reportURL = store.generatedComposePlanURL(for: profileName)
        try? ComposeSupport.writePlanReport(plan: preview.plan, to: reportURL)

        let serviceCount = preview.plan.services.count
        let bindCount = preview.plan.relativeProjectPaths.count
        let composeFileCount = preview.plan.sourceComposeURLs.count
        let ports = preview.plan.services.flatMap(\.ports).map(\.publishedPort).sorted()
        var bodyLines = [
            "Services: \(serviceCount)",
            "Compose files: \(composeFileCount)",
            "Project bind mounts: \(bindCount)",
        ]
        if !ports.isEmpty {
            bodyLines.append("Published ports: \(ports.map(String.init).joined(separator: ", "))")
        }
        if !preview.runningServiceNames.isEmpty {
            bodyLines.append("Currently running: \(preview.runningServiceNames.joined(separator: ", "))")
        }
        if !preview.diagnostics.errors.isEmpty {
            bodyLines.append("")
            bodyLines.append("Errors:")
            bodyLines.append(contentsOf: preview.diagnostics.errors.map { "- \($0)" })
        }
        if !preview.diagnostics.warnings.isEmpty {
            bodyLines.append("")
            bodyLines.append("Warnings:")
            bodyLines.append(contentsOf: preview.diagnostics.warnings.map { "- \($0)" })
        }

        let alert = NSAlert()
        alert.alertStyle = preview.diagnostics.errors.isEmpty ? .informational : .warning
        alert.messageText = "Compose preview for '\(profileName)'"
        alert.informativeText = bodyLines.joined(separator: "\n")
        alert.addButton(withTitle: preview.diagnostics.errors.isEmpty ? "Continue" : "Cancel")
        alert.addButton(withTitle: "Open Report")
        if preview.diagnostics.errors.isEmpty {
            alert.addButton(withTitle: "Cancel")
        }

        while true {
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                return preview.diagnostics.errors.isEmpty
            }
            if response == .alertSecondButtonReturn {
                NSWorkspace.shared.open(reportURL)
                continue
            }
            return false
        }
    }

    nonisolated private static func resolveCurrentProfileName(
        storedProfileName: String?,
        profiles: [String]
    ) -> String? {
        guard let storedProfileName else {
            return nil
        }
        return profiles.contains(storedProfileName) ? storedProfileName : nil
    }

    nonisolated private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private final class AIQuotaRemainingBarView: NSView {
    private let remainingFraction: CGFloat

    init(remainingFraction: Double) {
        self.remainingFraction = max(0, min(1, CGFloat(remainingFraction)))
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 12))
        wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 280, height: 12)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let barRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let trackRadius = min(barRect.height / 2, barRect.width / 2)
        let trackPath = NSBezierPath(
            roundedRect: barRect,
            xRadius: trackRadius,
            yRadius: trackRadius
        )
        NSColor.quaternaryLabelColor.withAlphaComponent(0.35).setFill()
        trackPath.fill()

        let fillWidth = barRect.width * remainingFraction
        guard fillWidth > 0.5 else {
            return
        }

        let fillRect = NSRect(x: barRect.minX, y: barRect.minY, width: fillWidth, height: barRect.height)
        let fillRadius = min(fillRect.height / 2, fillRect.width / 2)
        let fillPath = NSBezierPath(
            roundedRect: fillRect,
            xRadius: fillRadius,
            yRadius: fillRadius
        )
        NSColor.systemGreen.setFill()
        fillPath.fill()
    }
}

public enum DevStackMenuApplication {
    @MainActor
    public static func run() {
        guard SingleInstanceCoordinator.acquire() else {
            SingleInstanceCoordinator.activateExistingInstance()
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
