import AppKit
import SwiftUI

// Debug mode: `UsageMonitor --fetch` prints one usage snapshot and exits,
// for verifying the Keychain + API path without the UI.
if CommandLine.arguments.contains("--fetch") {
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        defer { semaphore.signal() }
        do {
            let snapshot = try await UsageClient.fetch()
            if let percent = snapshot.headlinePercent {
                print(String(format: "headline: %.1f%%", percent))
            }
            for bucket in snapshot.buckets {
                print(String(format: "%@: %.1f%%", bucket.label, bucket.utilization))
            }
            if let extra = snapshot.extraUsage {
                print(String(format: "extra usage: %.1f%% ($%.2f of $%.2f)",
                             extra.utilization, extra.usedCents / 100, extra.monthlyLimitCents / 100))
            }
        } catch {
            print("error: \(error.localizedDescription)")
        }
    }
    semaphore.wait()
    exit(0)
}

// Debug mode: `UsageMonitor --tokens` runs the transcript scan and prints
// the scoreboard numbers, for verifying the ledger without the UI.
if CommandLine.arguments.contains("--tokens") {
    guard let stats = TokenLedger.collect() else {
        print("no ~/.claude/projects directory found")
        exit(1)
    }
    let tier = TierLadder.tier(for: stats.monthTokens)
    print("month total: \(compactTokens(stats.monthTokens)) (\(stats.monthTokens) tokens)")
    print("tier: \(tier.emoji) \(tier.name)")
    print("  input: \(compactTokens(stats.monthBreakdown.input))")
    print("  output: \(compactTokens(stats.monthBreakdown.output))")
    print("  cache write: \(compactTokens(stats.monthBreakdown.cacheCreate))")
    print("  cache read: \(compactTokens(stats.monthBreakdown.cacheRead))")
    print("today: \(compactTokens(stats.todayTokens))")
    print("pace: \(compactTokens(Int64(stats.dailyPace)))/day → projected \(compactTokens(stats.projectedMonthTokens))")
    print("last month: \(compactTokens(stats.prevMonthTokens))")
    if let best = stats.bestDay {
        print("best day: \(best.dayKey) (\(compactTokens(best.total)))")
    }
    print("last 30 days:")
    for sample in stats.last30 where sample.total > 0 {
        print("  \(sample.dayKey)  \(compactTokens(sample.total))")
    }
    exit(0)
}

// Debug mode: `UsageMonitor --preview` renders the menu content views in
// a normal window for layout checks, then exits.
if CommandLine.arguments.contains("--preview") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let stats = TokenLedger.collect()
    DispatchQueue.main.async {
        let content = VStack(spacing: 0) {
            if let stats {
                TierCardView(
                    stats: stats,
                    flavor: TierLadder.tier(for: stats.monthTokens).randomFlavor())
            }
            Divider()
            BucketRowView(label: "Current session", utilization: 42.0,
                          detail: "resets today at 5:00 PM")
            BucketRowView(label: "Current week (Opus)", utilization: 87.5,
                          detail: "resets Jun 15, 3:45 PM")
            BucketRowView(label: "Promotional credits", utilization: 100.0,
                          detail: nil)
        }
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: content)
        hosting.frame.size = hosting.fittingSize
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: 200, y: 200), size: hosting.frame.size),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 8) { exit(0) }
    app.run()
}

// Debug mode: `UsageMonitor --celebrate [tierIndex]` previews the
// promotion effect (default: Agentic) and exits.
if let flagIndex = CommandLine.arguments.firstIndex(of: "--celebrate") {
    let tierIndex = CommandLine.arguments.indices.contains(flagIndex + 1)
        ? Int(CommandLine.arguments[flagIndex + 1]) ?? 4
        : 4
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    DispatchQueue.main.async {
        Celebration.show(tierIndex: tierIndex)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
        exit(0)
    }
    app.run()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menu bar only — no Dock icon, no main window.
app.setActivationPolicy(.accessory)
app.run()
