import Foundation

enum AIToolKind: String, CaseIterable, Sendable {
    case codex
    case sonnet
    case qwen
    case google

    var title: String {
        switch self {
        case .codex:
            return "Codex"
        case .sonnet:
            return "Sonnet"
        case .qwen:
            return "Qwen"
        case .google:
            return "Google"
        }
    }
}

struct AIToolQuotaSnapshot: Sendable {
    let kind: AIToolKind
    let statusSymbolName: String
    let cliStatus: String
    let authStatus: String
    let quotaStatus: String
    let progressMetrics: [AIToolProgressMetric]
    let highlightLines: [String]
    let detailLines: [String]
    let helpMessage: String
    let helpCommand: String?
}

struct AIToolProgressMetric: Sendable {
    let id: String
    let title: String
    let usedPercent: Double
    let summary: String
    let resetAt: Date?
    let forecastExhaustionAt: Date?
}

private struct CodexRateLimitObservation: Sendable {
    let observedAt: Date?
    let primaryUsedPercent: Double?
    let primaryWindowMinutes: Int?
    let primaryResetsAt: Date?
    let secondaryUsedPercent: Double?
    let secondaryWindowMinutes: Int?
    let secondaryResetsAt: Date?
    let hasCredits: Bool?
    let unlimitedCredits: Bool?
    let planType: String?
    let totalTokens: Int?
    let lastTurnTokens: Int?
    let modelContextWindow: Int?
}

private struct QwenQuotaObservation: Sendable {
    let observedAt: Date?
    let message: String
}

private struct QwenUsageObservation: Sendable {
    let observedAt: Date?
    let promptTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
}

private struct ClaudeAuthObservation: Sendable {
    let loggedIn: Bool
    let authMethod: String?
}

private struct GoogleAuthObservation: Sendable {
    let activeAccount: String?
}

private enum CodexRateMetric {
    case primary
    case secondary
}

enum AIToolQuotaInspector {
    static func collectAll(forceRefresh: Bool = false) -> [AIToolQuotaSnapshot] {
        _ = forceRefresh
        return AIToolKind.allCases.map(inspect)
    }

    static func invalidateCache() {
        // No-op. Tool status is recomputed on each refresh.
    }

    package static func parseCodexRateLimitEvent(from line: String) -> (
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

    private static func inspect(_ kind: AIToolKind) -> AIToolQuotaSnapshot {
        switch kind {
        case .codex:
            return inspectCodex()
        case .sonnet:
            return inspectSonnet()
        case .qwen:
            return inspectQwen()
        case .google:
            return inspectGoogle()
        }
    }

    private static func inspectCodex() -> AIToolQuotaSnapshot {
        let health = commandHealth(path: ToolPaths.codex, arguments: ["--version"])
        let authStatus: String
        if ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.isEmpty == false {
            authStatus = "API key in environment"
        } else if let path = ToolPaths.codex {
            let result = Shell.run(path, arguments: ["login", "status"])
            authStatus = result.exitCode == 0
                ? trimmedOrFallback(result.stdout, fallback: "Login detected")
                : "Authorization required"
        } else {
            authStatus = "CLI not installed"
        }

        let observations = latestCodexRateLimitObservations(limit: 160)
        let observation = observations.last
        let quotaStatus: String
        var progressMetrics: [AIToolProgressMetric] = []
        var highlights: [String] = []
        var details: [String] = []

        if let observation {
            quotaStatus = codexQuotaSummary(observation)
            progressMetrics = codexProgressMetrics(latest: observation, history: observations)
            highlights = codexHighlightLines(latest: observation, metrics: progressMetrics)
            if let observedAt = observation.observedAt {
                details.append("Last seen: \(formatTimestamp(observedAt))")
            }
            if let secondary = codexSecondarySummary(observation) {
                details.append(secondary)
            }
            if let credits = codexCreditsSummary(observation) {
                details.append(credits)
            }
            if let planType = observation.planType, !planType.isEmpty {
                details.append("Plan: \(planType)")
            }
            details.append("Source: ~/.codex/sessions/*.jsonl")
        } else {
            quotaStatus = "No local quota data"
            progressMetrics = []
            highlights = []
            details.append("Source: ~/.codex/sessions/*.jsonl")
        }

        if let detail = health.detail {
            details.insert(detail, at: 0)
        }

        return AIToolQuotaSnapshot(
            kind: .codex,
            statusSymbolName: statusSymbol(
                installed: health.installed,
                isHealthy: health.isHealthy,
                authStatus: authStatus,
                quotaStatus: quotaStatus
            ),
            cliStatus: health.summary,
            authStatus: authStatus,
            quotaStatus: quotaStatus,
            progressMetrics: progressMetrics,
            highlightLines: highlights,
            detailLines: details,
            helpMessage: """
            DevStack checks `codex login status`, `OPENAI_API_KEY` and local Codex session logs. If authorization is missing, sign in with Codex CLI or provide an API key.
            """,
            helpCommand: health.installed ? "codex login --device-auth" : nil
        )
    }

    private static func inspectSonnet() -> AIToolQuotaSnapshot {
        let health = commandHealth(path: ToolPaths.claude, arguments: ["--version"])
        let authObservation = latestClaudeAuthObservation()
        let authStatus: String

        if ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]?.isEmpty == false {
            authStatus = "API key in environment"
        } else if let authObservation, authObservation.loggedIn {
            if let authMethod = authObservation.authMethod {
                authStatus = "Desktop account active via \(authMethod)"
            } else {
                authStatus = "Desktop account active"
            }
        } else {
            authStatus = "Authorization required"
        }

        var details: [String] = []
        if let detail = health.detail {
            details.append(detail)
        }
        if authObservation != nil {
            details.append("Source: ~/Library/Logs/Claude/main.log")
        } else {
            details.append("Source: ~/.claude.json and Claude Desktop logs")
        }

        return AIToolQuotaSnapshot(
            kind: .sonnet,
            statusSymbolName: statusSymbol(
                installed: health.installed || authObservation != nil,
                isHealthy: health.isHealthy || authObservation != nil,
                authStatus: authStatus,
                quotaStatus: "No local quota data"
            ),
            cliStatus: health.installed ? health.summary : "Claude CLI not installed",
            authStatus: authStatus,
            quotaStatus: "No local quota data",
            progressMetrics: [],
            highlightLines: [],
            detailLines: details,
            helpMessage: """
            DevStack can detect Anthropic authorization from `ANTHROPIC_API_KEY` or Claude Desktop logs. Local quota information is not exposed by the available files on this Mac.
            """,
            helpCommand: health.installed ? "claude login" : nil
        )
    }

    private static func inspectQwen() -> AIToolQuotaSnapshot {
        let health = commandHealth(path: ToolPaths.qwen, arguments: ["--help"])
        let authType = qwenSelectedAuthType()
        let googleAccount = qwenLinkedGoogleAccount()
        let usageObservation = latestQwenUsageObservation()
        let authStatus: String

        if let authType, !authType.isEmpty {
            if let googleAccount, !googleAccount.isEmpty {
                authStatus = "\(authType) via \(googleAccount)"
            } else {
                authStatus = authType
            }
        } else {
            authStatus = "Authorization required"
        }

        let quotaObservation = latestQwenQuotaObservation()
        var details: [String] = []
        var highlights: [String] = []
        if let detail = health.detail {
            details.append(detail)
        }
        if let googleAccount, !googleAccount.isEmpty {
            details.append("Linked Google account: \(googleAccount)")
        }
        if let usageObservation {
            highlights.append(qwenUsageSummary(usageObservation))
        }
        if let quotaObservation, let observedAt = quotaObservation.observedAt {
            highlights.append("Last quota error: \(formatTimestamp(observedAt))")
        }
        details.append("Source: ~/.qwen/settings.json and ~/.qwen/debug/*.txt")

        return AIToolQuotaSnapshot(
            kind: .qwen,
            statusSymbolName: statusSymbol(
                installed: health.installed,
                isHealthy: health.isHealthy,
                authStatus: authStatus,
                quotaStatus: qwenQuotaSummary(quotaObservation)
            ),
            cliStatus: health.summary,
            authStatus: authStatus,
            quotaStatus: qwenQuotaSummary(quotaObservation),
            progressMetrics: [],
            highlightLines: highlights,
            detailLines: details,
            helpMessage: """
            DevStack checks Qwen auth type in `~/.qwen/settings.json` and looks for last-known quota failures in debug logs. Your current installation should be repaired before reliable live checks are possible.
            """,
            helpCommand: nil
        )
    }

    private static func inspectGoogle() -> AIToolQuotaSnapshot {
        let geminiHealth = commandHealth(path: ToolPaths.gemini, arguments: ["--help"])
        let gcloudHealth = commandHealth(path: ToolPaths.gcloud, arguments: ["--version"])
        let authObservation = latestGoogleAuthObservation()
        let authStatus: String

        if ProcessInfo.processInfo.environment["GOOGLE_API_KEY"]?.isEmpty == false
            || ProcessInfo.processInfo.environment["GEMINI_API_KEY"]?.isEmpty == false
        {
            authStatus = "API key in environment"
        } else if let account = authObservation?.activeAccount, !account.isEmpty {
            authStatus = "gcloud account active: \(account)"
        } else if FileManager.default.fileExists(atPath: geminiSettingsURL.path) {
            authStatus = "Gemini config detected"
        } else {
            authStatus = "Authorization required"
        }

        let primaryHealth = geminiHealth.installed ? geminiHealth : gcloudHealth
        var details: [String] = []
        if let detail = primaryHealth.detail {
            details.append(detail)
        }
        if FileManager.default.fileExists(atPath: geminiSettingsURL.path) {
            details.append("Gemini settings: \(geminiSettingsURL.path)")
        }
        if let account = authObservation?.activeAccount, !account.isEmpty {
            details.append("Active gcloud account: \(account)")
        }
        details.append("Source: gcloud auth list and ~/.gemini")

        return AIToolQuotaSnapshot(
            kind: .google,
            statusSymbolName: statusSymbol(
                installed: primaryHealth.installed || authObservation != nil,
                isHealthy: primaryHealth.isHealthy || authObservation != nil,
                authStatus: authStatus,
                quotaStatus: "No local quota data"
            ),
            cliStatus: primaryHealth.installed ? primaryHealth.summary : "Gemini CLI not installed",
            authStatus: authStatus,
            quotaStatus: "No local quota data",
            progressMetrics: [],
            highlightLines: [],
            detailLines: details,
            helpMessage: """
            DevStack checks `gcloud auth list`, `GOOGLE_API_KEY` / `GEMINI_API_KEY`, and Gemini config files. Local quota information is not exposed by these sources, so this menu reports authorization only.
            """,
            helpCommand: ToolPaths.gcloud != nil ? "gcloud auth login" : nil
        )
    }

    private static func statusSymbol(
        installed: Bool,
        isHealthy: Bool,
        authStatus: String,
        quotaStatus: String
    ) -> String {
        let loweredAuth = authStatus.lowercased()
        let loweredQuota = quotaStatus.lowercased()

        if !installed {
            return "xmark.circle"
        }
        if !isHealthy || loweredAuth.contains("required") || loweredQuota.contains("exhausted") {
            return "exclamationmark.triangle"
        }
        return "checkmark.circle"
    }

    private static func latestCodexRateLimitObservations(limit: Int) -> [CodexRateLimitObservation] {
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

                observations.append(CodexRateLimitObservation(
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
                ))

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

    private static func latestClaudeAuthObservation() -> ClaudeAuthObservation? {
        let logURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Claude/main.log", isDirectory: false)
        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else {
            return nil
        }

        let loggedIn = text.contains("claude.ai account active and logged in")
        let authMethod: String?
        if text.contains("/login/app-google-auth") {
            authMethod = "Google"
        } else {
            authMethod = nil
        }

        guard loggedIn || authMethod != nil else {
            return nil
        }
        return ClaudeAuthObservation(loggedIn: loggedIn, authMethod: authMethod)
    }

    private static func latestQwenQuotaObservation() -> QwenQuotaObservation? {
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

    private static func latestQwenUsageObservation() -> QwenUsageObservation? {
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

    private static func latestGoogleAuthObservation() -> GoogleAuthObservation? {
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

    private static func qwenSelectedAuthType() -> String? {
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

    private static func qwenLinkedGoogleAccount() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".qwen/google_accounts.json", isDirectory: false)
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return object["active"] as? String
    }

    private static func codexProgressMetrics(
        latest: CodexRateLimitObservation,
        history: [CodexRateLimitObservation]
    ) -> [AIToolProgressMetric] {
        var result: [AIToolProgressMetric] = []

        if let usedPercent = latest.primaryUsedPercent {
            let forecast = codexForecastExhaustion(
                history: history,
                latestResetAt: latest.primaryResetsAt,
                metric: .primary
            )
            result.append(
                AIToolProgressMetric(
                    id: "codex.primary",
                    title: "Primary",
                    usedPercent: usedPercent,
                    summary: codexMetricSummary(
                        title: "Primary",
                        usedPercent: usedPercent,
                        resetAt: latest.primaryResetsAt
                    ),
                    resetAt: latest.primaryResetsAt,
                    forecastExhaustionAt: forecast
                )
            )
        }

        if let usedPercent = latest.secondaryUsedPercent {
            let forecast = codexForecastExhaustion(
                history: history,
                latestResetAt: latest.secondaryResetsAt,
                metric: .secondary
            )
            result.append(
                AIToolProgressMetric(
                    id: "codex.secondary",
                    title: "Secondary",
                    usedPercent: usedPercent,
                    summary: codexMetricSummary(
                        title: "Secondary",
                        usedPercent: usedPercent,
                        resetAt: latest.secondaryResetsAt
                    ),
                    resetAt: latest.secondaryResetsAt,
                    forecastExhaustionAt: forecast
                )
            )
        }

        return result
    }

    private static func codexHighlightLines(
        latest: CodexRateLimitObservation,
        metrics: [AIToolProgressMetric]
    ) -> [String] {
        var result: [String] = []

        if let lastTurnTokens = latest.lastTurnTokens {
            result.append("Last turn: \(formatTokenCount(lastTurnTokens)) tokens")
        }

        if let totalTokens = latest.totalTokens {
            if let contextWindow = latest.modelContextWindow, contextWindow > 0 {
                let percent = Int((Double(totalTokens) / Double(contextWindow) * 100).rounded())
                result.append("Context total: \(formatTokenCount(totalTokens)) / \(formatTokenCount(contextWindow)) (\(percent)%)")
            } else {
                result.append("Window total: \(formatTokenCount(totalTokens)) tokens")
            }
        }

        for metric in metrics.prefix(2) {
            if let forecast = metric.forecastExhaustionAt, let resetAt = metric.resetAt, forecast < resetAt {
                result.append("\(metric.title) forecast: ends around \(formatTimestamp(forecast))")
            }
        }

        return result
    }

    private static func codexForecastExhaustion(
        history: [CodexRateLimitObservation],
        latestResetAt: Date?,
        metric: CodexRateMetric
    ) -> Date? {
        guard let latestResetAt else {
            return nil
        }

        let matching = history.filter {
            $0.observedAt != nil
                && codexMetricValue(metric, in: $0) != nil
                && matchesResetDate($0, resetAt: latestResetAt, metric: metric)
        }

        guard let latest = matching.last,
              let latestObservedAt = latest.observedAt,
              let latestPercent = codexMetricValue(metric, in: latest)
        else {
            return nil
        }

        let recent = matching.filter {
            guard let observedAt = $0.observedAt else {
                return false
            }
            return latestObservedAt.timeIntervalSince(observedAt) <= 2 * 60 * 60
        }

        guard let first = recent.first,
              let firstObservedAt = first.observedAt,
              let firstPercent = codexMetricValue(metric, in: first)
        else {
            return nil
        }

        let deltaPercent = latestPercent - firstPercent
        let deltaTime = latestObservedAt.timeIntervalSince(firstObservedAt)
        guard deltaPercent > 0.02, deltaTime > 10 * 60 else {
            return nil
        }

        let rate = deltaPercent / deltaTime
        guard rate > 0 else {
            return nil
        }

        let remainingPercent = max(0, 1 - latestPercent)
        let forecast = latestObservedAt.addingTimeInterval(remainingPercent / rate)
        return forecast < latestResetAt ? forecast : nil
    }

    private static func matchesResetDate(
        _ observation: CodexRateLimitObservation,
        resetAt: Date,
        metric: CodexRateMetric
    ) -> Bool {
        let observationResetAt: Date?
        switch metric {
        case .primary:
            observationResetAt = observation.primaryResetsAt
        case .secondary:
            observationResetAt = observation.secondaryResetsAt
        }

        guard let observationResetAt else {
            return false
        }
        return abs(observationResetAt.timeIntervalSince(resetAt)) < 1
    }

    private static func codexMetricValue(_ metric: CodexRateMetric, in observation: CodexRateLimitObservation) -> Double? {
        switch metric {
        case .primary:
            return observation.primaryUsedPercent
        case .secondary:
            return observation.secondaryUsedPercent
        }
    }

    private static func codexMetricSummary(title: String, usedPercent: Double, resetAt: Date?) -> String {
        let percent = formatPercent(usedPercent)
        if let resetAt {
            return "\(title): \(percent)% used, resets \(formatTimestamp(resetAt))"
        }
        return "\(title): \(percent)% used"
    }

    private static func qwenUsageSummary(_ observation: QwenUsageObservation) -> String {
        var parts: [String] = []
        if let totalTokens = observation.totalTokens {
            parts.append("Last request: \(formatTokenCount(totalTokens))")
        }
        if let promptTokens = observation.promptTokens, let outputTokens = observation.outputTokens {
            parts.append("in \(formatTokenCount(promptTokens)) / out \(formatTokenCount(outputTokens))")
        }
        let base = parts.joined(separator: ", ")
        if let observedAt = observation.observedAt {
            return "\(base) at \(formatTimestamp(observedAt))"
        }
        return base
    }

    private static func codexQuotaSummary(_ observation: CodexRateLimitObservation) -> String {
        guard let primaryUsedPercent = observation.primaryUsedPercent,
              let primaryWindowMinutes = observation.primaryWindowMinutes
        else {
            return "No local quota data"
        }

        let percent = formatPercent(primaryUsedPercent)
        if let resetsAt = observation.primaryResetsAt {
            if primaryUsedPercent >= 0.999 {
                return "Primary exhausted, resets \(formatTimestamp(resetsAt))"
            }
            return "Primary \(percent)% / \(primaryWindowMinutes)m, resets \(formatTimestamp(resetsAt))"
        }
        if primaryUsedPercent >= 0.999 {
            return "Primary exhausted"
        }
        return "Primary \(percent)% / \(primaryWindowMinutes)m"
    }

    private static func codexSecondarySummary(_ observation: CodexRateLimitObservation) -> String? {
        guard let usedPercent = observation.secondaryUsedPercent,
              let windowMinutes = observation.secondaryWindowMinutes
        else {
            return nil
        }

        let percent = formatPercent(usedPercent)
        if let resetsAt = observation.secondaryResetsAt {
            return "Secondary \(percent)% / \(windowMinutes)m, resets \(formatTimestamp(resetsAt))"
        }
        return "Secondary \(percent)% / \(windowMinutes)m"
    }

    private static func codexCreditsSummary(_ observation: CodexRateLimitObservation) -> String? {
        if observation.unlimitedCredits == true {
            return "Credits: unlimited"
        }
        if observation.hasCredits == false {
            return "Credits: unavailable"
        }
        if observation.hasCredits == true {
            return "Credits: available"
        }
        return nil
    }

    private static func qwenQuotaSummary(_ observation: QwenQuotaObservation?) -> String {
        guard let observation else {
            return "No local quota data"
        }
        if let observedAt = observation.observedAt {
            return "Quota exhausted on \(formatTimestamp(observedAt))"
        }
        return "Last known status: quota exhausted"
    }

    private static func latestFiles(at root: URL, withExtension pathExtension: String, limit: Int) -> [URL] {
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

    private static func trimmedOrFallback(_ text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func commandHealth(path: String?, arguments: [String]) -> (
        installed: Bool,
        isHealthy: Bool,
        summary: String,
        detail: String?
    ) {
        guard let path else {
            return (false, false, "Not installed", nil)
        }

        let result = Shell.run(path, arguments: arguments)
        if result.exitCode == 0 {
            let output = firstLine(trimmedOrFallback(result.stdout, fallback: "Installed"))
            return (true, true, output, "Binary: \(path)")
        }

        let problem = trimmedOrFallback(result.stderr, fallback: trimmedOrFallback(result.stdout, fallback: "Command failed"))
        let firstLine = problem.components(separatedBy: .newlines).first ?? problem
        return (true, false, "Installed but unhealthy", "Binary issue: \(firstLine)")
    }

    private static func firstLine(_ text: String) -> String {
        text.components(separatedBy: .newlines).first ?? text
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

    private static func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func formatTokenCount(_ value: Int) -> String {
        let absoluteValue = abs(Double(value))
        let sign = value < 0 ? "-" : ""

        switch absoluteValue {
        case 1_000_000...:
            return "\(sign)\(String(format: "%.1f", absoluteValue / 1_000_000))M"
        case 1_000...:
            return "\(sign)\(String(format: "%.1f", absoluteValue / 1_000))k"
        default:
            return "\(value)"
        }
    }

    private static func normalizePercent(_ value: Double?) -> Double? {
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

    private static func formatPercent(_ fraction: Double) -> Int {
        Int((fraction * 100).rounded())
    }

    private static let geminiSettingsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".gemini/settings.json", isDirectory: false)
}
