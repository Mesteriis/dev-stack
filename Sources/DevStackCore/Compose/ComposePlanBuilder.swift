import Foundation

enum ComposePlanBuilder {
    static func plan(profile: ProfileDefinition, store: ProfileStore) throws -> ComposePlan {
        let workingDirectory = composeWorkingDirectory(for: profile, store: store)
        let sourceComposeURLs = try composeSourceURLs(for: profile, store: store)
        let environmentFiles = try ComposeEnvironmentService.resolvedEnvironmentFiles(
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

    static func rewriteRemoteBindMounts(
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

    static func composeProjectName(for profile: ProfileDefinition) -> String {
        let trimmed = profile.compose.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? slugify(profile.name) : trimmed
    }

    static func composeWorkingDirectory(for profile: ProfileDefinition, store: ProfileStore) -> URL {
        if let managedDirectory = store.managedProjectDirectory(for: profile) {
            return managedDirectory
        }

        let trimmed = profile.compose.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return store.generatedProfileDirectory(for: profile.name)
        }
        return URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath, isDirectory: true)
    }

    static func composeSourceURLs(for profile: ProfileDefinition, store: ProfileStore) throws -> [URL] {
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

    static func composeReferenceText(profile: ProfileDefinition, sourceComposeURLs: [URL]) -> String {
        if !sourceComposeURLs.isEmpty {
            let contents = sourceComposeURLs.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            if !contents.isEmpty {
                return contents.joined(separator: "\n\n")
            }
        }
        return profile.compose.content
    }

    static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

    private static func fallbackImportServices(from content: String) -> [ServiceDefinition] {
        let shortPortPattern = #"(?:['\"]?[^'\":]+['\"]?:)?(\d+):(\d+)(?:/\w+)?"#
        guard let shortPortRegex = try? NSRegularExpression(pattern: shortPortPattern) else {
            return []
        }
        let targetRegex = #/^\s*target:\s*(\d+)\s*$/#
        let publishedRegex = #/^\s*published:\s*(\d+)\s*$/#

        let lines = content.components(separatedBy: .newlines)
        var servicesIndent = 0
        var insideServices = false
        var currentService: String?
        var serviceIndent: Int?
        var portsIndent: Int?
        var isCollectingLongPort = false
        var result: [ServiceDefinition] = []
        var discoveredPorts: [String: [Int]] = [:]

        for rawLine in lines {
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
                serviceIndent = nil
                portsIndent = nil
                isCollectingLongPort = false
                continue
            }

            if let currentServiceIndent = serviceIndent, indent <= currentServiceIndent {
                currentService = nil
                serviceIndent = nil
                portsIndent = nil
                isCollectingLongPort = false
            }

            if indent > servicesIndent,
               serviceIndent == nil || indent == serviceIndent,
               trimmed.hasSuffix(":"),
               !trimmed.hasPrefix("-")
            {
                currentService = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
                serviceIndent = indent
                portsIndent = nil
                isCollectingLongPort = false
                continue
            }

            guard let currentService, let serviceIndent else {
                continue
            }

            if indent <= serviceIndent {
                continue
            }

            if trimmed == "ports:" {
                portsIndent = indent
                isCollectingLongPort = false
                continue
            }

            if let currentPortsIndent = portsIndent {
                if indent <= currentPortsIndent {
                    portsIndent = nil
                    isCollectingLongPort = false
                }
            } else {
                continue
            }

            guard let currentPortsIndent = portsIndent else {
                continue
            }

            if indent <= currentPortsIndent {
                continue
            }

            if isCollectingLongPort {
                if let publishedMatch = trimmed.firstMatch(of: publishedRegex)?.1,
                   let published = Int(publishedMatch)
                {
                    discoveredPorts[currentService, default: []].append(published)
                    isCollectingLongPort = false
                    continue
                }

                if trimmed.firstMatch(of: targetRegex)?.1 == nil {
                    isCollectingLongPort = false
                }
            }

            if !trimmed.hasPrefix("-") {
                continue
            }

            if isCollectingLongPort {
                isCollectingLongPort = false
            }

            let entryLine = String(trimmed.dropFirst())
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

            if let publishedMatch = entryLine.firstMatch(of: publishedRegex)?.1,
               let publishedPort = Int(publishedMatch)
            {
                discoveredPorts[currentService, default: []].append(publishedPort)
                continue
            }

            let shortRange = NSRange(entryLine.startIndex..<entryLine.endIndex, in: entryLine)
            if let shortMatch = shortPortRegex.firstMatch(in: entryLine, range: shortRange),
               let publishedRange = Range(shortMatch.range(at: 1), in: entryLine),
               let publishedPort = Int(entryLine[publishedRange])
            {
                discoveredPorts[currentService, default: []].append(publishedPort)
                continue
            }

            if let targetMatch = entryLine.firstMatch(of: targetRegex)?.1, Int(targetMatch) != nil {
                isCollectingLongPort = true
                continue
            }
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
}
