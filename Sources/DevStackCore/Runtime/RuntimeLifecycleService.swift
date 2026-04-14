import Foundation

enum RuntimeLifecycleService {
    static func prepareServer(
        server: RemoteServerDefinition,
        store _: ProfileStore,
        bootstrapIfNeeded: Bool
    ) throws -> RemoteServerPreparationResult {
        let server = try server.normalized()

        if server.isLocal {
            try RuntimeSharedSupport.ensureDockerContextExists(named: server.dockerContext)
            let serverVersion = try RuntimeSharedSupport.dockerInfo(context: server.dockerContext)
            return RemoteServerPreparationResult(
                server: server,
                remoteOS: "macOS local",
                dockerVersion: "docker context \(server.dockerContext)",
                serverVersion: serverVersion
            )
        }

        let firstInspection = try RuntimeSharedSupport.inspect(server: server)
        if !firstInspection.dockerPresent {
            guard bootstrapIfNeeded else {
                throw ValidationError("Docker is not installed on \(server.remoteDockerServerDisplay).")
            }
            try bootstrapRemoteDocker(on: server)
        }

        let finalInspection = try RuntimeSharedSupport.inspect(server: server)
        guard finalInspection.dockerPresent else {
            throw ValidationError("Docker is still missing on \(server.remoteDockerServerDisplay) after bootstrap.")
        }

        try RuntimeSharedSupport.upsertDockerContext(for: server)
        let serverVersion = try RuntimeSharedSupport.dockerInfo(context: server.dockerContext)

        return RemoteServerPreparationResult(
            server: server,
            remoteOS: finalInspection.remoteOS,
            dockerVersion: finalInspection.dockerVersion,
            serverVersion: serverVersion
        )
    }

    static func activateProfile(named profileName: String, store: ProfileStore) throws {
        let profile = try store.loadProfile(named: profileName)
        let diagnostics = try RuntimeDiagnosticsService.runtimeDiagnostics(profile: profile, store: store)
        if !diagnostics.errors.isEmpty {
            throw ValidationError(diagnostics.errors.joined(separator: "\n"))
        }

        try runProfileHooks("before-activate", profile: profile, store: store)
        try switchAwayFromPreviousProfile(nextProfile: profile, store: store)
        try ensureDockerContext(profile: profile, store: store)

        if profile.compose.autoUpOnActivate && profile.compose.configured {
            try composeUp(profile: profile, store: store)
        }

        if profile.services.contains(where: \.enabled) {
            try TunnelService.bootstrapAgents(profile: profile, store: store)
        } else {
            try TunnelService.bootoutAgents(profileName: profile.name, store: store)
        }

        try store.saveCurrentProfile(profile.name)
        try store.markProfileActive(profile.name)
        try runProfileHooks("after-activate", profile: profile, store: store)
    }

    static func stopProfile(named profileName: String, store: ProfileStore) throws {
        try TunnelService.bootoutAgents(profileName: profileName, store: store)
        if let profile = try? store.loadProfile(named: profileName),
           !(try isProfileRuntimeActive(profile: profile, store: store))
        {
            try? store.markProfileInactive(profile.name)
        }
    }

    static func restartProfile(named profileName: String, store: ProfileStore) throws {
        let profile = try store.loadProfile(named: profileName)
        try ensureDockerContext(profile: profile, store: store)
        try TunnelService.bootoutAgents(profileName: profile.name, store: store)

        if profile.services.contains(where: \.enabled) {
            try TunnelService.bootstrapAgents(profile: profile, store: store)
        }

        try store.markProfileActive(profile.name)
    }

    static func composeUp(profileName: String, store: ProfileStore) throws {
        let profile = try store.loadProfile(named: profileName)
        try ensureDockerContext(profile: profile, store: store)
        try composeUp(profile: profile, store: store)
    }

    static func composeDown(profileName: String, store: ProfileStore) throws {
        let profile = try store.loadProfile(named: profileName)
        try ensureDockerContext(profile: profile, store: store)
        try composeDown(profile: profile, store: store, removeVolumes: false)
    }

    static func composeRestart(profileName: String, store: ProfileStore) throws {
        let profile = try store.loadProfile(named: profileName)
        try ensureDockerContext(profile: profile, store: store)
        try composeDown(profile: profile, store: store, removeVolumes: false)
        try composeUp(profile: profile, store: store)
    }

    static func cleanupRuntime(for profile: ProfileDefinition, store: ProfileStore, removeVolumes: Bool) throws {
        try TunnelService.bootoutAgents(profileName: profile.name, store: store)

        if profile.compose.configured {
            try ensureDockerContext(profile: profile, store: store)
            try composeDown(profile: profile, store: store, removeVolumes: removeVolumes)
        }

        if !(try isProfileRuntimeActive(profile: profile, store: store)) {
            try? store.markProfileInactive(profile.name)
        }
    }

    static func shellExports(profileName: String, store: ProfileStore) throws -> String {
        let profile = try store.loadProfile(named: profileName)
        let resolvedServer = try RuntimeSharedSupport.resolvePrimaryServer(for: profile, store: store)
        let serverDefinition = try RuntimeSharedSupport.resolveServerDefinition(for: profile, store: store)
        var exports: [String] = []
        exports.append("export DEVSTACK_PROFILE=\(RuntimeSharedSupport.shellQuote(profile.name))")
        exports.append("export DEVSTACK_SERVER=\(RuntimeSharedSupport.shellQuote(resolvedServer.name))")
        exports.append("export DOCKER_CONTEXT=\(RuntimeSharedSupport.shellQuote(resolvedServer.dockerContext))")
        exports.append("export REMOTE_DOCKER_SERVER=\(RuntimeSharedSupport.shellQuote(resolvedServer.remoteDockerServer))")
        exports.append("export DEVSTACK_PROFILE_DATA_DIR=\(RuntimeSharedSupport.shellQuote(store.profileDataDirectory(for: profile).path))")
        if let serverDefinition, !serverDefinition.isLocal {
            exports.append("export DEVSTACK_REMOTE_DATA_DIR=\(RuntimeSharedSupport.shellQuote(serverDefinition.remoteProfileDataDirectory(for: profile.name)))")
        }
        if let managedVariables = try? ComposeSupport.applicableManagedVariables(profile: profile, store: store) {
            for variable in managedVariables {
                exports.append("export \(variable.name)=\(RuntimeSharedSupport.shellQuote(variable.value))")
            }
        }

        let activeServices = profile.services.filter(\.enabled)
        for service in activeServices {
            let prefix = service.envPrefix
            exports.append("export \(prefix)_HOST=\(RuntimeSharedSupport.shellQuote(service.aliasHost))")
            exports.append("export \(prefix)_PORT=\(RuntimeSharedSupport.shellQuote(String(service.localPort)))")
            exports.append("export \(prefix)_URL=\(RuntimeSharedSupport.shellQuote(RuntimeSharedSupport.serviceURL(service: service)))")
        }

        if let postgres = activeServices.first(where: { $0.role == "postgres" }) {
            exports.append("export PGHOST=\(RuntimeSharedSupport.shellQuote(postgres.aliasHost))")
            exports.append("export PGPORT=\(RuntimeSharedSupport.shellQuote(String(postgres.localPort)))")
            exports.append("export POSTGRES_URL=\(RuntimeSharedSupport.shellQuote(RuntimeSharedSupport.serviceURL(service: postgres)))")
        }

        if let redis = activeServices.first(where: { $0.role == "redis" }) {
            exports.append("export REDIS_HOST=\(RuntimeSharedSupport.shellQuote(redis.aliasHost))")
            exports.append("export REDIS_URL=\(RuntimeSharedSupport.shellQuote(RuntimeSharedSupport.serviceURL(service: redis)))")
        }

        if let http = activeServices.first(where: { $0.role == "http" || $0.role == "https" }) {
            exports.append("export API_BASE_URL=\(RuntimeSharedSupport.shellQuote(RuntimeSharedSupport.serviceURL(service: http)))")
        }

        for customLine in profile.shellExports {
            exports.append(
                customLine
                    .replacingOccurrences(of: "{profile}", with: profile.name)
                    .replacingOccurrences(of: "{dockerContext}", with: resolvedServer.dockerContext)
                    .replacingOccurrences(of: "{remoteServer}", with: resolvedServer.remoteDockerServer)
            )
        }

        return exports.joined(separator: "\n") + "\n"
    }

    private static func isProfileRuntimeActive(profile: ProfileDefinition, store: ProfileStore) throws -> Bool {
        if TunnelService.agentLoaded(profileName: profile.name, store: store) {
            return true
        }

        if profile.compose.configured {
            let running = try RuntimeSharedSupport.composePS(profile: profile, store: store)
            return !running.isEmpty
        }

        return false
    }

    private static func projectIdentity(for profile: ProfileDefinition, store: ProfileStore) -> String {
        if let directory = store.managedProjectDirectory(for: profile) {
            return directory.standardizedFileURL.path
        }

        let workingDirectory = profile.compose.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !workingDirectory.isEmpty {
            return URL(fileURLWithPath: workingDirectory).standardizedFileURL.path
        }

        return "profile:\(profile.name)"
    }

    private static func runProfileHooks(_ hookName: String, profile: ProfileDefinition, store: ProfileStore) throws {
        let workingDirectoryPath = profile.compose.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let workingDirectory = store.managedProjectDirectory(for: profile)
            ?? URL(
                fileURLWithPath: workingDirectoryPath.isEmpty
                    ? store.generatedProfileDirectory(for: profile.name).path
                    : workingDirectoryPath
            )

        let candidates = [
            workingDirectory.appendingPathComponent(".devstackmenu/hooks/\(hookName).sh", isDirectory: false),
            workingDirectory.appendingPathComponent(".devstackmenu/\(hookName).sh", isDirectory: false),
        ]

        let fileManager = FileManager.default
        guard let hookURL = candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) || fileManager.fileExists(atPath: $0.path) }) else {
            return
        }

        let exports = try shellExports(profileName: profile.name, store: store)
        let command = """
        set -eu
        cd \(RuntimeSharedSupport.shellQuote(workingDirectory.path))
        \(exports)
        export DEVSTACK_HOOK=\(RuntimeSharedSupport.shellQuote(hookName))
        /bin/sh \(RuntimeSharedSupport.shellQuote(hookURL.path))
        """
        let result = RuntimeSharedSupport.runLocalShell(command)
        guard result.exitCode == 0 else {
            throw ValidationError(RuntimeSharedSupport.nonEmpty(result.stderr) ?? RuntimeSharedSupport.nonEmpty(result.stdout) ?? "Hook \(hookName) failed")
        }
    }

    private static func switchAwayFromPreviousProfile(nextProfile: ProfileDefinition, store: ProfileStore) throws {
        guard let previousName = store.currentProfileName(), previousName != nextProfile.name else {
            return
        }

        guard let previousProfile = try? store.loadProfile(named: previousName) else {
            return
        }

        guard projectIdentity(for: previousProfile, store: store) == projectIdentity(for: nextProfile, store: store) else {
            return
        }

        try TunnelService.bootoutAgents(profileName: previousName, store: store)

        if previousProfile.compose.autoDownOnSwitch, previousProfile.compose.configured {
            try? ensureDockerContext(profile: previousProfile, store: store)
            try composeDown(profile: previousProfile, store: store, removeVolumes: false)
        }

        if !(try isProfileRuntimeActive(profile: previousProfile, store: store)) {
            try? store.markProfileInactive(previousProfile.name)
        }
    }

    private static func ensureDockerContext(profile: ProfileDefinition, store: ProfileStore) throws {
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
            throw ValidationError(RuntimeSharedSupport.nonEmpty(switchResult.stderr) ?? RuntimeSharedSupport.nonEmpty(switchResult.stdout) ?? "Failed to switch docker context")
        }
    }

    private static func composeUp(profile: ProfileDefinition, store: ProfileStore) throws {
        guard profile.compose.configured else {
            throw ValidationError("Profile '\(profile.name)' does not have docker compose content.")
        }
        let diagnostics = try RuntimeDiagnosticsService.runtimeDiagnostics(profile: profile, store: store)
        if !diagnostics.errors.isEmpty {
            throw ValidationError(diagnostics.errors.joined(separator: "\n"))
        }
        try runProfileHooks("before-compose-up", profile: profile, store: store)
        if let server = try RuntimeSharedSupport.resolveServerDefinition(for: profile, store: store), !server.isLocal {
            try RemoteSyncService.syncProjectBindMountSources(profile: profile, store: store, server: server)
        }
        let result = RuntimeSharedSupport.runCompose(profile: profile, store: store, subcommand: ["up", "-d"])
        guard result.exitCode == 0 else {
            throw ValidationError(RuntimeSharedSupport.nonEmpty(result.stderr) ?? RuntimeSharedSupport.nonEmpty(result.stdout) ?? "docker compose up failed")
        }
        try store.markProfileActive(profile.name)
        try runProfileHooks("after-compose-up", profile: profile, store: store)
    }

    private static func composeDown(profile: ProfileDefinition, store: ProfileStore, removeVolumes: Bool) throws {
        guard profile.compose.configured else {
            throw ValidationError("Profile '\(profile.name)' does not have docker compose content.")
        }
        try runProfileHooks("before-compose-down", profile: profile, store: store)
        var subcommand = ["down", "--remove-orphans"]
        if removeVolumes {
            subcommand.append("--volumes")
        }
        let result = RuntimeSharedSupport.runCompose(profile: profile, store: store, subcommand: subcommand)
        guard result.exitCode == 0 else {
            throw ValidationError(RuntimeSharedSupport.nonEmpty(result.stderr) ?? RuntimeSharedSupport.nonEmpty(result.stdout) ?? "docker compose down failed")
        }
        if !(try isProfileRuntimeActive(profile: profile, store: store)) {
            try? store.markProfileInactive(profile.name)
        }
        try runProfileHooks("after-compose-down", profile: profile, store: store)
    }

    private static func bootstrapRemoteDocker(on server: RemoteServerDefinition) throws {
        let script = """
        set -eu
        if command -v docker >/dev/null 2>&1; then
          exit 0
        fi
        if ! command -v apt-get >/dev/null 2>&1; then
          echo "Automatic Docker bootstrap is only implemented for apt-based hosts." >&2
          exit 32
        fi
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y ca-certificates curl
        curl -fsSL https://get.docker.com | sh
        if command -v systemctl >/dev/null 2>&1; then
          systemctl enable --now docker >/dev/null 2>&1 || true
        fi
        """

        let result = RuntimeSharedSupport.runRemoteShell(on: server, script: script)
        guard result.exitCode == 0 else {
            throw ValidationError(RuntimeSharedSupport.nonEmpty(result.stderr) ?? RuntimeSharedSupport.nonEmpty(result.stdout) ?? "Failed to bootstrap Docker on \(server.remoteDockerServerDisplay)")
        }
    }
}
