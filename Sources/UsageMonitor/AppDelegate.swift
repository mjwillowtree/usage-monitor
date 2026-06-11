import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var snapshot: UsageSnapshot?
    private var lastError: Error?
    private var refreshTimer: Timer?

    private static let refreshInterval: TimeInterval = 5 * 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize(for: .small), weight: .medium)
        statusItem.button?.title = "✳ …"
        menu.delegate = self
        statusItem.menu = menu

        refresh()
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: Self.refreshInterval, repeats: true
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Opening the menu always gets fresh-enough data on screen
        // immediately and kicks off a refetch in the background.
        rebuildMenu()
        refresh()
    }

    @objc private func refreshClicked() {
        refresh()
    }

    private func refresh() {
        Task { @MainActor in
            do {
                snapshot = try await UsageClient.fetch()
                lastError = nil
            } catch {
                lastError = error
            }
            updateTitle()
            rebuildMenu()
        }
    }

    // MARK: - Menu bar title

    private func updateTitle() {
        guard let button = statusItem.button else { return }
        if let percent = snapshot?.headlinePercent {
            button.title = "✳ \(Int(percent.rounded()))%"
        } else if lastError != nil {
            button.title = "✳ !"
        } else {
            button.title = "✳ …"
        }
    }

    // MARK: - Menu construction

    private func rebuildMenu() {
        menu.removeAllItems()

        menu.addItem(header("Claude Usage"))
        menu.addItem(.separator())

        if let snapshot {
            for bucket in snapshot.buckets {
                menu.addItem(bucketItem(
                    label: bucket.label,
                    utilization: bucket.utilization,
                    detail: resetText(bucket.resetsAt)
                ))
            }
            if let extra = snapshot.extraUsage, extra.isEnabled {
                if !snapshot.buckets.isEmpty { menu.addItem(.separator()) }
                menu.addItem(bucketItem(
                    label: "Extra usage (this month)",
                    utilization: extra.utilization,
                    detail: "\(dollars(extra.usedCents, extra.currency)) of \(dollars(extra.monthlyLimitCents, extra.currency))"
                ))
            }
            if snapshot.buckets.isEmpty && snapshot.extraUsage == nil {
                menu.addItem(disabledItem("No usage limits reported"))
            }
        }

        if let lastError {
            menu.addItem(disabledItem("⚠︎ \(lastError.localizedDescription)"))
        } else if snapshot == nil {
            menu.addItem(disabledItem("Loading…"))
        }

        menu.addItem(.separator())
        if let fetchedAt = snapshot?.fetchedAt {
            menu.addItem(disabledItem("Updated \(Self.timeFormatter.string(from: fetchedAt))"))
        }
        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshClicked), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Usage Monitor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    /// Two-line item: "Label                       42.0%" over a progress bar
    /// and reset/detail text, mirroring the /usage screen.
    private func bucketItem(label: String, utilization: Double, detail: String?) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false

        let percentText = String(format: "%.1f%%", utilization)
        let titleFont = NSFont.menuFont(ofSize: 0)
        let monoFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .regular)

        let result = NSMutableAttributedString()
        result.append(NSAttributedString(
            string: "\(label)  —  \(percentText)\n",
            attributes: [.font: titleFont, .foregroundColor: NSColor.labelColor]
        ))

        let filled = max(0, min(20, Int((utilization / 5.0).rounded())))
        let barColor: NSColor = utilization >= 95 ? .systemRed
            : utilization >= 80 ? .systemOrange
            : .systemGreen
        result.append(NSAttributedString(
            string: String(repeating: "█", count: filled),
            attributes: [.font: monoFont, .foregroundColor: barColor]
        ))
        result.append(NSAttributedString(
            string: String(repeating: "░", count: 20 - filled),
            attributes: [.font: monoFont, .foregroundColor: NSColor.tertiaryLabelColor]
        ))
        if let detail {
            result.append(NSAttributedString(
                string: "  \(detail)",
                attributes: [.font: monoFont, .foregroundColor: NSColor.secondaryLabelColor]
            ))
        }

        item.attributedTitle = result
        return item
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize(for: .small)),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Formatting

    private func resetText(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        let isToday = Calendar.current.isDateInToday(date)
        formatter.dateFormat = isToday ? "'today at' h:mm a" : "MMM d, h:mm a"
        return "resets \(formatter.string(from: date))"
    }

    private func dollars(_ cents: Double, _ currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSNumber(value: cents / 100)) ?? "$\(cents / 100)"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}
