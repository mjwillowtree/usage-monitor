import AppKit

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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menu bar only — no Dock icon, no main window.
app.setActivationPolicy(.accessory)
app.run()
