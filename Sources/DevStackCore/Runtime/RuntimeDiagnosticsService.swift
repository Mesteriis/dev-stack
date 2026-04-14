import Foundation

enum RuntimeDiagnosticsService {
    static func runtimeDiagnostics(
        profile: ProfileDefinition,
        store: ProfileStore,
        plan: ComposePlan? = nil
    ) throws -> RuntimeDiagnosticsReport {
        let plan = try plan ?? ComposeSupport.plan(profile: profile, store: store)
        var errors: [String] = []
        var warnings: [String] = []
        var localConflicts: [ComposePortBinding] = []
        let runningServices = try RuntimeSharedSupport.composePS(profile: profile, store: store)

        if let server = try RuntimeSharedSupport.resolveServerDefinition(for: profile, store: store), !server.isLocal {
            let inspection = try RuntimeSharedSupport.inspect(server: server)
            if !inspection.dockerPresent {
                errors.append("Docker is not available on \(server.remoteDockerServerDisplay).")
            }

            let diskScript = """
            set -eu
            base=\(RuntimeSharedSupport.shellQuote(server.remoteDataRoot))
            mkdir -p "$base"
            df -Pk "$base" | tail -n 1 | awk '{print $4}'
            """
            let diskResult = RuntimeSharedSupport.runRemoteShell(on: server, script: diskScript)
            if diskResult.exitCode == 0,
               let availableKB = Int(diskResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)),
               availableKB < 524_288
            {
                warnings.append("Remote free space on \(server.remoteDockerServerDisplay) is below 512 MB.")
            }

            if !plan.unsupportedRemoteBindSources.isEmpty {
                errors.append("Remote compose uses host bind mounts outside the project directory: \(plan.unsupportedRemoteBindSources.joined(separator: ", "))")
            }

            let remotePorts = Set(plan.services.flatMap(\.ports).map(\.publishedPort))
            let remoteListeningPorts = try self.remoteListeningPorts(on: server, candidates: Array(remotePorts))
            for port in plan.services.flatMap(\.ports) where remoteListeningPorts.contains(port.publishedPort) {
                warnings.append("Remote port \(port.publishedPort) is already listening on \(server.remoteDockerServerDisplay).")
            }
        } else {
            for port in plan.services.flatMap(\.ports) where portListening(port.publishedPort) {
                localConflicts.append(port)
                if runningServices.isEmpty {
                    errors.append("Local port \(port.publishedPort) is already listening before compose up.")
                } else {
                    warnings.append("Local port \(port.publishedPort) is already listening.")
                }
            }
        }

        return RuntimeDiagnosticsReport(
            errors: deduplicated(errors),
            warnings: deduplicated(warnings),
            localPortConflicts: uniquePortBindings(localConflicts)
        )
    }

    static func portListening(_ port: Int) -> Bool {
        guard port > 0 else {
            return false
        }

        let result = Shell.run(
            "/usr/sbin/lsof",
            arguments: ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"]
        )
        return result.exitCode == 0
    }

    static func parsePercent(_ value: String?) -> Double? {
        guard let value else {
            return nil
        }
        let cleaned = value.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
    }

    private static func uniquePortBindings(_ bindings: [ComposePortBinding]) -> [ComposePortBinding] {
        var seen = Set<String>()
        var result: [ComposePortBinding] = []
        for binding in bindings {
            let key = "\(binding.serviceName):\(binding.publishedPort)"
            if seen.insert(key).inserted {
                result.append(binding)
            }
        }
        return result
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        var result: [String] = []
        for value in values where !result.contains(value) {
            result.append(value)
        }
        return result
    }

    private static func remoteListeningPorts(on server: RemoteServerDefinition, candidates: [Int]) throws -> Set<Int> {
        guard !candidates.isEmpty else {
            return []
        }

        let script = """
        set -eu
        if command -v ss >/dev/null 2>&1; then
          ss -ltnH 2>/dev/null | awk '{print $4}'
        else
          netstat -ltn 2>/dev/null | tail -n +3 | awk '{print $4}'
        fi
        """
        let result = RuntimeSharedSupport.runRemoteShell(on: server, script: script)
        guard result.exitCode == 0 else {
            throw ValidationError(RuntimeSharedSupport.nonEmpty(result.stderr) ?? RuntimeSharedSupport.nonEmpty(result.stdout) ?? "Failed to inspect remote listening ports")
        }

        let candidateSet = Set(candidates)
        var listening = Set<Int>()
        for line in result.stdout.split(whereSeparator: \.isNewline) {
            let value = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let port = extractTerminalPort(from: value), candidateSet.contains(port) else {
                continue
            }
            listening.insert(port)
        }
        return listening
    }

    private static func extractTerminalPort(from endpoint: String) -> Int? {
        let separators = endpoint.split(separator: ":")
        guard let last = separators.last else {
            return nil
        }
        return Int(last.trimmingCharacters(in: CharacterSet(charactersIn: "[]")))
    }
}
