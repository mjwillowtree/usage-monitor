import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var snapshot: UsageSnapshot?
    private var tokenStats: TokenStats?
    private var lastError: Error?
    private var refreshTimer: Timer?
    private var ledgerRunning = false
    private var titleFlashTimer: Timer?
    private var menuFlavor: String = ""

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
        menuFlavor = tokenStats.map {
            TierLadder.tier(for: $0.monthTokens).randomFlavor()
        } ?? ""
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
        refreshLedger()
    }

    /// Token counting reads hundreds of transcript files; keep it off the
    /// main thread and never overlap two scans.
    private func refreshLedger() {
        guard !ledgerRunning else { return }
        ledgerRunning = true
        Task.detached(priority: .utility) {
            let stats = TokenLedger.collect()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.ledgerRunning = false
                self.tokenStats = stats
                if self.menuFlavor.isEmpty, let stats {
                    self.menuFlavor = TierLadder.tier(for: stats.monthTokens).randomFlavor()
                }
                self.updateTitle()
                self.rebuildMenu()
                if let stats { self.checkPromotion(stats) }
            }
        }
    }

    // MARK: - Tier promotion

    /// Fire the clickover celebration once per tier per month. First scan
    /// of a month celebrates the tier you walk in holding — partly demo,
    /// partly monthly ritual.
    private func checkPromotion(_ stats: TokenStats) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let key = "celebratedTier-\(formatter.string(from: Date()))"
        let index = TierLadder.tierIndex(for: stats.monthTokens)
        let celebrated = UserDefaults.standard.object(forKey: key) as? Int ?? -1
        guard index > celebrated else { return }
        UserDefaults.standard.set(index, forKey: key)
        guard index > 0 else { return }
        Celebration.show(tierIndex: index)
        flashTitle(TierLadder.tiers[index])
    }

    private func flashTitle(_ tier: Tier) {
        titleFlashTimer?.invalidate()
        statusItem.button?.title = "🍌 \(tier.name.uppercased()) \(tier.emoji)"
        titleFlashTimer = Timer.scheduledTimer(
            withTimeInterval: 6, repeats: false
        ) { [weak self] _ in
            Task { @MainActor in self?.updateTitle() }
        }
    }

    // MARK: - Menu bar title

    private func updateTitle() {
        guard let button = statusItem.button else { return }
        if titleFlashTimer?.isValid == true { return }
        var parts: [String] = []
        if let percent = snapshot?.headlinePercent {
            parts.append("\(Int(percent.rounded()))%")
        } else if lastError != nil {
            parts.append("!")
        }
        if let stats = tokenStats {
            parts.append(compactTokens(stats.monthTokens))
        }
        button.title = parts.isEmpty ? "✳ …" : "✳ " + parts.joined(separator: " · ")
    }

    // MARK: - Menu construction

    private func rebuildMenu() {
        menu.removeAllItems()

        if let stats = tokenStats {
            menu.addItem(hostedItem(TierCardView(stats: stats, flavor: menuFlavor)))
        } else {
            menu.addItem(disabledItem("Counting tokens… (first scan takes a moment)"))
        }
        menu.addItem(.separator())

        menu.addItem(header("Rate Limits"))
        if let snapshot {
            for bucket in snapshot.buckets {
                menu.addItem(hostedItem(BucketRowView(
                    label: bucket.label,
                    utilization: bucket.utilization,
                    detail: resetText(bucket.resetsAt)
                )))
            }
            if let extra = snapshot.extraUsage, extra.isEnabled {
                menu.addItem(hostedItem(BucketRowView(
                    label: "Extra usage (this month)",
                    utilization: extra.utilization,
                    detail: "\(dollars(extra.usedCents, extra.currency)) of \(dollars(extra.monthlyLimitCents, extra.currency))"
                )))
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

    private func hostedItem<V: View>(_ view: V) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false
        let hosting = NSHostingView(rootView: view)
        hosting.frame.size = hosting.fittingSize
        item.view = hosting
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
