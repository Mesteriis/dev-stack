import AppKit
import Foundation

enum ReportActionService {
    @MainActor
    static func confirmComposeUpPreview(profileName: String, store: ProfileStore) -> Bool {
        guard let preview = try? RuntimeController.composePreview(profileName: profileName, store: store) else {
            return true
        }

        let reportURL = store.generatedComposePlanURL(for: profileName)
        try? ComposeSupport.writePlanReport(plan: preview.plan, to: reportURL)

        let serviceCount = preview.plan.services.count
        let bindCount = preview.plan.relativeProjectPaths.count
        let composeFileCount = preview.plan.sourceComposeURLs.count
        let ports = preview.plan.services.flatMap(\.ports).map(\.publishedPort).sorted()
        var bodyLines = [
            "Services: \(serviceCount)",
            "Compose files: \(composeFileCount)",
            "Project bind mounts: \(bindCount)",
        ]

        if !ports.isEmpty {
            bodyLines.append("Published ports: \(ports.map(String.init).joined(separator: ", "))")
        }
        if !preview.runningServiceNames.isEmpty {
            bodyLines.append("Currently running: \(preview.runningServiceNames.joined(separator: ", "))")
        }
        if !preview.diagnostics.errors.isEmpty {
            bodyLines.append("")
            bodyLines.append("Errors:")
            bodyLines.append(contentsOf: preview.diagnostics.errors.map { "- \($0)" })
        }
        if !preview.diagnostics.warnings.isEmpty {
            bodyLines.append("")
            bodyLines.append("Warnings:")
            bodyLines.append(contentsOf: preview.diagnostics.warnings.map { "- \($0)" })
        }

        let alert = NSAlert()
        alert.alertStyle = preview.diagnostics.errors.isEmpty ? .informational : .warning
        alert.messageText = "Compose preview for '\(profileName)'"
        alert.informativeText = bodyLines.joined(separator: "\n")
        alert.addButton(withTitle: preview.diagnostics.errors.isEmpty ? "Continue" : "Cancel")
        alert.addButton(withTitle: "Open Report")
        if preview.diagnostics.errors.isEmpty {
            alert.addButton(withTitle: "Cancel")
        }

        while true {
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                return preview.diagnostics.errors.isEmpty
            }
            if response == .alertSecondButtonReturn {
                NSWorkspace.shared.open(reportURL)
                continue
            }
            return false
        }
    }
}
