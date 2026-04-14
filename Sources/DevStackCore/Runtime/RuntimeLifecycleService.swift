import Foundation

enum RuntimeLifecycleService {
    static func prepareServer(
        server: RemoteServerDefinition,
        store: ProfileStore,
        bootstrapIfNeeded: Bool
    ) throws -> RemoteServerPreparationResult {
        try RuntimeServerPreparationService.prepareServer(
            server: server,
            store: store,
            bootstrapIfNeeded: bootstrapIfNeeded
        )
    }

    static func activateProfile(named profileName: String, store: ProfileStore) throws {
        let profile = try store.loadProfile(named: profileName)
        let diagnostics = try RuntimeDiagnosticsService.runtimeDiagnostics(profile: profile, store: store)
        if !diagnostics.errors.isEmpty {
            throw ValidationError(diagnostics.errors.joined(separator: "\n"))
        }

        try RuntimeProfileHooksService.runProfileHooks("before-activate", profile: profile, store: store)
        try RuntimeComposeFlowService.switchAwayFromPreviousProfile(nextProfile: profile, store: store)
        try RuntimeComposeFlowService.ensureDockerContext(profile: profile, store: store)

        if profile.compose.autoUpOnActivate && profile.compose.configured {
            try RuntimeComposeFlowService.composeUp(profile: profile, store: store)
        }

        if profile.services.contains(where: \.enabled) {
            try TunnelService.bootstrapAgents(profile: profile, store: store)
        } else {
            try TunnelService.bootoutAgents(profileName: profile.name, store: store)
        }

        try store.saveCurrentProfile(profile.name)
        try store.markProfileActive(profile.name)
        try RuntimeProfileHooksService.runProfileHooks("after-activate", profile: profile, store: store)
    }

    static func stopProfile(named profileName: String, store: ProfileStore) throws {
        try TunnelService.bootoutAgents(profileName: profileName, store: store)
        if let profile = try? store.loadProfile(named: profileName),
           !(try RuntimeProfileHooksService.isProfileRuntimeActive(profile: profile, store: store))
        {
            try? store.markProfileInactive(profile.name)
        }
    }

    static func restartProfile(named profileName: String, store: ProfileStore) throws {
        let profile = try store.loadProfile(named: profileName)
        try RuntimeComposeFlowService.ensureDockerContext(profile: profile, store: store)
        try TunnelService.bootoutAgents(profileName: profile.name, store: store)

        if profile.services.contains(where: \.enabled) {
            try TunnelService.bootstrapAgents(profile: profile, store: store)
        }

        try store.markProfileActive(profile.name)
    }

    static func composeUp(profileName: String, store: ProfileStore) throws {
        let profile = try store.loadProfile(named: profileName)
        try RuntimeComposeFlowService.ensureDockerContext(profile: profile, store: store)
        try RuntimeComposeFlowService.composeUp(profile: profile, store: store)
    }

    static func composeDown(profileName: String, store: ProfileStore) throws {
        let profile = try store.loadProfile(named: profileName)
        try RuntimeComposeFlowService.ensureDockerContext(profile: profile, store: store)
        try RuntimeComposeFlowService.composeDown(profile: profile, store: store, removeVolumes: false)
    }

    static func composeRestart(profileName: String, store: ProfileStore) throws {
        let profile = try store.loadProfile(named: profileName)
        try RuntimeComposeFlowService.ensureDockerContext(profile: profile, store: store)
        try RuntimeComposeFlowService.composeDown(profile: profile, store: store, removeVolumes: false)
        try RuntimeComposeFlowService.composeUp(profile: profile, store: store)
    }

    static func cleanupRuntime(for profile: ProfileDefinition, store: ProfileStore, removeVolumes: Bool) throws {
        try TunnelService.bootoutAgents(profileName: profile.name, store: store)

        if profile.compose.configured {
            try RuntimeComposeFlowService.ensureDockerContext(profile: profile, store: store)
            try RuntimeComposeFlowService.composeDown(profile: profile, store: store, removeVolumes: removeVolumes)
        }

        if !(try RuntimeProfileHooksService.isProfileRuntimeActive(profile: profile, store: store)) {
            try? store.markProfileInactive(profile.name)
        }
    }

    static func shellExports(profileName: String, store: ProfileStore) throws -> String {
        try RuntimeProfileHooksService.shellExports(profileName: profileName, store: store)
    }
}
