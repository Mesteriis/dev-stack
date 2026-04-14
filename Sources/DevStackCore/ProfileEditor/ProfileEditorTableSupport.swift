import AppKit
import Foundation

@MainActor
extension ProfileEditorWindowController {
    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == environmentTableView {
            return environmentOverview?.entries.count ?? 0
        }
        return services.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView == environmentTableView {
            guard let entry = environmentOverview?.entries[row] else {
                return nil
            }

            let identifier = tableColumn?.identifier.rawValue ?? "status"
            let text = identifier == "key" ? entry.key : entry.statusText
            let cellIdentifier = NSUserInterfaceItemIdentifier("env-cell-\(identifier)")
            let labelField: NSTextField
            if let existing = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTextField {
                labelField = existing
            } else {
                labelField = NSTextField(labelWithString: "")
                labelField.identifier = cellIdentifier
                labelField.lineBreakMode = .byTruncatingMiddle
            }
            labelField.stringValue = text
            if identifier == "status", entry.isMissing || entry.isEmptyValue {
                labelField.textColor = .systemRed
            } else if identifier == "status", entry.isMarkedExternal {
                labelField.textColor = .systemOrange
            } else {
                labelField.textColor = .labelColor
            }
            return labelField
        }

        guard row >= 0, row < services.count else {
            return nil
        }

        let service = services[row]
        let identifier = tableColumn?.identifier.rawValue ?? "cell"
        let text: String

        switch identifier {
        case "name":
            text = service.name
        case "role":
            text = service.role
        case "tunnelHost":
            text = service.remoteServer.isEmpty ? "(profile default)" : service.remoteServer
        case "aliasHost":
            text = service.aliasHost
        case "localPort":
            text = service.localPort == 0 ? "" : "\(service.localPort)"
        case "remotePort":
            text = service.remotePort == 0 ? "" : "\(service.remotePort)"
        case "enabled":
            text = service.enabled ? "yes" : "no"
        default:
            text = ""
        }

        let cellIdentifier = NSUserInterfaceItemIdentifier("profile-cell-\(identifier)")
        let labelField: NSTextField
        if let existing = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTextField {
            labelField = existing
        } else {
            labelField = NSTextField(labelWithString: "")
            labelField.identifier = cellIdentifier
            labelField.lineBreakMode = .byTruncatingMiddle
        }
        labelField.stringValue = text
        return labelField
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView else {
            return
        }
        if tableView == environmentTableView {
            updateEnvironmentDetails()
        }
    }
}
