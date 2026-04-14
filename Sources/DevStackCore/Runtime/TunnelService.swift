import Foundation

private struct TunnelEndpoint: Hashable, Sendable {
    let labelComponent: String
    let displayName: String
    let sshTarget: String
    let sshPort: Int
}

enum TunnelService {
    static func bootstrapAgents(profile: ProfileDefinition, store: ProfileStore) throws {
        var grouped: [TunnelEndpoint: [ServiceDefinition]] = [:]
        for service in profile.services where service.enabled {
            guard let endpoint = try resolveTunnelEndpoint(for: service, profile: profile, store: store) else {
                throw ValidationError("Profile '\(profile.name)' uses service tunnels but its server is local. Choose an SSH server or override the service server.")
            }
            grouped[endpoint, default: []].append(service)
        }

        try bootoutAgents(profileName: profile.name, store: store)
        try store.ensureRuntimeDirectories()

        for (endpoint, services) in grouped {
            let label = store.launchAgentLabel(for: profile.name, serverName: endpoint.labelComponent)
            let plistURL = store.launchAgentPlistURL(for: label)

            var programArguments = [
                "/usr/bin/ssh",
                "-NT",
                "-o",
                "BatchMode=yes",
                "-o",
                "StrictHostKeyChecking=accept-new",
                "-o",
                "ExitOnForwardFailure=yes",
                "-o",
                "ServerAliveInterval=30",
                "-o",
                "ServerAliveCountMax=3",
                "-o",
                "ControlMaster=no",
            ]

            if endpoint.sshPort != 22 {
                programArguments.append(contentsOf: ["-p", String(endpoint.sshPort)])
            }

            for service in services.sorted(by: { $0.localPort < $1.localPort }) {
                programArguments.append(contentsOf: [
                    "-L",
                    "127.0.0.1:\(service.localPort):\(service.remoteHost):\(service.remotePort)",
                    "-L",
                    "[::1]:\(service.localPort):\(service.remoteHost):\(service.remotePort)",
                ])
            }

            programArguments.append(endpoint.sshTarget)

            let plistData: [String: Any] = [
                "Label": label,
                "ProgramArguments": programArguments,
                "RunAtLoad": true,
                "KeepAlive": true,
                "StandardOutPath": store.logsDirectory.appendingPathComponent("\(label).out.log").path,
                "StandardErrorPath": store.logsDirectory.appendingPathComponent("\(label).err.log").path,
                "ProcessType": "Background",
            ]

            let encoded = try PropertyListSerialization.data(
                fromPropertyList: plistData,
                format: .xml,
                options: 0
            )
            try encoded.write(to: plistURL, options: .atomic)

            let lint = Shell.run("/usr/bin/plutil", arguments: ["-lint", plistURL.path])
            guard lint.exitCode == 0 else {
                throw ValidationError(RuntimeSharedSupport.nonEmpty(lint.stderr) ?? RuntimeSharedSupport.nonEmpty(lint.stdout) ?? "launchd plist validation failed")
            }

            let bootstrap = Shell.run(
                "/bin/launchctl",
                arguments: ["bootstrap", "gui/\(getuid())", plistURL.path]
            )
            guard bootstrap.exitCode == 0 else {
                throw ValidationError(RuntimeSharedSupport.nonEmpty(bootstrap.stderr) ?? RuntimeSharedSupport.nonEmpty(bootstrap.stdout) ?? "Failed to bootstrap launch agent")
            }

            let kickstart = Shell.run(
                "/bin/launchctl",
                arguments: ["kickstart", "-k", store.launchTarget(for: label)]
            )
            guard kickstart.exitCode == 0 else {
                throw ValidationError(RuntimeSharedSupport.nonEmpty(kickstart.stderr) ?? RuntimeSharedSupport.nonEmpty(kickstart.stdout) ?? "Failed to start launch agent")
            }
        }
    }

    static func bootoutAgents(profileName: String, store: ProfileStore) throws {
        let plistURLs = store.launchAgentPlistURLs(for: profileName)

        for plistURL in plistURLs {
            let label = plistURL.deletingPathExtension().lastPathComponent
            _ = Shell.run(
                "/bin/launchctl",
                arguments: ["bootout", store.launchTarget(for: label)]
            )
            try? FileManager.default.removeItem(at: plistURL)
        }
    }

    static func agentLoaded(profileName: String, store: ProfileStore) -> Bool {
        for plistURL in store.launchAgentPlistURLs(for: profileName) {
            let label = plistURL.deletingPathExtension().lastPathComponent
            let result = Shell.run(
                "/bin/launchctl",
                arguments: ["print", store.launchTarget(for: label)]
            )
            if result.exitCode == 0 {
                return true
            }
        }
        return false
    }

    static func tunnelDisplayName(
        for service: ServiceDefinition,
        profile: ProfileDefinition,
        store: ProfileStore,
        fallback: String
    ) -> String {
        if let endpoint = try? resolveTunnelEndpoint(for: service, profile: profile, store: store) {
            return endpoint.displayName
        }
        return service.tunnelHost.isEmpty ? fallback : service.tunnelHost
    }

    private static func resolveTunnelEndpoint(
        for service: ServiceDefinition,
        profile: ProfileDefinition,
        store: ProfileStore
    ) throws -> TunnelEndpoint? {
        let override = service.tunnelHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty {
            if let server = try? store.loadServer(named: override) {
                guard !server.isLocal else {
                    throw ValidationError("Server '\(server.name)' is local and cannot be used for SSH tunnels.")
                }
                return TunnelEndpoint(
                    labelComponent: server.name,
                    displayName: server.remoteDockerServerDisplay,
                    sshTarget: server.sshTarget,
                    sshPort: server.sshPort
                )
            }

            return TunnelEndpoint(
                labelComponent: override,
                displayName: override,
                sshTarget: override,
                sshPort: 22
            )
        }

        let resolvedServer = try RuntimeSharedSupport.resolvePrimaryServer(for: profile, store: store)
        guard let sshTarget = resolvedServer.sshTarget else {
            return nil
        }

        return TunnelEndpoint(
            labelComponent: resolvedServer.name,
            displayName: resolvedServer.remoteDockerServer,
            sshTarget: sshTarget,
            sshPort: resolvedServer.sshPort
        )
    }
}
