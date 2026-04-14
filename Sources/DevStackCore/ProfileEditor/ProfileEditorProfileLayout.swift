import AppKit
import Foundation

@MainActor
extension ProfileEditorWindowController {
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
}
