import Foundation

enum RuntimeProfileHooksService {
    static func runProfileHooks(_ hookName: String, profile: ProfileDefinition, store: ProfileStore) throws {
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

    static func projectIdentity(for profile: ProfileDefinition, store: ProfileStore) -> String {
        if let directory = store.managedProjectDirectory(for: profile) {
            return directory.standardizedFileURL.path
        }

        let workingDirectory = profile.compose.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !workingDirectory.isEmpty {
            return URL(fileURLWithPath: workingDirectory).standardizedFileURL.path
        }

        return "profile:\(profile.name)"
    }

    static func isProfileRuntimeActive(profile: ProfileDefinition, store: ProfileStore) throws -> Bool {
        if TunnelService.agentLoaded(profileName: profile.name, store: store) {
            return true
        }

        if profile.compose.configured {
            let running = try RuntimeSharedSupport.composePS(profile: profile, store: store)
            return !running.isEmpty
        }

        return false
    }
}

