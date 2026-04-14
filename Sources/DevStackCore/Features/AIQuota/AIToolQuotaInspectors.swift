import Foundation

package enum AIToolQuotaInspectors {
    static func inspect(_ kind: AIToolKind) -> AIToolQuotaSnapshot {
        switch kind {
        case .codex:
            inspectCodex()
        case .sonnet:
            inspectSonnet()
        case .qwen:
            inspectQwen()
        case .google:
            inspectGoogle()
        }
    }

    static func inspectCodex() -> AIToolQuotaSnapshot {
        let health = AIToolQuotaInspectionFormatting.commandHealth(path: ToolPaths.codex, arguments: ["--version"])
        let authStatus: String
        if ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.isEmpty == false {
            authStatus = "API key in environment"
        } else if let path = ToolPaths.codex {
            let result = Shell.run(path, arguments: ["login", "status"])
            authStatus = result.exitCode == 0
                ? AIToolQuotaInspectionFormatting.trimmedOrFallback(result.stdout, fallback: "Login detected")
                : "Authorization required"
        } else {
            authStatus = "CLI not installed"
        }

        let observations = AIToolQuotaDataService.latestCodexRateLimitObservations(limit: 160)
        let observation = observations.last
        let quotaStatus: String
        var progressMetrics: [AIToolProgressMetric] = []
        var highlights: [String] = []
        var details: [String] = []

        if let observation {
            quotaStatus = AIToolQuotaInspectionFormatting.codexQuotaSummary(observation)
            progressMetrics = AIToolQuotaInspectionFormatting.codexProgressMetrics(latest: observation, history: observations)
            highlights = AIToolQuotaInspectionFormatting.codexHighlightLines(latest: observation, metrics: progressMetrics)
            if let observedAt = observation.observedAt {
                details.append("Last seen: \(AIToolQuotaDataService.formatTimestamp(observedAt))")
            }
            if let secondary = AIToolQuotaInspectionFormatting.codexSecondarySummary(observation) {
                details.append(secondary)
            }
            if let credits = AIToolQuotaInspectionFormatting.codexCreditsSummary(observation) {
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
            statusSymbolName: AIToolQuotaInspectionFormatting.statusSymbol(
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

    static func inspectSonnet() -> AIToolQuotaSnapshot {
        let health = AIToolQuotaInspectionFormatting.commandHealth(path: ToolPaths.claude, arguments: ["--version"])
        let authObservation = AIToolQuotaDataService.latestClaudeAuthObservation()
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
            statusSymbolName: AIToolQuotaInspectionFormatting.statusSymbol(
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

    static func inspectQwen() -> AIToolQuotaSnapshot {
        let health = AIToolQuotaInspectionFormatting.commandHealth(path: ToolPaths.qwen, arguments: ["--help"])
        let authType = AIToolQuotaDataService.qwenSelectedAuthType()
        let googleAccount = AIToolQuotaDataService.qwenLinkedGoogleAccount()
        let usageObservation = AIToolQuotaDataService.latestQwenUsageObservation()
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

        let quotaObservation = AIToolQuotaDataService.latestQwenQuotaObservation()
        var details: [String] = []
        var highlights: [String] = []
        if let detail = health.detail {
            details.append(detail)
        }
        if let googleAccount, !googleAccount.isEmpty {
            details.append("Linked Google account: \(googleAccount)")
        }
        if let usageObservation {
            highlights.append(AIToolQuotaInspectionFormatting.qwenUsageSummary(usageObservation))
        }
        if let quotaObservation, let observedAt = quotaObservation.observedAt {
            highlights.append("Last quota error: \(AIToolQuotaDataService.formatTimestamp(observedAt))")
        }
        details.append("Source: ~/.qwen/settings.json and ~/.qwen/debug/*.txt")

        return AIToolQuotaSnapshot(
            kind: .qwen,
            statusSymbolName: AIToolQuotaInspectionFormatting.statusSymbol(
                installed: health.installed,
                isHealthy: health.isHealthy,
                authStatus: authStatus,
                quotaStatus: AIToolQuotaInspectionFormatting.qwenQuotaSummary(quotaObservation)
            ),
            cliStatus: health.summary,
            authStatus: authStatus,
            quotaStatus: AIToolQuotaInspectionFormatting.qwenQuotaSummary(quotaObservation),
            progressMetrics: [],
            highlightLines: highlights,
            detailLines: details,
            helpMessage: """
            DevStack checks Qwen auth type in `~/.qwen/settings.json` and looks for last-known quota failures in debug logs. Your current installation should be repaired before reliable live checks are possible.
            """,
            helpCommand: nil
        )
    }

    static func inspectGoogle() -> AIToolQuotaSnapshot {
        let geminiHealth = AIToolQuotaInspectionFormatting.commandHealth(path: ToolPaths.gemini, arguments: ["--help"])
        let gcloudHealth = AIToolQuotaInspectionFormatting.commandHealth(path: ToolPaths.gcloud, arguments: ["--version"])
        let authObservation = AIToolQuotaDataService.latestGoogleAuthObservation()
        let authStatus: String

        if ProcessInfo.processInfo.environment["GOOGLE_API_KEY"]?.isEmpty == false
            || ProcessInfo.processInfo.environment["GEMINI_API_KEY"]?.isEmpty == false
        {
            authStatus = "API key in environment"
        } else if let account = authObservation?.activeAccount, !account.isEmpty {
            authStatus = "gcloud account active: \(account)"
        } else if FileManager.default.fileExists(atPath: AIToolQuotaDataService.geminiSettingsURL.path) {
            authStatus = "Gemini config detected"
        } else {
            authStatus = "Authorization required"
        }

        let primaryHealth = geminiHealth.installed ? geminiHealth : gcloudHealth
        var details: [String] = []
        if let detail = primaryHealth.detail {
            details.append(detail)
        }
        if FileManager.default.fileExists(atPath: AIToolQuotaDataService.geminiSettingsURL.path) {
            details.append("Gemini settings: \(AIToolQuotaDataService.geminiSettingsURL.path)")
        }
        if let account = authObservation?.activeAccount, !account.isEmpty {
            details.append("Active gcloud account: \(account)")
        }
        details.append("Source: gcloud auth list and ~/.gemini")

        return AIToolQuotaSnapshot(
            kind: .google,
            statusSymbolName: AIToolQuotaInspectionFormatting.statusSymbol(
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
}
