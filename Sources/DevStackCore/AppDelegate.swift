import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let store = ProfileStore()
    let projectWatchCoordinator = ProjectWatchCoordinator()

    var refreshTimer: Timer?
    var snapshot: AppSnapshot?
    var profiles: [String] = []
    var activeProfiles: [String] = []
    var runtimeTargets: [RemoteServerDefinition] = []
    var dockerContexts: [DockerContextEntry] = []
    var errorMessage: String?
    var isRefreshing = false
    var lastMessage: String?
    var editors: [NSWindowController] = []
    var aiToolSnapshots: [AIToolQuotaSnapshot] = []
    var currentGitProjectInfo: GitProjectInfo?
    var currentMetricsSnapshot: CompactMetricsSnapshot?
    var ideActivationPromptShown = false
    var pendingWatchRefresh: DispatchWorkItem?

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

    func rebuildMenu() {
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

    func loadCurrentProfile() -> ProfileDefinition? {
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

    func loadCurrentServer() -> RemoteServerDefinition? {
        guard let profile = loadCurrentProfile(), !profile.runtimeName.isEmpty else {
            return nil
        }
        return try? store.loadRuntime(named: profile.runtimeName)
    }

    func serverDisplayText(for profile: ProfileDefinition) -> String {
        if !profile.runtimeName.isEmpty, let server = try? store.loadRuntime(named: profile.runtimeName) {
            return "\(server.name)  \(server.remoteDockerServerDisplay)"
        }
        return profile.remoteDockerServer
    }

    func selectedProfileName() -> String? {
        Self.resolveCurrentProfileName(
            storedProfileName: snapshot?.profile ?? store.currentProfileName(),
            profiles: profiles
        )
    }

    func shouldResetComposeRuntime(previous: ProfileDefinition, next: ProfileDefinition) -> Bool {
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

    func handleLaunchArguments() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--import-compose"), index + 1 < arguments.count else {
            return
        }
        let path = arguments[index + 1]
        beginComposeImport(from: URL(fileURLWithPath: path))
    }

    func actionItem(title: String, action: Selector, isEnabled: Bool = true, symbolName: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = isEnabled
        configureSymbol(symbolName, for: item)
        return item
    }

    func disabledItem(title: String, symbolName: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        configureSymbol(symbolName, for: item)
        return item
    }

    func submenuItem(title: String, symbolName: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        configureSymbol(symbolName, for: item)
        return item
    }

    func configureSymbol(_ symbolName: String?, for item: NSMenuItem) {
        guard let symbolName, let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            return
        }
        image.isTemplate = true
        image.size = NSSize(width: 14, height: 14)
        item.image = image
    }

    func runRuntimeAction(
        successMessage: String,
        operation: @escaping @Sendable () throws -> Void
    ) {
        isRefreshing = true
        lastMessage = "Working..."
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

    func updateStatusButton() {
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
        let title = isRefreshing ? "DX..." : (isHealthy ? "DX" : "DX!")
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

    func showError(_ message: String) {
        lastMessage = message
        rebuildMenu()
        updateStatusButton()
        NSSound.beep()
    }

    func currentProfileDisplayName() -> String {
        selectedProfileName() ?? "none"
    }

    func profileMenuTitle() -> String {
        selectedProfileName() ?? "Select Profile"
    }

    nonisolated static func resolveCurrentProfileName(
        storedProfileName: String?,
        profiles: [String]
    ) -> String? {
        guard let storedProfileName else {
            return nil
        }
        return profiles.contains(storedProfileName) ? storedProfileName : nil
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
