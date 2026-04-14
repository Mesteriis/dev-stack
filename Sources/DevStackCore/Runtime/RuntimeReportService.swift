import Foundation

enum RuntimeReportService {
    static func composePreview(profileName: String, store: ProfileStore) throws -> ComposeActionPreview {
        let profile = try store.loadProfile(named: profileName)
        let plan = try ComposeSupport.plan(profile: profile, store: store)
        let diagnostics = try RuntimeDiagnosticsService.runtimeDiagnostics(profile: profile, store: store, plan: plan)
        let runningServices = try RuntimeSharedSupport.composePS(profile: profile, store: store).map(\.displayName).sorted()
        return ComposeActionPreview(plan: plan, diagnostics: diagnostics, runningServiceNames: runningServices)
    }

    static func writeComposeLogsSnapshot(profileName: String, store: ProfileStore) throws -> URL {
        let profile = try store.loadProfile(named: profileName)
        let result = RuntimeSharedSupport.runCompose(profile: profile, store: store, subcommand: ["logs", "--no-color", "--timestamps", "--tail", "400"])
        guard result.exitCode == 0 else {
            throw ValidationError(RuntimeSharedSupport.nonEmpty(result.stderr) ?? RuntimeSharedSupport.nonEmpty(result.stdout) ?? "docker compose logs failed")
        }

        let outputURL = store.generatedComposeLogsURL(for: profile.name)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try result.stdout.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    static func writeVolumeReport(profileName: String, store: ProfileStore) throws -> URL {
        let profile = try store.loadProfile(named: profileName)
        let records = try RuntimeSharedSupport.composeVolumes(profile: profile, store: store)
        var lines: [String] = []
        lines.append("Profile: \(profile.name)")
        lines.append("Project: \(ComposePlanBuilder.composeProjectName(for: profile))")
        lines.append("")
        if records.isEmpty {
            lines.append("No compose volumes found.")
        } else {
            for record in records {
                lines.append("- \(record.name)")
                if let driver = record.driver {
                    lines.append("  driver: \(driver)")
                }
                if let mountpoint = record.mountpoint {
                    lines.append("  mountpoint: \(mountpoint)")
                }
            }
        }

        let outputURL = store.generatedVolumeReportURL(for: profile.name)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").appending("\n").write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    static func writeMetricsReport(profileName: String, store: ProfileStore) throws -> URL {
        let profile = try store.loadProfile(named: profileName)
        let snapshot = try compactMetrics(profileName: profileName, store: store)
        var lines = [snapshot.summaryLine, ""]
        lines.append(contentsOf: snapshot.detailLines)
        let outputURL = store.generatedMetricsReportURL(for: profile.name)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").appending("\n").write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    static func compactMetrics(profileName: String, store: ProfileStore) throws -> CompactMetricsSnapshot {
        let profile = try store.loadProfile(named: profileName)
        let containerIDs = try RuntimeSharedSupport.composeContainerIDs(profile: profile, store: store)
        guard !containerIDs.isEmpty else {
            return CompactMetricsSnapshot(summaryLine: "No running containers for \(profile.name).", detailLines: [])
        }

        guard let dockerPath = ToolPaths.docker else {
            throw ValidationError("docker not found")
        }
        let resolvedServer = try RuntimeSharedSupport.resolvePrimaryServer(for: profile, store: store)

        let result = Shell.run(
            dockerPath,
            arguments: ["--context", resolvedServer.dockerContext, "stats", "--no-stream", "--format", "{{json .}}"] + containerIDs
        )
        guard result.exitCode == 0 else {
            throw ValidationError(RuntimeSharedSupport.nonEmpty(result.stderr) ?? RuntimeSharedSupport.nonEmpty(result.stdout) ?? "docker stats failed")
        }

        let stats = result.stdout
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> [String: Any]? in
                guard let data = String(line).data(using: .utf8) else {
                    return nil
                }
                return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            }

        let totalCPU = stats.compactMap { RuntimeDiagnosticsService.parsePercent($0["CPUPerc"] as? String) }.reduce(0, +)
        let detailLines = stats.compactMap { stat -> String? in
            guard let name = stat["Name"] as? String else {
                return nil
            }
            let cpu = (stat["CPUPerc"] as? String) ?? "0%"
            let memory = (stat["MemUsage"] as? String) ?? "n/a"
            let network = (stat["NetIO"] as? String) ?? "n/a"
            return "\(name): CPU \(cpu) | Mem \(memory) | Net \(network)"
        }

        let summary = "\(profile.name): \(detailLines.count) container(s), total CPU \(String(format: "%.1f", totalCPU))%"
        return CompactMetricsSnapshot(summaryLine: summary, detailLines: detailLines)
    }

    static func writeRemoteBrowseReport(profileName: String, store: ProfileStore) throws -> URL {
        let profile = try store.loadProfile(named: profileName)
        guard let server = try RuntimeSharedSupport.resolveServerDefinition(for: profile, store: store), !server.isLocal else {
            throw ValidationError("Current profile does not use a remote SSH server.")
        }

        let script = """
        set -eu
        base=\(RuntimeSharedSupport.shellQuote(server.remoteProfileDirectory(for: profile.name)))
        if [ ! -d "$base" ]; then
          echo "Remote directory does not exist: $base"
          exit 0
        fi
        find "$base" -maxdepth 5 -print | sort
        """
        let result = RuntimeSharedSupport.runRemoteShell(on: server, script: script)
        guard result.exitCode == 0 else {
            throw ValidationError(RuntimeSharedSupport.nonEmpty(result.stderr) ?? RuntimeSharedSupport.nonEmpty(result.stdout) ?? "Failed to inspect remote files")
        }

        let outputURL = store.generatedRemoteBrowseReportURL(for: profile.name)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try result.stdout.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }
}
