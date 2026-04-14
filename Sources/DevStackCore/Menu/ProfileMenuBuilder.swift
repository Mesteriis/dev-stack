import AppKit
import Foundation

extension AppDelegate {
    func makeProfileMenu(currentProfileDefinition: ProfileDefinition?, isEnabled: Bool) -> NSMenuItem {
        let item = submenuItem(title: profileMenuTitle(), symbolName: "person.crop.rectangle")
        let submenu = NSMenu()

        if !isEnabled {
            populateProfileSelectionItems(into: submenu, includeFolders: true)
            item.submenu = submenu
            item.isEnabled = true
            return item
        }

        if let currentProfileDefinition {
            submenu.addItem(disabledItem(title: "Runtime: \(serverDisplayText(for: currentProfileDefinition))", symbolName: "network"))
            submenu.addItem(.separator())
        }

        submenu.addItem(actionItem(title: "Activate Profile", action: #selector(tunnelUpAction(_:)), isEnabled: isEnabled, symbolName: "play.circle"))
        submenu.addItem(actionItem(title: "Stop Tunnels", action: #selector(tunnelDownAction(_:)), isEnabled: isEnabled, symbolName: "stop.circle"))
        submenu.addItem(actionItem(title: "Restart Tunnels", action: #selector(tunnelRestartAction(_:)), isEnabled: isEnabled, symbolName: "arrow.clockwise.circle"))

        if snapshot?.compose.configured == true {
            submenu.addItem(.separator())
            submenu.addItem(actionItem(title: "Preview Compose Changes...", action: #selector(openComposePreviewAction(_:)), isEnabled: isEnabled, symbolName: "doc.text.magnifyingglass"))
            submenu.addItem(actionItem(title: "Compose Up", action: #selector(composeUpAction(_:)), isEnabled: isEnabled, symbolName: "play.square"))
            submenu.addItem(actionItem(title: "Compose Down", action: #selector(composeDownAction(_:)), isEnabled: isEnabled, symbolName: "stop.square"))
            submenu.addItem(actionItem(title: "Compose Restart", action: #selector(composeRestartAction(_:)), isEnabled: isEnabled, symbolName: "arrow.clockwise.square"))
            submenu.addItem(actionItem(title: "Open Compose Logs", action: #selector(openComposeLogsAction(_:)), isEnabled: isEnabled, symbolName: "doc.text"))
            submenu.addItem(actionItem(title: "Open Volume Report", action: #selector(openVolumeReportAction(_:)), isEnabled: isEnabled, symbolName: "shippingbox"))
            submenu.addItem(actionItem(title: "Open Metrics Report", action: #selector(openMetricsReportAction(_:)), isEnabled: isEnabled, symbolName: "chart.bar"))
            submenu.addItem(actionItem(title: "Open Remote Files", action: #selector(openRemoteFilesAction(_:)), isEnabled: isEnabled, symbolName: "externaldrive"))
            submenu.addItem(actionItem(title: "Remove Current Volumes...", action: #selector(removeCurrentVolumesAction(_:)), isEnabled: isEnabled, symbolName: "trash"))
        }

        submenu.addItem(.separator())
        submenu.addItem(actionItem(title: "Copy Shell Exports", action: #selector(copyShellExportsAction(_:)), isEnabled: isEnabled, symbolName: "document.on.document"))
        submenu.addItem(actionItem(title: "Manage Secrets...", action: #selector(manageSecretsAction(_:)), isEnabled: isEnabled, symbolName: "key"))
        submenu.addItem(actionItem(title: "Open Project Env Files", action: #selector(openProjectEnvFilesAction(_:)), isEnabled: isEnabled, symbolName: "doc.plaintext"))
        submenu.addItem(actionItem(title: "Open Compose Project Folder", action: #selector(openCurrentProjectFolderAction(_:)), isEnabled: isEnabled, symbolName: "folder"))
        submenu.addItem(actionItem(title: "Open Profile Data Folder", action: #selector(openCurrentProfileDataFolderAction(_:)), isEnabled: isEnabled, symbolName: "folder"))

        submenu.addItem(.separator())
        submenu.addItem(actionItem(title: "Edit Current Profile...", action: #selector(editCurrentProfileAction(_:)), isEnabled: isEnabled, symbolName: "pencil"))
        submenu.addItem(actionItem(title: "Add Service To Current Profile...", action: #selector(addServiceToCurrentProfileAction(_:)), isEnabled: isEnabled, symbolName: "plus"))
        submenu.addItem(actionItem(title: "Edit Current Runtime...", action: #selector(editCurrentRuntimeAction(_:)), isEnabled: isEnabled, symbolName: "server.rack"))

        submenu.addItem(.separator())
        submenu.addItem(makeProfileSwitcherMenu())
        submenu.addItem(.separator())
        submenu.addItem(actionItem(title: "Delete Current Profile...", action: #selector(deleteCurrentProfileAction(_:)), isEnabled: isEnabled, symbolName: "trash"))

        item.submenu = submenu
        item.isEnabled = true
        return item
    }

    func makeProfileSwitcherMenu() -> NSMenuItem {
        let item = submenuItem(title: "Switch Profile", symbolName: "arrow.left.arrow.right")
        let submenu = NSMenu()
        populateProfileSelectionItems(into: submenu, includeFolders: true)

        item.submenu = submenu
        return item
    }

    func populateProfileSelectionItems(into menu: NSMenu, includeFolders: Bool) {
        let currentProfile = selectedProfileName()

        if profiles.isEmpty {
            menu.addItem(disabledItem(title: "No profiles"))
        } else {
            for profile in profiles {
                let menuItem = actionItem(title: profile, action: #selector(switchProfileAction(_:)))
                menuItem.representedObject = profile
                if profile == currentProfile {
                    menuItem.state = .on
                } else if activeProfiles.contains(profile) {
                    menuItem.state = .mixed
                } else {
                    menuItem.state = .off
                }
                menu.addItem(menuItem)
            }
        }

        menu.addItem(.separator())
        menu.addItem(actionItem(title: "New Profile...", action: #selector(newProfileAction(_:)), symbolName: "plus.circle"))
        menu.addItem(actionItem(title: "Import Compose File...", action: #selector(importComposeFileAction(_:)), symbolName: "square.and.arrow.down"))
        if includeFolders {
            menu.addItem(actionItem(title: "Open Profiles Folder", action: #selector(openProfilesFolderAction(_:)), symbolName: "folder"))
        }
    }
}
