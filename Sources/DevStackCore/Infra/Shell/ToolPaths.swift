import Foundation

package enum ToolPaths {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    package static let docker = resolve([
        "/usr/local/bin/docker",
        "/opt/homebrew/bin/docker",
        "\(home)/.orbstack/bin/docker",
    ])
    package static let codex = resolve([
        "/usr/local/bin/codex",
        "/opt/homebrew/bin/codex",
    ])
    package static let claude = resolve([
        "/usr/local/bin/claude",
        "/opt/homebrew/bin/claude",
    ])
    package static let qwen = resolve([
        "/usr/local/bin/qwen",
        "/opt/homebrew/bin/qwen",
    ])
    package static let gemini = resolve([
        "/usr/local/bin/gemini",
        "/opt/homebrew/bin/gemini",
    ])
    package static let gcloud = resolve([
        "/usr/local/bin/gcloud",
        "/opt/homebrew/bin/gcloud",
    ])

    package static func resolve(_ candidates: [String]) -> String? {
        let fileManager = FileManager.default
        if let directMatch = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return directMatch
        }

        let binaryNames = Set(candidates.map { URL(fileURLWithPath: $0).lastPathComponent })
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let fallbackEntries = ["/usr/bin", "/bin", "/usr/sbin", "/sbin", "/opt/homebrew/bin", "/usr/local/bin"]
        var searchPaths: [String] = []

        for entry in pathEntries + fallbackEntries where !searchPaths.contains(entry) {
            searchPaths.append(entry)
        }

        for directory in searchPaths {
            for binaryName in binaryNames {
                let candidate = URL(fileURLWithPath: directory).appendingPathComponent(binaryName).path
                if fileManager.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }

        return nil
    }
}
