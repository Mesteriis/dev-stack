import AppKit
import Foundation

struct AppRefreshState {
    let snapshot: AppSnapshot?
    let profiles: [String]
    let runtimeTargets: [RemoteServerDefinition]
    let dockerContexts: [DockerContextEntry]
    let activeProfiles: [String]
    let gitProjectInfo: GitProjectInfo?
    let metricsSnapshot: CompactMetricsSnapshot?
    let errorMessage: String?
    let cleanupMessage: String?
}

enum AppRefreshCoordinator {
    static func collectState(store: ProfileStore) -> AppRefreshState {
        var snapshot: AppSnapshot?
        var profiles: [String] = []
        var activeProfiles: [String] = []
        var runtimeTargets: [RemoteServerDefinition] = []
        var dockerContexts: [DockerContextEntry] = []
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

        let selectedProfileName = AppDelegate.resolveCurrentProfileName(
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

        return AppRefreshState(
            snapshot: snapshot,
            profiles: profiles,
            runtimeTargets: runtimeTargets,
            dockerContexts: dockerContexts,
            activeProfiles: activeProfiles,
            gitProjectInfo: gitProjectInfo,
            metricsSnapshot: metricsSnapshot,
            errorMessage: errorMessage,
            cleanupMessage: cleanupMessage
        )
    }
}

extension AppDelegate {
    func refreshSnapshot(force: Bool = false) {
        if isRefreshing && !force {
            return
        }

        isRefreshing = true
        updateStatusButton()
        rebuildMenu()

        let store = store

        Task {
            let snapshotState = await Task.detached(priority: .utility) {
                AppRefreshCoordinator.collectState(store: store)
            }.value

            self.snapshot = snapshotState.snapshot
            self.profiles = snapshotState.profiles
            self.activeProfiles = snapshotState.activeProfiles
            self.runtimeTargets = snapshotState.runtimeTargets
            self.dockerContexts = snapshotState.dockerContexts
            self.currentGitProjectInfo = snapshotState.gitProjectInfo
            self.currentMetricsSnapshot = snapshotState.metricsSnapshot
            self.errorMessage = snapshotState.errorMessage
            if let cleanupMessage = snapshotState.cleanupMessage {
                self.lastMessage = cleanupMessage
            }
            self.isRefreshing = false
            self.configureProjectWatchers()
            self.maybePromptForOpenIDEProjects()
            self.rebuildMenu()
            self.updateStatusButton()
        }
    }

    func configureProjectWatchers() {
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

    func scheduleWatchedRefresh() {
        pendingWatchRefresh?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.refreshSnapshot(force: true)
        }
        pendingWatchRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
    }

    func maybePromptForOpenIDEProjects() {
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
}
