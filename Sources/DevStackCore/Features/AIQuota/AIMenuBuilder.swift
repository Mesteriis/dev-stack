import AppKit
import Foundation

@MainActor
enum AIMenuBuilder {
    static func buildMenu(delegate: AppDelegate, snapshots: [AIToolQuotaSnapshot]) -> NSMenuItem {
        let item = delegate.submenuItem(title: "AI CLI Limits", symbolName: "gauge.with.dots.needle.50percent")
        let submenu = NSMenu()

        if snapshots.isEmpty {
            submenu.addItem(delegate.disabledItem(title: "No tool data yet"))
        } else {
            for snapshot in snapshots {
                let toolItem = delegate.submenuItem(title: snapshot.kind.title, symbolName: snapshot.statusSymbolName)
                let toolMenu = NSMenu()
                if !snapshot.progressMetrics.isEmpty || !snapshot.highlightLines.isEmpty {
                    toolMenu.addItem(aiQuotaSummaryItem(delegate: delegate, snapshot: snapshot))
                    toolMenu.addItem(.separator())
                }
                toolMenu.addItem(delegate.disabledItem(title: "CLI: \(snapshot.cliStatus)", symbolName: "terminal"))
                toolMenu.addItem(delegate.disabledItem(title: "Auth: \(snapshot.authStatus)", symbolName: "lock"))
                toolMenu.addItem(delegate.disabledItem(title: "Quota: \(snapshot.quotaStatus)", symbolName: "chart.bar"))

                if !snapshot.detailLines.isEmpty {
                    toolMenu.addItem(.separator())
                    for line in snapshot.detailLines {
                        toolMenu.addItem(delegate.disabledItem(title: line, symbolName: "info.circle"))
                    }
                }

                toolMenu.addItem(.separator())
                let helpItem = delegate.actionItem(title: "Setup / Auth Help...", action: #selector(AppDelegate.aiToolHelpAction(_:)), symbolName: "questionmark.circle")
                helpItem.representedObject = snapshot.kind.rawValue
                toolMenu.addItem(helpItem)
                toolItem.submenu = toolMenu
                submenu.addItem(toolItem)
            }
        }

        item.submenu = submenu
        return item
    }

    private static func aiQuotaSummaryItem(delegate: AppDelegate, snapshot: AIToolQuotaSnapshot) -> NSMenuItem {
        let item = NSMenuItem()
        let view = makeAIQuotaSummaryView(snapshot: snapshot)
        item.isEnabled = true
        item.view = view
        _ = delegate
        return item
    }

    private static func makeAIQuotaSummaryView(snapshot: AIToolQuotaSnapshot) -> NSView {
        let preferredWidth: CGFloat = 310
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: snapshot.kind.title)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(title)

        let quota = NSTextField(labelWithString: snapshot.quotaStatus)
        quota.textColor = .secondaryLabelColor
        quota.font = .systemFont(ofSize: 11)
        quota.lineBreakMode = .byTruncatingTail
        stack.addArrangedSubview(quota)

        for highlight in snapshot.highlightLines.prefix(3) {
            let label = NSTextField(labelWithString: highlight)
            label.textColor = .secondaryLabelColor
            label.font = .systemFont(ofSize: 11)
            label.lineBreakMode = .byTruncatingTail
            stack.addArrangedSubview(label)
        }

        for metric in snapshot.progressMetrics {
            stack.addArrangedSubview(aiQuotaMetricRow(metric))
        }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: preferredWidth, height: 1))
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: preferredWidth),
        ])

        container.layoutSubtreeIfNeeded()
        let fittingHeight = max(44, stack.fittingSize.height)
        container.frame = NSRect(x: 0, y: 0, width: preferredWidth, height: fittingHeight)

        return container
    }

    private static func aiQuotaMetricRow(_ metric: AIToolProgressMetric) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: metric.summary)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        header.addArrangedSubview(label)

        let remainingPercent = max(0, min(100, Int(((1 - metric.usedPercent) * 100).rounded())))
        let remainingLabel = NSTextField(labelWithString: "\(remainingPercent)% left")
        remainingLabel.textColor = .systemGreen
        remainingLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        remainingLabel.alignment = .right
        remainingLabel.setContentHuggingPriority(.required, for: .horizontal)
        remainingLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        header.addArrangedSubview(remainingLabel)
        stack.addArrangedSubview(header)

        let remainingBar = AIQuotaRemainingBarView(remainingFraction: 1 - metric.usedPercent)
        remainingBar.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(remainingBar)

        if let forecast = metric.forecastExhaustionAt, let resetAt = metric.resetAt, forecast < resetAt {
            let forecastLabel = NSTextField(labelWithString: "Forecast: ends around \(formattedForecast(forecast))")
            forecastLabel.textColor = .systemOrange
            forecastLabel.font = .systemFont(ofSize: 10)
            forecastLabel.lineBreakMode = .byTruncatingTail
            stack.addArrangedSubview(forecastLabel)
        }

        NSLayoutConstraint.activate([
            remainingBar.widthAnchor.constraint(equalToConstant: 280),
        ])

        return stack
    }

    private static func formattedForecast(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

extension AppDelegate {
    @objc func aiToolHelpAction(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let kind = AIToolKind(rawValue: rawValue),
              let snapshot = aiToolSnapshots.first(where: { $0.kind == kind })
        else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "\(snapshot.kind.title) Setup"
        var informativeText = snapshot.helpMessage
        if let helpCommand = snapshot.helpCommand {
            informativeText += "\n\nCommand:\n\(helpCommand)"
            alert.addButton(withTitle: "Copy Command")
        }
        alert.informativeText = informativeText
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn, let helpCommand = snapshot.helpCommand {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(helpCommand, forType: .string)
            lastMessage = "\(snapshot.kind.title) auth command copied"
            rebuildMenu()
            updateStatusButton()
        }
    }
}

private final class AIQuotaRemainingBarView: NSView {
    private let remainingFraction: CGFloat

    init(remainingFraction: Double) {
        self.remainingFraction = max(0, min(1, CGFloat(remainingFraction)))
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 12))
        wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 280, height: 12)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let barRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let trackRadius = min(barRect.height / 2, barRect.width / 2)
        let trackPath = NSBezierPath(
            roundedRect: barRect,
            xRadius: trackRadius,
            yRadius: trackRadius
        )
        NSColor.quaternaryLabelColor.withAlphaComponent(0.35).setFill()
        trackPath.fill()

        let fillWidth = barRect.width * remainingFraction
        guard fillWidth > 0.5 else {
            return
        }

        let fillRect = NSRect(x: barRect.minX, y: barRect.minY, width: fillWidth, height: barRect.height)
        let fillRadius = min(fillRect.height / 2, fillRect.width / 2)
        let fillPath = NSBezierPath(
            roundedRect: fillRect,
            xRadius: fillRadius,
            yRadius: fillRadius
        )
        NSColor.systemGreen.setFill()
        fillPath.fill()
    }
}
