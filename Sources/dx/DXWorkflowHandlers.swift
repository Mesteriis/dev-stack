import DevStackCore
import Foundation

enum DXWorkflowHandlers {
    static func handle(_ command: DXCommand, store: ProfileStore) throws {
        switch command {
        case let .addProfile(file):
            try addProfile(composeFileArgument: file, store: store)
        case .addServer:
            _ = try addServer(store: store)
        case let .useProfile(name):
            let report = try DXWorkflowService.useProfile(named: name, store: store)
            print(DXWorkflowService.formatStatus(report))
        case .status:
            print(DXWorkflowService.formatStatus(try DXWorkflowService.status(store: store)))
        case let .envCheck(profile):
            let (resolvedProfile, overview) = try DXWorkflowService.environmentOverview(store: store, profileName: profile)
            print(DXWorkflowService.formatEnvironmentCheck(profileName: resolvedProfile.name, overview: overview))
        case .up:
            print(DXWorkflowService.formatStatus(try DXWorkflowService.up(store: store)))
        case .down:
            print(DXWorkflowService.formatStatus(try DXWorkflowService.down(store: store)))
        }
    }

    private static func addProfile(composeFileArgument: String, store: ProfileStore) throws {
        try DXTerminal.requireInteractive()
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let composeURL = resolvedFileURL(argument: composeFileArgument, currentDirectory: currentDirectory)
        guard FileManager.default.fileExists(atPath: composeURL.path) else {
            throw DXCLIError("Compose file not found: \(composeURL.path)")
        }

        let imported = try ProfileImportService.importedServices(from: composeURL)
        let dockerContexts = (try? RuntimeController.dockerContexts()) ?? []
        var runtimeTargets = (try? store.runtimeTargets()) ?? []

        if runtimeTargets.isEmpty {
            print("No runtimes configured yet.")
            if try DXTerminal.confirm("Create one now?", defaultYes: true) {
                runtimeTargets = [try addServer(store: store)]
            } else {
                throw DXCLIError("Run `dx add server` first, then retry `dx add profile`.")
            }
        }

        let defaultProfileName = composeURL.deletingLastPathComponent().lastPathComponent
        let profileName = try DXTerminal.prompt("Profile name", defaultValue: defaultProfileName)
        let selectedRuntime = try selectRuntime(from: runtimeTargets)
        let overlayCandidates = suggestedOverlayFiles(for: composeURL)
        let selectedOverlays = try DXTerminal.chooseManyURLs(
            title: "Optional compose overlays detected:",
            options: overlayCandidates
        )

        let existingProfile = try? store.loadProfile(named: profileName)
        let replaceServices: Bool
        if existingProfile != nil {
            replaceServices = try DXTerminal.confirm("Profile exists. Replace imported services?", defaultYes: true)
        } else {
            replaceServices = true
        }

        let request = ComposeImportRequest(
            composeURL: composeURL,
            composeOverlayURLs: selectedOverlays,
            targetProfileName: profileName,
            replaceServices: replaceServices,
            services: imported.services,
            composeContent: imported.content,
            composeWorkingDirectory: composeURL.deletingLastPathComponent().path,
            composeProjectName: composeURL.deletingLastPathComponent().lastPathComponent
        )

        var profile = try ProfileImportService.draftProfile(
            from: request,
            store: store,
            currentProfileName: store.currentProfileName(),
            activeDockerContext: try? RuntimeController.currentDockerContext(),
            dockerContexts: dockerContexts,
            runtimeTargets: runtimeTargets
        )
        profile.runtimeName = selectedRuntime.name
        profile.dockerContext = selectedRuntime.dockerContext
        profile.tunnelHost = selectedRuntime.remoteDockerServerDisplay
        profile = try profile.normalized()

        try resolveMissingEnvironment(for: &profile, store: store)
        try store.saveProfile(profile, originalName: existingProfile?.name)

        let finalOverview = try ComposeSupport.environmentOverview(profile: profile, store: store)
        let unresolvedCount = finalOverview.entries.filter { $0.isMissing || $0.isEmptyValue }.count
        let composeFiles = ([composeURL] + selectedOverlays).map { $0.lastPathComponent }.joined(separator: ", ")

        print("Created profile \(profile.name)")
        print("Runtime: \(selectedRuntime.name) -> \(selectedRuntime.connectionSummary)")
        print("Compose files: \(composeFiles)")
        print("Imported services: \(profile.services.count)")
        print("Unresolved env vars: \(unresolvedCount)")

        if try DXTerminal.confirm("Open DevStackMenu now?", defaultYes: false) {
            DXAppBridge.openDevStackMenu()
        }
    }

    private static func addServer(store: ProfileStore) throws -> RemoteServerDefinition {
        try DXTerminal.requireInteractive()
        let dockerContexts = (try? RuntimeController.dockerContexts()) ?? []
        let kind = try DXTerminal.chooseOne(
            title: "Select runtime type:",
            options: [RemoteServerTransport.local, .ssh],
            defaultIndex: dockerContexts.isEmpty ? 1 : 0,
            render: { $0.title }
        )

        let runtime: RemoteServerDefinition
        let bootstrapIfNeeded: Bool
        switch kind {
        case .local:
            guard !dockerContexts.isEmpty else {
                throw DXCLIError("No Docker contexts found on this Mac.")
            }
            let context = try DXTerminal.chooseOne(
                title: "Available Docker contexts:",
                options: dockerContexts,
                defaultIndex: dockerContexts.firstIndex(where: \.isCurrent) ?? 0,
                render: { context in
                    let currentSuffix = context.isCurrent ? "  [current]" : ""
                    return "\(context.name)  \(context.endpoint)\(currentSuffix)"
                }
            )
            let name = try DXTerminal.prompt("Runtime name", defaultValue: context.name)
            runtime = try RemoteServerDefinition(
                name: name,
                transport: .local,
                dockerContext: context.name
            ).normalized()
            bootstrapIfNeeded = false
        case .ssh:
            let name = try DXTerminal.prompt("Runtime name")
            let host = try DXTerminal.prompt("SSH host")
            let user = try DXTerminal.prompt("SSH user", defaultValue: "root")
            let portText = try DXTerminal.prompt("SSH port", defaultValue: "22")
            let port = Int(portText) ?? 22
            let contextDefault = "srv-\(dxSlugify(name))"
            let dockerContext = try DXTerminal.prompt("Docker context", defaultValue: contextDefault)
            let remoteDataRoot = try DXTerminal.prompt("Remote data root", defaultValue: "/var/lib/devstackmenu")
            bootstrapIfNeeded = try DXTerminal.confirm("Bootstrap Docker if missing?", defaultYes: true)
            runtime = try RemoteServerDefinition(
                name: name,
                transport: .ssh,
                dockerContext: dockerContext,
                sshHost: host,
                sshPort: port,
                sshUser: user,
                remoteDataRoot: remoteDataRoot
            ).normalized()
        }

        let prepared = try RuntimeController.prepareServer(
            server: runtime,
            store: store,
            bootstrapIfNeeded: bootstrapIfNeeded
        )
        try store.saveRuntime(prepared.server, originalName: nil)
        print("Saved runtime \(prepared.server.name)")
        print("Connection: \(prepared.server.connectionSummary)")
        print("Remote OS: \(prepared.remoteOS)")
        print("Docker: \(prepared.serverVersion)")
        return prepared.server
    }

    private static func resolveMissingEnvironment(for profile: inout ProfileDefinition, store: ProfileStore) throws {
        var ignoredKeys = Set<String>()
        while true {
            let overview = try ComposeSupport.environmentOverview(profile: profile, store: store, ignoredKeys: ignoredKeys)
            let pending = overview.entries.filter { $0.isMissing || $0.isEmptyValue }
            guard let entry = pending.first else {
                return
            }

            print("")
            print("Compose variable \(entry.key): \(entry.statusText)")
            let choice = try DXTerminal.chooseOne(
                title: "How should DevStack handle it?",
                options: ["Generate", "Ignore", "Mark as external"],
                defaultIndex: ContextValueGenerator.looksSensitive(key: entry.key) ? 0 : 1,
                render: { $0 }
            )

            switch choice {
            case "Generate":
                let generator = try DXTerminal.chooseOne(
                    title: "Generator type:",
                    options: EnvironmentValueGeneratorKind.allCases,
                    defaultIndex: ContextValueGenerator.looksSensitive(key: entry.key) ? 1 : 0,
                    render: { $0.title }
                )
                let value = try ContextValueGenerator.generate(kind: generator)
                let canSaveToKeychain = entry.envFileURL == nil && !entry.isEmptyValue
                let shouldSaveToKeychain = canSaveToKeychain && ContextValueGenerator.looksSensitive(key: entry.key)
                    ? try DXTerminal.confirm("Save \(entry.key) in Keychain instead of .env.devstack?", defaultYes: true)
                    : false

                profile.externalEnvironmentKeys.removeAll { $0 == entry.key }
                if shouldSaveToKeychain {
                    try ComposeSupport.saveProfileSecret(key: entry.key, value: value, profile: profile)
                } else {
                    try ComposeSupport.saveEnvironmentValue(
                        key: entry.key,
                        value: value,
                        profile: profile,
                        store: store,
                        fileURL: entry.suggestedWriteURL
                    )
                }
            case "Ignore":
                ignoredKeys.insert(entry.key)
            default:
                if !profile.externalEnvironmentKeys.contains(entry.key) {
                    profile.externalEnvironmentKeys.append(entry.key)
                }
                profile = try profile.normalized()
            }
        }
    }

    private static func resolvedFileURL(argument: String, currentDirectory: URL) -> URL {
        let expanded = NSString(string: argument).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded, isDirectory: false).standardizedFileURL
        }
        return currentDirectory.appendingPathComponent(expanded, isDirectory: false).standardizedFileURL
    }

    private static func selectRuntime(from runtimeTargets: [RemoteServerDefinition]) throws -> RemoteServerDefinition {
        if runtimeTargets.count == 1, let only = runtimeTargets.first {
            print("Using runtime: \(only.name) (\(only.connectionSummary))")
            return only
        }
        return try DXTerminal.chooseOne(
            title: "Available runtimes:",
            options: runtimeTargets.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            render: { "\($0.name)  \($0.connectionSummary)" }
        )
    }

    private static func suggestedOverlayFiles(for composeURL: URL) -> [URL] {
        let directory = composeURL.deletingLastPathComponent()
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .filter {
                $0 != composeURL
                    && ["yml", "yaml"].contains($0.pathExtension.lowercased())
                    && ($0.lastPathComponent.localizedCaseInsensitiveContains("compose")
                        || $0.lastPathComponent.localizedCaseInsensitiveContains("docker-compose"))
            }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func dxSlugify(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { result, character in
                if character == "-" {
                    if result.last != "-" {
                        result.append(character)
                    }
                } else {
                    result.append(contentsOf: String(character).lowercased())
                }
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
