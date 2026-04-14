import Foundation

enum ComposePlanParsingService {
    static func composeArguments(
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

    static func buildPlan(
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

    static func serviceDefinitions(from plan: ComposePlan) -> [ServiceDefinition] {
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
}
