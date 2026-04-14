import AppKit
import Foundation

@MainActor
enum ServiceEditorDialog {
    static func runModal(service: ServiceDefinition?, parentWindow: NSWindow?) -> ServiceDefinition? {
        let nameField = NSTextField(string: service?.name ?? "")
        let roleField = NSPopUpButton()
        roleField.addItems(withTitles: ["generic", "postgres", "redis", "http", "https", "minio"])
        roleField.selectItem(withTitle: service?.role ?? "generic")

        let aliasField = NSTextField(string: service?.aliasHost ?? "")
        let localPortField = NSTextField(string: service?.localPort == 0 ? "" : "\(service?.localPort ?? 0)")
        let remoteHostField = NSTextField(string: service?.remoteHost ?? "127.0.0.1")
        let remotePortField = NSTextField(string: service?.remotePort == 0 ? "" : "\(service?.remotePort ?? 0)")
        let remoteServerField = NSTextField(string: service?.remoteServer ?? "")
        let envPrefixField = NSTextField(string: service?.envPrefix ?? "")
        let enabledCheckbox = NSButton(
            checkboxWithTitle: "Enabled",
            target: nil,
            action: nil
        )
        enabledCheckbox.state = (service?.enabled ?? true) ? .on : .off

        let exportsTextView = NSTextView()
        exportsTextView.string = service?.extraExports.joined(separator: "\n") ?? ""
        exportsTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        let accessory = NSStackView()
        accessory.orientation = .vertical
        accessory.alignment = .leading
        accessory.spacing = 8
        accessory.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 0, right: 0)

        let grid = NSGridView(views: [
            [fieldLabel("Name"), nameField],
            [fieldLabel("Role"), roleField],
            [fieldLabel("Alias Host"), aliasField],
            [fieldLabel("Local Port"), localPortField],
            [fieldLabel("Remote Host"), remoteHostField],
            [fieldLabel("Remote Port"), remotePortField],
            [fieldLabel("Remote Server"), remoteServerField],
            [fieldLabel("Env Prefix"), envPrefixField],
            [fieldLabel(""), enabledCheckbox],
        ])
        grid.column(at: 0).width = 100
        grid.rowSpacing = 6
        grid.columnSpacing = 12

        accessory.addArrangedSubview(grid)
        accessory.addArrangedSubview(fieldLabel("Extra Export Lines"))
        accessory.addArrangedSubview(scrollContainer(for: exportsTextView, height: 90, width: 420))

        let alert = NSAlert()
        alert.messageText = service == nil ? "Add Service" : "Edit Service"
        alert.informativeText = "One profile can contain multiple databases and services."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = accessory

        while true {
            let response: NSApplication.ModalResponse
            if let parentWindow {
                response = alert.runModal()
                _ = parentWindow
            } else {
                response = alert.runModal()
            }

            guard response == .alertFirstButtonReturn else {
                return nil
            }

            let localPort = Int(localPortField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let remotePort = Int(remotePortField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let trimmedName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedName.isEmpty {
                showSimpleError("Service name is required.")
                continue
            }

            let built = ServiceDefinition(
                name: trimmedName,
                role: roleField.selectedItem?.title ?? "generic",
                aliasHost: aliasField.stringValue,
                localPort: localPort,
                remoteHost: remoteHostField.stringValue,
                remotePort: remotePort,
                tunnelHost: remoteServerField.stringValue,
                enabled: enabledCheckbox.state == .on,
                envPrefix: envPrefixField.stringValue,
                extraExports: exportsTextView.string
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )

            do {
                let validated = try ProfileDefinition(name: "validation", services: [built]).normalized().services[0]
                return validated
            } catch {
                showSimpleError(error.localizedDescription)
            }
        }
    }

    private static func fieldLabel(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        field.alignment = .right
        return field
    }

    private static func scrollContainer(for textView: NSTextView, height: CGFloat, width: CGFloat) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = textView
        textView.minSize = NSSize(width: width, height: height)
        textView.maxSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scrollView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        return scrollView
    }

    private static func showSimpleError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Service Error"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
