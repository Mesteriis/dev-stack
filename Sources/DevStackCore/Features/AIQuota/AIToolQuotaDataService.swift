import Foundation

enum AIToolQuotaDataService {
    package static func parseCodexRateLimitEvent(
        from line: String
    ) -> (
        primaryUsedPercent: Double?,
        primaryWindowMinutes: Int?,
        primaryResetsAt: Date?
    )? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["payload"] as? [String: Any],
              let payloadType = payload["type"] as? String,
              payloadType == "token_count",
              let rateLimits = payload["rate_limits"] as? [String: Any]
        else {
            return nil
        }

        let primary = rateLimits["primary"] as? [String: Any]
        let resetsAt = (primary?["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
        return (
            normalizePercent(primary?["used_percent"] as? Double),
            primary?["window_minutes"] as? Int,
            resetsAt
        )
    }

    package static func parseTimestampedQuotaIssue(from line: String) -> Date? {
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let timestamp = parts.first else {
            return nil
        }
        return parseISO8601Date(String(timestamp))
    }

    package static func latestCodexRateLimitObservations(limit: Int) -> [CodexRateLimitObservation] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        let urls = latestFiles(at: root, withExtension: "jsonl", limit: 24)
        var observations: [CodexRateLimitObservation] = []

        for url in urls {
            guard let lines = try? String(contentsOf: url, encoding: .utf8)
                .split(whereSeparator: \.isNewline)
                .map(String.init)
            else {
                continue
            }

            for line in lines.reversed() {
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let payload = object["payload"] as? [String: Any],
                      let payloadType = payload["type"] as? String,
                      payloadType == "token_count",
                      let rateLimits = payload["rate_limits"] as? [String: Any]
                else {
                    continue
                }

                let primary = rateLimits["primary"] as? [String: Any]
                let secondary = rateLimits["secondary"] as? [String: Any]
                let credits = rateLimits["credits"] as? [String: Any]
                let timestamp = (object["timestamp"] as? String).flatMap(parseISO8601Date)
                let info = payload["info"] as? [String: Any]
                let totalUsage = info?["total_token_usage"] as? [String: Any]
                let lastUsage = info?["last_token_usage"] as? [String: Any]

                observations.append(
                    CodexRateLimitObservation(
                        observedAt: timestamp,
                        primaryUsedPercent: normalizePercent(primary?["used_percent"] as? Double),
                        primaryWindowMinutes: primary?["window_minutes"] as? Int,
                        primaryResetsAt: (primary?["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) },
                        secondaryUsedPercent: normalizePercent(secondary?["used_percent"] as? Double),
                        secondaryWindowMinutes: secondary?["window_minutes"] as? Int,
                        secondaryResetsAt: (secondary?["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) },
                        hasCredits: credits?["has_credits"] as? Bool,
                        unlimitedCredits: credits?["unlimited"] as? Bool,
                        planType: rateLimits["plan_type"] as? String,
                        totalTokens: totalUsage?["total_tokens"] as? Int,
                        lastTurnTokens: lastUsage?["total_tokens"] as? Int,
                        modelContextWindow: info?["model_context_window"] as? Int
                    )
                )

                if observations.count >= limit {
                    break
                }
            }

            if observations.count >= limit {
                break
            }
        }

        return observations
            .filter { $0.observedAt != nil }
            .sorted { ($0.observedAt ?? .distantPast) < ($1.observedAt ?? .distantPast) }
    }

    package static func latestClaudeAuthObservation() -> ClaudeAuthObservation? {
        let logURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Claude/main.log", isDirectory: false)
        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else {
            return nil
        }

        let loggedIn = text.contains("claude.ai account active and logged in")
        let authMethod: String? = text.contains("/login/app-google-auth")
            ? "Google"
            : nil

        guard loggedIn || authMethod != nil else {
            return nil
        }
        return ClaudeAuthObservation(loggedIn: loggedIn, authMethod: authMethod)
    }

    package static func latestQwenQuotaObservation() -> QwenQuotaObservation? {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".qwen/debug", isDirectory: true)
        let urls = latestFiles(at: root, withExtension: "txt", limit: 24)

        for url in urls {
            guard let lines = try? String(contentsOf: url, encoding: .utf8)
                .split(whereSeparator: \.isNewline)
                .map(String.init)
            else {
                continue
            }

            for line in lines.reversed() {
                guard line.contains("quota exceeded") || line.contains("exceeded your current quota") else {
                    continue
                }
                return QwenQuotaObservation(
                    observedAt: parseTimestampedQuotaIssue(from: line),
                    message: line
                )
            }
        }

        return nil
    }

    package static func latestQwenUsageObservation() -> QwenUsageObservation? {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".qwen/projects", isDirectory: true)
        let urls = latestFiles(at: root, withExtension: "jsonl", limit: 32)

        for url in urls {
            guard let lines = try? String(contentsOf: url, encoding: .utf8)
                .split(whereSeparator: \.isNewline)
                .map(String.init)
            else {
                continue
            }

            for line in lines.reversed() {
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let subtype = object["subtype"] as? String,
                      subtype == "ui_telemetry",
                      let systemPayload = object["systemPayload"] as? [String: Any],
                      let uiEvent = systemPayload["uiEvent"] as? [String: Any],
                      let eventName = uiEvent["event.name"] as? String,
                      eventName == "qwen-code.api_response"
                else {
                    continue
                }

                let timestamp = (object["timestamp"] as? String).flatMap(parseISO8601Date)
                return QwenUsageObservation(
                    observedAt: timestamp,
                    promptTokens: uiEvent["input_token_count"] as? Int,
                    outputTokens: uiEvent["output_token_count"] as? Int,
                    totalTokens: uiEvent["total_token_count"] as? Int
                )
            }
        }

        return nil
    }

    package static func latestGoogleAuthObservation() -> GoogleAuthObservation? {
        guard let gcloudPath = ToolPaths.gcloud else {
            return nil
        }

        let result = Shell.run(gcloudPath, arguments: ["auth", "list", "--format=json"])
        guard result.exitCode == 0,
              let data = result.stdout.data(using: .utf8),
              let accounts = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return nil
        }

        let active = accounts.first(where: { ($0["status"] as? String) == "ACTIVE" })?["account"] as? String
        return GoogleAuthObservation(activeAccount: active)
    }

    package static func qwenSelectedAuthType() -> String? {
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".qwen/settings.json", isDirectory: false),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".qwen/settings.json.orig", isDirectory: false),
        ]

        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                continue
            }

            if let security = object["security"] as? [String: Any],
               let auth = security["auth"] as? [String: Any],
               let selectedType = auth["selectedType"] as? String
            {
                return selectedType
            }

            if let selectedType = object["selectedAuthType"] as? String {
                return selectedType
            }
        }

        return nil
    }

    package static func qwenLinkedGoogleAccount() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".qwen/google_accounts.json", isDirectory: false)
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return object["active"] as? String
    }

    package static let geminiSettingsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".gemini/settings.json", isDirectory: false)

    package static func latestFiles(at root: URL, withExtension pathExtension: String, limit: Int) -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var result: [(url: URL, modificationDate: Date)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == pathExtension else {
                continue
            }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else {
                continue
            }
            result.append((url, values?.contentModificationDate ?? .distantPast))
        }

        return result
            .sorted { $0.modificationDate > $1.modificationDate }
            .prefix(limit)
            .map(\.url)
    }

    package static func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    package static func normalizePercent(_ value: Double?) -> Double? {
        guard let value, value.isFinite else {
            return nil
        }

        let clampedValue = max(0, value)
        if clampedValue == 0 {
            return 0
        }

        // Codex session logs currently use whole percentage points such as
        // 1.0, 9.0 and 33.0. Keep supporting fractional inputs below 1.0.
        if clampedValue >= 1 {
            return min(clampedValue / 100, 1)
        }

        return min(clampedValue, 1)
    }

    private static func parseISO8601Date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
