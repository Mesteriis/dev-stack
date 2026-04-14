import Foundation

enum ComposePreviewFormatter {
    static func writePlanReport(plan: ComposePlan, to url: URL) throws {
        let text = planReport(plan: plan)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    static func planReport(plan: ComposePlan) -> String {
        var lines: [String] = []
        lines.append("Project: \(plan.projectName)")
        lines.append("Working directory: \(plan.workingDirectory.path)")
        if plan.sourceComposeURLs.count == 1 {
            lines.append("Compose source: \(plan.sourceComposeURL.path)")
        } else {
            lines.append("Compose sources:")
            for url in plan.sourceComposeURLs {
                lines.append("  - \(url.path)")
            }
        }
        if !plan.environmentFiles.isEmpty {
            lines.append("Environment files:")
            for url in plan.environmentFiles {
                lines.append("  - \(url.path)")
            }
        }

        if !plan.services.isEmpty {
            lines.append("")
            lines.append("Services:")
            for service in plan.services {
                let imageText = service.image ?? "(no image)"
                lines.append("  - \(service.name)  \(imageText)")
                for port in service.ports {
                    let hostIP = port.hostIP ?? "0.0.0.0"
                    let target = port.targetPort.map(String.init) ?? "?"
                    lines.append("      port: \(hostIP):\(port.publishedPort) -> \(target)/\(port.protocolName)")
                }
                for mount in service.bindMounts {
                    let source = mount.relativeProjectPath ?? mount.sourcePath
                    let ro = mount.readOnly ? " (ro)" : ""
                    lines.append("      bind: \(source) -> \(mount.targetPath)\(ro)")
                }
                for volume in service.namedVolumes {
                    lines.append("      volume: \(volume.sourceName) -> \(volume.targetPath)")
                }
            }
        }

        if !plan.topLevelVolumeNames.isEmpty {
            lines.append("")
            lines.append("Top-level volumes:")
            for volume in plan.topLevelVolumeNames.sorted() {
                lines.append("  - \(volume)")
            }
        }

        if !plan.unsupportedRemoteBindSources.isEmpty {
            lines.append("")
            lines.append("Unsupported remote bind sources:")
            for path in plan.unsupportedRemoteBindSources.sorted() {
                lines.append("  - \(path)")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
