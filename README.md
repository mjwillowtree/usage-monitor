# Claude Usage Monitor

macOS menu bar app that shows your current-month Claude usage as a percent,
with a click-down breakdown like Claude Code's `/usage` screen.

- **Menu bar**: `✳ 12%` — monthly extra-usage utilization (falls back to the
  most-constrained rate-limit bucket if extra usage isn't enabled).
- **Click**: every limit bucket the API reports — session, weekly,
  promotional credits, extra usage in dollars — each with a colored progress
  bar (green / orange ≥80% / red ≥95%) and reset time.
- Refreshes every 5 minutes, on menu open, and via Refresh Now (⌘R).

## How it works

Reads the OAuth access token Claude Code keeps in the login Keychain
(service `Claude Code-credentials`) and calls the same endpoint `/usage`
uses: `GET https://api.anthropic.com/api/oauth/usage` with the
`anthropic-beta: oauth-2025-04-20` header. The token never leaves the
machine and is never written anywhere. Claude Code owns token refresh — if
the token has expired, the menu says so; opening Claude Code fixes it.

Buckets are discovered dynamically (any response object with a
`utilization` field), so new limit types show up without code changes.

## Build & run

```sh
./build-app.sh            # builds dist/UsageMonitor.app
./build-app.sh install    # also copies to /Applications and launches
```

Requires Xcode command line tools (Swift 5.9+). No dependencies.

**Start at login**: System Settings → General → Login Items → add
UsageMonitor.

**Keychain prompt**: first launch may ask for access to "Claude
Code-credentials" — click **Always Allow**. The app is ad-hoc signed, so a
rebuild produces a new signature and macOS may ask again after rebuilding.

## Debugging

```sh
./dist/UsageMonitor.app/Contents/MacOS/UsageMonitor --fetch
```

prints one snapshot to stdout and exits.
