import Foundation

struct RemoteServerInspection: Sendable {
    let remoteOS: String
    let dockerPresent: Bool
    let dockerVersion: String
    let serverVersion: String
}

struct ResolvedServer: Sendable {
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

enum RuntimeSharedSupport {
    static func dockerContexts() throws -> [DockerContextEntry] {
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

    static func currentDockerContext() throws -> String {
        guard let dockerPath = ToolPaths.docker else {
            throw ValidationError("docker not found")
        }

        let result = Shell.run(dockerPath, arguments: ["context", "show"])
        guard result.exitCode == 0 else {
            throw ValidationError(nonEmpty(result.stderr) ?? nonEmpty(result.stdout) ?? "Failed to read docker context")
        }

        return nonEmpty(result.stdout) ?? "unknown"
    }

    static func resolvePrimaryServer(for profile: ProfileDefinition, store: ProfileStore) throws -> ResolvedServer {
        if !profile.serverName.isEmpty {
            return try ResolvedServer(server: store.loadServer(named: profile.serverName))
        }
        return ResolvedServer(legacyProfile: profile)
    }

    static func resolveServerDefinition(for profile: ProfileDefinition, store: ProfileStore) throws -> RemoteServerDefinition? {
        guard !profile.serverName.isEmpty else {
            return nil
        }
        return try store.loadServer(named: profile.serverName)
    }

    static func composePS(profile: ProfileDefinition, store: ProfileStore) throws -> [ComposeRuntimeService] {
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

    static func runCompose(
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

    static func composeVolumes(profile: ProfileDefinition, store: ProfileStore) throws -> [ComposeVolumeRecord] {
        guard let dockerPath = ToolPaths.docker else {
            throw ValidationError("docker not found")
        }

        let projectName = ComposePlanBuilder.composeProjectName(for: profile)
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

    static func composeContainerIDs(profile: ProfileDefinition, store: ProfileStore) throws -> [String] {
        let result = runCompose(profile: profile, store: store, subcommand: ["ps", "-q"])
        guard result.exitCode == 0 else {
            throw ValidationError(nonEmpty(result.stderr) ?? nonEmpty(result.stdout) ?? "Failed to list compose containers")
        }

        return result.stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func inspect(server: RemoteServerDefinition) throws -> RemoteServerInspection {
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

    static func ensureDockerContextExists(named context: String) throws {
        let contexts = try dockerContexts()
        guard contexts.contains(where: { $0.name == context }) else {
            throw ValidationError("Docker context '\(context)' not found.")
        }
    }

    static func upsertDockerContext(for server: RemoteServerDefinition) throws {
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

    static func dockerInfo(context: String) throws -> String {
        guard let dockerPath = ToolPaths.docker else {
            throw ValidationError("docker not found")
        }

        let result = Shell.run(dockerPath, arguments: ["--context", context, "info", "--format", "{{.ServerVersion}}"])
        guard result.exitCode == 0 else {
            throw ValidationError(nonEmpty(result.stderr) ?? nonEmpty(result.stdout) ?? "Failed to query docker info")
        }

        return nonEmpty(result.stdout) ?? "unknown"
    }

    static func runRemoteShell(on server: RemoteServerDefinition, script: String) -> CommandResult {
        var arguments = sshArguments(for: server)
        arguments.append(contentsOf: ["/bin/sh", "-s", "--"])
        return Shell.run(
            "/usr/bin/ssh",
            arguments: arguments,
            standardInput: Data(script.utf8)
        )
    }

    static func sshArguments(for server: RemoteServerDefinition) -> [String] {
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

    static func runLocalShell(_ command: String) -> CommandResult {
        Shell.run("/bin/sh", arguments: ["-lc", command])
    }

    static func shellCommand(executable: String, arguments: [String]) -> String {
        ([executable] + arguments).map(shellQuote).joined(separator: " ")
    }

    static func parseKeyValueOutput(_ output: String) -> [String: String] {
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

    static func serviceURL(service: ServiceDefinition) -> String {
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

    static func shellQuote(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
