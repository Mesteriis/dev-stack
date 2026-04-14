import Foundation

package enum RemoteServerTransport: String, CaseIterable, Codable, Sendable {
    case ssh
    case local

    package var title: String {
        switch self {
        case .ssh:
            return "Remote SSH Runtime"
        case .local:
            return "Local Docker Context"
        }
    }

    package var summary: String {
        switch self {
        case .ssh:
            return "Use Docker on a remote host over SSH and create a managed runtime target for it."
        case .local:
            return "Use an existing local Docker context on this Mac without SSH tunnels."
        }
    }
}

package struct RemoteServerDefinition: Codable, Equatable, Sendable {
    package var name = ""
    package var transport: RemoteServerTransport = .ssh
    package var dockerContext = ""
    package var sshHost = ""
    package var sshPort = 22
    package var sshUser = "root"
    package var remoteDataRoot = "/var/lib/devstackmenu"

    package var isLocal: Bool {
        transport == .local
    }

    package var sshTarget: String {
        guard !isLocal else {
            return ""
        }
        return "\(sshUser)@\(sshHost)"
    }

    package var dockerEndpoint: String {
        guard !isLocal else {
            return ""
        }
        let portSuffix = sshPort == 22 ? "" : ":\(sshPort)"
        return "ssh://\(sshUser)@\(sshHost)\(portSuffix)"
    }

    package var remoteDockerServerDisplay: String {
        guard !isLocal else {
            return "local"
        }
        return sshPort == 22 ? sshTarget : "\(sshTarget):\(sshPort)"
    }

    package var connectionSummary: String {
        switch transport {
        case .local:
            return "Local runtime on \(dockerContext)"
        case .ssh:
            return "\(remoteDockerServerDisplay) via \(dockerContext)"
        }
    }

    package func remoteProfileDirectory(for profileName: String) -> String {
        let root = remoteDataRoot.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "/\(root)/profiles/\(slugify(profileName))"
    }

    package func remoteProfileDataDirectory(for profileName: String) -> String {
        "\(remoteProfileDirectory(for: profileName))/data"
    }

    package func remoteProfileProjectDirectory(for profileName: String) -> String {
        "\(remoteProfileDirectory(for: profileName))/project"
    }

    package func normalized() throws -> RemoteServerDefinition {
        var copy = self
        copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.dockerContext = copy.dockerContext.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.sshHost = copy.sshHost.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.sshUser = copy.sshUser.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.remoteDataRoot = copy.remoteDataRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.sshPort = copy.sshPort > 0 ? copy.sshPort : 22

        guard !copy.name.isEmpty else {
            throw ValidationError("Runtime name is required.")
        }

        switch copy.transport {
        case .local:
            copy.dockerContext = trimmedOrDefault(copy.dockerContext, defaultValue: "default")
            copy.sshHost = ""
            copy.sshUser = ""
            copy.sshPort = 22
            copy.remoteDataRoot = ""
        case .ssh:
            guard !copy.sshHost.isEmpty else {
                throw ValidationError("Remote server host is required.")
            }
            copy.sshUser = trimmedOrDefault(copy.sshUser, defaultValue: "root")
            copy.remoteDataRoot = trimmedOrDefault(copy.remoteDataRoot, defaultValue: "/var/lib/devstackmenu")
            if copy.dockerContext.isEmpty {
                copy.dockerContext = "srv-\(slugify(copy.name))"
            }
        }

        return copy
    }

    package init() {}

    package init(
        name: String = "",
        transport: RemoteServerTransport = .ssh,
        dockerContext: String = "",
        sshHost: String = "",
        sshPort: Int = 22,
        sshUser: String = "root",
        remoteDataRoot: String = "/var/lib/devstackmenu"
    ) {
        self.name = name
        self.transport = transport
        self.dockerContext = dockerContext
        self.sshHost = sshHost
        self.sshPort = sshPort
        self.sshUser = sshUser
        self.remoteDataRoot = remoteDataRoot
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        transport = try container.decodeIfPresent(RemoteServerTransport.self, forKey: .transport) ?? .ssh
        dockerContext = try container.decodeIfPresent(String.self, forKey: .dockerContext) ?? ""
        sshHost = try container.decodeIfPresent(String.self, forKey: .sshHost) ?? ""
        sshPort = try container.decodeIfPresent(Int.self, forKey: .sshPort) ?? 22
        sshUser = try container.decodeIfPresent(String.self, forKey: .sshUser) ?? "root"
        remoteDataRoot = try container.decodeIfPresent(String.self, forKey: .remoteDataRoot) ?? "/var/lib/devstackmenu"
    }
}
