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
