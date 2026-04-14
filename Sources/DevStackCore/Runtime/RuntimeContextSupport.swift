import Foundation

enum RuntimeContextSupport {
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
}

private extension RuntimeContextSupport {
    static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
