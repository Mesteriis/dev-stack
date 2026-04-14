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
}
