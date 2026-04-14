import Foundation

package enum DXCommand: Equatable {
    case addProfile(file: String)
    case addServer
    case useProfile(name: String)
    case status
    case envCheck(profile: String?)
    case up
    case down
}

package struct DXCLIError: LocalizedError, Sendable {
    let message: String

    package init(_ message: String) {
        self.message = message
    }

    package var errorDescription: String? {
        message
    }
}

package enum DXCommandParser {
    package static func parse(_ arguments: [String]) throws -> DXCommand {
        guard let first = arguments.first else {
            throw DXCLIError(usageText)
        }

        switch first {
        case "add":
            return try parseAdd(Array(arguments.dropFirst()))
        case "use":
            return try parseUse(Array(arguments.dropFirst()))
        case "status":
            guard arguments.count == 1 else {
                throw DXCLIError("`dx status` does not take extra arguments.")
            }
            return .status
        case "env":
            return try parseEnv(Array(arguments.dropFirst()))
        case "up":
            guard arguments.count == 1 else {
                throw DXCLIError("`dx up` does not take extra arguments.")
            }
            return .up
        case "down":
            guard arguments.count == 1 else {
                throw DXCLIError("`dx down` does not take extra arguments.")
            }
            return .down
        case "help", "--help", "-h":
            throw DXCLIError(usageText)
        default:
            throw DXCLIError("Unknown command `\(first)`.\n\n\(usageText)")
        }
    }

    package static let usageText = """
    Usage:
      dx add profile -f docker-compose.yml
      dx add server
      dx use profile <name>
      dx status
      dx env check [--profile <name>]
      dx up
      dx down
    """

    private static func parseAdd(_ arguments: [String]) throws -> DXCommand {
        guard let subject = arguments.first else {
            throw DXCLIError("Specify what to add.\n\n\(usageText)")
        }

        switch subject {
        case "profile":
            var filePath: String?
            var index = 1
            while index < arguments.count {
                let argument = arguments[index]
                switch argument {
                case "-f", "--file":
                    index += 1
                    guard index < arguments.count else {
                        throw DXCLIError("`dx add profile` requires a compose file after \(argument).")
                    }
                    filePath = arguments[index]
                default:
                    throw DXCLIError("Unknown argument for `dx add profile`: \(argument)")
                }
                index += 1
            }

            guard let filePath else {
                throw DXCLIError("`dx add profile` requires `-f <compose-file>`.")
            }
            return .addProfile(file: filePath)
        case "server":
            guard arguments.count == 1 else {
                throw DXCLIError("`dx add server` does not take extra arguments.")
            }
            return .addServer
        default:
            throw DXCLIError("Unknown add target `\(subject)`.\n\n\(usageText)")
        }
    }

    private static func parseUse(_ arguments: [String]) throws -> DXCommand {
        guard arguments.count == 2, arguments[0] == "profile" else {
            throw DXCLIError("Usage: dx use profile <name>")
        }
        return .useProfile(name: arguments[1])
    }

    private static func parseEnv(_ arguments: [String]) throws -> DXCommand {
        guard let subject = arguments.first, subject == "check" else {
            throw DXCLIError("Usage: dx env check [--profile <name>]")
        }

        var profileName: String?
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--profile":
                index += 1
                guard index < arguments.count else {
                    throw DXCLIError("`dx env check` requires a profile name after --profile.")
                }
                profileName = arguments[index]
            default:
                throw DXCLIError("Unknown argument for `dx env check`: \(argument)")
            }
            index += 1
        }

        return .envCheck(profile: profileName)
    }
}

package struct DXStatusReport: Sendable {
    let activeProfileName: String?
    let activeRuntimeName: String?
    let activeRuntimeDisplay: String?
    let activeDockerContext: String
    let snapshot: AppSnapshot?
}

package enum DXWorkflowService {
    package static func useProfile(
        named profileName: String,
        store: ProfileStore,
        activate: (String, ProfileStore) throws -> Void = { name, store in
            try RuntimeController.activateProfile(named: name, store: store)
        },
        snapshotProvider: (ProfileStore, String) throws -> AppSnapshot = { store, profileName in
            try RuntimeController.statusSnapshot(store: store, profileName: profileName)
        }
    ) throws -> DXStatusReport {
        try activate(profileName, store)
        return try status(store: store, snapshotProvider: snapshotProvider)
    }

    package static func status(
        store: ProfileStore,
        snapshotProvider: (ProfileStore, String) throws -> AppSnapshot = { store, profileName in
            try RuntimeController.statusSnapshot(store: store, profileName: profileName)
        }
    ) throws -> DXStatusReport {
        let knownProfiles = (try? store.profileNames()) ?? []
        let activeProfileName = store.currentProfileName().flatMap { knownProfiles.contains($0) ? $0 : nil }
        let currentDockerContext = (try? RuntimeController.currentDockerContext()) ?? "unknown"
        guard let activeProfileName, let profile = try? store.loadProfile(named: activeProfileName) else {
            return DXStatusReport(
                activeProfileName: nil,
                activeRuntimeName: nil,
                activeRuntimeDisplay: nil,
                activeDockerContext: currentDockerContext,
                snapshot: nil
            )
        }

        let runtime = try loadRuntime(for: profile, store: store)
        let snapshot = try? snapshotProvider(store, activeProfileName)
        return DXStatusReport(
            activeProfileName: activeProfileName,
            activeRuntimeName: runtime?.name,
            activeRuntimeDisplay: runtime?.remoteDockerServerDisplay ?? profile.remoteDockerServer,
            activeDockerContext: snapshot?.configuredDockerContext ?? currentDockerContext,
            snapshot: snapshot
        )
    }

    package static func up(
        store: ProfileStore,
        start: (String, ProfileStore) throws -> Void = { profileName, store in
            try RuntimeController.composeUp(profileName: profileName, store: store)
        },
        snapshotProvider: (ProfileStore, String) throws -> AppSnapshot = { store, profileName in
            try RuntimeController.statusSnapshot(store: store, profileName: profileName)
        }
    ) throws -> DXStatusReport {
        guard let activeProfile = store.currentProfileName() else {
            throw DXCLIError("No active profile. Use `dx use profile <name>` first.")
        }
        try start(activeProfile, store)
        return try status(store: store, snapshotProvider: snapshotProvider)
    }

    package static func down(
        store: ProfileStore,
        stop: (String, ProfileStore) throws -> Void = { profileName, store in
            try RuntimeController.composeDown(profileName: profileName, store: store)
        },
        snapshotProvider: (ProfileStore, String) throws -> AppSnapshot = { store, profileName in
            try RuntimeController.statusSnapshot(store: store, profileName: profileName)
        }
    ) throws -> DXStatusReport {
        guard let activeProfile = store.currentProfileName() else {
            throw DXCLIError("No active profile. Use `dx use profile <name>` first.")
        }
        try stop(activeProfile, store)
        return try status(store: store, snapshotProvider: snapshotProvider)
    }

    package static func environmentOverview(
        store: ProfileStore,
        profileName: String?
    ) throws -> (profile: ProfileDefinition, overview: ComposeEnvironmentOverview) {
        let profile = try resolveProfile(store: store, requestedProfileName: profileName)
        let overview = try ComposeSupport.environmentOverview(profile: profile, store: store)
        return (profile, overview)
    }

    package static func resolveProfile(store: ProfileStore, requestedProfileName: String?) throws -> ProfileDefinition {
        if let requestedProfileName {
            return try store.loadProfile(named: requestedProfileName)
        }
        guard let activeProfile = store.currentProfileName() else {
            throw DXCLIError("No active profile. Use `dx use profile <name>` or pass `--profile`.")
        }
        return try store.loadProfile(named: activeProfile)
    }

    package static func formatStatus(_ report: DXStatusReport) -> String {
        var lines: [String] = []
        lines.append("Profile: \(report.activeProfileName ?? "none")")
        lines.append("Runtime: \(report.activeRuntimeName ?? "none")")
        lines.append("Docker context: \(report.activeDockerContext)")
        if let activeRuntimeDisplay = report.activeRuntimeDisplay {
            lines.append("Docker endpoint: \(activeRuntimeDisplay)")
        }
        if let snapshot = report.snapshot {
            lines.append("Tunnel: \(snapshot.tunnelLoaded ? "loaded" : "stopped")")
            if snapshot.compose.configured {
                lines.append("Compose: \(snapshot.compose.projectName) (\(snapshot.compose.runningServices.count) running)")
            }
            if !snapshot.services.isEmpty {
                lines.append("Forwarded services: \(snapshot.services.count)")
            }
        }
        return lines.joined(separator: "\n")
    }

    package static func formatEnvironmentCheck(profileName: String, overview: ComposeEnvironmentOverview) -> String {
        var lines: [String] = []
        lines.append("Profile: \(profileName)")
        lines.append("Working directory: \(overview.workingDirectory.path)")
        lines.append("Compose refs: \(overview.referencedKeys.count)")
        let unresolvedCount = overview.entries.filter { $0.isMissing || $0.isEmptyValue }.count
        lines.append("Unresolved: \(unresolvedCount)")
        if overview.entries.isEmpty {
            lines.append("Environment: all referenced variables are resolved")
            return lines.joined(separator: "\n")
        }

        lines.append("Environment:")
        for entry in overview.entries {
            let source: String
            if let envFileURL = entry.envFileURL {
                source = envFileURL.lastPathComponent
            } else if entry.providedByManagedVariables {
                source = "Variable Manager"
            } else if entry.hasProfileKeychainValue {
                source = "Profile Keychain"
            } else if entry.hasProjectKeychainValue {
                source = "Project Keychain"
            } else if entry.isMarkedExternal {
                source = "External"
            } else {
                source = "Unresolved"
            }
            lines.append("- \(entry.key): \(entry.statusText) [source: \(source)]")
        }
        return lines.joined(separator: "\n")
    }

    private static func loadRuntime(for profile: ProfileDefinition, store: ProfileStore) throws -> RemoteServerDefinition? {
        guard !profile.runtimeName.isEmpty else {
            return nil
        }
        return try store.loadRuntime(named: profile.runtimeName)
    }
}
