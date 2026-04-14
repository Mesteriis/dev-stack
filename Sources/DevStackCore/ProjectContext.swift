import AppKit
import Foundation

struct GitProjectInfo: Sendable {
    let repositoryRoot: String
    let currentBranch: String?
}

struct IDEProjectContext: Sendable {
    let ideName: String
    let projectPath: String
}

enum GitProjectInspector {
    static func inspectProject(at url: URL) -> GitProjectInfo? {
        let path = url.standardizedFileURL.path
        let rootResult = Shell.run("/usr/bin/git", arguments: ["-C", path, "rev-parse", "--show-toplevel"])
        guard rootResult.exitCode == 0 else {
            return nil
        }

        let repositoryRoot = rootResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repositoryRoot.isEmpty else {
            return nil
        }

        let branchResult = Shell.run("/usr/bin/git", arguments: ["-C", repositoryRoot, "branch", "--show-current"])
        let currentBranch: String?
        if branchResult.exitCode == 0 {
            let trimmed = branchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            currentBranch = trimmed.isEmpty ? nil : trimmed
        } else {
            currentBranch = nil
        }

        return GitProjectInfo(repositoryRoot: repositoryRoot, currentBranch: currentBranch)
    }
}

enum IDEProjectDetector {
    static func activeProjects() -> [IDEProjectContext] {
        deduplicated(pyCharmProjects() + vscodeProjects())
    }

    static func watchRoots() -> [URL] {
        var roots: [URL] = []

        let pyCharmRoots = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/JetBrains", isDirectory: true)
        if FileManager.default.fileExists(atPath: pyCharmRoots.path) {
            roots.append(pyCharmRoots)
        }

        let codeRoots = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Code", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Code - Insiders", isDirectory: true),
        ]
        for root in codeRoots where FileManager.default.fileExists(atPath: root.path) {
            roots.append(root)
        }

        return roots
    }

    private static func pyCharmProjects() -> [IDEProjectContext] {
        guard isAppRunning(namedLike: ["pycharm"]) else {
            return []
        }

        let jetBrainsRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/JetBrains", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: jetBrainsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var recentFiles: [URL] = []
        for case let url as URL in enumerator where url.lastPathComponent == "recentProjects.xml" {
            recentFiles.append(url)
        }

        recentFiles.sort { lhs, rhs in
            let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return leftDate > rightDate
        }

        var results: [IDEProjectContext] = []
        for url in recentFiles.prefix(3) {
            let entries = parseRecentProjectEntries(from: url)
            for entry in entries.prefix(3) {
                results.append(IDEProjectContext(ideName: "PyCharm", projectPath: entry))
            }
        }

        return deduplicated(results)
    }

    private static func vscodeProjects() -> [IDEProjectContext] {
        guard isAppRunning(namedLike: ["visual studio code", "code", "cursor", "windsurf", "trae", "qoder"]) else {
            return []
        }

        let roots = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Code", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Code - Insiders", isDirectory: true),
        ]

        var contexts: [IDEProjectContext] = []
        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            let candidates = [
                root.appendingPathComponent("User/globalStorage/storage.json", isDirectory: false),
                root.appendingPathComponent("storage.json", isDirectory: false),
                root.appendingPathComponent("Backups/workspaces.json", isDirectory: false),
            ]

            for url in candidates where FileManager.default.fileExists(atPath: url.path) {
                for path in extractLocalPaths(fromJSONLikeFile: url).prefix(5) {
                    contexts.append(IDEProjectContext(ideName: "VS Code", projectPath: path))
                }
            }

            let workspaceStorage = root.appendingPathComponent("User/workspaceStorage", isDirectory: true)
            if let enumerator = FileManager.default.enumerator(
                at: workspaceStorage,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) {
                var workspaceFiles: [URL] = []
                for case let url as URL in enumerator where url.lastPathComponent == "workspace.json" {
                    workspaceFiles.append(url)
                }
                workspaceFiles.sort { lhs, rhs in
                    let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return leftDate > rightDate
                }
                for url in workspaceFiles.prefix(5) {
                    for path in extractLocalPaths(fromJSONLikeFile: url).prefix(1) {
                        contexts.append(IDEProjectContext(ideName: "VS Code", projectPath: path))
                    }
                }
            }
        }

        return deduplicated(contexts)
    }

    private static func parseRecentProjectEntries(from url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        guard let regex = try? NSRegularExpression(pattern: #"<entry key="([^"]+)">"#) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        return matches.compactMap { match -> String? in
            guard let valueRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            let raw = String(text[valueRange])
                .replacingOccurrences(of: "$USER_HOME$", with: FileManager.default.homeDirectoryForCurrentUser.path)
            let normalized = URL(fileURLWithPath: raw).standardizedFileURL.path
            guard FileManager.default.fileExists(atPath: normalized),
                  !normalized.hasSuffix("PyCharmMiscProject")
            else {
                return nil
            }
            return normalized
        }
    }

    private static func extractLocalPaths(fromJSONLikeFile url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let regex = try? NSRegularExpression(pattern: #"/Users/[^"'\s,]+"#)
        else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        var results: [String] = []

        for match in matches {
            guard let valueRange = Range(match.range, in: text) else {
                continue
            }
            let path = String(text[valueRange])
                .replacingOccurrences(of: "\\u002F", with: "/")
                .replacingOccurrences(of: "%20", with: " ")
            let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
            if FileManager.default.fileExists(atPath: normalized), !results.contains(normalized) {
                results.append(normalized)
            }
        }

        return results
    }

    private static func deduplicated(_ contexts: [IDEProjectContext]) -> [IDEProjectContext] {
        var seen = Set<String>()
        var result: [IDEProjectContext] = []
        for context in contexts {
            let path = URL(fileURLWithPath: context.projectPath).standardizedFileURL.path
            if seen.insert(path).inserted {
                result.append(IDEProjectContext(ideName: context.ideName, projectPath: path))
            }
        }
        return result
    }

    private static func isAppRunning(namedLike names: [String]) -> Bool {
        let loweredNames = names.map { $0.lowercased() }
        return NSWorkspace.shared.runningApplications.contains { application in
            let localizedName = application.localizedName?.lowercased() ?? ""
            return loweredNames.contains { localizedName.contains($0) }
        }
    }
}
