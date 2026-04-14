import Foundation

enum ComposeEnvironmentService {
    static func resolvedEnvironmentFiles(
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

            let rawKey = line[..<separator].trimmingCharacters(in: .whitespaces)
            let key = rawKey.replacingOccurrences(of: #"^export\s+"#, with: "", options: .regularExpression)
            let value = String(line[line.index(after: separator)...])
            if !key.isEmpty {
                values[key] = value
            }
        }

        return values
    }

    static func environmentOverview(
        profile: ProfileDefinition,
        store: ProfileStore,
        ignoredKeys: Set<String> = []
    ) throws -> ComposeEnvironmentOverview {
        let workingDirectory = ComposePlanBuilder.composeWorkingDirectory(for: profile, store: store)
        let sourceComposeURLs = try ComposePlanBuilder.composeSourceURLs(for: profile, store: store)
        let environmentFiles = projectEnvironmentFiles(in: workingDirectory)
        let managedVariables = try applicableManagedVariables(profile: profile, store: store)
        let referencedKeys = referencedEnvironmentKeys(
            in: ComposePlanBuilder.composeReferenceText(profile: profile, sourceComposeURLs: sourceComposeURLs)
        )
        let sortedReferencedKeys = referencedKeys
            .filter { !ignoredKeys.contains($0) }
            .sorted()
        let profileServiceName = ComposeSecretSupport.profileSecretServiceName(for: profile)
        let projectServiceName = ComposeSecretSupport.projectSecretServiceName(for: workingDirectory)
        let profileEnvironmentFile = environmentFileURL(for: profile, store: store)

        var envSourceByKey: [String: URL] = [:]
        var envValueByKey: [String: String] = [:]
        for url in environmentFiles {
            let values = parseEnvironmentFile(at: url)
            for (key, value) in values where envSourceByKey[key] == nil {
                envSourceByKey[key] = url
                envValueByKey[key] = value
            }
        }

        let managedVariableNames = Set(managedVariables.map(\.name))
        let entries = sortedReferencedKeys.map { key in
            let envFileURL = envSourceByKey[key]
            let envFileValue = envValueByKey[key]
            let providedByManagedVariables = managedVariableNames.contains(key)
            let hasProfileKeychainValue = KeychainSecretStore.lookup(
                account: key,
                serviceNames: [profileServiceName]
            ) != nil
            let hasProjectKeychainValue = profileServiceName == projectServiceName
                ? false
                : KeychainSecretStore.lookup(account: key, serviceNames: [projectServiceName]) != nil
            let isMarkedExternal = profile.externalEnvironmentKeys.contains(key)
            let isEmptyValue = envFileValue?.isEmpty == true

            let statusText: String
            let isMissing: Bool
            let suggestedWriteURL: URL?
            if let envFileURL {
                if isEmptyValue {
                    statusText = "Empty in \(envFileURL.lastPathComponent)"
                    isMissing = true
                } else {
                    statusText = "Provided by \(envFileURL.lastPathComponent)"
                    isMissing = false
                }
                suggestedWriteURL = envFileURL
            } else if providedByManagedVariables {
                statusText = "Provided by Variable Manager"
                isMissing = false
                suggestedWriteURL = nil
            } else if hasProfileKeychainValue {
                statusText = "Stored in Keychain for this profile"
                isMissing = false
                suggestedWriteURL = nil
            } else if hasProjectKeychainValue {
                statusText = "Inherited from project Keychain"
                isMissing = false
                suggestedWriteURL = nil
            } else if isMarkedExternal {
                statusText = "Marked as external"
                isMissing = false
                suggestedWriteURL = profileEnvironmentFile
            } else {
                statusText = "Missing"
                isMissing = true
                suggestedWriteURL = profileEnvironmentFile
            }

            return ComposeEnvironmentEntry(
                key: key,
                statusText: statusText,
                envFileURL: envFileURL,
                envFileValue: envFileValue,
                suggestedWriteURL: suggestedWriteURL,
                providedByManagedVariables: providedByManagedVariables,
                hasProfileKeychainValue: hasProfileKeychainValue,
                hasProjectKeychainValue: hasProjectKeychainValue,
                isMarkedExternal: isMarkedExternal,
                isMissing: isMissing,
                isEmptyValue: isEmptyValue
            )
        }

        return ComposeEnvironmentOverview(
            workingDirectory: workingDirectory,
            profileEnvironmentFile: profileEnvironmentFile,
            environmentFiles: environmentFiles,
            referencedKeys: sortedReferencedKeys,
            entries: entries,
            profileServiceName: profileServiceName,
            projectServiceName: projectServiceName
        )
    }

    static func saveEnvironmentValue(
        key: String,
        value: String,
        profile: ProfileDefinition,
        store: ProfileStore,
        fileURL: URL?
    ) throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw ValidationError("Environment key is required.")
        }

        let targetURL = fileURL ?? environmentFileURL(for: profile, store: store)
        try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let line = "\(trimmedKey)=\(shellSafeEnvironmentValue(value))"
        let existingText = (try? String(contentsOf: targetURL, encoding: .utf8)) ?? ""
        let lineEnding = existingText.contains("\r\n") ? "\r\n" : "\n"
        let pattern = #"^\s*(?:export\s+)?"# + NSRegularExpression.escapedPattern(for: trimmedKey) + #"\s*="#

        var replaced = false
        let updatedLines = existingText
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)
            .map { currentLine -> String in
                guard currentLine.range(of: pattern, options: .regularExpression) != nil else {
                    return currentLine
                }
                replaced = true
                return line
            }

        let finalText: String
        if replaced {
            finalText = updatedLines.joined(separator: lineEnding)
        } else if existingText.isEmpty {
            finalText = line + lineEnding
        } else {
            let suffix = existingText.hasSuffix("\n") || existingText.hasSuffix("\r\n") ? "" : lineEnding
            finalText = existingText + suffix + line + lineEnding
        }

        try finalText.write(to: targetURL, atomically: true, encoding: .utf8)
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

    static func projectEnvironmentFiles(in workingDirectory: URL) -> [URL] {
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

    static func environmentFileURL(for profile: ProfileDefinition, store: ProfileStore) -> URL {
        ComposePlanBuilder.composeWorkingDirectory(for: profile, store: store)
            .appendingPathComponent(".env.devstack", isDirectory: false)
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
            in: ComposePlanBuilder.composeReferenceText(profile: profile, sourceComposeURLs: sourceComposeURLs)
        )
        guard !referencedKeys.isEmpty else {
            return nil
        }

        var knownValues = ProcessInfo.processInfo.environment
        for url in baseEnvironmentFiles {
            knownValues.merge(parseEnvironmentFile(at: url), uniquingKeysWith: { current, _ in current })
        }

        let secretServices = ComposeSecretSupport.secretServiceNames(profile: profile, workingDirectory: workingDirectory)

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

    private static func shellSafeEnvironmentValue(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: "\\n")
    }
}
