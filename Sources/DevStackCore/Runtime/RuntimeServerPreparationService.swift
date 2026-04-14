import Foundation

enum RuntimeServerPreparationService {
    static func prepareServer(
        server: RemoteServerDefinition,
        store _: ProfileStore,
        bootstrapIfNeeded: Bool
    ) throws -> RemoteServerPreparationResult {
        let normalizedServer = try server.normalized()

        if normalizedServer.isLocal {
            try RuntimeSharedSupport.ensureDockerContextExists(named: normalizedServer.dockerContext)
            let serverVersion = try RuntimeSharedSupport.dockerInfo(context: normalizedServer.dockerContext)
            return RemoteServerPreparationResult(
                server: normalizedServer,
                remoteOS: "macOS local",
                dockerVersion: "docker context \(normalizedServer.dockerContext)",
                serverVersion: serverVersion
            )
        }

        let firstInspection = try RuntimeSharedSupport.inspect(server: normalizedServer)
        if !firstInspection.dockerPresent {
            guard bootstrapIfNeeded else {
                throw ValidationError("Docker is not installed on \(normalizedServer.remoteDockerServerDisplay).")
            }
            try bootstrapRemoteDocker(on: normalizedServer)
        }

        let finalInspection = try RuntimeSharedSupport.inspect(server: normalizedServer)
        guard finalInspection.dockerPresent else {
            throw ValidationError("Docker is still missing on \(normalizedServer.remoteDockerServerDisplay) after bootstrap.")
        }

        try RuntimeSharedSupport.upsertDockerContext(for: normalizedServer)
        let serverVersion = try RuntimeSharedSupport.dockerInfo(context: normalizedServer.dockerContext)

        return RemoteServerPreparationResult(
            server: normalizedServer,
            remoteOS: finalInspection.remoteOS,
            dockerVersion: finalInspection.dockerVersion,
            serverVersion: serverVersion
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

        let result = RuntimeSharedSupport.runRemoteShell(on: server, script: script)
        guard result.exitCode == 0 else {
            throw ValidationError(
                RuntimeSharedSupport.nonEmpty(result.stderr)
                    ?? RuntimeSharedSupport.nonEmpty(result.stdout)
                    ?? "Failed to bootstrap Docker on \(server.remoteDockerServerDisplay)"
            )
        }
    }
}
