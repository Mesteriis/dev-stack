import Foundation

enum ComposeSecretSupport {
    static func secretOverview(profile: ProfileDefinition, store: ProfileStore) throws -> ComposeSecretOverview {
        let workingDirectory = ComposePlanBuilder.composeWorkingDirectory(for: profile, store: store)
        let sourceComposeURLs = try ComposePlanBuilder.composeSourceURLs(for: profile, store: store)
        let environmentFiles = ComposeEnvironmentService.projectEnvironmentFiles(in: workingDirectory)
        let managedVariables = try ComposeEnvironmentService.applicableManagedVariables(profile: profile, store: store)
        let referencedKeys = ComposeEnvironmentService.referencedEnvironmentKeys(
            in: ComposePlanBuilder.composeReferenceText(profile: profile, sourceComposeURLs: sourceComposeURLs)
        ).sorted()
        let profileServiceName = profileSecretServiceName(for: profile)
        let projectServiceName = projectSecretServiceName(for: workingDirectory)

        var envSourceByKey: [String: URL] = [:]
        for url in environmentFiles {
            for key in ComposeEnvironmentService.parseEnvironmentFile(at: url).keys where envSourceByKey[key] == nil {
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
            } else if profile.externalEnvironmentKeys.contains(key) {
                statusText = "Marked as external"
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

    static func secretServiceNames(profile: ProfileDefinition, workingDirectory: URL) -> [String] {
        var result = [profileSecretServiceName(for: profile)]
        let projectServiceName = projectSecretServiceName(for: workingDirectory)
        if !result.contains(projectServiceName) {
            result.append(projectServiceName)
        }
        return result
    }

    static func profileSecretServiceName(for profile: ProfileDefinition) -> String {
        "devstackmenu.\(slugify(profile.name))"
    }

    static func projectSecretServiceName(for workingDirectory: URL) -> String {
        "devstackmenu.\(slugify(workingDirectory.lastPathComponent))"
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
