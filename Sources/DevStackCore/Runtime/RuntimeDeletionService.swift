import Foundation

enum RuntimeDeletionService {
    static func deleteProfile(named profileName: String, store: ProfileStore, removeData: Bool) throws {
        let profile = try store.loadProfile(named: profileName)

        try RuntimeLifecycleService.cleanupRuntime(for: profile, store: store, removeVolumes: removeData)

        if removeData, let server = try RuntimeSharedSupport.resolveServerDefinition(for: profile, store: store), !server.isLocal {
            try RemoteSyncService.removeRemoteProfileDirectory(profile: profile, server: server)
        }

        try? FileManager.default.removeItem(at: store.generatedProfileDirectory(for: profile.name))
        if removeData {
            try? RemoteSyncService.removeManagedLocalData(profile: profile, store: store)
        }
        try? FileManager.default.removeItem(at: store.profileURL(named: profile.name))
        try? store.removeManagedVariableProfileReferences(for: profile.name)
        try? store.markProfileInactive(profile.name)

        if store.currentProfileName() == profile.name {
            try? store.clearCurrentProfile()
        }
    }

    static func deletionPlan(profileName: String, store: ProfileStore, removeData: Bool) throws -> ProfileDeletionPlan {
        let profile = try store.loadProfile(named: profileName)
        let plan = profile.compose.configured
            ? try ComposeSupport.plan(profile: profile, store: store)
            : nil
        let server = try RuntimeSharedSupport.resolveServerDefinition(for: profile, store: store)
        let volumes = profile.compose.configured
            ? try RuntimeSharedSupport.composeVolumes(profile: profile, store: store).map(\.name).sorted()
            : []
        let running = profile.compose.configured
            ? try RuntimeSharedSupport.composePS(profile: profile, store: store).map(\.displayName).sorted()
            : []

        return ProfileDeletionPlan(
            profileName: profile.name,
            projectName: plan?.projectName ?? ComposePlanBuilder.composeProjectName(for: profile),
            runningServiceNames: running,
            localDataPath: removeData ? store.profileDataDirectory(for: profile).path : nil,
            remoteDataPath: removeData ? server?.remoteProfileDataDirectory(for: profile.name) : nil,
            remoteProjectPath: removeData ? server?.remoteProfileProjectDirectory(for: profile.name) : nil,
            volumes: removeData ? volumes : []
        )
    }

    static func removeComposeVolumes(profileName: String, store: ProfileStore) throws -> [String] {
        let profile = try store.loadProfile(named: profileName)
        let records = try RuntimeSharedSupport.composeVolumes(profile: profile, store: store)
        guard !records.isEmpty else {
            return []
        }

        guard let dockerPath = ToolPaths.docker else {
            throw ValidationError("docker not found")
        }
        let resolvedServer = try RuntimeSharedSupport.resolvePrimaryServer(for: profile, store: store)

        let result = Shell.run(
            dockerPath,
            arguments: ["--context", resolvedServer.dockerContext, "volume", "rm", "-f"] + records.map(\.name)
        )
        guard result.exitCode == 0 else {
            throw ValidationError(RuntimeSharedSupport.nonEmpty(result.stderr) ?? RuntimeSharedSupport.nonEmpty(result.stdout) ?? "Failed to remove compose volumes")
        }

        return records.map(\.name).sorted()
    }
}
