import AppKit
import Foundation

@MainActor
extension ProfileEditorWindowController {
    @objc func addServiceAction(_ sender: Any?) {
        if let service = ServiceEditorDialog.runModal(service: nil, parentWindow: window) {
            services.append(service)
            servicesTableView.reloadData()
            servicesTableView.selectRowIndexes(IndexSet(integer: services.count - 1), byExtendingSelection: false)
        }
    }

    @objc func editServiceAction(_ sender: Any?) {
        let row = servicesTableView.selectedRow
        guard row >= 0, row < services.count else {
            presentError("Select a service first.")
            return
        }

        if let updated = ServiceEditorDialog.runModal(service: services[row], parentWindow: window) {
            services[row] = updated
            servicesTableView.reloadData()
            servicesTableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

    @objc func removeServiceAction(_ sender: Any?) {
        let row = servicesTableView.selectedRow
        guard row >= 0, row < services.count else {
            presentError("Select a service first.")
            return
        }
        services.remove(at: row)
        servicesTableView.reloadData()
    }

    @objc func importServicesFromComposeAction(_ sender: Any?) {
        let workingDirectory = composeWorkingDirectoryField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let imported = ComposeSupport.importServices(
            from: composeTextView.string,
            workingDirectory: workingDirectory.isEmpty ? nil : URL(fileURLWithPath: workingDirectory, isDirectory: true)
        )
        guard !imported.isEmpty else {
            presentError("Could not infer any published ports from the docker-compose contents.")
            return
        }

        if services.isEmpty {
            services = imported
            servicesTableView.reloadData()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Import services from compose?"
        alert.informativeText = "Replace the current service list or append imported services."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Append")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            services = imported
        case .alertSecondButtonReturn:
            services.append(contentsOf: imported)
        default:
            return
        }

        servicesTableView.reloadData()
    }
}
