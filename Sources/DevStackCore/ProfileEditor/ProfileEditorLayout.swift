import AppKit
import Foundation

@MainActor
extension ProfileEditorWindowController {
    func buildUI() {
        guard let contentView = window?.contentView else {
            return
        }

        let rootScrollView = NSScrollView()
        rootScrollView.translatesAutoresizingMaskIntoConstraints = false
        rootScrollView.drawsBackground = false
        rootScrollView.hasVerticalScroller = true
        rootScrollView.hasHorizontalScroller = false
        rootScrollView.borderType = .noBorder

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        rootScrollView.documentView = documentView

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14

        documentView.addSubview(stack)
        contentView.addSubview(rootScrollView)

        NSLayoutConstraint.activate([
            rootScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rootScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rootScrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            rootScrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -18),
            stack.widthAnchor.constraint(equalTo: rootScrollView.contentView.widthAnchor, constant: -36),
        ])

        stack.addArrangedSubview(sectionTitle("Profile"))
        stack.addArrangedSubview(profileGrid())
        stack.addArrangedSubview(localContainerModeSection())

        stack.addArrangedSubview(sectionTitle("Services"))
        stack.addArrangedSubview(serviceTableSection())

        stack.addArrangedSubview(sectionTitle("Shell Exports"))
        stack.addArrangedSubview(textSection(shellExportsTextView, height: 90))

        stack.addArrangedSubview(sectionTitle("Docker Compose Contents"))
        stack.addArrangedSubview(textSection(composeTextView, height: 250))
        stack.addArrangedSubview(sectionTitle("Compose Environment"))
        stack.addArrangedSubview(composeEnvironmentSection())

        stack.addArrangedSubview(buttonRow())
    }

    func profileGrid() -> NSGridView {
        let grid = NSGridView(views: [
            [label("Name"), nameField],
            [label("Runtime"), runtimeSelectionRow()],
            [label("Docker Context"), runtimeDockerContextField],
            [label("Remote Docker Runtime"), runtimeRemoteHostField],
            [NSView(), runtimeSummaryField],
            [label("Compose Project"), composeProjectField],
            [label("Compose Working Dir"), composeWorkingDirectoryField],
            [label("Source Compose"), composeSourceSelectionRow()],
            [NSView(), composeSourceField],
            [label("Compose Overlays"), composeOverlaySelectionRow()],
            [NSView(), composeOverlaysSummaryField],
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        grid.xPlacement = .fill
        grid.yPlacement = .center
        grid.column(at: 0).width = 150
        return grid
    }

    func runtimeSelectionRow() -> NSView {
        let addButton = button(title: "New Runtime…", action: #selector(addRuntimeAction(_:)))
        let editButton = button(title: "Edit…", action: #selector(editRuntimeAction(_:)))
        let stack = NSStackView(views: [runtimeField, addButton, editButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    func composeSourceSelectionRow() -> NSView {
        let chooseButton = button(title: "Choose…", action: #selector(chooseComposeSourceAction(_:)))
        let clearButton = button(title: "Clear", action: #selector(clearComposeSourceAction(_:)))
        let openButton = button(title: "Open", action: #selector(openComposeSourceAction(_:)))
        let stack = NSStackView(views: [chooseButton, clearButton, openButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    func composeOverlaySelectionRow() -> NSView {
        composeOverlaysField.target = self
        composeOverlaysField.action = #selector(composeOverlaySelectionChanged(_:))

        let addButton = button(title: "Add…", action: #selector(addComposeOverlayAction(_:)))
        let removeButton = button(title: "Remove", action: #selector(removeComposeOverlayAction(_:)))
        let openButton = button(title: "Open", action: #selector(openComposeOverlayAction(_:)))

        let stack = NSStackView(views: [composeOverlaysField, addButton, removeButton, openButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    func localContainerModeSection() -> NSView {
        let modeLabel = label("Local Container Mode")
        let grid = NSGridView(views: [
            [modeLabel, localContainerModeField],
            [NSView(), localContainerModeDescription],
        ])
        grid.column(at: 0).width = 150
        grid.columnSpacing = 12
        grid.rowSpacing = 6

        let stack = NSStackView(views: [grid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        return stack
    }

    func composeEnvironmentSection() -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 8
        container.translatesAutoresizingMaskIntoConstraints = false

        environmentSummaryField.maximumNumberOfLines = 4
        environmentSummaryField.textColor = .secondaryLabelColor
        container.addArrangedSubview(environmentSummaryField)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = environmentTableView

        environmentTableView.headerView = NSTableHeaderView()
        environmentTableView.usesAlternatingRowBackgroundColors = true
        environmentTableView.rowHeight = 24
        environmentTableView.delegate = self
        environmentTableView.dataSource = self
        environmentTableView.target = self
        environmentTableView.action = #selector(environmentSelectionChanged(_:))
        environmentTableView.allowsMultipleSelection = false

        addEnvironmentColumn(id: "key", title: "Variable", width: 220)
        addEnvironmentColumn(id: "status", title: "Status", width: 540)

        NSLayoutConstraint.activate([
            scrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 860),
            scrollView.heightAnchor.constraint(equalToConstant: 150),
        ])
        container.addArrangedSubview(scrollView)

        environmentStatusField.maximumNumberOfLines = 3
        environmentStatusField.textColor = .secondaryLabelColor
        environmentNoteField.maximumNumberOfLines = 3
        environmentNoteField.textColor = .secondaryLabelColor
        clipboardPreviewField.maximumNumberOfLines = 3
        clipboardPreviewField.textColor = .secondaryLabelColor

        let detailGrid = NSGridView(views: [
            [label("Selected"), environmentKeyField],
            [label("Value"), environmentValueField],
            [NSView(), environmentSensitiveCheckbox],
            [NSView(), environmentStatusField],
            [NSView(), environmentNoteField],
            [NSView(), clipboardPreviewRow()],
        ])
        detailGrid.column(at: 0).width = 150
        detailGrid.columnSpacing = 12
        detailGrid.rowSpacing = 6
        container.addArrangedSubview(detailGrid)

        let generateButton = button(title: "Generate…", action: #selector(generateEnvironmentValueAction(_:)))
        let saveButton = button(title: "Save Value", action: #selector(saveEnvironmentValueAction(_:)))
        let ignoreButton = button(title: "Ignore", action: #selector(ignoreEnvironmentVariableAction(_:)))
        let externalButton = button(title: "Mark as External", action: #selector(toggleExternalEnvironmentVariableAction(_:)))
        environmentGenerateButton = generateButton
        environmentSaveButton = saveButton
        environmentIgnoreButton = ignoreButton
        environmentExternalButton = externalButton
        let buttons = NSStackView(views: [
            generateButton,
            saveButton,
            ignoreButton,
            externalButton,
            button(title: "Refresh Env", action: #selector(refreshComposeEnvironmentAction(_:))),
        ])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8
        container.addArrangedSubview(buttons)

        return container
    }

    func serviceTableSection() -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 8
        container.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = servicesTableView

        servicesTableView.headerView = NSTableHeaderView()
        servicesTableView.usesAlternatingRowBackgroundColors = true
        servicesTableView.rowHeight = 24
        servicesTableView.delegate = self
        servicesTableView.dataSource = self
        servicesTableView.target = self
        servicesTableView.doubleAction = #selector(editServiceAction(_:))
        servicesTableView.allowsMultipleSelection = false

        addColumn(id: "name", title: "Name", width: 150)
        addColumn(id: "role", title: "Role", width: 90)
        addColumn(id: "tunnelHost", title: "Server", width: 120)
        addColumn(id: "aliasHost", title: "Alias", width: 180)
        addColumn(id: "localPort", title: "Local", width: 70)
        addColumn(id: "remotePort", title: "Remote", width: 70)
        addColumn(id: "enabled", title: "On", width: 50)

        NSLayoutConstraint.activate([
            scrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 860),
            scrollView.heightAnchor.constraint(equalToConstant: 210),
        ])

        let buttons = NSStackView(views: [
            button(title: "Add Service", action: #selector(addServiceAction(_:))),
            button(title: "Edit Service", action: #selector(editServiceAction(_:))),
            button(title: "Remove Service", action: #selector(removeServiceAction(_:))),
            button(title: "Import From Compose", action: #selector(importServicesFromComposeAction(_:))),
        ])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8

        container.addArrangedSubview(scrollView)
        container.addArrangedSubview(buttons)
        return container
    }

    func textSection(_ textView: NSTextView, height: CGFloat) -> NSView {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = true
        scrollView.documentView = textView
        textView.minSize = NSSize(width: 0, height: height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        NSLayoutConstraint.activate([
            scrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 860),
            scrollView.heightAnchor.constraint(equalToConstant: height),
        ])

        return scrollView
    }

    func buttonRow() -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let saveButton = button(title: "Save Profile", action: #selector(saveAction(_:)))
        saveButton.keyEquivalent = "\r"

        let cancelButton = button(title: "Cancel", action: #selector(cancelAction(_:)))
        let stack = NSStackView(views: [spacer, cancelButton, saveButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    func addColumn(id: String, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        column.resizingMask = .userResizingMask
        servicesTableView.addTableColumn(column)
    }

    func addEnvironmentColumn(id: String, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        column.resizingMask = .userResizingMask
        environmentTableView.addTableColumn(column)
    }
}
