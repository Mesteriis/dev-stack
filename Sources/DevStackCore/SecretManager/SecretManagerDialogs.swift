import AppKit

@MainActor
enum SecretManagerDialogs {
    @MainActor
    static func runSaveValueModal(entry: ComposeSecretEntry, profileName: String) -> String? {
        let keyField = NSTextField(string: entry.key)
        keyField.isEditable = false
        let valueField = NSSecureTextField()

        let accessory = NSStackView()
        accessory.orientation = .vertical
        accessory.alignment = .leading
        accessory.spacing = 8

        let info = NSTextField(wrappingLabelWithString: "Save a profile-scoped Keychain value for \(entry.key). Env files still take precedence if they already define this key.")
        info.maximumNumberOfLines = 3
        info.textColor = .secondaryLabelColor
        accessory.addArrangedSubview(info)
        accessory.addArrangedSubview(formRow(label: "Key", field: keyField))
        accessory.addArrangedSubview(formRow(label: "Value", field: valueField))

        let alert = NSAlert()
        alert.messageText = "Save Secret"
        alert.informativeText = "The value is stored in Keychain service devstackmenu.\(slugify(profileName))."
        alert.accessoryView = accessory
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        return valueField.stringValue
    }

    private static func formRow(label text: String, field: NSView) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        label.alignment = .right
        field.translatesAutoresizingMaskIntoConstraints = false

        let grid = NSGridView(views: [[label, field]])
        grid.column(at: 0).width = 80
        grid.columnSpacing = 12
        return grid
    }
}
