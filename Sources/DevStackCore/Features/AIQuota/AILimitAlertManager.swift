import Foundation
import UserNotifications

@MainActor
enum AILimitAlertManager {
    static func process(snapshots: [AIToolQuotaSnapshot]) async {
        let alerts = collectAlerts(from: snapshots)
        guard !alerts.isEmpty else {
            return
        }

        let center = UNUserNotificationCenter.current()
        let authorizationStatus = await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }

        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else {
                return
            }
        case .denied:
            return
        @unknown default:
            return
        }

        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: alert.identifier,
                content: content,
                trigger: nil
            )
            try? await center.add(request)
            markDelivered(alert)
        }
    }

    private static func collectAlerts(from snapshots: [AIToolQuotaSnapshot]) -> [PendingAlert] {
        var alerts: [PendingAlert] = []

        for snapshot in snapshots {
            for metric in snapshot.progressMetrics {
                if let threshold = reachedThreshold(for: metric), shouldSendThresholdAlert(metric: metric, threshold: threshold) {
                    alerts.append(
                        PendingAlert(
                            identifier: "ai-limit-threshold-\(metric.id)-\(alertWindowID(metric))-\(threshold)",
                            metricID: metric.id,
                            windowID: alertWindowID(metric),
                            title: "\(snapshot.kind.title) \(metric.title) limit reached \(threshold)%",
                            body: thresholdAlertBody(tool: snapshot.kind, metric: metric, threshold: threshold),
                            threshold: threshold,
                            forecastTimestamp: nil
                        )
                    )
                }

                if let forecast = metric.forecastExhaustionAt,
                   let resetAt = metric.resetAt,
                   forecast < resetAt,
                   shouldSendForecastAlert(metric: metric, forecast: forecast)
                {
                    alerts.append(
                        PendingAlert(
                            identifier: "ai-limit-forecast-\(metric.id)-\(alertWindowID(metric))",
                            metricID: metric.id,
                            windowID: alertWindowID(metric),
                            title: "\(snapshot.kind.title) \(metric.title) may exhaust early",
                            body: forecastAlertBody(tool: snapshot.kind, metric: metric, forecast: forecast, resetAt: resetAt),
                            threshold: nil,
                            forecastTimestamp: forecast.timeIntervalSince1970
                        )
                    )
                }
            }
        }

        return alerts
    }

    private static func reachedThreshold(for metric: AIToolProgressMetric) -> Int? {
        let thresholds = [25, 50, 75, 100]
        let current = Int((metric.usedPercent * 100).rounded(.down))
        return thresholds.last(where: { current >= $0 })
    }

    private static func shouldSendThresholdAlert(metric: AIToolProgressMetric, threshold: Int) -> Bool {
        let defaults = UserDefaults.standard
        let key = "ai-limit-threshold.\(metric.id).\(alertWindowID(metric))"
        let lastSent = defaults.integer(forKey: key)
        return threshold > lastSent
    }

    private static func shouldSendForecastAlert(metric: AIToolProgressMetric, forecast: Date) -> Bool {
        _ = forecast
        let defaults = UserDefaults.standard
        let key = "ai-limit-forecast.\(metric.id).\(alertWindowID(metric))"
        let stored = defaults.double(forKey: key)
        return stored == 0
    }

    private static func markDelivered(_ alert: PendingAlert) {
        let defaults = UserDefaults.standard
        if let threshold = alert.threshold {
            defaults.set(threshold, forKey: "ai-limit-threshold.\(alert.metricID).\(alert.windowID)")
        }
        if let forecastTimestamp = alert.forecastTimestamp {
            defaults.set(forecastTimestamp, forKey: "ai-limit-forecast.\(alert.metricID).\(alert.windowID)")
        }
    }

    private static func thresholdAlertBody(tool: AIToolKind, metric: AIToolProgressMetric, threshold: Int) -> String {
        var body = "\(tool.title) \(metric.title.lowercased()) limit is at \(threshold)%."
        if let resetAt = metric.resetAt {
            body += " Reset: \(formatTimestamp(resetAt))."
        }
        if let forecast = metric.forecastExhaustionAt, let resetAt = metric.resetAt, forecast < resetAt {
            body += " Current pace ends around \(formatTimestamp(forecast))."
        }
        return body
    }

    private static func forecastAlertBody(tool: AIToolKind, metric: AIToolProgressMetric, forecast: Date, resetAt: Date) -> String {
        "\(tool.title) \(metric.title.lowercased()) limit is projected to end around \(formatTimestamp(forecast)), before reset at \(formatTimestamp(resetAt))."
    }

    private static func alertWindowID(_ metric: AIToolProgressMetric) -> String {
        if let resetAt = metric.resetAt {
            return String(Int(resetAt.timeIntervalSince1970))
        }
        return "none"
    }

    private static func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct PendingAlert {
    let identifier: String
    let metricID: String
    let windowID: String
    let title: String
    let body: String
    let threshold: Int?
    let forecastTimestamp: Double?
}
