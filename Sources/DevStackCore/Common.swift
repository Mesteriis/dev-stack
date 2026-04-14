import Foundation

package struct DockerContextEntry: Sendable {
    package let name: String
    package let endpoint: String
    package let isCurrent: Bool
}

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

    var summary: String {
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

    var dockerEndpoint: String {
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

    func remoteProfileDirectory(for profileName: String) -> String {
        let root = remoteDataRoot.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "/\(root)/profiles/\(slugify(profileName))"
    }

    func remoteProfileDataDirectory(for profileName: String) -> String {
        "\(remoteProfileDirectory(for: profileName))/data"
    }

    func remoteProfileProjectDirectory(for profileName: String) -> String {
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

    init() {}

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

struct CommandResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

struct ComposeRuntimeService: Codable, Sendable {
    let Name: String?
    let Service: String?
    let State: String?
    let Status: String?

    var displayName: String {
        Service ?? Name ?? "service"
    }

    var displayStatus: String {
        Status ?? State ?? "unknown"
    }
}

struct ComposeRuntimeSnapshot: Codable, Sendable {
    let configured: Bool
    let projectName: String
    let workingDirectory: String
    let autoDownOnSwitch: Bool
    let autoUpOnActivate: Bool
    let runningServices: [ComposeRuntimeService]

    var localContainerMode: LocalContainerMode {
        LocalContainerMode(autoDownOnSwitch: autoDownOnSwitch, autoUpOnActivate: autoUpOnActivate)
    }
}

struct ServiceRuntimeSnapshot: Codable, Sendable {
    let name: String
    let role: String
    let aliasHost: String
    let localPort: Int
    let remoteHost: String
    let remotePort: Int
    let tunnelHost: String
    let envPrefix: String
    let enabled: Bool
    let listening: Bool
}

package struct AppSnapshot: Codable, Sendable {
    let profile: String
    let configuredDockerContext: String
    let activeDockerContext: String
    let tunnelLoaded: Bool
    let tunnelLabel: String
    let compose: ComposeRuntimeSnapshot
    let services: [ServiceRuntimeSnapshot]
}

struct ComposeDefinition: Codable, Equatable, Sendable {
    var projectName = ""
    var workingDirectory = ""
    var sourceFile = ""
    var additionalSourceFiles: [String] = []
    var autoDownOnSwitch = false
    var autoUpOnActivate = false
    var content = ""

    var configured: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var localContainerMode: LocalContainerMode {
        get {
            LocalContainerMode(autoDownOnSwitch: autoDownOnSwitch, autoUpOnActivate: autoUpOnActivate)
        }
        set {
            autoDownOnSwitch = newValue.autoDownOnSwitch
            autoUpOnActivate = newValue.autoUpOnActivate
        }
    }

    init() {}

    init(
        projectName: String = "",
        workingDirectory: String = "",
        sourceFile: String = "",
        additionalSourceFiles: [String] = [],
        autoDownOnSwitch: Bool = false,
        autoUpOnActivate: Bool = false,
        content: String = ""
    ) {
        self.projectName = projectName
        self.workingDirectory = workingDirectory
        self.sourceFile = sourceFile
        self.additionalSourceFiles = additionalSourceFiles
        self.autoDownOnSwitch = autoDownOnSwitch
        self.autoUpOnActivate = autoUpOnActivate
        self.content = content
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectName = try container.decodeIfPresent(String.self, forKey: .projectName) ?? ""
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory) ?? ""
        sourceFile = try container.decodeIfPresent(String.self, forKey: .sourceFile) ?? ""
        additionalSourceFiles = try container.decodeIfPresent([String].self, forKey: .additionalSourceFiles) ?? []
        autoDownOnSwitch = try container.decodeIfPresent(Bool.self, forKey: .autoDownOnSwitch) ?? false
        autoUpOnActivate = try container.decodeIfPresent(Bool.self, forKey: .autoUpOnActivate) ?? false
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
    }
}

package struct ServiceDefinition: Codable, Equatable, Sendable {
    var name = ""
    var role = "generic"
    var aliasHost = ""
    var localPort = 0
    var remoteHost = "127.0.0.1"
    var remotePort = 0
    var tunnelHost = ""
    var enabled = true
    var envPrefix = ""
    var extraExports: [String] = []

    var remoteServer: String {
        get { tunnelHost }
        set { tunnelHost = newValue }
    }
}

struct ManagedVariableDefinition: Codable, Equatable, Sendable {
    var name = ""
    var value = ""
    var profileNames: [String] = []

    func normalized() throws -> ManagedVariableDefinition {
        var copy = self
        copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !copy.name.isEmpty else {
            throw ValidationError("Variable name is required.")
        }

        guard copy.name.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
            throw ValidationError("Variable '\(copy.name)' is not a valid env variable name.")
        }

        var uniqueProfileNames: [String] = []
        for profileName in copy.profileNames.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !profileName.isEmpty {
            if !uniqueProfileNames.contains(profileName) {
                uniqueProfileNames.append(profileName)
            }
        }
        copy.profileNames = uniqueProfileNames.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        guard !copy.profileNames.isEmpty else {
            throw ValidationError("Variable '\(copy.name)' must be assigned to at least one profile.")
        }

        return copy
    }

    func applies(to profileName: String) -> Bool {
        profileNames.contains(profileName)
    }
}

package struct ProfileDefinition: Codable, Equatable, Sendable {
    package var name = ""
    package var runtimeName = ""
    package var dockerContext = "default"
    package var tunnelHost = "docker"
    var shellExports: [String] = []
    package var externalEnvironmentKeys: [String] = []
    package var services: [ServiceDefinition] = []
    var compose = ComposeDefinition()

    var serverName: String {
        get { runtimeName }
        set { runtimeName = newValue }
    }

    var remoteDockerServer: String {
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
        copy.services = try copy.services.map { try normalize(service: $0, profile: copy) }

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

    init() {}

    init(
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

    private func normalize(service: ServiceDefinition, profile: ProfileDefinition) throws -> ServiceDefinition {
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

        _ = profile
        return copy
    }
}

struct ValidationError: LocalizedError, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

enum LocalContainerMode: String, CaseIterable, Codable, Sendable {
    case manual
    case startOnActivate
    case stopOnSwitch
    case switchActive

    init(autoDownOnSwitch: Bool, autoUpOnActivate: Bool) {
        switch (autoDownOnSwitch, autoUpOnActivate) {
        case (false, false):
            self = .manual
        case (false, true):
            self = .startOnActivate
        case (true, false):
            self = .stopOnSwitch
        case (true, true):
            self = .switchActive
        }
    }

    var autoDownOnSwitch: Bool {
        switch self {
        case .manual, .startOnActivate:
            return false
        case .stopOnSwitch, .switchActive:
            return true
        }
    }

    var autoUpOnActivate: Bool {
        switch self {
        case .manual, .stopOnSwitch:
            return false
        case .startOnActivate, .switchActive:
            return true
        }
    }

    var title: String {
        switch self {
        case .manual:
            return "Manual"
        case .startOnActivate:
            return "Start On Activate"
        case .stopOnSwitch:
            return "Stop On Switch"
        case .switchActive:
            return "Switch Active Containers"
        }
    }

    var summary: String {
        switch self {
        case .manual:
            return "Do not manage local compose containers automatically."
        case .startOnActivate:
            return "Start this profile's local containers when the profile becomes active."
        case .stopOnSwitch:
            return "Stop this profile's local containers when switching away."
        case .switchActive:
            return "Keep one active local compose stack by stopping the previous profile and starting the new one."
        }
    }
}

private final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func set(_ data: Data) {
        lock.lock()
        self.data = data
        lock.unlock()
    }

    func get() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

enum ToolPaths {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    static let docker = resolve([
        "/usr/local/bin/docker",
        "/opt/homebrew/bin/docker",
        "\(home)/.orbstack/bin/docker",
    ])
    static let codex = resolve([
        "/usr/local/bin/codex",
        "/opt/homebrew/bin/codex",
    ])
    static let claude = resolve([
        "/usr/local/bin/claude",
        "/opt/homebrew/bin/claude",
    ])
    static let qwen = resolve([
        "/usr/local/bin/qwen",
        "/opt/homebrew/bin/qwen",
    ])
    static let gemini = resolve([
        "/usr/local/bin/gemini",
        "/opt/homebrew/bin/gemini",
    ])
    static let gcloud = resolve([
        "/usr/local/bin/gcloud",
        "/opt/homebrew/bin/gcloud",
    ])

    static func resolve(_ candidates: [String]) -> String? {
        let fileManager = FileManager.default
        if let directMatch = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return directMatch
        }

        let binaryNames = Set(candidates.map { URL(fileURLWithPath: $0).lastPathComponent })
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let fallbackEntries = ["/usr/bin", "/bin", "/usr/sbin", "/sbin", "/opt/homebrew/bin", "/usr/local/bin"]
        var searchPaths: [String] = []

        for entry in pathEntries + fallbackEntries where !searchPaths.contains(entry) {
            searchPaths.append(entry)
        }

        for directory in searchPaths {
            for binaryName in binaryNames {
                let candidate = URL(fileURLWithPath: directory).appendingPathComponent(binaryName).path
                if fileManager.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }

        return nil
    }
}

enum Shell {
    @discardableResult
    static func run(
        _ launchPath: String,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        standardInput: Data? = nil
    ) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        let stdinPipe = Pipe()
        if standardInput != nil {
            process.standardInput = stdinPipe
        }

        let stdoutQueue = DispatchQueue(label: "devstackmenu.shell.stdout")
        let stderrQueue = DispatchQueue(label: "devstackmenu.shell.stderr")
        let outputGroup = DispatchGroup()
        let stdoutBuffer = LockedDataBuffer()
        let stderrBuffer = LockedDataBuffer()

        do {
            try process.run()
        } catch {
            return CommandResult(
                exitCode: 127,
                stdout: "",
                stderr: error.localizedDescription
            )
        }

        if let standardInput {
            try? stdinPipe.fileHandleForWriting.write(contentsOf: standardInput)
            try? stdinPipe.fileHandleForWriting.close()
        }

        outputGroup.enter()
        stdoutQueue.async {
            stdoutBuffer.set(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
            outputGroup.leave()
        }

        outputGroup.enter()
        stderrQueue.async {
            stderrBuffer.set(stderrPipe.fileHandleForReading.readDataToEndOfFile())
            outputGroup.leave()
        }

        process.waitUntilExit()
        outputGroup.wait()

        let stdout = String(
            data: stdoutBuffer.get(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: stderrBuffer.get(),
            encoding: .utf8
        ) ?? ""

        return CommandResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}

package struct ProfileStore: Sendable {
    let rootDirectory: URL
    let profilesDirectory: URL
    let serversDirectory: URL
    let legacyServersDirectory: URL
    let managedVariablesFile: URL
    let currentProfileFile: URL
    let activeProfilesFile: URL
    let generatedDirectory: URL
    let logsDirectory: URL
    let launchAgentsDirectory: URL

    package init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support", isDirectory: true)
        self.init(
            rootDirectory: applicationSupport.appendingPathComponent("DevStackMenu", isDirectory: true),
            logsDirectory: home.appendingPathComponent("Library/Logs/DevStackMenu", isDirectory: true),
            launchAgentsDirectory: home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        )
    }

    init(rootDirectory: URL, logsDirectory: URL, launchAgentsDirectory: URL) {
        self.rootDirectory = rootDirectory
        profilesDirectory = rootDirectory.appendingPathComponent("profiles", isDirectory: true)
        serversDirectory = rootDirectory.appendingPathComponent("runtimes", isDirectory: true)
        legacyServersDirectory = rootDirectory.appendingPathComponent("servers", isDirectory: true)
        managedVariablesFile = rootDirectory.appendingPathComponent("managed-vars.json", isDirectory: false)
        currentProfileFile = rootDirectory.appendingPathComponent("current-profile", isDirectory: false)
        activeProfilesFile = rootDirectory.appendingPathComponent("active-profiles.json", isDirectory: false)
        generatedDirectory = rootDirectory.appendingPathComponent("generated", isDirectory: true)
        self.logsDirectory = logsDirectory
        self.launchAgentsDirectory = launchAgentsDirectory
    }

    var runtimesDirectory: URL {
        serversDirectory
    }

    func profileNames() throws -> [String] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: profilesDirectory.path) else {
            return []
        }

        let urls = try fileManager.contentsOfDirectory(
            at: profilesDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        return urls
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    package func loadProfile(named name: String) throws -> ProfileDefinition {
        let url = profileURL(named: name)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let profile = try decoder.decode(ProfileDefinition.self, from: data)
        return try profile.normalized()
    }

    func serverNames() throws -> [String] {
        let fileManager = FileManager.default
        var urls: [URL] = []

        if fileManager.fileExists(atPath: serversDirectory.path) {
            urls += try fileManager.contentsOfDirectory(
                at: serversDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        }

        if fileManager.fileExists(atPath: legacyServersDirectory.path) {
            urls += try fileManager.contentsOfDirectory(
                at: legacyServersDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        }

        return Set(urls
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
        )
        .sorted()
    }

    func remoteServers() throws -> [RemoteServerDefinition] {
        try serverNames().compactMap { try loadServer(named: $0) }
    }

    func loadServer(named name: String) throws -> RemoteServerDefinition {
        let url = preferredServerURL(named: name)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let server = try decoder.decode(RemoteServerDefinition.self, from: data)
        return try server.normalized()
    }

    package func saveProfile(_ profile: ProfileDefinition, originalName: String?) throws {
        let normalized = try profile.normalized()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)

        let targetURL = profileURL(named: normalized.name)
        let originalURL = originalName.map { profileURL(named: $0) }

        if originalName != normalized.name && fileManager.fileExists(atPath: targetURL.path) {
            throw ValidationError("Profile '\(normalized.name)' already exists.")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(normalized)
        try data.write(to: targetURL, options: .atomic)

        if let originalURL, originalURL != targetURL, fileManager.fileExists(atPath: originalURL.path) {
            try fileManager.removeItem(at: originalURL)
        }

        if let originalName, originalName != normalized.name {
            try renameManagedVariableProfileReferences(from: originalName, to: normalized.name)
        }
    }

    func saveServer(_ server: RemoteServerDefinition, originalName: String?) throws {
        let normalized = try server.normalized()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: serversDirectory, withIntermediateDirectories: true)

        let targetURL = serverURL(named: normalized.name)
        let originalURL = originalName.map { preferredServerURL(named: $0) }

        if originalName != normalized.name && fileManager.fileExists(atPath: targetURL.path) {
            throw ValidationError("Runtime '\(normalized.name)' already exists.")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(normalized)
        try data.write(to: targetURL, options: .atomic)

        if let originalURL, originalURL != targetURL, fileManager.fileExists(atPath: originalURL.path) {
            try fileManager.removeItem(at: originalURL)
        }

        let legacyURL = legacyServerURL(named: normalized.name)
        if fileManager.fileExists(atPath: legacyURL.path) {
            try? fileManager.removeItem(at: legacyURL)
        }
    }

    func deleteServer(named name: String) throws {
        let fileManager = FileManager.default
        for url in [serverURL(named: name), legacyServerURL(named: name)] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    func runtimeNames() throws -> [String] {
        try serverNames()
    }

    package func runtimeTargets() throws -> [RemoteServerDefinition] {
        try remoteServers()
    }

    func loadRuntime(named name: String) throws -> RemoteServerDefinition {
        try loadServer(named: name)
    }

    package func saveRuntime(_ runtime: RemoteServerDefinition, originalName: String?) throws {
        try saveServer(runtime, originalName: originalName)
    }

    func deleteRuntime(named name: String) throws {
        try deleteServer(named: name)
    }

    package func currentProfileName() -> String? {
        guard let text = try? String(contentsOf: currentProfileFile, encoding: .utf8) else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func saveCurrentProfile(_ name: String) throws {
        try ensureRuntimeDirectories()
        try "\(name)\n".write(to: currentProfileFile, atomically: true, encoding: .utf8)
    }

    func clearCurrentProfile() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: currentProfileFile.path) {
            try fileManager.removeItem(at: currentProfileFile)
        }
    }

    func activeProfileNames() -> [String] {
        guard let data = try? Data(contentsOf: activeProfilesFile),
              let names = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }

        return names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func saveActiveProfileNames(_ names: [String]) throws {
        try ensureRuntimeDirectories()
        var uniqueNames: [String] = []
        for name in names.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !name.isEmpty {
            if !uniqueNames.contains(name) {
                uniqueNames.append(name)
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(uniqueNames)
        try data.write(to: activeProfilesFile, options: .atomic)
    }

    func markProfileActive(_ name: String) throws {
        var names = activeProfileNames()
        if !names.contains(name) {
            names.append(name)
        }
        try saveActiveProfileNames(names)
    }

    func markProfileInactive(_ name: String) throws {
        let fileManager = FileManager.default
        let updated = activeProfileNames().filter { $0 != name }
        if updated.isEmpty {
            if fileManager.fileExists(atPath: activeProfilesFile.path) {
                try fileManager.removeItem(at: activeProfilesFile)
            }
            return
        }

        try saveActiveProfileNames(updated)
    }

    func managedVariables() throws -> [ManagedVariableDefinition] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: managedVariablesFile.path) else {
            return []
        }

        let data = try Data(contentsOf: managedVariablesFile)
        let decoder = JSONDecoder()
        let values = try decoder.decode([ManagedVariableDefinition].self, from: data)
        return try values
            .map { try $0.normalized() }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func saveManagedVariables(_ variables: [ManagedVariableDefinition]) throws {
        try ensureRuntimeDirectories()
        let normalized = try variables
            .map { try $0.normalized() }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if normalized.isEmpty {
            if FileManager.default.fileExists(atPath: managedVariablesFile.path) {
                try FileManager.default.removeItem(at: managedVariablesFile)
            }
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(normalized)
        try data.write(to: managedVariablesFile, options: .atomic)
    }

    func upsertManagedVariable(_ variable: ManagedVariableDefinition) throws {
        let normalized = try variable.normalized()
        var values = try managedVariables().filter { $0.name != normalized.name }
        values.append(normalized)
        try saveManagedVariables(values)
    }

    func deleteManagedVariable(named name: String) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = try managedVariables().filter { $0.name != trimmedName }
        try saveManagedVariables(updated)
    }

    func renameManagedVariableProfileReferences(from oldName: String, to newName: String) throws {
        guard oldName != newName else {
            return
        }

        var didChange = false
        let updated = try managedVariables().map { variable -> ManagedVariableDefinition in
            var copy = variable
            let replaced = copy.profileNames.map { $0 == oldName ? newName : $0 }
            if replaced != copy.profileNames {
                copy.profileNames = replaced
                didChange = true
            }
            return copy
        }

        if didChange {
            try saveManagedVariables(updated)
        }
    }

    func removeManagedVariableProfileReferences(for profileName: String) throws {
        var didChange = false
        let updated = try managedVariables().compactMap { variable -> ManagedVariableDefinition? in
            var copy = variable
            let filtered = copy.profileNames.filter { $0 != profileName }
            if filtered != copy.profileNames {
                didChange = true
            }
            copy.profileNames = filtered
            return filtered.isEmpty ? nil : copy
        }

        if didChange {
            try saveManagedVariables(updated)
        }
    }

    package func ensureRuntimeDirectories() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)
        try migrateLegacyServersDirectoryIfNeeded(fileManager: fileManager)
        try fileManager.createDirectory(at: serversDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: generatedDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
    }

    func profileURL(named name: String) -> URL {
        profilesDirectory.appendingPathComponent("\(name).json", isDirectory: false)
    }

    func composeFileURL(for profileName: String) -> URL {
        generatedDirectory
            .appendingPathComponent(profileName, isDirectory: true)
            .appendingPathComponent("docker-compose.generated.yml", isDirectory: false)
    }

    func generatedProfileDirectory(for profileName: String) -> URL {
        generatedDirectory.appendingPathComponent(profileName, isDirectory: true)
    }

    func generatedComposeSourceURL(for profileName: String) -> URL {
        generatedProfileDirectory(for: profileName)
            .appendingPathComponent("docker-compose.source.yml", isDirectory: false)
    }

    func generatedComposePlanURL(for profileName: String) -> URL {
        generatedProfileDirectory(for: profileName)
            .appendingPathComponent("compose-plan.txt", isDirectory: false)
    }

    func generatedComposeLogsURL(for profileName: String) -> URL {
        logsDirectory.appendingPathComponent("\(slugify(profileName)).compose.log", isDirectory: false)
    }

    func generatedVolumeReportURL(for profileName: String) -> URL {
        generatedProfileDirectory(for: profileName)
            .appendingPathComponent("volume-report.txt", isDirectory: false)
    }

    func generatedMetricsReportURL(for profileName: String) -> URL {
        generatedProfileDirectory(for: profileName)
            .appendingPathComponent("metrics-report.txt", isDirectory: false)
    }

    func generatedRemoteBrowseReportURL(for profileName: String) -> URL {
        generatedProfileDirectory(for: profileName)
            .appendingPathComponent("remote-files.txt", isDirectory: false)
    }

    func generatedSecretsEnvURL(for profileName: String) -> URL {
        generatedProfileDirectory(for: profileName)
            .appendingPathComponent("secrets.env", isDirectory: false)
    }

    func generatedManagedVariablesEnvURL(for profileName: String) -> URL {
        generatedProfileDirectory(for: profileName)
            .appendingPathComponent("managed-vars.env", isDirectory: false)
    }

    func sourceComposeURLs(for profile: ProfileDefinition) -> [URL] {
        var result: [URL] = []
        let paths = [profile.compose.sourceFile] + profile.compose.additionalSourceFiles

        for rawPath in paths {
            let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else {
                continue
            }

            let url = URL(
                fileURLWithPath: NSString(string: path).expandingTildeInPath,
                isDirectory: false
            ).standardizedFileURL

            if !result.contains(url) {
                result.append(url)
            }
        }

        return result
    }

    func sourceComposeURL(for profile: ProfileDefinition) -> URL? {
        sourceComposeURLs(for: profile).first
    }

    func managedProjectDirectory(for profile: ProfileDefinition) -> URL? {
        if let sourceComposeURL = sourceComposeURL(for: profile) {
            return sourceComposeURL.deletingLastPathComponent()
        }

        let path = profile.compose.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
    }

    func profileDataDirectory(for profile: ProfileDefinition) -> URL {
        if let projectDirectory = managedProjectDirectory(for: profile) {
            return projectDirectory.appendingPathComponent("data", isDirectory: true)
        }
        return generatedProfileDirectory(for: profile.name).appendingPathComponent("data", isDirectory: true)
    }

    func serviceDataDirectory(for profile: ProfileDefinition, serviceName: String) -> URL {
        profileDataDirectory(for: profile).appendingPathComponent(slugify(serviceName), isDirectory: true)
    }

    func serverURL(named name: String) -> URL {
        serversDirectory.appendingPathComponent("\(name).json", isDirectory: false)
    }

    func legacyServerURL(named name: String) -> URL {
        legacyServersDirectory.appendingPathComponent("\(name).json", isDirectory: false)
    }

    func launchAgentPrefix(for profileName: String) -> String {
        "local.devstackmenu.\(slugify(profileName))"
    }

    func launchAgentLabel(for profileName: String, serverName: String) -> String {
        "\(launchAgentPrefix(for: profileName)).\(slugify(serverName))"
    }

    func launchTarget(for label: String) -> String {
        "gui/\(getuid())/\(label)"
    }

    func launchAgentPlistURL(for label: String) -> URL {
        launchAgentsDirectory.appendingPathComponent("\(label).plist", isDirectory: false)
    }

    func launchAgentPlistURLs(for profileName: String) -> [URL] {
        let prefix = launchAgentPrefix(for: profileName)
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: launchAgentsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.filter {
            $0.lastPathComponent.hasPrefix(prefix + ".") && $0.pathExtension == "plist"
        }
    }

    private func preferredServerURL(named name: String) -> URL {
        let runtimeURL = serverURL(named: name)
        if FileManager.default.fileExists(atPath: runtimeURL.path) {
            return runtimeURL
        }
        return legacyServerURL(named: name)
    }

    private func migrateLegacyServersDirectoryIfNeeded(fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: legacyServersDirectory.path) else {
            return
        }

        try fileManager.createDirectory(at: serversDirectory, withIntermediateDirectories: true)
        let legacyURLs = try fileManager.contentsOfDirectory(
            at: legacyServersDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for legacyURL in legacyURLs where legacyURL.pathExtension == "json" {
            let targetURL = serversDirectory.appendingPathComponent(legacyURL.lastPathComponent, isDirectory: false)
            if fileManager.fileExists(atPath: targetURL.path) {
                continue
            }
            try fileManager.copyItem(at: legacyURL, to: targetURL)
        }
    }
}

func parseDockerContexts(from raw: String) -> [DockerContextEntry] {
    raw
        .split(whereSeparator: \.isNewline)
        .compactMap { line -> DockerContextEntry? in
            let parts = String(line).components(separatedBy: "\t")
            guard parts.count >= 3 else {
                return nil
            }
            return DockerContextEntry(
                name: parts[0],
                endpoint: parts[2],
                isCurrent: parts[1] == "*"
            )
        }
}

func slugify(_ value: String) -> String {
    let pattern = "[^A-Za-z0-9._-]+"
    let range = value.range(of: pattern, options: .regularExpression) ?? value.startIndex..<value.startIndex
    let replaced = value.replacingOccurrences(of: pattern, with: "-", options: .regularExpression)
    if !range.isEmpty || !replaced.isEmpty {
        return replaced.trimmingCharacters(in: CharacterSet(charactersIn: "-")).ifEmpty("service")
    }
    return "service"
}

func inferRole(serviceName: String, publishedPort: Int) -> String {
    let lowered = serviceName.lowercased()
    if lowered.contains("postgres") || lowered == "db" || publishedPort == 5432 {
        return "postgres"
    }
    if lowered.contains("redis") || publishedPort == 6379 {
        return "redis"
    }
    if lowered.contains("minio") || publishedPort == 9000 {
        return "minio"
    }
    if publishedPort == 443 || lowered.contains("https") {
        return "https"
    }
    if lowered.contains("api") || lowered.contains("web") || lowered.contains("nginx")
        || lowered.contains("frontend") || publishedPort == 80 || publishedPort == 8000 || publishedPort == 8080
    {
        return "http"
    }
    return "generic"
}

func parseComposeServices(from content: String) -> [ServiceDefinition] {
    ComposeSupport.importServices(from: content, workingDirectory: nil)
}

private func trimmedOrDefault(_ value: String, defaultValue: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? defaultValue : trimmed
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
