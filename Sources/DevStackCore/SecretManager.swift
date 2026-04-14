import AppKit
import Foundation

@MainActor
final class SecretManagerWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private let store: ProfileStore
    private let profile: ProfileDefinition
    private let onClose: () -> Void

    private let summaryField = NSTextField(wrappingLabelWithString: "")
    private let tableView = NSTableView()
    private var overview: ComposeSecretOverview?

    init(
        store: ProfileStore,
        profile: ProfileDefinition,
        onClose: @escaping () -> Void
    ) {
        self.store = store
        self.profile = profile
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Manage Secrets"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self

        buildUI()
        reloadOverview()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        overview?.entries.count ?? 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let entry = overview?.entries[row] else {
            return nil
        }

        let identifier = tableColumn?.identifier.rawValue ?? "value"
        let text: String
        switch identifier {
        case "key":
            text = entry.key
        default:
            text = entry.statusText
        }

        let viewIdentifier = NSUserInterfaceItemIdentifier("secret-\(identifier)")
        let label: NSTextField
        if let existing = tableView.makeView(withIdentifier: viewIdentifier, owner: self) as? NSTextField {
            label = existing
        } else {
            label = NSTextField(labelWithString: "")
            label.identifier = viewIdentifier
            label.lineBreakMode = .byTruncatingMiddle
        }
        label.stringValue = text
        label.textColor = identifier == "status" && text == "Missing" ? .systemRed : .labelColor
        return label
    }

    @objc private func saveSecretAction(_ sender: Any?) {
        guard let entry = selectedEntry() else {
            presentError("Select a secret first.")
            return
        }

        guard let value = SecretManagerDialogs.runSaveValueModal(entry: entry, profileName: profile.name) else {
            return
        }

        do {
            try SecretManagerDataService.saveProfileSecret(
                key: entry.key,
                value: value,
                profile: profile
            )
            reloadOverview(message: "Secret '\(entry.key)' saved in Keychain")
        } catch {
            presentError(error.localizedDescription)
        }
    }

    @objc private func deleteSecretAction(_ sender: Any?) {
        guard let entry = selectedEntry() else {
            presentError("Select a secret first.")
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete profile secret '\(entry.key)'?"
        alert.informativeText = "This removes only the profile-scoped Keychain value. Project Keychain or env file values are left untouched."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        do {
            try SecretManagerDataService.deleteProfileSecret(key: entry.key, profile: profile)
            reloadOverview(message: "Secret '\(entry.key)' removed from profile Keychain")
        } catch {
            presentError(error.localizedDescription)
        }
    }

    @objc private func openEnvFilesAction(_ sender: Any?) {
        guard let overview else {
            return
        }

        if let firstEnvironmentFile = overview.environmentFiles.first {
            NSWorkspace.shared.open(firstEnvironmentFile)
        } else {
            NSWorkspace.shared.open(overview.workingDirectory)
        }
    }

    @objc private func refreshAction(_ sender: Any?) {
        reloadOverview()
    }

    private func buildUI() {
        guard let contentView = window?.contentView else {
            return
        }

        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)

        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        let title = NSTextField(labelWithString: "Compose secrets for \(profile.name)")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        root.addArrangedSubview(title)

        summaryField.maximumNumberOfLines = 4
        summaryField.textColor = .secondaryLabelColor
        root.addArrangedSubview(summaryField)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView

        tableView.headerView = NSTableHeaderView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 24
        tableView.delegate = self
        tableView.dataSource = self
        tableView.allowsMultipleSelection = false
        tableView.doubleAction = #selector(saveSecretAction(_:))
        tableView.target = self

        addColumn(id: "key", title: "Key", width: 240)
        addColumn(id: "status", title: "Status", width: 420)

        NSLayoutConstraint.activate([
            scrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 700),
            scrollView.heightAnchor.constraint(equalToConstant: 340),
        ])
        root.addArrangedSubview(scrollView)

        let buttons = NSStackView(views: [
            button(title: "Save Value…", action: #selector(saveSecretAction(_:))),
            button(title: "Delete Profile Secret", action: #selector(deleteSecretAction(_:))),
            button(title: "Open Env Files", action: #selector(openEnvFilesAction(_:))),
            button(title: "Refresh", action: #selector(refreshAction(_:))),
        ])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8
        root.addArrangedSubview(buttons)
    }

    private func addColumn(id: String, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        column.resizingMask = .userResizingMask
        tableView.addTableColumn(column)
    }

    private func selectedEntry() -> ComposeSecretEntry? {
        let row = tableView.selectedRow
        guard row >= 0, row < (overview?.entries.count ?? 0) else {
            return nil
        }
        return overview?.entries[row]
    }

    private func reloadOverview(message: String? = nil) {
        do {
            let overview = try SecretManagerDataService.secretOverview(profile: profile, store: store)
            self.overview = overview
            let summary = SecretManagerDataService.summaryLines(overview: overview)
            summaryField.stringValue = ([message].compactMap { $0 } + [summary.joined(separator: "\n")]).joined(separator: "\n\n")
        } catch {
            overview = nil
            summaryField.stringValue = error.localizedDescription
        }

        tableView.reloadData()
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Secrets Error"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window ?? NSWindow(), completionHandler: nil)
    }

    private func button(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }
}
