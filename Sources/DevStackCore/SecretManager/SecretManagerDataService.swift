import Foundation

enum SecretManagerDataService {
    static func secretOverview(profile: ProfileDefinition, store: ProfileStore) throws -> ComposeSecretOverview {
        try ComposeSupport.secretOverview(profile: profile, store: store)
    }

    static func saveProfileSecret(key: String, value: String, profile: ProfileDefinition) throws {
        try ComposeSupport.saveProfileSecret(key: key, value: value, profile: profile)
    }

    static func deleteProfileSecret(key: String, profile: ProfileDefinition) throws {
        try ComposeSupport.deleteProfileSecret(key: key, profile: profile)
    }

    static func summaryLines(overview: ComposeSecretOverview) -> [String] {
        [
            "Working directory: \(overview.workingDirectory.path)",
            "Env files: \(overview.environmentFiles.isEmpty ? "none" : overview.environmentFiles.map(\.lastPathComponent).joined(separator: ", "))",
            "Referenced keys: \(overview.referencedKeys.isEmpty ? "none" : String(overview.referencedKeys.count))",
            "Keychain service: \(overview.profileServiceName)",
        ]
    }
}
