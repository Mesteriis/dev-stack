import AppKit
import UniformTypeIdentifiers

@MainActor
extension ProfileEditorWindowController {
    @objc func localContainerModeChanged(_ sender: Any?) {
        updateLocalContainerModeDescription()
    }

    @objc func chooseComposeSourceAction(_ sender: Any?) {
        guard let url = selectComposeURLs(allowsMultipleSelection: false).first else {
            return
        }

        if !composeSourceFile.isEmpty, composeSourceFile != url.path, !composeAdditionalSourceFiles.contains(composeSourceFile) {
            composeAdditionalSourceFiles.insert(composeSourceFile, at: 0)
        }
        composeSourceFile = url.path
        composeAdditionalSourceFiles.removeAll { $0 == composeSourceFile }
        composeWorkingDirectoryField.stringValue = url.deletingLastPathComponent().path
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            composeTextView.string = content
        }
        updateComposeSourceDetails()
        updateComposeOverlayDetails()
        reloadComposeEnvironmentOverview()
    }

    @objc func clearComposeSourceAction(_ sender: Any?) {
        if let replacement = composeAdditionalSourceFiles.first {
            composeSourceFile = replacement
            composeAdditionalSourceFiles.removeFirst()
        } else {
            composeSourceFile = ""
        }
        updateComposeSourceDetails()
        updateComposeOverlayDetails()
        reloadComposeEnvironmentOverview()
    }

    @objc func openComposeSourceAction(_ sender: Any?) {
        let path = composeSourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: false))
    }

    @objc func addComposeOverlayAction(_ sender: Any?) {
        let urls = selectComposeURLs(allowsMultipleSelection: true)
        guard !urls.isEmpty else {
            return
        }

        for url in urls {
            let path = url.path
            guard path != composeSourceFile, !composeAdditionalSourceFiles.contains(path) else {
                continue
            }
            composeAdditionalSourceFiles.append(path)
        }
        updateComposeOverlayDetails()
        reloadComposeEnvironmentOverview()
    }

    @objc func removeComposeOverlayAction(_ sender: Any?) {
        let selectedPath = selectedOverlayPath()
        guard let selectedPath else {
            return
        }
        composeAdditionalSourceFiles.removeAll { $0 == selectedPath }
        updateComposeOverlayDetails()
        reloadComposeEnvironmentOverview()
    }

    @objc func openComposeOverlayAction(_ sender: Any?) {
        guard let selectedPath = selectedOverlayPath() else {
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: selectedPath, isDirectory: false))
    }

    @objc func composeOverlaySelectionChanged(_ sender: Any?) {
        updateComposeOverlayDetails()
        updateEnvironmentDetails()
    }

    func updateComposeSourceDetails() {
        if composeSourceFile.isEmpty {
            composeSourceField.stringValue = "Manual compose contents. The working directory controls where ./data is materialized."
            composeWorkingDirectoryField.isEditable = true
            return
        }

        composeSourceField.stringValue = composeSourceFile
        composeWorkingDirectoryField.isEditable = false
        composeWorkingDirectoryField.stringValue = URL(fileURLWithPath: composeSourceFile, isDirectory: false)
            .deletingLastPathComponent()
            .path
    }

    func updateComposeOverlayDetails() {
        composeOverlaysField.removeAllItems()
        if composeAdditionalSourceFiles.isEmpty {
            composeOverlaysField.addItem(withTitle: "No overlays")
            composeOverlaysField.isEnabled = false
            composeOverlaysSummaryField.stringValue = "Optional override files passed after the main compose file."
            return
        }

        composeOverlaysField.addItems(withTitles: composeAdditionalSourceFiles)
        composeOverlaysField.isEnabled = true
        if composeOverlaysField.indexOfSelectedItem < 0 {
            composeOverlaysField.selectItem(at: 0)
        }
        composeOverlaysSummaryField.stringValue = "\(composeAdditionalSourceFiles.count) overlay file(s) will be appended with `docker compose -f ...`."
    }

    func selectedOverlayPath() -> String? {
        let title = composeOverlaysField.selectedItem?.title ?? ""
        guard !title.isEmpty, title != "No overlays" else {
            return nil
        }
        return title
    }

    func selectComposeURLs(allowsMultipleSelection: Bool) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.allowedContentTypes = [
            UTType(filenameExtension: "yml") ?? .yaml,
            UTType(filenameExtension: "yaml") ?? .yaml,
        ]
        panel.directoryURL = composeSourceFile.isEmpty
            ? (
                composeWorkingDirectoryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : URL(fileURLWithPath: composeWorkingDirectoryField.stringValue, isDirectory: true)
            )
            : URL(fileURLWithPath: composeSourceFile, isDirectory: false).deletingLastPathComponent()

        guard panel.runModal() == .OK else {
            return []
        }
        return panel.urls
    }

    func selectedLocalContainerMode() -> LocalContainerMode {
        let selectedTitle = localContainerModeField.selectedItem?.title
        return LocalContainerMode.allCases.first(where: { $0.title == selectedTitle }) ?? .manual
    }

    func updateLocalContainerModeDescription() {
        localContainerModeDescription.stringValue = selectedLocalContainerMode().summary
    }
}
