import Foundation

enum RuntimeShellSupport {
    static func inspect(server: RemoteServerDefinition) throws -> RemoteServerInspection {
        let script = """
        set -eu
        if [ -f /etc/os-release ]; then
          . /etc/os-release
        fi
        printf 'os=%s\n' "${PRETTY_NAME:-unknown}"
        if command -v docker >/dev/null 2>&1; then
          printf 'docker_present=yes\n'
          printf 'docker_version=%s\\n' "$(docker --version 2>/dev/null | tr '\\n' ' ')"
          printf 'server_version=%s\\n' "$(docker info --format '{{.ServerVersion}}' 2>/dev/null || true)"
        else
          printf 'docker_present=no\\n'
          printf 'docker_version=\\n'
          printf 'server_version=\\n'
        fi
        """

        let result = runRemoteShell(on: server, script: script)
        guard result.exitCode == 0 else {
            throw ValidationError(nonEmpty(result.stderr) ?? nonEmpty(result.stdout) ?? "Failed to connect to \(server.remoteDockerServerDisplay)")
        }

        let values = parseKeyValueOutput(result.stdout)
        return RemoteServerInspection(
            remoteOS: values["os"] ?? "unknown",
            dockerPresent: values["docker_present"] == "yes",
            dockerVersion: values["docker_version"] ?? "",
            serverVersion: values["server_version"] ?? ""
        )
    }

    static func runRemoteShell(on server: RemoteServerDefinition, script: String) -> CommandResult {
        var arguments = sshArguments(for: server)
        arguments.append(contentsOf: ["/bin/sh", "-s", "--"])
        return Shell.run(
            "/usr/bin/ssh",
            arguments: arguments,
            standardInput: Data(script.utf8)
        )
    }

    static func sshArguments(for server: RemoteServerDefinition) -> [String] {
        var arguments = [
            "-o",
            "BatchMode=yes",
            "-o",
            "StrictHostKeyChecking=accept-new",
            "-o",
            "ConnectTimeout=5",
        ]
        if server.sshPort != 22 {
            arguments.append(contentsOf: ["-p", String(server.sshPort)])
        }
        arguments.append(server.sshTarget)
        return arguments
    }

    static func runLocalShell(_ command: String) -> CommandResult {
        Shell.run("/bin/sh", arguments: ["-lc", command])
    }

    static func shellCommand(executable: String, arguments: [String]) -> String {
        ([executable] + arguments).map(shellQuote).joined(separator: " ")
    }

    static func serviceURL(service: ServiceDefinition) -> String {
        let host = service.aliasHost
        let port = service.localPort

        switch service.role {
        case "postgres":
            return "postgresql://\(host):\(port)"
        case "redis":
            return "redis://\(host):\(port)"
        case "https":
            return "https://\(host)"
        case "http":
            return "http://\(host):\(port)"
        case "minio":
            return "http://\(host):\(port)"
        default:
            return "\(host):\(port)"
        }
    }

    static func shellQuote(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    static func parseKeyValueOutput(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let string = String(line)
            guard let separator = string.firstIndex(of: "=") else {
                continue
            }
            let key = String(string[..<separator])
            let value = String(string[string.index(after: separator)...])
            result[key] = value
        }
        return result
    }

    static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
