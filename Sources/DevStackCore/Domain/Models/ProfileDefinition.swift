import Foundation

package struct ProfileDefinition: Codable, Equatable, Sendable {
    package var name = ""
    package var runtimeName = ""
    package var dockerContext = "default"
    package var tunnelHost = "docker"
    package var shellExports: [String] = []
    package var externalEnvironmentKeys: [String] = []
    package var services: [ServiceDefinition] = []
    package var compose = ComposeDefinition()

    package var serverName: String {
        get { runtimeName }
        set { runtimeName = newValue }
    }

    package var remoteDockerServer: String {
        get { tunnelHost }
        set { tunnelHost = newValue }
    }

    package func normalized() throws -> ProfileDefinition {
        var copy = self
        copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.runtimeName = copy.runtimeName.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.dockerContext = trimmedOrDefault(copy.dockerContext, defaultValue: "default")
        copy.tunnelHost = trimmedOrDefault(copy.tunnelHost, defaultValue: "docker")
        copy.compose.projectName = copy.compose.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.compose.workingDirectory = copy.compose.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.compose.sourceFile = copy.compose.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.compose.additionalSourceFiles = copy.compose.additionalSourceFiles
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        copy.shellExports = copy.shellExports
            .map { $0.trimmingCharacters(in: .newlines) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        copy.externalEnvironmentKeys = Array(
            Set(
                copy.externalEnvironmentKeys
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        guard !copy.name.isEmpty else {
            throw ValidationError("Profile name is required.")
        }

        if copy.compose.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            copy.compose.content = ""
            copy.compose.sourceFile = ""
            copy.compose.additionalSourceFiles = []
            if copy.compose.autoDownOnSwitch || copy.compose.autoUpOnActivate {
                throw ValidationError("Compose auto-actions require docker-compose content.")
            }
        } else if copy.compose.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            copy.compose.projectName = slugify(copy.name)
        }

        if copy.compose.sourceFile.isEmpty, let firstOverlay = copy.compose.additionalSourceFiles.first {
            copy.compose.sourceFile = firstOverlay
            copy.compose.additionalSourceFiles.removeFirst()
        }

        if !copy.compose.sourceFile.isEmpty {
            let sourcePath = NSString(string: copy.compose.sourceFile).expandingTildeInPath
            copy.compose.sourceFile = sourcePath
            copy.compose.workingDirectory = URL(fileURLWithPath: sourcePath, isDirectory: false)
                .deletingLastPathComponent()
                .path
        } else if !copy.compose.workingDirectory.isEmpty {
            copy.compose.workingDirectory = NSString(string: copy.compose.workingDirectory).expandingTildeInPath
        }

        let composeBaseDirectory = !copy.compose.sourceFile.isEmpty
            ? URL(fileURLWithPath: copy.compose.sourceFile, isDirectory: false).deletingLastPathComponent()
            : (
                copy.compose.workingDirectory.isEmpty
                    ? nil
                    : URL(fileURLWithPath: copy.compose.workingDirectory, isDirectory: true)
            )

        var normalizedAdditionalSourceFiles: [String] = []
        for path in copy.compose.additionalSourceFiles {
            let expanded = NSString(string: path).expandingTildeInPath
            let resolvedURL: URL
            if expanded.hasPrefix("/") {
                resolvedURL = URL(fileURLWithPath: expanded, isDirectory: false)
            } else if let composeBaseDirectory {
                resolvedURL = composeBaseDirectory.appendingPathComponent(expanded, isDirectory: false)
            } else {
                resolvedURL = URL(fileURLWithPath: expanded, isDirectory: false)
            }

            let normalizedPath = resolvedURL.standardizedFileURL.path
            guard normalizedPath != copy.compose.sourceFile else {
                continue
            }
            if !normalizedAdditionalSourceFiles.contains(normalizedPath) {
                normalizedAdditionalSourceFiles.append(normalizedPath)
            }
        }
        copy.compose.additionalSourceFiles = normalizedAdditionalSourceFiles

        var seenNames = Set<String>()
        var seenPorts = Set<Int>()
        copy.services = try copy.services.map { try normalize(service: $0) }

        for service in copy.services where service.enabled {
            guard !seenNames.contains(service.name) else {
                throw ValidationError("Duplicate service name: \(service.name)")
            }
            seenNames.insert(service.name)

            guard !seenPorts.contains(service.localPort) else {
                throw ValidationError("Duplicate local port inside one profile: \(service.localPort)")
            }
            seenPorts.insert(service.localPort)
        }

        return copy
    }

    package init() {}

    package init(
        name: String = "",
        serverName: String = "",
        dockerContext: String = "default",
        tunnelHost: String = "docker",
        shellExports: [String] = [],
        externalEnvironmentKeys: [String] = [],
        services: [ServiceDefinition] = [],
        compose: ComposeDefinition = ComposeDefinition()
    ) {
        self.name = name
        runtimeName = serverName
        self.dockerContext = dockerContext
        self.tunnelHost = tunnelHost
        self.shellExports = shellExports
        self.externalEnvironmentKeys = externalEnvironmentKeys
        self.services = services
        self.compose = compose
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        runtimeName =
            try container.decodeIfPresent(String.self, forKey: .runtimeName)
            ?? container.decodeIfPresent(String.self, forKey: .serverName)
            ?? ""
        dockerContext = try container.decodeIfPresent(String.self, forKey: .dockerContext) ?? "default"
        tunnelHost = try container.decodeIfPresent(String.self, forKey: .tunnelHost) ?? "docker"
        shellExports = try container.decodeIfPresent([String].self, forKey: .shellExports) ?? []
        externalEnvironmentKeys = try container.decodeIfPresent([String].self, forKey: .externalEnvironmentKeys) ?? []
        services = try container.decodeIfPresent([ServiceDefinition].self, forKey: .services) ?? []
        compose = try container.decodeIfPresent(ComposeDefinition.self, forKey: .compose) ?? ComposeDefinition()
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(runtimeName, forKey: .runtimeName)
        try container.encode(dockerContext, forKey: .dockerContext)
        try container.encode(tunnelHost, forKey: .tunnelHost)
        try container.encode(shellExports, forKey: .shellExports)
        try container.encode(externalEnvironmentKeys, forKey: .externalEnvironmentKeys)
        try container.encode(services, forKey: .services)
        try container.encode(compose, forKey: .compose)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case runtimeName
        case serverName
        case dockerContext
        case tunnelHost
        case shellExports
        case externalEnvironmentKeys
        case services
        case compose
    }

    private func normalize(service: ServiceDefinition) throws -> ServiceDefinition {
        var copy = service
        copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.role = trimmedOrDefault(copy.role, defaultValue: "generic")
        copy.aliasHost = trimmedOrDefault(copy.aliasHost, defaultValue: "\(slugify(copy.name)).localhost")
        copy.remoteHost = trimmedOrDefault(copy.remoteHost, defaultValue: "127.0.0.1")
        copy.tunnelHost = copy.tunnelHost.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.envPrefix = trimmedOrDefault(copy.envPrefix, defaultValue: slugify(copy.name).uppercased())
        copy.extraExports = copy.extraExports
            .map { $0.trimmingCharacters(in: .newlines) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !copy.name.isEmpty else {
            throw ValidationError("Every service must have a name.")
        }

        if copy.enabled {
            guard copy.localPort > 0 else {
                throw ValidationError("Service '\(copy.name)' must have a local port.")
            }
        }

        if copy.remotePort <= 0 {
            copy.remotePort = copy.localPort
        }

        if copy.remotePort <= 0 {
            throw ValidationError("Service '\(copy.name)' must have a remote port.")
        }

        if copy.tunnelHost.isEmpty {
            copy.tunnelHost = ""
        }

        return copy
    }
}
