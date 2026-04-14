import AppKit
import Foundation

extension AppDelegate {
    func makeOverviewMenu(currentProfileDefinition: ProfileDefinition?) -> NSMenuItem {
        let currentProfile = currentProfileDisplayName()
        let item = submenuItem(title: "Status", symbolName: "info.circle")
        let submenu = NSMenu()

        submenu.addItem(disabledItem(title: "Profile: \(currentProfile)", symbolName: "person.crop.rectangle"))
        submenu.addItem(disabledItem(title: "Active Profiles: \(activeProfiles.count)", symbolName: "square.stack.3d.down.right"))
        submenu.addItem(disabledItem(title: "Docker: \(snapshot?.activeDockerContext ?? "unknown")", symbolName: "shippingbox"))
        if let currentProfileDefinition {
            submenu.addItem(disabledItem(title: "Runtime: \(serverDisplayText(for: currentProfileDefinition))", symbolName: "network"))
        }
        if let currentGitProjectInfo {
            let branchText = currentGitProjectInfo.currentBranch ?? "detached"
            submenu.addItem(disabledItem(title: "Git: \(URL(fileURLWithPath: currentGitProjectInfo.repositoryRoot).lastPathComponent) @ \(branchText)", symbolName: "arrow.triangle.branch"))
        }
        submenu.addItem(disabledItem(title: "Tunnel: \(snapshot?.tunnelLoaded == true ? "loaded" : "stopped")", symbolName: "point.topleft.down.curvedto.point.bottomright.up"))
        if let currentMetricsSnapshot {
            submenu.addItem(disabledItem(title: "Metrics: \(currentMetricsSnapshot.summaryLine)", symbolName: "gauge"))
        }

        if let snapshot, snapshot.compose.configured {
            submenu.addItem(
                disabledItem(
                    title: "Compose: \(snapshot.compose.projectName) (\(snapshot.compose.runningServices.count) running)",
                    symbolName: "square.stack.3d.up"
                )
            )
            submenu.addItem(disabledItem(title: "Local Containers: \(snapshot.compose.localContainerMode.title)", symbolName: "switch.2"))
        }

        if let errorMessage {
            submenu.addItem(.separator())
            submenu.addItem(disabledItem(title: "Error: \(errorMessage)", symbolName: "exclamationmark.triangle"))
        } else if let message = lastMessage {
            submenu.addItem(.separator())
            submenu.addItem(disabledItem(title: message, symbolName: isRefreshing ? "hourglass" : "checkmark.circle"))
        }

        if let snapshot, !snapshot.compose.runningServices.isEmpty {
            submenu.addItem(.separator())
            submenu.addItem(disabledItem(title: "Compose Services", symbolName: "square.stack.3d.up"))
            for service in snapshot.compose.runningServices {
                submenu.addItem(disabledItem(title: "\(service.displayName)  \(service.displayStatus)", symbolName: "circle.fill"))
            }
        }

        if let snapshot, !snapshot.services.isEmpty {
            submenu.addItem(.separator())
            submenu.addItem(disabledItem(title: "Forwarded Services", symbolName: "point.topleft.down.curvedto.point.bottomright.up"))
            for service in snapshot.services {
                let line = "\(service.name)  \(service.aliasHost):\(service.localPort)  via \(service.tunnelHost)"
                submenu.addItem(disabledItem(title: line, symbolName: "arrow.left.arrow.right"))
            }
        }

        item.submenu = submenu
        return item
    }
}
