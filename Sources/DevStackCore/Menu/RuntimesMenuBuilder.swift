import AppKit
import Foundation

extension AppDelegate {
    func makeDockerContextsMenu(title: String = "Available Docker Contexts") -> NSMenuItem {
        let item = submenuItem(title: title, symbolName: "shippingbox")
        let submenu = NSMenu()

        if dockerContexts.isEmpty {
            submenu.addItem(disabledItem(title: "No docker contexts"))
        } else {
            for context in dockerContexts {
                let menuItem = actionItem(
                    title: "\(context.name)  \(context.endpoint)",
                    action: #selector(switchDockerContextAction(_:))
                )
                menuItem.representedObject = context.name
                menuItem.state = context.isCurrent ? .on : .off
                submenu.addItem(menuItem)
            }
        }

        item.submenu = submenu
        return item
    }

    func makeRuntimesMenu() -> NSMenuItem {
        let item = submenuItem(title: "Runtimes", symbolName: "server.rack")
        let submenu = NSMenu()
        let currentServerName = selectedProfileName()
            .flatMap { try? store.loadProfile(named: $0).runtimeName }

        submenu.addItem(disabledItem(title: "Current Docker Context: \(snapshot?.activeDockerContext ?? "unknown")", symbolName: "shippingbox"))

        submenu.addItem(.separator())

        if runtimeTargets.isEmpty {
            submenu.addItem(disabledItem(title: "No saved runtimes"))
        } else {
            for server in runtimeTargets {
                let menuItem = actionItem(
                    title: "\(server.name)  \(server.connectionSummary)",
                    action: #selector(editRuntimeAction(_:)),
                    symbolName: server.isLocal ? "desktopcomputer" : "network"
                )
                menuItem.representedObject = server.name
                menuItem.state = server.name == currentServerName ? .on : .off
                submenu.addItem(menuItem)
            }
        }

        submenu.addItem(.separator())
        submenu.addItem(makeDockerContextsMenu())
        submenu.addItem(.separator())
        submenu.addItem(actionItem(title: "New Runtime...", action: #selector(newRuntimeAction(_:)), symbolName: "plus.circle"))
        submenu.addItem(actionItem(title: "Open Runtimes Folder", action: #selector(openRuntimesFolderAction(_:)), symbolName: "folder"))

        item.submenu = submenu
        return item
    }
}
