import AppKit
import Foundation

extension AppDelegate {
    func makeVariablesMenu() -> NSMenuItem {
        let item = submenuItem(title: "Variables", symbolName: "slider.horizontal.below.square.and.square.filled")
        let submenu = NSMenu()
        let allVariables = (try? store.managedVariables()) ?? []

        submenu.addItem(disabledItem(title: "Managed vars: \(allVariables.count)", symbolName: "text.badge.plus"))
        if let currentProfileName = selectedProfileName() {
            let assignedCount = allVariables.filter { $0.applies(to: currentProfileName) }.count
            submenu.addItem(disabledItem(title: "Assigned to \(currentProfileName): \(assignedCount)", symbolName: "person.crop.rectangle"))
        }
        submenu.addItem(.separator())
        submenu.addItem(actionItem(title: "Manage Variables...", action: #selector(manageVariablesAction(_:)), symbolName: "slider.horizontal.3"))

        item.submenu = submenu
        return item
    }
}
