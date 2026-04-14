import Foundation

struct ComposePortBinding: Sendable {
    let serviceName: String
    let publishedPort: Int
    let targetPort: Int?
    let hostIP: String?
    let protocolName: String
}

struct ComposeBindMount: Sendable {
    let serviceName: String
    let sourcePath: String
    let targetPath: String
    let relativeProjectPath: String?
    let readOnly: Bool
}

struct ComposeNamedVolumeMount: Sendable {
    let serviceName: String
    let sourceName: String
    let targetPath: String
}

struct ComposeServicePlan: Sendable {
    let name: String
    let image: String?
    let ports: [ComposePortBinding]
    let bindMounts: [ComposeBindMount]
    let namedVolumes: [ComposeNamedVolumeMount]
}

struct ComposePlan: Sendable {
    let projectName: String
    let workingDirectory: URL
    let sourceComposeURLs: [URL]
    let environmentFiles: [URL]
    let services: [ComposeServicePlan]
    let topLevelVolumeNames: [String]
    let relativeProjectPaths: [String]
    let unsupportedRemoteBindSources: [String]
    fileprivate let normalizedData: Data

    var sourceComposeURL: URL {
        sourceComposeURLs[0]
    }
}

struct ComposeSecretEntry: Sendable {
    let key: String
    let statusText: String
    let envFileURL: URL?
    let providedByManagedVariables: Bool
    let hasProfileKeychainValue: Bool
    let hasProjectKeychainValue: Bool
}

struct ComposeSecretOverview: Sendable {
    let workingDirectory: URL
    let environmentFiles: [URL]
    let referencedKeys: [String]
    let entries: [ComposeSecretEntry]
    let profileServiceName: String
    let projectServiceName: String
}

enum ComposeSupport {
    static func plan(profile: ProfileDefinition, store: ProfileStore) throws -> ComposePlan {
        let workingDirectory = composeWorkingDirectory(for: profile, store: store)
        let sourceComposeURLs = try composeSourceURLs(for: profile, store: store)
        let environmentFiles = try resolvedEnvironmentFiles(
            profile: profile,
            store: store,
            workingDirectory: workingDirectory,
            sourceComposeURLs: sourceComposeURLs
        )

        guard let dockerPath = ToolPaths.docker else {
            throw ValidationError("docker not found")
        }

        let result = Shell.run(
            dockerPath,
            arguments: composeArguments(
                projectName: composeProjectName(for: profile),
                sourceComposeURLs: sourceComposeURLs,
                workingDirectory: workingDirectory,
                environmentFiles: environmentFiles,
                command: ["config", "--format", "json"]
            ),
            currentDirectoryURL: workingDirectory
        )

        guard result.exitCode == 0 else {
            throw ValidationError(
                nonEmpty(result.stderr)
                    ?? nonEmpty(result.stdout)
                    ?? "docker compose config failed"
            )
        }

        guard let data = result.stdout.data(using: .utf8),
              let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ValidationError("Failed to parse docker compose config output.")
        }

        return buildPlan(
            normalizedObject: jsonObject,
            normalizedData: data,
            projectName: composeProjectName(for: profile),
            workingDirectory: workingDirectory,
            sourceComposeURLs: sourceComposeURLs,
            environmentFiles: environmentFiles
        )
    }

    static func generatedComposeFile(
        profile: ProfileDefinition,
        store: ProfileStore,
        server: RemoteServerDefinition?
    ) throws -> (composeURL: URL, plan: ComposePlan) {
        let plan = try plan(profile: profile, store: store)
        try store.ensureRuntimeDirectories()
        let generatedDirectory = store.generatedProfileDirectory(for: profile.name)
        try FileManager.default.createDirectory(at: generatedDirectory, withIntermediateDirectories: true)

        guard var normalizedObject = try JSONSerialization.jsonObject(with: plan.normalizedData) as? [String: Any] else {
            throw ValidationError("Failed to rebuild normalized compose model.")
        }
        if let server, !server.isLocal {
            rewriteRemoteBindMounts(
                in: &normalizedObject,
                plan: plan,
                server: server,
                profileName: profile.name
            )
        }

        let data = try JSONSerialization.data(
            withJSONObject: normalizedObject,
            options: [.prettyPrinted, .sortedKeys]
        )
        let composeURL = store.composeFileURL(for: profile.name)
        try data.write(to: composeURL, options: .atomic)
        return (composeURL, plan)
    }

    static func importServices(from content: String, workingDirectory: URL?) -> [ServiceDefinition] {
        do {
            let syntheticProfile = try ProfileDefinition(
                name: "compose-import",
                compose: ComposeDefinition(
                    projectName: "compose-import",
                    workingDirectory: workingDirectory?.path ?? FileManager.default.temporaryDirectory.path,
                    content: content
                )
            ).normalized()
            let plan = try plan(profile: syntheticProfile, store: ProfileStore())
            return serviceDefinitions(from: plan)
        } catch {
            return fallbackImportServices(from: content)
        }
    }

    static func writePlanReport(plan: ComposePlan, to url: URL) throws {
        let text = planReport(plan: plan)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    static func planReport(plan: ComposePlan) -> String {
        var lines: [String] = []
        lines.append("Project: \(plan.projectName)")
        lines.append("Working directory: \(plan.workingDirectory.path)")
        if plan.sourceComposeURLs.count == 1 {
            lines.append("Compose source: \(plan.sourceComposeURL.path)")
        } else {
            lines.append("Compose sources:")
            for url in plan.sourceComposeURLs {
                lines.append("  - \(url.path)")
            }
        }
        if !plan.environmentFiles.isEmpty {
            lines.append("Environment files:")
            for url in plan.environmentFiles {
                lines.append("  - \(url.path)")
            }
        }

        if !plan.services.isEmpty {
            lines.append("")
            lines.append("Services:")
            for service in plan.services {
                let imageText = service.image ?? "(no image)"
                lines.append("  - \(service.name)  \(imageText)")
                for port in service.ports {
                    let hostIP = port.hostIP ?? "0.0.0.0"
                    let target = port.targetPort.map(String.init) ?? "?"
                    lines.append("      port: \(hostIP):\(port.publishedPort) -> \(target)/\(port.protocolName)")
                }
                for mount in service.bindMounts {
                    let source = mount.relativeProjectPath ?? mount.sourcePath
                    let ro = mount.readOnly ? " (ro)" : ""
                    lines.append("      bind: \(source) -> \(mount.targetPath)\(ro)")
                }
                for volume in service.namedVolumes {
                    lines.append("      volume: \(volume.sourceName) -> \(volume.targetPath)")
                }
            }
        }

        if !plan.topLevelVolumeNames.isEmpty {
            lines.append("")
            lines.append("Top-level volumes:")
            for volume in plan.topLevelVolumeNames.sorted() {
                lines.append("  - \(volume)")
            }
        }

        if !plan.unsupportedRemoteBindSources.isEmpty {
            lines.append("")
            lines.append("Unsupported remote bind sources:")
            for path in plan.unsupportedRemoteBindSources.sorted() {
                lines.append("  - \(path)")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func buildPlan(
        normalizedObject: [String: Any],
        normalizedData: Data,
        projectName: String,
        workingDirectory: URL,
        sourceComposeURLs: [URL],
        environmentFiles: [URL]
    ) -> ComposePlan {
        var services: [ComposeServicePlan] = []
        var relativePaths = Set<String>()
        var unsupportedRemoteSources = Set<String>()

        let servicesObject = normalizedObject["services"] as? [String: Any] ?? [:]
        for serviceName in servicesObject.keys.sorted() {
            guard let serviceObject = servicesObject[serviceName] as? [String: Any] else {
                continue
            }

            let ports = extractPorts(serviceName: serviceName, serviceObject: serviceObject)
            let bindMounts = extractBindMounts(
                serviceName: serviceName,
                serviceObject: serviceObject,
                workingDirectory: workingDirectory,
                relativePaths: &relativePaths,
                unsupportedRemoteSources: &unsupportedRemoteSources
            )
            let namedVolumes = extractNamedVolumes(serviceName: serviceName, serviceObject: serviceObject)

            services.append(
                ComposeServicePlan(
                    name: serviceName,
                    image: serviceObject["image"] as? String,
                    ports: ports,
                    bindMounts: bindMounts,
                    namedVolumes: namedVolumes
                )
            )
        }

        let topLevelVolumes = ((normalizedObject["volumes"] as? [String: Any]) ?? [:]).keys.sorted()

        return ComposePlan(
            projectName: projectName,
            workingDirectory: workingDirectory,
            sourceComposeURLs: sourceComposeURLs,
            environmentFiles: environmentFiles,
            services: services,
            topLevelVolumeNames: topLevelVolumes,
            relativeProjectPaths: relativePaths.sorted(),
            unsupportedRemoteBindSources: unsupportedRemoteSources.sorted(),
            normalizedData: normalizedData
        )
    }

    private static func extractPorts(serviceName: String, serviceObject: [String: Any]) -> [ComposePortBinding] {
        let rawPorts = serviceObject["ports"] as? [[String: Any]] ?? []
        return rawPorts.compactMap { portObject in
            let publishedValue = portObject["published"]
            let publishedPort: Int?
            if let publishedString = publishedValue as? String {
                publishedPort = Int(publishedString)
            } else {
                publishedPort = publishedValue as? Int
            }

            guard let publishedPort else {
                return nil
            }

            let targetPort = portObject["target"] as? Int
            return ComposePortBinding(
                serviceName: serviceName,
                publishedPort: publishedPort,
                targetPort: targetPort,
                hostIP: portObject["host_ip"] as? String,
                protocolName: (portObject["protocol"] as? String) ?? "tcp"
            )
        }
    }

    private static func extractBindMounts(
        serviceName: String,
        serviceObject: [String: Any],
        workingDirectory: URL,
        relativePaths: inout Set<String>,
        unsupportedRemoteSources: inout Set<String>
    ) -> [ComposeBindMount] {
        let rawVolumes = serviceObject["volumes"] as? [[String: Any]] ?? []
        var result: [ComposeBindMount] = []
        let workingPath = standardizedPath(workingDirectory.path)

        for volumeObject in rawVolumes {
            guard let type = volumeObject["type"] as? String, type == "bind",
                  let sourcePath = volumeObject["source"] as? String,
                  let targetPath = volumeObject["target"] as? String
            else {
                continue
            }

            let standardizedSource = standardizedPath(sourcePath)
            let relativeProjectPath = relativePath(for: standardizedSource, under: workingPath)
            if let relativeProjectPath {
                relativePaths.insert(relativeProjectPath)
            } else {
                unsupportedRemoteSources.insert(standardizedSource)
            }

            result.append(
                ComposeBindMount(
                    serviceName: serviceName,
                    sourcePath: standardizedSource,
                    targetPath: targetPath,
                    relativeProjectPath: relativeProjectPath,
                    readOnly: volumeObject["read_only"] as? Bool ?? false
                )
            )
        }

        return result
    }

    private static func extractNamedVolumes(
        serviceName: String,
        serviceObject: [String: Any]
    ) -> [ComposeNamedVolumeMount] {
        let rawVolumes = serviceObject["volumes"] as? [[String: Any]] ?? []
        return rawVolumes.compactMap { volumeObject in
            guard let type = volumeObject["type"] as? String, type == "volume",
                  let sourceName = volumeObject["source"] as? String,
                  let targetPath = volumeObject["target"] as? String
            else {
                return nil
            }

            return ComposeNamedVolumeMount(
                serviceName: serviceName,
                sourceName: sourceName,
                targetPath: targetPath
            )
        }
    }

    private static func rewriteRemoteBindMounts(
        in normalizedObject: inout [String: Any],
        plan: ComposePlan,
        server: RemoteServerDefinition,
        profileName: String
    ) {
        guard var servicesObject = normalizedObject["services"] as? [String: Any] else {
            return
        }

        for service in plan.services {
            guard var serviceObject = servicesObject[service.name] as? [String: Any],
                  var volumes = serviceObject["volumes"] as? [[String: Any]]
            else {
                continue
            }

            for index in volumes.indices {
                guard let type = volumes[index]["type"] as? String,
                      type == "bind",
                      let sourcePath = volumes[index]["source"] as? String
                else {
                    continue
                }

                let standardizedSource = standardizedPath(sourcePath)
                guard let relativePath = relativePath(
                    for: standardizedSource,
                    under: standardizedPath(plan.workingDirectory.path)
                ) else {
                    continue
                }

                let remoteSource = server.remoteProfileProjectDirectory(for: profileName)
                    + "/"
                    + relativePath
                volumes[index]["source"] = remoteSource
            }

            serviceObject["volumes"] = volumes
            servicesObject[service.name] = serviceObject
        }

        normalizedObject["services"] = servicesObject
    }

    private static func resolvedEnvironmentFiles(
        profile: ProfileDefinition,
        store: ProfileStore,
        workingDirectory: URL,
        sourceComposeURLs: [URL]
    ) throws -> [URL] {
        var result: [URL] = []

        if let managedVariablesURL = try generatedManagedVariablesEnvFile(profile: profile, store: store) {
            result.append(managedVariablesURL)
        }

        result.append(contentsOf: projectEnvironmentFiles(in: workingDirectory))

        if let secretsURL = try generatedSecretsEnvFile(
            profile: profile,
            store: store,
            workingDirectory: workingDirectory,
            baseEnvironmentFiles: result,
            sourceComposeURLs: sourceComposeURLs
        ) {
            result.append(secretsURL)
        }

        return result
    }

    private static func generatedManagedVariablesEnvFile(
        profile: ProfileDefinition,
        store: ProfileStore
    ) throws -> URL? {
        let variables = try applicableManagedVariables(profile: profile, store: store)
        let outputURL = store.generatedManagedVariablesEnvURL(for: profile.name)

        guard !variables.isEmpty else {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
            return nil
        }

        let lines = variables.map { "\($0.name)=\(shellSafeEnvironmentValue($0.value))" }
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").appending("\n").write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    private static func generatedSecretsEnvFile(
        profile: ProfileDefinition,
        store: ProfileStore,
        workingDirectory: URL,
        baseEnvironmentFiles: [URL],
        sourceComposeURLs: [URL]
    ) throws -> URL? {
        let referencedKeys = referencedEnvironmentKeys(
            in: composeReferenceText(profile: profile, sourceComposeURLs: sourceComposeURLs)
        )
        guard !referencedKeys.isEmpty else {
            return nil
        }

        var knownValues = ProcessInfo.processInfo.environment
        for url in baseEnvironmentFiles {
            knownValues.merge(parseEnvironmentFile(at: url), uniquingKeysWith: { current, _ in current })
        }

        let secretServices = secretServiceNames(profile: profile, workingDirectory: workingDirectory)

        var lines: [String] = []
        for key in referencedKeys.sorted() where knownValues[key] == nil {
            if let value = KeychainSecretStore.lookup(account: key, serviceNames: secretServices) {
                lines.append("\(key)=\(shellSafeEnvironmentValue(value))")
            }
        }

        guard !lines.isEmpty else {
            return nil
        }

        let secretsURL = store.generatedSecretsEnvURL(for: profile.name)
        try FileManager.default.createDirectory(at: secretsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").appending("\n").write(to: secretsURL, atomically: true, encoding: .utf8)
        return secretsURL
    }

    static func parseEnvironmentFile(at url: URL) -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return [:]
        }
        return parseEnvironmentText(text)
    }

    static func parseEnvironmentText(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else {
                continue
            }

            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...])
            if !key.isEmpty {
                values[key] = value
            }
        }

        return values
    }

    static func secretOverview(profile: ProfileDefinition, store: ProfileStore) throws -> ComposeSecretOverview {
        let workingDirectory = composeWorkingDirectory(for: profile, store: store)
        let sourceComposeURLs = try composeSourceURLs(for: profile, store: store)
        let environmentFiles = projectEnvironmentFiles(in: workingDirectory)
        let managedVariables = try applicableManagedVariables(profile: profile, store: store)
        let referencedKeys = referencedEnvironmentKeys(
            in: composeReferenceText(profile: profile, sourceComposeURLs: sourceComposeURLs)
        ).sorted()
        let profileServiceName = profileSecretServiceName(for: profile)
        let projectServiceName = projectSecretServiceName(for: workingDirectory)

        var envSourceByKey: [String: URL] = [:]
        for url in environmentFiles {
            for key in parseEnvironmentFile(at: url).keys {
                envSourceByKey[key] = url
            }
        }
        let managedVariableNames = Set(managedVariables.map(\.name))

        let entries = referencedKeys.map { key in
            let envFileURL = envSourceByKey[key]
            let providedByManagedVariables = managedVariableNames.contains(key)
            let hasProfileKeychainValue = KeychainSecretStore.lookup(
                account: key,
                serviceNames: [profileServiceName]
            ) != nil
            let hasProjectKeychainValue = profileServiceName == projectServiceName
                ? false
                : KeychainSecretStore.lookup(account: key, serviceNames: [projectServiceName]) != nil

            let statusText: String
            if let envFileURL {
                statusText = "Provided by \(envFileURL.lastPathComponent)"
            } else if providedByManagedVariables {
                statusText = "Provided by Variable Manager"
            } else if hasProfileKeychainValue {
                statusText = "Stored in Keychain for this profile"
            } else if hasProjectKeychainValue {
                statusText = "Inherited from project Keychain"
            } else {
                statusText = "Missing"
            }

            return ComposeSecretEntry(
                key: key,
                statusText: statusText,
                envFileURL: envFileURL,
                providedByManagedVariables: providedByManagedVariables,
                hasProfileKeychainValue: hasProfileKeychainValue,
                hasProjectKeychainValue: hasProjectKeychainValue
            )
        }

        return ComposeSecretOverview(
            workingDirectory: workingDirectory,
            environmentFiles: environmentFiles,
            referencedKeys: referencedKeys,
            entries: entries,
            profileServiceName: profileServiceName,
            projectServiceName: projectServiceName
        )
    }

    static func saveProfileSecret(key: String, value: String, profile: ProfileDefinition) throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw ValidationError("Secret key is required.")
        }
        try KeychainSecretStore.upsert(
            account: trimmedKey,
            serviceName: profileSecretServiceName(for: profile),
            value: value
        )
    }

    static func deleteProfileSecret(key: String, profile: ProfileDefinition) throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw ValidationError("Secret key is required.")
        }
        try KeychainSecretStore.delete(
            account: trimmedKey,
            serviceName: profileSecretServiceName(for: profile)
        )
    }

    static func applicableManagedVariables(
        profile: ProfileDefinition,
        store: ProfileStore
    ) throws -> [ManagedVariableDefinition] {
        try store.managedVariables()
            .filter { $0.applies(to: profile.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func referencedEnvironmentKeys(in text: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: #"\$\{([A-Za-z_][A-Za-z0-9_]*)"#) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var result = Set<String>()
        for match in regex.matches(in: text, range: range) {
            guard match.numberOfRanges > 1,
                  let keyRange = Range(match.range(at: 1), in: text)
            else {
                continue
            }
            result.insert(String(text[keyRange]))
        }
        return result
    }

    private static func serviceDefinitions(from plan: ComposePlan) -> [ServiceDefinition] {
        var result: [ServiceDefinition] = []

        for service in plan.services.sorted(by: { $0.name < $1.name }) {
            let sortedPorts = service.ports.sorted {
                if $0.publishedPort == $1.publishedPort {
                    return ($0.targetPort ?? 0) < ($1.targetPort ?? 0)
                }
                return $0.publishedPort < $1.publishedPort
            }

            for (index, port) in sortedPorts.enumerated() {
                let entryName = sortedPorts.count == 1 ? service.name : "\(service.name)-\(port.publishedPort)"
                let aliasBase = index == 0 ? service.name : "\(service.name)-\(port.publishedPort)"
                result.append(
                    ServiceDefinition(
                        name: entryName,
                        role: inferRole(serviceName: service.name, publishedPort: port.publishedPort),
                        aliasHost: "\(slugify(aliasBase)).localhost",
                        localPort: port.publishedPort,
                        remoteHost: "127.0.0.1",
                        remotePort: port.publishedPort,
                        tunnelHost: "",
                        enabled: true,
                        envPrefix: slugify(entryName).uppercased(),
                        extraExports: []
                    )
                )
            }
        }

        return result
    }

    private static func composeArguments(
        projectName: String,
        sourceComposeURLs: [URL],
        workingDirectory: URL,
        environmentFiles: [URL],
        command: [String]
    ) -> [String] {
        var arguments: [String] = ["compose", "--project-name", projectName, "--project-directory", workingDirectory.path]
        for url in environmentFiles {
            arguments.append(contentsOf: ["--env-file", url.path])
        }
        for url in sourceComposeURLs {
            arguments.append(contentsOf: ["-f", url.path])
        }
        arguments.append(contentsOf: command)
        return arguments
    }

    private static func composeProjectName(for profile: ProfileDefinition) -> String {
        let trimmed = profile.compose.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? slugify(profile.name) : trimmed
    }

    private static func composeWorkingDirectory(for profile: ProfileDefinition, store: ProfileStore) -> URL {
        if let managedDirectory = store.managedProjectDirectory(for: profile) {
            return managedDirectory
        }

        let trimmed = profile.compose.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return store.generatedProfileDirectory(for: profile.name)
        }
        return URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath, isDirectory: true)
    }

    private static func composeSourceURLs(for profile: ProfileDefinition, store: ProfileStore) throws -> [URL] {
        let sourceURLs = store.sourceComposeURLs(for: profile)
        if !sourceURLs.isEmpty {
            let missingURLs = sourceURLs.filter { !FileManager.default.fileExists(atPath: $0.path) }
            if !missingURLs.isEmpty {
                let message = missingURLs.map(\.path).joined(separator: ", ")
                throw ValidationError("Compose source file is missing: \(message)")
            }
            return sourceURLs
        }

        let sourceURL = store.generatedComposeSourceURL(for: profile.name)
        try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try profile.compose.content.write(to: sourceURL, atomically: true, encoding: .utf8)
        return [sourceURL]
    }

    private static func composeReferenceText(profile: ProfileDefinition, sourceComposeURLs: [URL]) -> String {
        if !sourceComposeURLs.isEmpty {
            let contents = sourceComposeURLs.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            if !contents.isEmpty {
                return contents.joined(separator: "\n\n")
            }
        }
        return profile.compose.content
    }

    private static func projectEnvironmentFiles(in workingDirectory: URL) -> [URL] {
        let fileManager = FileManager.default
        var result: [URL] = []

        for name in [".env", ".env.local", ".env.devstack"] {
            let url = workingDirectory.appendingPathComponent(name, isDirectory: false)
            if fileManager.fileExists(atPath: url.path) {
                result.append(url)
            }
        }

        return result
    }

    private static func secretServiceNames(profile: ProfileDefinition, workingDirectory: URL) -> [String] {
        var result = [profileSecretServiceName(for: profile)]
        let projectServiceName = projectSecretServiceName(for: workingDirectory)
        if !result.contains(projectServiceName) {
            result.append(projectServiceName)
        }
        return result
    }

    private static func profileSecretServiceName(for profile: ProfileDefinition) -> String {
        "devstackmenu.\(slugify(profile.name))"
    }

    private static func projectSecretServiceName(for workingDirectory: URL) -> String {
        "devstackmenu.\(slugify(workingDirectory.lastPathComponent))"
    }

    private static func relativePath(for path: String, under root: String) -> String? {
        guard path == root || path.hasPrefix(root + "/") else {
            return nil
        }

        let suffix = path == root ? "" : String(path.dropFirst(root.count + 1))
        guard !suffix.isEmpty else {
            return nil
        }
        return suffix
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func shellSafeEnvironmentValue(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func inferRole(serviceName: String, publishedPort: Int) -> String {
        let normalized = serviceName.lowercased()

        if normalized.contains("postgres") || publishedPort == 5432 {
            return "postgres"
        }
        if normalized.contains("redis") || publishedPort == 6379 {
            return "redis"
        }
        if normalized.contains("minio") || publishedPort == 9000 {
            return "minio"
        }
        if publishedPort == 443 || normalized.contains("https") {
            return "https"
        }
        if publishedPort == 80 || publishedPort == 8080 || publishedPort == 3000 || normalized.contains("http") || normalized.contains("api") {
            return "http"
        }

        return "generic"
    }

    private static func fallbackImportServices(from content: String) -> [ServiceDefinition] {
        let pattern = #"(?:.+:)?(\d+):(\d+)(?:/\w+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        var currentService: String?
        var insideServices = false
        var servicesIndent = 0
        var serviceIndent = 0
        var result: [ServiceDefinition] = []
        var discoveredPorts: [String: [Int]] = [:]

        for rawLine in content.components(separatedBy: .newlines) {
            let indent = rawLine.prefix { $0 == " " || $0 == "\t" }.count
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            if !insideServices {
                if trimmed == "services:" {
                    insideServices = true
                    servicesIndent = indent
                }
                continue
            }

            if indent <= servicesIndent {
                currentService = nil
                continue
            }

            if trimmed.hasSuffix(":") && !trimmed.hasPrefix("-") && indent == servicesIndent + 2 {
                currentService = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
                serviceIndent = indent
                continue
            }

            guard let currentService, indent > serviceIndent, trimmed.hasPrefix("-") else {
                continue
            }

            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            guard let match = regex.firstMatch(in: trimmed, range: range),
                  let publishedRange = Range(match.range(at: 1), in: trimmed),
                  let publishedPort = Int(trimmed[publishedRange])
            else {
                continue
            }
            discoveredPorts[currentService, default: []].append(publishedPort)
        }

        for (serviceName, ports) in discoveredPorts.sorted(by: { $0.key < $1.key }) {
            for (index, publishedPort) in ports.sorted().enumerated() {
                let entryName = ports.count == 1 ? serviceName : "\(serviceName)-\(publishedPort)"
                let aliasBase = index == 0 ? serviceName : "\(serviceName)-\(publishedPort)"
                result.append(
                    ServiceDefinition(
                        name: entryName,
                        role: inferRole(serviceName: serviceName, publishedPort: publishedPort),
                        aliasHost: "\(slugify(aliasBase)).localhost",
                        localPort: publishedPort,
                        remoteHost: "127.0.0.1",
                        remotePort: publishedPort,
                        tunnelHost: "",
                        enabled: true,
                        envPrefix: slugify(entryName).uppercased(),
                        extraExports: []
                    )
                )
            }
        }

        return result
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum KeychainSecretStore {
    static func lookup(account: String, serviceNames: [String]) -> String? {
        for serviceName in serviceNames {
            let result = Shell.run(
                "/usr/bin/security",
                arguments: ["find-generic-password", "-a", account, "-s", serviceName, "-w"]
            )
            guard result.exitCode == 0 else {
                continue
            }

            let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }

        return nil
    }

    static func upsert(account: String, serviceName: String, value: String) throws {
        let result = Shell.run(
            "/usr/bin/security",
            arguments: ["add-generic-password", "-U", "-a", account, "-s", serviceName, "-w", value]
        )
        guard result.exitCode == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ValidationError(!stderr.isEmpty ? stderr : (!stdout.isEmpty ? stdout : "Failed to save secret in Keychain"))
        }
    }

    static func delete(account: String, serviceName: String) throws {
        let result = Shell.run(
            "/usr/bin/security",
            arguments: ["delete-generic-password", "-a", account, "-s", serviceName]
        )
        guard result.exitCode == 0 || result.stderr.localizedCaseInsensitiveContains("could not be found") else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ValidationError(!stderr.isEmpty ? stderr : (!stdout.isEmpty ? stdout : "Failed to delete secret from Keychain"))
        }
    }
}
