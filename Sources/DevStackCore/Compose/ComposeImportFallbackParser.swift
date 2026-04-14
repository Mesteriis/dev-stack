import Foundation

enum ComposeImportFallbackParser {
    static func fallbackImportServices(from content: String) -> [ServiceDefinition] {
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

