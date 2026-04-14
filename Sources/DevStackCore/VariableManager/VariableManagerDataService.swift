import Foundation

enum VariableManagerDataService {
    static func importVariables(
        _ imported: [String: String],
        assignedProfiles: [String],
        overwriteExistingValues: Bool,
        store: ProfileStore
    ) throws -> (created: Int, updated: Int) {
        var currentValues = Dictionary(uniqueKeysWithValues: try store.managedVariables().map { ($0.name, $0) })
        var created = 0
        var updated = 0

        for (name, value) in imported.sorted(by: { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }) {
            if var existing = currentValues[name] {
                if overwriteExistingValues {
                    existing.value = value
                }
                existing.profileNames = Array(Set(existing.profileNames + assignedProfiles))
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                currentValues[name] = try existing.normalized()
                updated += 1
            } else {
                currentValues[name] = try ManagedVariableDefinition(
                    name: name,
                    value: value,
                    profileNames: assignedProfiles
                ).normalized()
                created += 1
            }
        }

        try store.saveManagedVariables(Array(currentValues.values))
        return (created, updated)
    }

    static func suggestedProfileNames(for envURL: URL, store: ProfileStore) -> [String] {
        let envDirectory = envURL.deletingLastPathComponent().standardizedFileURL
        let envGit = GitProjectInspector.inspectProject(at: envDirectory)
        let profiles = (try? store.profileNames().compactMap { try? store.loadProfile(named: $0) }) ?? []

        return profiles.compactMap { profile in
            guard let projectDirectory = store.managedProjectDirectory(for: profile) else {
                return nil
            }
            if projectDirectory.standardizedFileURL.path == envDirectory.path {
                return profile.name
            }
            let profileGit = GitProjectInspector.inspectProject(at: projectDirectory)
            if envGit?.repositoryRoot == profileGit?.repositoryRoot, envGit?.repositoryRoot != nil {
                return profile.name
            }
            return nil
        }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
