import Foundation

enum RuntimeStatusService {
    static func dockerContexts() throws -> [DockerContextEntry] {
        try RuntimeSharedSupport.dockerContexts()
    }

    static func currentDockerContext() throws -> String {
        try RuntimeSharedSupport.currentDockerContext()
    }

    static func remoteServers(store: ProfileStore) throws -> [RemoteServerDefinition] {
        try store.remoteServers().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func cleanupProfilesWithMissingComposeSources(store: ProfileStore) throws -> [String] {
        let fileManager = FileManager.default
        var removedProfiles: [String] = []

        for profileName in try store.profileNames() {
            let profile = try store.loadProfile(named: profileName)
            let sourceComposeURLs = store.sourceComposeURLs(for: profile)
            guard !sourceComposeURLs.isEmpty else {
                continue
            }
            guard sourceComposeURLs.contains(where: { !fileManager.fileExists(atPath: $0.path) }) else {
                continue
            }

            try RuntimeDeletionService.deleteProfile(named: profile.name, store: store, removeData: true)
            removedProfiles.append(profile.name)
        }

        return removedProfiles
    }

    static func statusSnapshot(store: ProfileStore, profileName: String) throws -> AppSnapshot {
        let profile = try store.loadProfile(named: profileName)
        let resolvedServer = try RuntimeSharedSupport.resolvePrimaryServer(for: profile, store: store)
        let activeDockerContext = (try? currentDockerContext()) ?? "unknown"
        let composeServices = try RuntimeSharedSupport.composePS(profile: profile, store: store)

        let serviceSnapshots = profile.services.map { service in
            ServiceRuntimeSnapshot(
                name: service.name,
                role: service.role,
                aliasHost: service.aliasHost,
                localPort: service.localPort,
                remoteHost: service.remoteHost,
                remotePort: service.remotePort,
                tunnelHost: TunnelService.tunnelDisplayName(for: service, profile: profile, store: store, fallback: resolvedServer.remoteDockerServer),
                envPrefix: service.envPrefix,
                enabled: service.enabled,
                listening: service.enabled ? RuntimeDiagnosticsService.portListening(service.localPort) : false
            )
        }

        return AppSnapshot(
            profile: profile.name,
            configuredDockerContext: resolvedServer.dockerContext,
            activeDockerContext: activeDockerContext,
            tunnelLoaded: TunnelService.agentLoaded(profileName: profile.name, store: store),
            tunnelLabel: store.launchAgentPrefix(for: profile.name),
            compose: ComposeRuntimeSnapshot(
                configured: profile.compose.configured,
                projectName: profile.compose.configured ? ComposePlanBuilder.composeProjectName(for: profile) : "",
                workingDirectory: profile.compose.workingDirectory,
                autoDownOnSwitch: profile.compose.autoDownOnSwitch,
                autoUpOnActivate: profile.compose.autoUpOnActivate,
                runningServices: composeServices
            ),
            services: serviceSnapshots
        )
    }

    static func activeProfileNames(store: ProfileStore) -> [String] {
        store.activeProfileNames()
    }
}
