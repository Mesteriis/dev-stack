import Foundation

package struct RemoteServerPreparationResult: Sendable {
    package let server: RemoteServerDefinition
    package let remoteOS: String
    let dockerVersion: String
    package let serverVersion: String
}

private struct RemoteServerInspection: Sendable {
    let remoteOS: String
    let dockerPresent: Bool
    let dockerVersion: String
    let serverVersion: String
}

private struct ResolvedServer: Sendable {
    let name: String
    let dockerContext: String
    let remoteDockerServer: String
    let sshTarget: String?
    let sshPort: Int
    let isLocal: Bool

    init(server: RemoteServerDefinition) {
        name = server.name
        dockerContext = server.dockerContext
        remoteDockerServer = server.remoteDockerServerDisplay
        sshTarget = server.isLocal ? nil : server.sshTarget
        sshPort = server.sshPort
        isLocal = server.isLocal
    }

    init(legacyProfile profile: ProfileDefinition) {
        let tunnelHost = profile.tunnelHost.trimmingCharacters(in: .whitespacesAndNewlines)
        name = tunnelHost.isEmpty ? profile.dockerContext : tunnelHost
        dockerContext = profile.dockerContext
        remoteDockerServer = tunnelHost.isEmpty ? "local" : tunnelHost
        sshTarget = tunnelHost.isEmpty ? nil : tunnelHost
        sshPort = 22
        isLocal = tunnelHost.isEmpty || tunnelHost == "local"
    }
}

private struct TunnelEndpoint: Hashable, Sendable {
    let labelComponent: String
    let displayName: String
    let sshTarget: String
    let sshPort: Int
}

private struct ManagedDataRewriteResult: Sendable {
    let content: String
    let serviceNames: Set<String>
}

struct RuntimeDiagnosticsReport: Sendable {
    let errors: [String]
    let warnings: [String]
    let localPortConflicts: [ComposePortBinding]
}

struct ComposeActionPreview: Sendable {
    let plan: ComposePlan
    let diagnostics: RuntimeDiagnosticsReport
    let runningServiceNames: [String]
}

struct ProfileDeletionPlan: Sendable {
    let profileName: String
    let projectName: String
    let runningServiceNames: [String]
    let localDataPath: String?
    let remoteDataPath: String?
    let remoteProjectPath: String?
    let volumes: [String]
}

struct ComposeVolumeRecord: Sendable {
    let name: String
    let mountpoint: String?
    let driver: String?
}

struct CompactMetricsSnapshot: Sendable {
    let summaryLine: String
    let detailLines: [String]
}

package enum RuntimeController {
    package static func dockerContexts() throws -> [DockerContextEntry] {
        guard let dockerPath = ToolPaths.docker else {
            throw ValidationError("docker not found")
        }

        let result = Shell.run(
            dockerPath,
            arguments: ["context", "ls", "--format", "{{.Name}}\t{{.Current}}\t{{.DockerEndpoint}}"]
        )
        guard result.exitCode == 0 else {
            throw ValidationError(nonEmpty(result.stderr) ?? nonEmpty(result.stdout) ?? "Failed to load docker contexts")
        }

        return parseDockerContexts(from: result.stdout)
    }

    static func remoteServers(store: ProfileStore) throws -> [RemoteServerDefinition] {
        try store.remoteServers().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    package static func currentDockerContext() throws -> String {
        guard let dockerPath = ToolPaths.docker else {
            throw ValidationError("docker not found")
        }

        let result = Shell.run(dockerPath, arguments: ["context", "show"])
        guard result.exitCode == 0 else {
            throw ValidationError(nonEmpty(result.stderr) ?? nonEmpty(result.stdout) ?? "Failed to read docker context")
        }

        return nonEmpty(result.stdout) ?? "unknown"
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

            try deleteProfile(named: profile.name, store: store, removeData: true)
            removedProfiles.append(profile.name)
        }

        return removedProfiles
    }

    package static func previewManagedDataRewrite(
        content: String,
        dataRootPath: String
    ) -> (content: String, serviceNames: [String]) {
        let rewrite = rewriteManagedDataMounts(in: content, dataRootPath: dataRootPath)
        return (rewrite.content, rewrite.serviceNames.sorted())
    }

    package static func prepareServer(
        server: RemoteServerDefinition,
        store: ProfileStore,
        bootstrapIfNeeded: Bool
    ) throws -> RemoteServerPreparationResult {
        let server = try server.normalized()

        if server.isLocal {
            try ensureDockerContextExists(named: server.dockerContext)
            let serverVersion = try dockerInfo(context: server.dockerContext)
            return RemoteServerPreparationResult(
                server: server,
                remoteOS: "macOS local",
                dockerVersion: "docker context \(server.dockerContext)",
                serverVersion: serverVersion
            )
        }

        let firstInspection = try inspect(server: server)
        if !firstInspection.dockerPresent {
            guard bootstrapIfNeeded else {
                throw ValidationError("Docker is not installed on \(server.remoteDockerServerDisplay).")
            }
            try bootstrapRemoteDocker(on: server)
        }

        let finalInspection = try inspect(server: server)
        guard finalInspection.dockerPresent else {
            throw ValidationError("Docker is still missing on \(server.remoteDockerServerDisplay) after bootstrap.")
        }

        try upsertDockerContext(for: server)
        let serverVersion = try dockerInfo(context: server.dockerContext)

        return RemoteServerPreparationResult(
            server: server,
            remoteOS: finalInspection.remoteOS,
            dockerVersion: finalInspection.dockerVersion,
            serverVersion: serverVersion
        )
    }

    package static func statusSnapshot(store: ProfileStore, profileName: String) throws -> AppSnapshot {
        let profile = try store.loadProfile(named: profileName)
        let resolvedServer = try resolvePrimaryServer(for: profile, store: store)
        let activeDockerContext = (try? currentDockerContext()) ?? "unknown"
        let composeServices = try composePS(profile: profile, store: store)

        let serviceSnapshots = profile.services.map { service in
            ServiceRuntimeSnapshot(
                name: service.name,
                role: service.role,
                aliasHost: service.aliasHost,
                localPort: service.localPort,
                remoteHost: service.remoteHost,
                remotePort: service.remotePort,
                tunnelHost: tunnelDisplayName(for: service, profile: profile, store: store, fallback: resolvedServer.remoteDockerServer),
                envPrefix: service.envPrefix,
                enabled: service.enabled,
                listening: service.enabled ? portListening(service.localPort) : false
            )
        }

        return AppSnapshot(
            profile: profile.name,
            configuredDockerContext: resolvedServer.dockerContext,
            activeDockerContext: activeDockerContext,
            tunnelLoaded: agentLoaded(profileName: profile.name, store: store),
            tunnelLabel: store.launchAgentPrefix(for: profile.name),
            compose: ComposeRuntimeSnapshot(
                configured: profile.compose.configured,
                projectName: profile.compose.configured ? composeProjectName(profile: profile) : "",
                workingDirectory: profile.compose.workingDirectory,
                autoDownOnSwitch: profile.compose.autoDownOnSwitch,
                autoUpOnActivate: profile.compose.autoUpOnActivate,
                runningServices: composeServices
            ),
            services: serviceSnapshots
        )
    }

    package static func activateProfile(named profileName: String, store: ProfileStore) throws {
        let profile = try store.loadProfile(named: profileName)
        let diagnostics = try runtimeDiagnostics(profile: profile, store: store)
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
            try bootstrapAgents(profile: profile, store: store)
        } else {
            try bootoutAgents(profileName: profile.name, store: store)
        }

        try store.saveCurrentProfile(profile.name)
        try store.markProfileActive(profile.name)
        try runProfileHooks("after-activate", profile: profile, store: store)
    }

    package static func stopProfile(named profileName: String, store: ProfileStore) throws {
        try bootoutAgents(profileName: profileName, store: store)
        if let profile = try? store.loadProfile(named: profileName),
           !(try isProfileRuntimeActive(profile: profile, store: store))
        {
            try? store.markProfileInactive(profile.name)
        }
    }

    static func restartProfile(named profileName: String, store: ProfileStore) throws {
        let profile = try store.loadProfile(named: profileName)
        try ensureDockerContext(profile: profile, store: store)
        try bootoutAgents(profileName: profile.name, store: store)

        if profile.services.contains(where: \.enabled) {
            try bootstrapAgents(profile: profile, store: store)
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

    static func deleteProfile(named profileName: String, store: ProfileStore, removeData: Bool) throws {
        let profile = try store.loadProfile(named: profileName)

        try cleanupRuntime(for: profile, store: store, removeVolumes: removeData)

        if removeData, let server = try resolveServerDefinition(for: profile, store: store), !server.isLocal {
            try removeRemoteProfileDirectory(profile: profile, server: server)
        }

        try? FileManager.default.removeItem(at: store.generatedProfileDirectory(for: profile.name))
        if removeData {
            try? removeManagedLocalData(profile: profile, store: store)
        }
        try? FileManager.default.removeItem(at: store.profileURL(named: profile.name))
        try? store.removeManagedVariableProfileReferences(for: profile.name)
        try? store.markProfileInactive(profile.name)

        if store.currentProfileName() == profile.name {
            try? store.clearCurrentProfile()
        }
    }

    static func cleanupRuntime(for profile: ProfileDefinition, store: ProfileStore, removeVolumes: Bool) throws {
        try bootoutAgents(profileName: profile.name, store: store)

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
        let resolvedServer = try resolvePrimaryServer(for: profile, store: store)
        let serverDefinition = try resolveServerDefinition(for: profile, store: store)
        var exports: [String] = []
        exports.append("export DEVSTACK_PROFILE=\(shellQuote(profile.name))")
        exports.append("export DEVSTACK_SERVER=\(shellQuote(resolvedServer.name))")
        exports.append("export DOCKER_CONTEXT=\(shellQuote(resolvedServer.dockerContext))")
        exports.append("export REMOTE_DOCKER_SERVER=\(shellQuote(resolvedServer.remoteDockerServer))")
        exports.append("export DEVSTACK_PROFILE_DATA_DIR=\(shellQuote(store.profileDataDirectory(for: profile).path))")
        if let serverDefinition, !serverDefinition.isLocal {
            exports.append("export DEVSTACK_REMOTE_DATA_DIR=\(shellQuote(serverDefinition.remoteProfileDataDirectory(for: profile.name)))")
        }
        if let managedVariables = try? ComposeSupport.applicableManagedVariables(profile: profile, store: store) {
            for variable in managedVariables {
                exports.append("export \(variable.name)=\(shellQuote(variable.value))")
            }
        }

        let activeServices = profile.services.filter(\.enabled)
        for service in activeServices {
            let prefix = service.envPrefix
            exports.append("export \(prefix)_HOST=\(shellQuote(service.aliasHost))")
            exports.append("export \(prefix)_PORT=\(shellQuote(String(service.localPort)))")
            exports.append("export \(prefix)_URL=\(shellQuote(serviceURL(service: service)))")
        }

        if let postgres = activeServices.first(where: { $0.role == "postgres" }) {
            exports.append("export PGHOST=\(shellQuote(postgres.aliasHost))")
            exports.append("export PGPORT=\(shellQuote(String(postgres.localPort)))")
            exports.append("export POSTGRES_URL=\(shellQuote(serviceURL(service: postgres)))")
        }

        if let redis = activeServices.first(where: { $0.role == "redis" }) {
            exports.append("export REDIS_HOST=\(shellQuote(redis.aliasHost))")
            exports.append("export REDIS_URL=\(shellQuote(serviceURL(service: redis)))")
        }

        if let http = activeServices.first(where: { $0.role == "http" || $0.role == "https" }) {
            exports.append("export API_BASE_URL=\(shellQuote(serviceURL(service: http)))")
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

    static func activeProfileNames(store: ProfileStore) -> [String] {
        store.activeProfileNames()
    }

    static func composePreview(profileName: String, store: ProfileStore) throws -> ComposeActionPreview {
        let profile = try store.loadProfile(named: profileName)
        let plan = try ComposeSupport.plan(profile: profile, store: store)
        let diagnostics = try runtimeDiagnostics(profile: profile, store: store, plan: plan)
        let runningServices = try composePS(profile: profile, store: store).map(\.displayName).sorted()
        return ComposeActionPreview(plan: plan, diagnostics: diagnostics, runningServiceNames: runningServices)
    }

    static func deletionPlan(profileName: String, store: ProfileStore, removeData: Bool) throws -> ProfileDeletionPlan {
        let profile = try store.loadProfile(named: profileName)
        let plan = profile.compose.configured
            ? try ComposeSupport.plan(profile: profile, store: store)
            : nil
        let server = try resolveServerDefinition(for: profile, store: store)
        let volumes = profile.compose.configured
            ? try composeVolumes(profile: profile, store: store).map(\.name).sorted()
            : []
        let running = profile.compose.configured
            ? try composePS(profile: profile, store: store).map(\.displayName).sorted()
            : []

        return ProfileDeletionPlan(
            profileName: profile.name,
            projectName: plan?.projectName ?? composeProjectName(profile: profile),
            runningServiceNames: running,
            localDataPath: removeData ? store.profileDataDirectory(for: profile).path : nil,
            remoteDataPath: removeData ? server?.remoteProfileDataDirectory(for: profile.name) : nil,
            remoteProjectPath: removeData ? server?.remoteProfileProjectDirectory(for: profile.name) : nil,
            volumes: removeData ? volumes : []
        )
    }

    static func writeComposeLogsSnapshot(profileName: String, store: ProfileStore) throws -> URL {
        let profile = try store.loadProfile(named: profileName)
        let result = runCompose(profile: profile, store: store, subcommand: ["logs", "--no-color", "--timestamps", "--tail", "400"])
        guard result.exitCode == 0 else {
            throw ValidationError(nonEmpty(result.stderr) ?? nonEmpty(result.stdout) ?? "docker compose logs failed")
        }

        let outputURL = store.generatedComposeLogsURL(for: profile.name)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try result.stdout.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    static func writeVolumeReport(profileName: String, store: ProfileStore) throws -> URL {
        let profile = try store.loadProfile(named: profileName)
        let records = try composeVolumes(profile: profile, store: store)
        var lines: [String] = []
        lines.append("Profile: \(profile.name)")
        lines.append("Project: \(composeProjectName(profile: profile))")
        lines.append("")
        if records.isEmpty {
            lines.append("No compose volumes found.")
        } else {
            for record in records {
                lines.append("- \(record.name)")
                if let driver = record.driver {
                    lines.append("  driver: \(driver)")
                }
                if let mountpoint = record.mountpoint {
                    lines.append("  mountpoint: \(mountpoint)")
                }
            }
        }

        let outputURL = store.generatedVolumeReportURL(for: profile.name)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").appending("\n").write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    static func removeComposeVolumes(profileName: String, store: ProfileStore) throws -> [String] {
        let profile = try store.loadProfile(named: profileName)
        let records = try composeVolumes(profile: profile, store: store)
        guard !records.isEmpty else {
            return []
        }

        guard let dockerPath = ToolPaths.docker else {
            throw ValidationError("docker not found")
        }
        let resolvedServer = try resolvePrimaryServer(for: profile, store: store)

        let result = Shell.run(
            dockerPath,
            arguments: ["--context", resolvedServer.dockerContext, "volume", "rm", "-f"] + records.map(\.name)
        )
        guard result.exitCode == 0 else {
            throw ValidationError(nonEmpty(result.stderr) ?? nonEmpty(result.stdout) ?? "Failed to remove compose volumes")
        }

        return records.map(\.name).sorted()
    }

    static func writeMetricsReport(profileName: String, store: ProfileStore) throws -> URL {
        let profile = try store.loadProfile(named: profileName)
        let snapshot = try compactMetrics(profileName: profileName, store: store)
        var lines = [snapshot.summaryLine, ""]
        lines.append(contentsOf: snapshot.detailLines)
        let outputURL = store.generatedMetricsReportURL(for: profile.name)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").appending("\n").write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    static func compactMetrics(profileName: String, store: ProfileStore) throws -> CompactMetricsSnapshot {
        let profile = try store.loadProfile(named: profileName)
        let containerIDs = try composeContainerIDs(profile: profile, store: store)
        guard !containerIDs.isEmpty else {
            return CompactMetricsSnapshot(summaryLine: "No running containers for \(profile.name).", detailLines: [])
        }

        guard let dockerPath = ToolPaths.docker else {
            throw ValidationError("docker not found")
        }
        let resolvedServer = try resolvePrimaryServer(for: profile, store: store)

        let result = Shell.run(
            dockerPath,
            arguments: ["--context", resolvedServer.dockerContext, "stats", "--no-stream", "--format", "{{json .}}"] + containerIDs
        )
        guard result.exitCode == 0 else {
            throw ValidationError(nonEmpty(result.stderr) ?? nonEmpty(result.stdout) ?? "docker stats failed")
        }

        let stats = result.stdout
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> [String: Any]? in
                guard let data = String(line).data(using: .utf8) else {
                    return nil
                }
                return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            }

        let totalCPU = stats.compactMap { parsePercent($0["CPUPerc"] as? String) }.reduce(0, +)
        let detailLines = stats.compactMap { stat -> String? in
            guard let name = stat["Name"] as? String else {
                return nil
            }
            let cpu = (stat["CPUPerc"] as? String) ?? "0%"
            let memory = (stat["MemUsage"] as? String) ?? "n/a"
            let network = (stat["NetIO"] as? String) ?? "n/a"
            return "\(name): CPU \(cpu) | Mem \(memory) | Net \(network)"
        }

        let summary = "\(profile.name): \(detailLines.count) container(s), total CPU \(String(format: "%.1f", totalCPU))%"
        return CompactMetricsSnapshot(summaryLine: summary, detailLines: detailLines)
    }

    static func writeRemoteBrowseReport(profileName: String, store: ProfileStore) throws -> URL {
        let profile = try store.loadProfile(named: profileName)
        guard let server = try resolveServerDefinition(for: profile, store: store), !server.isLocal else {
            throw ValidationError("Current profile does not use a remote SSH server.")
        }

        let script = """
        set -eu
        base=\(shellQuote(server.remoteProfileDirectory(for: profile.name)))
        if [ ! -d "$base" ]; then
          echo "Remote directory does not exist: $base"
          exit 0
        fi
        find "$base" -maxdepth 5 -print | sort
        """
        let result = runRemoteShell(on: server, script: script)
        guard result.exitCode == 0 else {
            throw ValidationError(nonEmpty(result.stderr) ?? nonEmpty(result.stdout) ?? "Failed to inspect remote files")
        }

        let outputURL = store.generatedRemoteBrowseReportURL(for: profile.name)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try result.stdout.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    private static func runtimeDiagnostics(
        profile: ProfileDefinition,
        store: ProfileStore,
        plan: ComposePlan? = nil
    ) throws -> RuntimeDiagnosticsReport {
        let plan = try plan ?? ComposeSupport.plan(profile: profile, store: store)
        var errors: [String] = []
        var warnings: [String] = []
        var localConflicts: [ComposePortBinding] = []
        let runningServices = try composePS(profile: profile, store: store)

        if let server = try resolveServerDefinition(for: profile, store: store), !server.isLocal {
            let inspection = try inspect(server: server)
            if !inspection.dockerPresent {
                errors.append("Docker is not available on \(server.remoteDockerServerDisplay).")
            }

            let diskScript = """
            set -eu
            base=\(shellQuote(server.remoteDataRoot))
            mkdir -p "$base"
            df -Pk "$base" | tail -n 1 | awk '{print $4}'
            """
            let diskResult = runRemoteShell(on: server, script: diskScript)
            if diskResult.exitCode == 0,
               let availableKB = Int(diskResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)),
               availableKB < 524_288
            {
                warnings.append("Remote free space on \(server.remoteDockerServerDisplay) is below 512 MB.")
            }

            if !plan.unsupportedRemoteBindSources.isEmpty {
                errors.append("Remote compose uses host bind mounts outside the project directory: \(plan.unsupportedRemoteBindSources.joined(separator: ", "))")
            }

            let remotePorts = Set(plan.services.flatMap(\.ports).map(\.publishedPort))
            let remoteListeningPorts = try remoteListeningPorts(on: server, candidates: Array(remotePorts))
            for port in plan.services.flatMap(\.ports) where remoteListeningPorts.contains(port.publishedPort) {
                let message = "Remote port \(port.publishedPort) is already listening on \(server.remoteDockerServerDisplay)."
                if runningServices.isEmpty {
                    warnings.append(message)
                } else {
                    warnings.append(message)
                }
            }
        } else {
            for port in plan.services.flatMap(\.ports) where portListening(port.publishedPort) {
                localConflicts.append(port)
                if runningServices.isEmpty {
                    errors.append("Local port \(port.publishedPort) is already listening before compose up.")
                } else {
                    warnings.append("Local port \(port.publishedPort) is already listening.")
                }
            }
        }

        return RuntimeDiagnosticsReport(
            errors: deduplicated(errors),
            warnings: deduplicated(warnings),
            localPortConflicts: uniquePortBindings(localConflicts)
        )
    }

    private static func isProfileRuntimeActive(profile: ProfileDefinition, store: ProfileStore) throws -> Bool {
        if agentLoaded(profileName: profile.name, store: store) {
            return true
        }

        if profile.compose.configured {
            let running = try composePS(profile: profile, store: store)
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
        cd \(shellQuote(workingDirectory.path))
        \(exports)
        export DEVSTACK_HOOK=\(shellQuote(hookName))
        /bin/sh \(shellQuote(hookURL.path))
        """
        let result = runLocalShell(command)
        guard result.exitCode == 0 else {
            throw ValidationError(nonEmpty(result.stderr) ?? nonEmpty(result.stdout) ?? "Hook \(hookName) failed")
        }
    }

    private static func syncProjectBindMountSources(
        profile: ProfileDefinition,
        store: ProfileStore,
        server: RemoteServerDefinition
    ) throws {
        let plan = try ComposeSupport.plan(profile: profile, store: store)
        let remoteProfileDirectory = server.remoteProfileDirectory(for: profile.name)
        let remoteProjectDirectory = server.remoteProfileProjectDirectory(for: profile.name)

        let prepareScript = """
        set -eu
        mkdir -p \(shellQuote(remoteProfileDirectory))
        rm -rf \(shellQuote(remoteProjectDirectory))
        mkdir -p \(shellQuote(remoteProjectDirectory))
        """
        let prepareResult = runRemoteShell(on: server, script: prepareScript)
        guard prepareResult.exitCode == 0 else {
            throw ValidationError(nonEmpty(prepareResult.stderr) ?? nonEmpty(prepareResult.stdout) ?? "Failed to prepare remote project directory")
        }

        let fileManager = FileManager.default
        let existingRelativePaths = plan.relativeProjectPaths.filter {
            fileManager.fileExists(atPath: plan.workingDirectory.appendingPathComponent($0).path)
        }
        guard !existingRelativePaths.isEmpty else {
            return
        }

        let tarCommand = shellCommand(
            executable: "/usr/bin/tar",
            arguments: ["-C", plan.workingDirectory.path, "-cf", "-"] + existingRelativePaths
        )
        let remoteExtractCommand = shellCommand(
            executable: "/usr/bin/ssh",
            arguments: sshArguments(for: server) + ["/usr/bin/tar", "--no-same-owner", "-xf", "-", "-C", remoteProjectDirectory]
        )
        let syncCommand = "set -euo pipefail; COPYFILE_DISABLE=1 \(tarCommand) | \(remoteExtractCommand)"
        let syncResult = runLocalShell(syncCommand)
        guard syncResult.exitCode == 0 else {
            throw ValidationError(nonEmpty(syncResult.stderr) ?? nonEmpty(syncResult.stdout) ?? "Failed to sync project bind mounts to remote server")
        }
    }

    private static func composeVolumes(profile: ProfileDefinition, store: ProfileStore) throws -> [ComposeVolumeRecord] {
        guard let dockerPath = ToolPaths.docker else {
            throw ValidationError("docker not found")
        }

        let projectName = composeProjectName(profile: profile)
        let resolvedServer = try resolvePrimaryServer(for: profile, store: store)
        let listResult = Shell.run(
            dockerPath,
            arguments: [
                "--context", resolvedServer.dockerContext,
                "volume", "ls",
                "--filter", "label=com.docker.compose.project=\(projectName)",
                "--format", "{{.Name}}",
            ]
        )
        guard listResult.exitCode == 0 else {
            throw ValidationError(nonEmpty(listResult.stderr) ?? nonEmpty(listResult.stdout) ?? "Failed to list compose volumes")
        }

        let names = listResult.stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return try names.map { name in
            let inspect = Shell.run(
                dockerPath,
                arguments: ["--context", resolvedServer.dockerContext, "volume", "inspect", name, "--format", "{{json .}}"]
            )
            guard inspect.exitCode == 0,
                  let data = inspect.stdout.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return ComposeVolumeRecord(name: name, mountpoint: nil, driver: nil)
            }

            return ComposeVolumeRecord(
                name: name,
                mountpoint: object["Mountpoint"] as? String,
                driver: object["Driver"] as? String
            )
        }
    }

    private static func composeContainerIDs(profile: ProfileDefinition, store: ProfileStore) throws -> [String] {
        let result = runCompose(profile: profile, store: store, subcommand: ["ps", "-q"])
        guard result.exitCode == 0 else {
            throw ValidationError(nonEmpty(result.stderr) ?? nonEmpty(result.stdout) ?? "Failed to list compose containers")
        }

        return result.stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func parsePercent(_ value: String?) -> Double? {
        guard let value else {
            return nil
        }
        let cleaned = value.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
    }

    private static func uniquePortBindings(_ bindings: [ComposePortBinding]) -> [ComposePortBinding] {
        var seen = Set<String>()
        var result: [ComposePortBinding] = []
        for binding in bindings {
            let key = "\(binding.serviceName):\(binding.publishedPort)"
            if seen.insert(key).inserted {
                result.append(binding)
            }
        }
        return result
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        var result: [String] = []
        for value in values where !result.contains(value) {
            result.append(value)
        }
        return result
    }

    private static func remoteListeningPorts(on server: RemoteServerDefinition, candidates: [Int]) throws -> Set<Int> {
        guard !candidates.isEmpty else {
            return []
        }

        let script = """
        set -eu
        if command -v ss >/dev/null 2>&1; then
          ss -ltnH 2>/dev/null | awk '{print $4}'
        else
          netstat -ltn 2>/dev/null | tail -n +3 | awk '{print $4}'
        fi
        """
        let result = runRemoteShell(on: server, script: script)
        guard result.exitCode == 0 else {
            throw ValidationError(nonEmpty(result.stderr) ?? nonEmpty(result.stdout) ?? "Failed to inspect remote listening ports")
        }

        let candidateSet = Set(candidates)
        var listening = Set<Int>()
        for line in result.stdout.split(whereSeparator: \.isNewline) {
            let value = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let port = extractTerminalPort(from: value), candidateSet.contains(port) else {
                continue
            }
            listening.insert(port)
        }
        return listening
    }

    private static func extractTerminalPort(from endpoint: String) -> Int? {
        let separators = endpoint.split(separator: ":")
        guard let last = separators.last else {
            return nil
        }
        return Int(last.trimmingCharacters(in: CharacterSet(charactersIn: "[]")))
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

        try bootoutAgents(profileName: previousName, store: store)

        if previousProfile.compose.autoDownOnSwitch, previousProfile.compose.configured {
            try? ensureDockerContext(profile: previousProfile, store: store)
            try composeDown(profile: previousProfile, store: store, removeVolumes: false)
        }

        if !(try isProfileRuntimeActive(profile: previousProfile, store: store)) {
            try? store.markProfileInactive(previousProfile.name)
        }
    }

    private static func resolvePrimaryServer(for profile: ProfileDefinition, store: ProfileStore) throws -> ResolvedServer {
        if !profile.serverName.isEmpty {
            return try ResolvedServer(server: store.loadServer(named: profile.serverName))
        }
        return ResolvedServer(legacyProfile: profile)
    }

    private static func resolveServerDefinition(for profile: ProfileDefinition, store: ProfileStore) throws -> RemoteServerDefinition? {
        guard !profile.serverName.isEmpty else {
            return nil
        }
        return try store.loadServer(named: profile.serverName)
    }

    private static func resolveTunnelEndpoint(
        for service: ServiceDefinition,
        profile: ProfileDefinition,
        store: ProfileStore
    ) throws -> TunnelEndpoint? {
        let override = service.tunnelHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty {
            if let server = try? store.loadServer(named: override) {
                guard !server.isLocal else {
                    throw ValidationError("Server '\(server.name)' is local and cannot be used for SSH tunnels.")
                }
                return TunnelEndpoint(
                    labelComponent: server.name,
                    displayName: server.remoteDockerServerDisplay,
                    sshTarget: server.sshTarget,
                    sshPort: server.sshPort
                )
            }

            return TunnelEndpoint(
                labelComponent: override,
                displayName: override,
                sshTarget: override,
                sshPort: 22
            )
        }

        let resolvedServer = try resolvePrimaryServer(for: profile, store: store)
        guard let sshTarget = resolvedServer.sshTarget else {
            return nil
        }

        return TunnelEndpoint(
            labelComponent: resolvedServer.name,
            displayName: resolvedServer.remoteDockerServer,
            sshTarget: sshTarget,
            sshPort: resolvedServer.sshPort
        )
    }

    private static func tunnelDisplayName(
        for service: ServiceDefinition,
        profile: ProfileDefinition,
        store: ProfileStore,
        fallback: String
    ) -> String {
        if let endpoint = try? resolveTunnelEndpoint(for: service, profile: profile, store: store) {
            return endpoint.displayName
        }
        return service.tunnelHost.isEmpty ? fallback : service.tunnelHost
    }

    private static func ensureDockerContext(profile: ProfileDefinition, store: ProfileStore) throws {
        let resolvedServer = try resolvePrimaryServer(for: profile, store: store)
        if let server = try resolveServerDefinition(for: profile, store: store), !server.isLocal {
            try upsertDockerContext(for: server)
        }

        let currentContext = try currentDockerContext()
        guard currentContext != resolvedServer.dockerContext else {
            return
        }

        guard let dockerPath = ToolPaths.docker else {
            throw ValidationError("docker not found")
        }

        let switchResult = Shell.run(dockerPath, arguments: ["context", "use", resolvedServer.dockerContext])
        guard switchResult.exitCode == 0 else {
            throw ValidationError(nonEmpty(switchResult.stderr) ?? nonEmpty(switchResult.stdout) ?? "Failed to switch docker context")
        }
    }

    private static func composeUp(profile: ProfileDefinition, store: ProfileStore) throws {
        guard profile.compose.configured else {
            throw ValidationError("Profile '\(profile.name)' does not have docker compose content.")
        }
        let diagnostics = try runtimeDiagnostics(profile: profile, store: store)
        if !diagnostics.errors.isEmpty {
            throw ValidationError(diagnostics.errors.joined(separator: "\n"))
        }
        try runProfileHooks("before-compose-up", profile: profile, store: store)
        if let server = try resolveServerDefinition(for: profile, store: store), !server.isLocal {
            try syncProjectBindMountSources(profile: profile, store: store, server: server)
        }
        let result = runCompose(profile: profile, store: store, subcommand: ["up", "-d"])
        guard result.exitCode == 0 else {
            throw ValidationError(nonEmpty(result.stderr) ?? nonEmpty(result.stdout) ?? "docker compose up failed")
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
        let result = runCompose(profile: profile, store: store, subcommand: subcommand)
        guard result.exitCode == 0 else {
            throw ValidationError(nonEmpty(result.stderr) ?? nonEmpty(result.stdout) ?? "docker compose down failed")
        }
        if !(try isProfileRuntimeActive(profile: profile, store: store)) {
            try? store.markProfileInactive(profile.name)
        }
        try runProfileHooks("after-compose-down", profile: profile, store: store)
    }

    private static func composePS(profile: ProfileDefinition, store: ProfileStore) throws -> [ComposeRuntimeService] {
        guard profile.compose.configured else {
            return []
        }

        let result = runCompose(profile: profile, store: store, subcommand: ["ps", "--format", "json"])
        guard result.exitCode == 0 else {
            let message = nonEmpty(result.stderr) ?? nonEmpty(result.stdout)
            if let message, !message.lowercased().contains("no such service") {
                throw ValidationError(message)
            }
            return []
        }

        let raw = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return []
        }

        let data = Data(raw.utf8)
        if let decoded = try? JSONDecoder().decode([ComposeRuntimeService].self, from: data) {
            return decoded
        }

        if let decoded = try? JSONDecoder().decode(ComposeRuntimeService.self, from: data) {
            return [decoded]
        }

        return raw
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                try? JSONDecoder().decode(ComposeRuntimeService.self, from: Data(String(line).utf8))
            }
    }

    private static func runCompose(
        profile: ProfileDefinition,
        store: ProfileStore,
        subcommand: [String]
    ) -> CommandResult {
        guard let dockerPath = ToolPaths.docker else {
            return CommandResult(exitCode: 127, stdout: "", stderr: "docker not found")
        }

        do {
            let server = try resolveServerDefinition(for: profile, store: store)
            let resolvedServer = try resolvePrimaryServer(for: profile, store: store)
            let generated = try ComposeSupport.generatedComposeFile(profile: profile, store: store, server: server)
            let arguments = [
                "--context",
                resolvedServer.dockerContext,
                "compose",
                "--project-name",
                generated.plan.projectName,
                "--project-directory",
                generated.plan.workingDirectory.path,
                "-f",
                generated.composeURL.path,
            ] + subcommand

            return Shell.run(
                dockerPath,
                arguments: arguments,
                currentDirectoryURL: generated.plan.workingDirectory
            )
        } catch {
            return CommandResult(exitCode: 1, stdout: "", stderr: error.localizedDescription)
        }
    }

    private static func composeProjectName(profile: ProfileDefinition) -> String {
        let trimmed = profile.compose.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? slugify(profile.name) : trimmed
    }

    private static func composeWorkingDirectory(profile: ProfileDefinition, store: ProfileStore) -> URL {
        let trimmed = profile.compose.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return store.generatedDirectory.appendingPathComponent(profile.name, isDirectory: true)
        }
        return URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath, isDirectory: true)
    }

    private static func writeComposeFile(
        profile: ProfileDefinition,
        store: ProfileStore,
        server: RemoteServerDefinition?
    ) throws -> URL {
        guard profile.compose.configured else {
            throw ValidationError("Profile '\(profile.name)' does not have docker compose content.")
        }

        try store.ensureRuntimeDirectories()
        let composeURL = store.composeFileURL(for: profile.name)
        let generatedProfileDirectory = store.generatedProfileDirectory(for: profile.name)
        try FileManager.default.createDirectory(at: generatedProfileDirectory, withIntermediateDirectories: true)
        let localDataRoot = store.profileDataDirectory(for: profile)
        let rewritten: ManagedDataRewriteResult
        if let server, !server.isLocal {
            rewritten = rewriteManagedDataMounts(
                in: profile.compose.content,
                dataRootPath: server.remoteProfileDataDirectory(for: profile.name)
            )
        } else {
            rewritten = rewriteManagedDataMounts(
                in: profile.compose.content,
                dataRootPath: localDataRoot.path
            )
        }

        if !rewritten.serviceNames.isEmpty {
            try FileManager.default.createDirectory(at: localDataRoot, withIntermediateDirectories: true)
            for serviceName in rewritten.serviceNames {
                try FileManager.default.createDirectory(
                    at: store.serviceDataDirectory(for: profile, serviceName: serviceName),
                    withIntermediateDirectories: true
                )
            }
        }

        try rewritten.content.write(to: composeURL, atomically: true, encoding: .utf8)
        return composeURL
    }

    private static func bootstrapAgents(profile: ProfileDefinition, store: ProfileStore) throws {
        var grouped: [TunnelEndpoint: [ServiceDefinition]] = [:]
        for service in profile.services where service.enabled {
            guard let endpoint = try resolveTunnelEndpoint(for: service, profile: profile, store: store) else {
                throw ValidationError("Profile '\(profile.name)' uses service tunnels but its server is local. Choose an SSH server or override the service server.")
            }
            grouped[endpoint, default: []].append(service)
        }

        try bootoutAgents(profileName: profile.name, store: store)
        try store.ensureRuntimeDirectories()

        for (endpoint, services) in grouped {
            let label = store.launchAgentLabel(for: profile.name, serverName: endpoint.labelComponent)
            let plistURL = store.launchAgentPlistURL(for: label)

            var programArguments = [
                "/usr/bin/ssh",
                "-NT",
                "-o",
                "BatchMode=yes",
                "-o",
                "StrictHostKeyChecking=accept-new",
                "-o",
                "ExitOnForwardFailure=yes",
                "-o",
                "ServerAliveInterval=30",
                "-o",
                "ServerAliveCountMax=3",
                "-o",
                "ControlMaster=no",
            ]

            if endpoint.sshPort != 22 {
                programArguments.append(contentsOf: ["-p", String(endpoint.sshPort)])
            }

            for service in services.sorted(by: { $0.localPort < $1.localPort }) {
                programArguments.append(contentsOf: [
                    "-L",
                    "127.0.0.1:\(service.localPort):\(service.remoteHost):\(service.remotePort)",
                    "-L",
                    "[::1]:\(service.localPort):\(service.remoteHost):\(service.remotePort)",
                ])
            }

            programArguments.append(endpoint.sshTarget)

            let plistData: [String: Any] = [
                "Label": label,
                "ProgramArguments": programArguments,
                "RunAtLoad": true,
                "KeepAlive": true,
                "StandardOutPath": store.logsDirectory.appendingPathComponent("\(label).out.log").path,
                "StandardErrorPath": store.logsDirectory.appendingPathComponent("\(label).err.log").path,
                "ProcessType": "Background",
            ]

            let encoded = try PropertyListSerialization.data(
                fromPropertyList: plistData,
                format: .xml,
                options: 0
            )
            try encoded.write(to: plistURL, options: .atomic)

            let lint = Shell.run("/usr/bin/plutil", arguments: ["-lint", plistURL.path])
            guard lint.exitCode == 0 else {
                throw ValidationError(nonEmpty(lint.stderr) ?? nonEmpty(lint.stdout) ?? "launchd plist validation failed")
            }

            let bootstrap = Shell.run(
                "/bin/launchctl",
                arguments: ["bootstrap", "gui/\(getuid())", plistURL.path]
            )
            guard bootstrap.exitCode == 0 else {
                throw ValidationError(nonEmpty(bootstrap.stderr) ?? nonEmpty(bootstrap.stdout) ?? "Failed to bootstrap launch agent")
            }

            let kickstart = Shell.run(
                "/bin/launchctl",
                arguments: ["kickstart", "-k", store.launchTarget(for: label)]
            )
            guard kickstart.exitCode == 0 else {
                throw ValidationError(nonEmpty(kickstart.stderr) ?? nonEmpty(kickstart.stdout) ?? "Failed to start launch agent")
            }
        }
    }

    private static func bootoutAgents(profileName: String, store: ProfileStore) throws {
        let plistURLs = store.launchAgentPlistURLs(for: profileName)

        for plistURL in plistURLs {
            let label = plistURL.deletingPathExtension().lastPathComponent
            _ = Shell.run(
                "/bin/launchctl",
                arguments: ["bootout", store.launchTarget(for: label)]
            )
            try? FileManager.default.removeItem(at: plistURL)
        }
    }

    private static func agentLoaded(profileName: String, store: ProfileStore) -> Bool {
        for plistURL in store.launchAgentPlistURLs(for: profileName) {
            let label = plistURL.deletingPathExtension().lastPathComponent
            let result = Shell.run(
                "/bin/launchctl",
                arguments: ["print", store.launchTarget(for: label)]
            )
            if result.exitCode == 0 {
                return true
            }
        }
        return false
    }

    private static func prepareManagedLocalDataDirectories(profile: ProfileDefinition, store: ProfileStore) throws {
        let rewrite = rewriteManagedDataMounts(
            in: profile.compose.content,
            dataRootPath: store.profileDataDirectory(for: profile).path
        )

        guard !rewrite.serviceNames.isEmpty else {
            return
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: store.profileDataDirectory(for: profile), withIntermediateDirectories: true)
        for serviceName in rewrite.serviceNames {
            try fileManager.createDirectory(
                at: store.serviceDataDirectory(for: profile, serviceName: serviceName),
                withIntermediateDirectories: true
            )
        }
    }

    private static func syncProfileDataDirectory(
        profile: ProfileDefinition,
        store: ProfileStore,
        server: RemoteServerDefinition
    ) throws {
        let remoteProjectDirectory = server.remoteProfileDirectory(for: profile.name)
        let remoteDataDirectory = server.remoteProfileDataDirectory(for: profile.name)
        let prepareScript = """
        set -eu
        mkdir -p \(shellQuote(remoteProjectDirectory))
        rm -rf \(shellQuote(remoteDataDirectory))
        mkdir -p \(shellQuote(remoteDataDirectory))
        """
        let prepareResult = runRemoteShell(on: server, script: prepareScript)
        guard prepareResult.exitCode == 0 else {
            throw ValidationError(nonEmpty(prepareResult.stderr) ?? nonEmpty(prepareResult.stdout) ?? "Failed to prepare remote data directory")
        }

        let localDataDirectory = store.profileDataDirectory(for: profile)
        let tarCommand = shellCommand(
            executable: "/usr/bin/tar",
            arguments: ["-C", localDataDirectory.path, "-cf", "-", "."]
        )
        let remoteExtractCommand = shellCommand(
            executable: "/usr/bin/ssh",
            arguments: sshArguments(for: server) + ["/usr/bin/tar", "--no-same-owner", "-xf", "-", "-C", remoteDataDirectory]
        )
        let syncCommand = "set -euo pipefail; COPYFILE_DISABLE=1 \(tarCommand) | \(remoteExtractCommand)"
        let syncResult = runLocalShell(syncCommand)
        guard syncResult.exitCode == 0 else {
            throw ValidationError(nonEmpty(syncResult.stderr) ?? nonEmpty(syncResult.stdout) ?? "Failed to sync profile data to remote server")
        }
    }

    private static func removeRemoteProfileDirectory(profile: ProfileDefinition, server: RemoteServerDefinition) throws {
        let removeScript = """
        set -eu
        rm -rf \(shellQuote(server.remoteProfileDirectory(for: profile.name)))
        """
        let result = runRemoteShell(on: server, script: removeScript)
        guard result.exitCode == 0 else {
            throw ValidationError(nonEmpty(result.stderr) ?? nonEmpty(result.stdout) ?? "Failed to remove remote profile data")
        }
    }

    private static func removeManagedLocalData(profile: ProfileDefinition, store: ProfileStore) throws {
        let fileManager = FileManager.default
        let dataRoot = store.profileDataDirectory(for: profile)
        let rewrite = rewriteManagedDataMounts(in: profile.compose.content, dataRootPath: dataRoot.path)

        for serviceName in rewrite.serviceNames {
            let directory = store.serviceDataDirectory(for: profile, serviceName: serviceName)
            if fileManager.fileExists(atPath: directory.path) {
                try? fileManager.removeItem(at: directory)
            }
        }

        if fileManager.fileExists(atPath: dataRoot.path),
           (try? fileManager.contentsOfDirectory(atPath: dataRoot.path).isEmpty) == true
        {
            try? fileManager.removeItem(at: dataRoot)
        }
    }

    private static func rewriteManagedDataMounts(in content: String, dataRootPath: String) -> ManagedDataRewriteResult {
        enum ParserState {
            case outside
            case inServices(servicesIndent: Int)
        }

        let lines = content.components(separatedBy: .newlines)
        var state = ParserState.outside
        var serviceIndent: Int?
        var currentServiceName: String?
        var currentServiceIndent = 0
        var insideVolumes = false
        var volumesIndent = 0
        var serviceNames = Set<String>()
        var rewrittenLines: [String] = []

        func startService(named name: String, indent: Int) {
            currentServiceName = name
            currentServiceIndent = indent
            insideVolumes = false
            volumesIndent = 0
        }

        for rawLine in lines {
            let indent = rawLine.prefix { $0 == " " || $0 == "\t" }.count
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            var line = rawLine

            switch state {
            case .outside:
                if trimmed == "services:" {
                    state = .inServices(servicesIndent: indent)
                    serviceIndent = nil
                }
            case let .inServices(servicesIndent):
                if indent <= servicesIndent && trimmed != "services:" {
                    currentServiceName = nil
                    insideVolumes = false
                    serviceIndent = nil
                    state = .outside
                    if trimmed == "services:" {
                        state = .inServices(servicesIndent: indent)
                    }
                } else {
                    if trimmed.hasSuffix(":") && !trimmed.hasPrefix("-") && indent > servicesIndent {
                        let candidateName = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
                        if let serviceIndent {
                            if indent == serviceIndent {
                                startService(named: candidateName, indent: indent)
                            }
                        } else {
                            serviceIndent = indent
                            startService(named: candidateName, indent: indent)
                        }
                    }

                    if let currentServiceName {
                        if indent <= currentServiceIndent {
                            insideVolumes = false
                        } else if trimmed == "volumes:" && indent > currentServiceIndent {
                            insideVolumes = true
                            volumesIndent = indent
                        } else if insideVolumes {
                            if indent <= volumesIndent {
                                insideVolumes = false
                            } else {
                                let shortSyntax = rewriteShortSyntaxDataMountLine(
                                    rawLine,
                                    serviceName: currentServiceName,
                                    dataRootPath: dataRootPath
                                )
                                let rewritten = rewriteKeyedDataMountLine(
                                    shortSyntax,
                                    serviceName: currentServiceName,
                                    keys: ["source", "device"],
                                    dataRootPath: dataRootPath
                                )
                                if rewritten != rawLine {
                                    serviceNames.insert(currentServiceName)
                                    line = rewritten
                                }
                            }
                        }
                    }
                }
            }

            rewrittenLines.append(line)
        }

        return ManagedDataRewriteResult(content: rewrittenLines.joined(separator: "\n"), serviceNames: serviceNames)
    }

    private static func rewriteShortSyntaxDataMountLine(
        _ line: String,
        serviceName: String,
        dataRootPath: String
    ) -> String {
        guard let dashIndex = line.firstIndex(of: "-") else {
            return line
        }

        let contentSlice = line[line.index(after: dashIndex)...]
        guard let valueStart = contentSlice.firstIndex(where: { !$0.isWhitespace }) else {
            return line
        }

        let prefix = String(line[..<valueStart])
        let rawValue = String(line[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let quote = rawValue.first.flatMap { first -> Character? in
            guard (first == "\"" || first == "'"), rawValue.last == first else {
                return nil
            }
            return first
        }
        let unwrapped = quote == nil ? rawValue : String(rawValue.dropFirst().dropLast())
        guard let colonIndex = unwrapped.firstIndex(of: ":") else {
            return line
        }

        let source = String(unwrapped[..<colonIndex])
        guard let rewrittenSource = managedDataSourcePath(
            serviceName: serviceName,
            source: source,
            dataRootPath: dataRootPath
        ) else {
            return line
        }

        let rewritten = rewrittenSource + String(unwrapped[colonIndex...])
        if let quote {
            return prefix + "\(quote)\(rewritten)\(quote)"
        }
        return prefix + rewritten
    }

    private static func rewriteKeyedDataMountLine(
        _ line: String,
        serviceName: String,
        keys: [String],
        dataRootPath: String
    ) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let key = keys.first(where: { trimmed.hasPrefix("\($0):") }) else {
            return line
        }

        guard let keyRange = line.range(of: "\(key):") else {
            return line
        }
        let valueRange = keyRange.upperBound..<line.endIndex
        guard let valueStart = line[valueRange].firstIndex(where: { !$0.isWhitespace }) else {
            return line
        }
        let rawValue = String(line[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let quote = rawValue.first.flatMap { first -> Character? in
            guard (first == "\"" || first == "'"), rawValue.last == first else {
                return nil
            }
            return first
        }
        let unwrapped = quote == nil ? rawValue : String(rawValue.dropFirst().dropLast())
        guard let rewrittenValue = managedDataSourcePath(
            serviceName: serviceName,
            source: unwrapped,
            dataRootPath: dataRootPath
        ) else {
            return line
        }

        let prefix = String(line[..<valueStart])
        if let quote {
            return prefix + "\(quote)\(rewrittenValue)\(quote)"
        }
        return prefix + rewrittenValue
    }

    private static func managedDataSourcePath(
        serviceName: String,
        source: String,
        dataRootPath: String
    ) -> String? {
        guard source == "./data" || source.hasPrefix("./data/") else {
            return nil
        }

        let normalizedRoot = dataRootPath.hasSuffix("/") ? String(dataRootPath.dropLast()) : dataRootPath
        let suffix = String(source.dropFirst("./data".count))
        return "\(normalizedRoot)/\(slugify(serviceName))\(suffix)"
    }

    private static func ensureDockerContextExists(named context: String) throws {
        let contexts = try dockerContexts()
        guard contexts.contains(where: { $0.name == context }) else {
            throw ValidationError("Docker context '\(context)' not found.")
        }
    }

    private static func upsertDockerContext(for server: RemoteServerDefinition) throws {
        guard !server.isLocal else {
            try ensureDockerContextExists(named: server.dockerContext)
            return
        }

        guard let dockerPath = ToolPaths.docker else {
            throw ValidationError("docker not found")
        }

        let inspect = Shell.run(dockerPath, arguments: ["context", "inspect", server.dockerContext])
        if inspect.exitCode == 0, inspect.stdout.contains(server.dockerEndpoint) {
            return
        }

        if inspect.exitCode == 0, (try? currentDockerContext()) == server.dockerContext {
            let fallback = (try? dockerContexts().first(where: { $0.name != server.dockerContext })?.name) ?? "default"
            _ = Shell.run(dockerPath, arguments: ["context", "use", fallback])
        }

        _ = Shell.run(dockerPath, arguments: ["context", "rm", "-f", server.dockerContext])
        let create = Shell.run(
            dockerPath,
            arguments: ["context", "create", server.dockerContext, "--docker", "host=\(server.dockerEndpoint)"]
        )
        guard create.exitCode == 0 else {
            throw ValidationError(nonEmpty(create.stderr) ?? nonEmpty(create.stdout) ?? "Failed to create docker context")
        }
    }

    private static func dockerInfo(context: String) throws -> String {
        guard let dockerPath = ToolPaths.docker else {
            throw ValidationError("docker not found")
        }

        let result = Shell.run(dockerPath, arguments: ["--context", context, "info", "--format", "{{.ServerVersion}}"])
        guard result.exitCode == 0 else {
            throw ValidationError(nonEmpty(result.stderr) ?? nonEmpty(result.stdout) ?? "Failed to query docker info")
        }

        return nonEmpty(result.stdout) ?? "unknown"
    }

    private static func inspect(server: RemoteServerDefinition) throws -> RemoteServerInspection {
        let script = """
        set -eu
        if [ -f /etc/os-release ]; then
          . /etc/os-release
        fi
        printf 'os=%s\n' "${PRETTY_NAME:-unknown}"
        if command -v docker >/dev/null 2>&1; then
          printf 'docker_present=yes\n'
          printf 'docker_version=%s\n' "$(docker --version 2>/dev/null | tr '\n' ' ')"
          printf 'server_version=%s\n' "$(docker info --format '{{.ServerVersion}}' 2>/dev/null || true)"
        else
          printf 'docker_present=no\n'
          printf 'docker_version=\n'
          printf 'server_version=\n'
        fi
        """

        let result = runRemoteShell(on: server, script: script)
        guard result.exitCode == 0 else {
            throw ValidationError(nonEmpty(result.stderr) ?? nonEmpty(result.stdout) ?? "Failed to connect to \(server.remoteDockerServerDisplay)")
        }

        let values = parseKeyValueOutput(result.stdout)
        return RemoteServerInspection(
            remoteOS: values["os"] ?? "unknown",
            dockerPresent: values["docker_present"] == "yes",
            dockerVersion: values["docker_version"] ?? "",
            serverVersion: values["server_version"] ?? ""
        )
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

        let result = runRemoteShell(on: server, script: script)
        guard result.exitCode == 0 else {
            throw ValidationError(nonEmpty(result.stderr) ?? nonEmpty(result.stdout) ?? "Failed to bootstrap Docker on \(server.remoteDockerServerDisplay)")
        }
    }

    private static func runRemoteShell(on server: RemoteServerDefinition, script: String) -> CommandResult {
        var arguments = sshArguments(for: server)
        arguments.append(contentsOf: ["/bin/sh", "-s", "--"])
        return Shell.run(
            "/usr/bin/ssh",
            arguments: arguments,
            standardInput: Data(script.utf8)
        )
    }

    private static func sshArguments(for server: RemoteServerDefinition) -> [String] {
        var arguments = [
            "-o",
            "BatchMode=yes",
            "-o",
            "StrictHostKeyChecking=accept-new",
            "-o",
            "ConnectTimeout=5",
        ]
        if server.sshPort != 22 {
            arguments.append(contentsOf: ["-p", String(server.sshPort)])
        }
        arguments.append(server.sshTarget)
        return arguments
    }

    private static func runLocalShell(_ command: String) -> CommandResult {
        Shell.run("/bin/sh", arguments: ["-lc", command])
    }

    private static func shellCommand(executable: String, arguments: [String]) -> String {
        ([executable] + arguments).map(shellQuote).joined(separator: " ")
    }

    private static func parseKeyValueOutput(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let string = String(line)
            guard let separator = string.firstIndex(of: "=") else {
                continue
            }
            let key = String(string[..<separator])
            let value = String(string[string.index(after: separator)...])
            result[key] = value
        }
        return result
    }

    private static func portListening(_ port: Int) -> Bool {
        guard port > 0 else {
            return false
        }

        let result = Shell.run(
            "/usr/sbin/lsof",
            arguments: ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"]
        )
        return result.exitCode == 0
    }

    private static func serviceURL(service: ServiceDefinition) -> String {
        let host = service.aliasHost
        let port = service.localPort

        switch service.role {
        case "postgres":
            return "postgresql://\(host):\(port)"
        case "redis":
            return "redis://\(host):\(port)"
        case "https":
            return "https://\(host)"
        case "http":
            return "http://\(host):\(port)"
        case "minio":
            return "http://\(host):\(port)"
        default:
            return "\(host):\(port)"
        }
    }

    private static func shellQuote(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
