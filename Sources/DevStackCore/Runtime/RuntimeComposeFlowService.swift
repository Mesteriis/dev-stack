import Foundation

enum RuntimeComposeFlowService {
    static func ensureDockerContext(profile: ProfileDefinition, store: ProfileStore) throws {
        let resolvedServer = try RuntimeSharedSupport.resolvePrimaryServer(for: profile, store: store)
        if let server = try RuntimeSharedSupport.resolveServerDefinition(for: profile, store: store), !server.isLocal {
            try RuntimeSharedSupport.upsertDockerContext(for: server)
        }

        let currentContext = try RuntimeSharedSupport.currentDockerContext()
        guard currentContext != resolvedServer.dockerContext else {
            return
        }

        guard let dockerPath = ToolPaths.docker else {
            throw ValidationError("docker not found")
        }

        let switchResult = Shell.run(dockerPath, arguments: ["context", "use", resolvedServer.dockerContext])
        guard switchResult.exitCode == 0 else {
            throw ValidationError(
                RuntimeSharedSupport.nonEmpty(switchResult.stderr)
                    ?? RuntimeSharedSupport.nonEmpty(switchResult.stdout)
                    ?? "Failed to switch docker context"
            )
        }
    }

    static func composeUp(profile: ProfileDefinition, store: ProfileStore) throws {
        guard profile.compose.configured else {
            throw ValidationError("Profile '\(profile.name)' does not have docker compose content.")
        }

        let diagnostics = try RuntimeDiagnosticsService.runtimeDiagnostics(profile: profile, store: store)
        if !diagnostics.errors.isEmpty {
            throw ValidationError(diagnostics.errors.joined(separator: "\n"))
        }

        try RuntimeProfileHooksService.runProfileHooks("before-compose-up", profile: profile, store: store)
        if let server = try RuntimeSharedSupport.resolveServerDefinition(for: profile, store: store), !server.isLocal {
            try RemoteSyncService.syncProjectBindMountSources(profile: profile, store: store, server: server)
        }

        let result = RuntimeSharedSupport.runCompose(profile: profile, store: store, subcommand: ["up", "-d"])
        guard result.exitCode == 0 else {
            throw ValidationError(RuntimeSharedSupport.nonEmpty(result.stderr)
                ?? RuntimeSharedSupport.nonEmpty(result.stdout)
                ?? "docker compose up failed")
        }

        try store.markProfileActive(profile.name)
        try RuntimeProfileHooksService.runProfileHooks("after-compose-up", profile: profile, store: store)
    }

    static func composeDown(profile: ProfileDefinition, store: ProfileStore, removeVolumes: Bool) throws {
        guard profile.compose.configured else {
            throw ValidationError("Profile '\(profile.name)' does not have docker compose content.")
        }

        try RuntimeProfileHooksService.runProfileHooks("before-compose-down", profile: profile, store: store)
        var subcommand = ["down", "--remove-orphans"]
        if removeVolumes {
            subcommand.append("--volumes")
        }

        let result = RuntimeSharedSupport.runCompose(profile: profile, store: store, subcommand: subcommand)
        guard result.exitCode == 0 else {
            throw ValidationError(
                RuntimeSharedSupport.nonEmpty(result.stderr)
                    ?? RuntimeSharedSupport.nonEmpty(result.stdout)
                    ?? "docker compose down failed"
            )
        }

        if !(try RuntimeProfileHooksService.isProfileRuntimeActive(profile: profile, store: store)) {
            try? store.markProfileInactive(profile.name)
        }

        try RuntimeProfileHooksService.runProfileHooks("after-compose-down", profile: profile, store: store)
    }

    static func switchAwayFromPreviousProfile(nextProfile: ProfileDefinition, store: ProfileStore) throws {
        guard let previousName = store.currentProfileName(), previousName != nextProfile.name else {
            return
        }

        guard let previousProfile = try? store.loadProfile(named: previousName) else {
            return
        }
        guard RuntimeProfileHooksService.projectIdentity(for: previousProfile, store: store)
                == RuntimeProfileHooksService.projectIdentity(for: nextProfile, store: store) else {
            return
        }

        try TunnelService.bootoutAgents(profileName: previousName, store: store)

        if previousProfile.compose.autoDownOnSwitch, previousProfile.compose.configured {
            try? ensureDockerContext(profile: previousProfile, store: store)
            try composeDown(profile: previousProfile, store: store, removeVolumes: false)
        }

        if !(try RuntimeProfileHooksService.isProfileRuntimeActive(profile: previousProfile, store: store)) {
            try? store.markProfileInactive(previousProfile.name)
        }
    }
}
