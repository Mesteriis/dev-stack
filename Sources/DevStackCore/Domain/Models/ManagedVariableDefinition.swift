import Foundation

package struct ManagedVariableDefinition: Codable, Equatable, Sendable {
    package var name = ""
    package var value = ""
    package var profileNames: [String] = []

    package init(name: String = "", value: String = "", profileNames: [String] = []) {
        self.name = name
        self.value = value
        self.profileNames = profileNames
    }

    package func normalized() throws -> ManagedVariableDefinition {
        var copy = self
        copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !copy.name.isEmpty else {
            throw ValidationError("Variable name is required.")
        }

        guard copy.name.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
            throw ValidationError("Variable '\(copy.name)' is not a valid env variable name.")
        }

        var uniqueProfileNames: [String] = []
        for profileName in copy.profileNames.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !profileName.isEmpty {
            if !uniqueProfileNames.contains(profileName) {
                uniqueProfileNames.append(profileName)
            }
        }
        copy.profileNames = uniqueProfileNames.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        guard !copy.profileNames.isEmpty else {
            throw ValidationError("Variable '\(copy.name)' must be assigned to at least one profile.")
        }

        return copy
    }

    package func applies(to profileName: String) -> Bool {
        profileNames.contains(profileName)
    }
}
