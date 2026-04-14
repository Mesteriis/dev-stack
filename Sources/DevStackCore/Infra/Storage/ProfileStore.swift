import Foundation

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

    package init(rootDirectory: URL, logsDirectory: URL, launchAgentsDirectory: URL) {
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

    package var runtimesDirectory: URL {
        serversDirectory
    }

    package func profileNames() throws -> [String] {
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

    package func serverNames() throws -> [String] {
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

    package func remoteServers() throws -> [RemoteServerDefinition] {
        try serverNames().compactMap { try loadServer(named: $0) }
    }

    package func loadServer(named name: String) throws -> RemoteServerDefinition {
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

    package func saveServer(_ server: RemoteServerDefinition, originalName: String?) throws {
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

    package func deleteServer(named name: String) throws {
        let fileManager = FileManager.default
        for url in [serverURL(named: name), legacyServerURL(named: name)] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    package func runtimeNames() throws -> [String] {
        try serverNames()
    }

    package func runtimeTargets() throws -> [RemoteServerDefinition] {
        try remoteServers()
    }

    package func loadRuntime(named name: String) throws -> RemoteServerDefinition {
        try loadServer(named: name)
    }

    package func saveRuntime(_ runtime: RemoteServerDefinition, originalName: String?) throws {
        try saveServer(runtime, originalName: originalName)
    }

    package func deleteRuntime(named name: String) throws {
        try deleteServer(named: name)
    }

    package func currentProfileName() -> String? {
        guard let text = try? String(contentsOf: currentProfileFile, encoding: .utf8) else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    package func saveCurrentProfile(_ name: String) throws {
        try ensureRuntimeDirectories()
        try "\(name)\n".write(to: currentProfileFile, atomically: true, encoding: .utf8)
    }

    package func clearCurrentProfile() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: currentProfileFile.path) {
            try fileManager.removeItem(at: currentProfileFile)
        }
    }

    package func activeProfileNames() -> [String] {
        guard let data = try? Data(contentsOf: activeProfilesFile),
              let names = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }

        return names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    package func saveActiveProfileNames(_ names: [String]) throws {
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

    package func markProfileActive(_ name: String) throws {
        var names = activeProfileNames()
        if !names.contains(name) {
            names.append(name)
        }
        try saveActiveProfileNames(names)
    }

    package func markProfileInactive(_ name: String) throws {
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

    package func managedVariables() throws -> [ManagedVariableDefinition] {
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

    package func saveManagedVariables(_ variables: [ManagedVariableDefinition]) throws {
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

    package func upsertManagedVariable(_ variable: ManagedVariableDefinition) throws {
        let normalized = try variable.normalized()
        var values = try managedVariables().filter { $0.name != normalized.name }
        values.append(normalized)
        try saveManagedVariables(values)
    }

    package func deleteManagedVariable(named name: String) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = try managedVariables().filter { $0.name != trimmedName }
        try saveManagedVariables(updated)
    }

    package func renameManagedVariableProfileReferences(from oldName: String, to newName: String) throws {
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

    package func removeManagedVariableProfileReferences(for profileName: String) throws {
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

    package func profileURL(named name: String) -> URL {
        profilesDirectory.appendingPathComponent("\(name).json", isDirectory: false)
    }

    package func composeFileURL(for profileName: String) -> URL {
        generatedDirectory
            .appendingPathComponent(profileName, isDirectory: true)
            .appendingPathComponent("docker-compose.generated.yml", isDirectory: false)
    }

    package func generatedProfileDirectory(for profileName: String) -> URL {
        generatedDirectory.appendingPathComponent(profileName, isDirectory: true)
    }

    package func generatedComposeSourceURL(for profileName: String) -> URL {
        generatedProfileDirectory(for: profileName)
            .appendingPathComponent("docker-compose.source.yml", isDirectory: false)
    }

    package func generatedComposePlanURL(for profileName: String) -> URL {
        generatedProfileDirectory(for: profileName)
            .appendingPathComponent("compose-plan.txt", isDirectory: false)
    }

    package func generatedComposeLogsURL(for profileName: String) -> URL {
        logsDirectory.appendingPathComponent("\(slugify(profileName)).compose.log", isDirectory: false)
    }

    package func generatedVolumeReportURL(for profileName: String) -> URL {
        generatedProfileDirectory(for: profileName)
            .appendingPathComponent("volume-report.txt", isDirectory: false)
    }

    package func generatedMetricsReportURL(for profileName: String) -> URL {
        generatedProfileDirectory(for: profileName)
            .appendingPathComponent("metrics-report.txt", isDirectory: false)
    }

    package func generatedRemoteBrowseReportURL(for profileName: String) -> URL {
        generatedProfileDirectory(for: profileName)
            .appendingPathComponent("remote-files.txt", isDirectory: false)
    }

    package func generatedSecretsEnvURL(for profileName: String) -> URL {
        generatedProfileDirectory(for: profileName)
            .appendingPathComponent("secrets.env", isDirectory: false)
    }

    package func generatedManagedVariablesEnvURL(for profileName: String) -> URL {
        generatedProfileDirectory(for: profileName)
            .appendingPathComponent("managed-vars.env", isDirectory: false)
    }

    package func sourceComposeURLs(for profile: ProfileDefinition) -> [URL] {
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

    package func sourceComposeURL(for profile: ProfileDefinition) -> URL? {
        sourceComposeURLs(for: profile).first
    }

    package func managedProjectDirectory(for profile: ProfileDefinition) -> URL? {
        if let sourceComposeURL = sourceComposeURL(for: profile) {
            return sourceComposeURL.deletingLastPathComponent()
        }

        let path = profile.compose.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
    }

    package func profileDataDirectory(for profile: ProfileDefinition) -> URL {
        if let projectDirectory = managedProjectDirectory(for: profile) {
            return projectDirectory.appendingPathComponent("data", isDirectory: true)
        }
        return generatedProfileDirectory(for: profile.name).appendingPathComponent("data", isDirectory: true)
    }

    package func serviceDataDirectory(for profile: ProfileDefinition, serviceName: String) -> URL {
        profileDataDirectory(for: profile).appendingPathComponent(slugify(serviceName), isDirectory: true)
    }

    package func serverURL(named name: String) -> URL {
        serversDirectory.appendingPathComponent("\(name).json", isDirectory: false)
    }

    package func legacyServerURL(named name: String) -> URL {
        legacyServersDirectory.appendingPathComponent("\(name).json", isDirectory: false)
    }

    package func launchAgentPrefix(for profileName: String) -> String {
        "local.devstackmenu.\(slugify(profileName))"
    }

    package func launchAgentLabel(for profileName: String, serverName: String) -> String {
        "\(launchAgentPrefix(for: profileName)).\(slugify(serverName))"
    }

    package func launchTarget(for label: String) -> String {
        "gui/\(getuid())/\(label)"
    }

    package func launchAgentPlistURL(for label: String) -> URL {
        launchAgentsDirectory.appendingPathComponent("\(label).plist", isDirectory: false)
    }

    package func launchAgentPlistURLs(for profileName: String) -> [URL] {
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
