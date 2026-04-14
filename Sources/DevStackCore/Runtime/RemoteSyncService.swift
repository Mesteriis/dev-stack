import Foundation

private struct ManagedDataRewriteResult: Sendable {
    let content: String
    let serviceNames: Set<String>
}

enum RemoteSyncService {
    static func previewManagedDataRewrite(
        content: String,
        dataRootPath: String
    ) -> (content: String, serviceNames: [String]) {
        let rewrite = rewriteManagedDataMounts(in: content, dataRootPath: dataRootPath)
        return (rewrite.content, rewrite.serviceNames.sorted())
    }

    static func syncProjectBindMountSources(
        profile: ProfileDefinition,
        store: ProfileStore,
        server: RemoteServerDefinition
    ) throws {
        let plan = try ComposeSupport.plan(profile: profile, store: store)
        let remoteProfileDirectory = server.remoteProfileDirectory(for: profile.name)
        let remoteProjectDirectory = server.remoteProfileProjectDirectory(for: profile.name)

        let prepareScript = """
        set -eu
        mkdir -p \(RuntimeSharedSupport.shellQuote(remoteProfileDirectory))
        rm -rf \(RuntimeSharedSupport.shellQuote(remoteProjectDirectory))
        mkdir -p \(RuntimeSharedSupport.shellQuote(remoteProjectDirectory))
        """
        let prepareResult = RuntimeSharedSupport.runRemoteShell(on: server, script: prepareScript)
        guard prepareResult.exitCode == 0 else {
            throw ValidationError(RuntimeSharedSupport.nonEmpty(prepareResult.stderr) ?? RuntimeSharedSupport.nonEmpty(prepareResult.stdout) ?? "Failed to prepare remote project directory")
        }

        let fileManager = FileManager.default
        let existingRelativePaths = plan.relativeProjectPaths.filter {
            fileManager.fileExists(atPath: plan.workingDirectory.appendingPathComponent($0).path)
        }
        guard !existingRelativePaths.isEmpty else {
            return
        }

        let tarCommand = RuntimeSharedSupport.shellCommand(
            executable: "/usr/bin/tar",
            arguments: ["-C", plan.workingDirectory.path, "-cf", "-"] + existingRelativePaths
        )
        let remoteExtractCommand = RuntimeSharedSupport.shellCommand(
            executable: "/usr/bin/ssh",
            arguments: RuntimeSharedSupport.sshArguments(for: server) + ["/usr/bin/tar", "--no-same-owner", "-xf", "-", "-C", remoteProjectDirectory]
        )
        let syncCommand = "set -euo pipefail; COPYFILE_DISABLE=1 \(tarCommand) | \(remoteExtractCommand)"
        let syncResult = RuntimeSharedSupport.runLocalShell(syncCommand)
        guard syncResult.exitCode == 0 else {
            throw ValidationError(RuntimeSharedSupport.nonEmpty(syncResult.stderr) ?? RuntimeSharedSupport.nonEmpty(syncResult.stdout) ?? "Failed to sync project bind mounts to remote server")
        }
    }

    static func removeRemoteProfileDirectory(profile: ProfileDefinition, server: RemoteServerDefinition) throws {
        let removeScript = """
        set -eu
        rm -rf \(RuntimeSharedSupport.shellQuote(server.remoteProfileDirectory(for: profile.name)))
        """
        let result = RuntimeSharedSupport.runRemoteShell(on: server, script: removeScript)
        guard result.exitCode == 0 else {
            throw ValidationError(RuntimeSharedSupport.nonEmpty(result.stderr) ?? RuntimeSharedSupport.nonEmpty(result.stdout) ?? "Failed to remove remote profile data")
        }
    }

    static func removeManagedLocalData(profile: ProfileDefinition, store: ProfileStore) throws {
        let fileManager = FileManager.default
        let dataRoot = store.profileDataDirectory(for: profile)
        let rewrite = rewriteManagedDataMounts(in: profile.compose.content, dataRootPath: dataRoot.path)

        for serviceName in rewrite.serviceNames {
            let directory = store.serviceDataDirectory(for: profile, serviceName: serviceName)
            if fileManager.fileExists(atPath: directory.path) {
                try? fileManager.removeItem(at: directory)
            }
        }

        if fileManager.fileExists(atPath: dataRoot.path),
           (try? fileManager.contentsOfDirectory(atPath: dataRoot.path).isEmpty) == true
        {
            try? fileManager.removeItem(at: dataRoot)
        }
    }

    private static func rewriteManagedDataMounts(in content: String, dataRootPath: String) -> ManagedDataRewriteResult {
        enum ParserState {
            case outside
            case inServices(servicesIndent: Int)
        }

        let lines = content.components(separatedBy: .newlines)
        var state = ParserState.outside
        var serviceIndent: Int?
        var currentServiceName: String?
        var currentServiceIndent = 0
        var insideVolumes = false
        var volumesIndent = 0
        var serviceNames = Set<String>()
        var rewrittenLines: [String] = []

        func startService(named name: String, indent: Int) {
            currentServiceName = name
            currentServiceIndent = indent
            insideVolumes = false
            volumesIndent = 0
        }

        for rawLine in lines {
            let indent = rawLine.prefix { $0 == " " || $0 == "\t" }.count
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            var line = rawLine

            switch state {
            case .outside:
                if trimmed == "services:" {
                    state = .inServices(servicesIndent: indent)
                    serviceIndent = nil
                }
            case let .inServices(servicesIndent):
                if indent <= servicesIndent && trimmed != "services:" {
                    currentServiceName = nil
                    insideVolumes = false
                    serviceIndent = nil
                    state = .outside
                    if trimmed == "services:" {
                        state = .inServices(servicesIndent: indent)
                    }
                } else {
                    if trimmed.hasSuffix(":") && !trimmed.hasPrefix("-") && indent > servicesIndent {
                        let candidateName = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
                        if let serviceIndent {
                            if indent == serviceIndent {
                                startService(named: candidateName, indent: indent)
                            }
                        } else {
                            serviceIndent = indent
                            startService(named: candidateName, indent: indent)
                        }
                    }

                    if let currentServiceName {
                        if indent <= currentServiceIndent {
                            insideVolumes = false
                        } else if trimmed == "volumes:" && indent > currentServiceIndent {
                            insideVolumes = true
                            volumesIndent = indent
                        } else if insideVolumes {
                            if indent <= volumesIndent {
                                insideVolumes = false
                            } else {
                                let shortSyntax = rewriteShortSyntaxDataMountLine(
                                    rawLine,
                                    serviceName: currentServiceName,
                                    dataRootPath: dataRootPath
                                )
                                let rewritten = rewriteKeyedDataMountLine(
                                    shortSyntax,
                                    serviceName: currentServiceName,
                                    keys: ["source", "device"],
                                    dataRootPath: dataRootPath
                                )
                                if rewritten != rawLine {
                                    serviceNames.insert(currentServiceName)
                                    line = rewritten
                                }
                            }
                        }
                    }
                }
            }

            rewrittenLines.append(line)
        }

        return ManagedDataRewriteResult(content: rewrittenLines.joined(separator: "\n"), serviceNames: serviceNames)
    }

    private static func rewriteShortSyntaxDataMountLine(
        _ line: String,
        serviceName: String,
        dataRootPath: String
    ) -> String {
        guard let dashIndex = line.firstIndex(of: "-") else {
            return line
        }

        let contentSlice = line[line.index(after: dashIndex)...]
        guard let valueStart = contentSlice.firstIndex(where: { !$0.isWhitespace }) else {
            return line
        }

        let prefix = String(line[..<valueStart])
        let rawValue = String(line[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let quote = rawValue.first.flatMap { first -> Character? in
            guard (first == "\"" || first == "'"), rawValue.last == first else {
                return nil
            }
            return first
        }
        let unwrapped = quote == nil ? rawValue : String(rawValue.dropFirst().dropLast())
        guard let colonIndex = unwrapped.firstIndex(of: ":") else {
            return line
        }

        let source = String(unwrapped[..<colonIndex])
        guard let rewrittenSource = managedDataSourcePath(
            serviceName: serviceName,
            source: source,
            dataRootPath: dataRootPath
        ) else {
            return line
        }

        let rewritten = rewrittenSource + String(unwrapped[colonIndex...])
        if let quote {
            return prefix + "\(quote)\(rewritten)\(quote)"
        }
        return prefix + rewritten
    }

    private static func rewriteKeyedDataMountLine(
        _ line: String,
        serviceName: String,
        keys: [String],
        dataRootPath: String
    ) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let key = keys.first(where: { trimmed.hasPrefix("\($0):") }) else {
            return line
        }

        guard let keyRange = line.range(of: "\(key):") else {
            return line
        }
        let valueRange = keyRange.upperBound..<line.endIndex
        guard let valueStart = line[valueRange].firstIndex(where: { !$0.isWhitespace }) else {
            return line
        }
        let rawValue = String(line[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let quote = rawValue.first.flatMap { first -> Character? in
            guard (first == "\"" || first == "'"), rawValue.last == first else {
                return nil
            }
            return first
        }
        let unwrapped = quote == nil ? rawValue : String(rawValue.dropFirst().dropLast())
        guard let rewrittenValue = managedDataSourcePath(
            serviceName: serviceName,
            source: unwrapped,
            dataRootPath: dataRootPath
        ) else {
            return line
        }

        let prefix = String(line[..<valueStart])
        if let quote {
            return prefix + "\(quote)\(rewrittenValue)\(quote)"
        }
        return prefix + rewrittenValue
    }

    private static func managedDataSourcePath(
        serviceName: String,
        source: String,
        dataRootPath: String
    ) -> String? {
        guard source == "./data" || source.hasPrefix("./data/") else {
            return nil
        }

        let normalizedRoot = dataRootPath.hasSuffix("/") ? String(dataRootPath.dropLast()) : dataRootPath
        let suffix = String(source.dropFirst("./data".count))
        return "\(normalizedRoot)/\(slugify(serviceName))\(suffix)"
    }
}
