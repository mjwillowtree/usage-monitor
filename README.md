# Claude Usage Monitor

macOS menu bar app that shows your current-month Claude usage — rate
limits, dollars, and most importantly your **token scoreboard tier**.

- **Menu bar**: `✳ 14% · 919.8M` — extra-usage percent plus this month's
  token total (the number that matters).
- **Click**: the scoreboard card — current tier, progress to the next
  rung, burn rate and projected month-end tier, a 30-day sparkline, token
  composition (spoiler: it's cache reads), and every rate-limit bucket
  with a pill progress bar (green / orange ≥80% / red ≥95% with glow).
- **Clickover**: crossing a tier floor rains full-screen confetti and
  bananas with a promotion card. Once per tier per month. Non-negotiable.
- Refreshes every 5 minutes, on menu open, and via Refresh Now (⌘R).

## The tiers

| Floor | Tier |
|---|---|
| 0 | 🚶 Token Tourist |
| 1M | 👀 AI Curious |
| 10M | 🌱 AI Adopter |
| 100M | 🔌 Deeply Connected |
| 1B | 🤖 Agentic |
| 10B | 🌌 Post-Scarcity |

The middle three match the company scoreboard; the rest are extrapolated
with confidence. All four token categories count — input, output, cache
write, cache read. Tokens are tokens.

## How it works

**Rate limits & dollars**: reads the OAuth access token Claude Code keeps
in the login Keychain (service `Claude Code-credentials`) and calls the
same endpoint `/usage` uses: `GET https://api.anthropic.com/api/oauth/usage`
with the `anthropic-beta: oauth-2025-04-20` header. The token never
leaves the machine. Claude Code owns token refresh — if the token has
expired, the menu says so; opening Claude Code fixes it. Buckets are
discovered dynamically (any response object with a `utilization` field),
so new limit types show up without code changes.

**Token counts**: parsed from Claude Code's local transcripts
(`~/.claude/projects/**/*.jsonl`), which record per-message usage. Files
are cached by size + mtime in
`~/Library/Application Support/UsageMonitor/token-ledger.json`, so the
first scan takes ~15s and later scans take ~0.5s. Messages are deduped on
`message.id + requestId` since resumed sessions duplicate history. Note
this only sees Claude Code usage on this machine — claude.ai web tokens
go uncounted (a known injustice).

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
BIN=./dist/UsageMonitor.app/Contents/MacOS/UsageMonitor
$BIN --fetch          # one API snapshot to stdout
$BIN --tokens         # scoreboard numbers from the transcript ledger
$BIN --celebrate 4    # preview the Agentic promotion effect
$BIN --preview        # render the menu content in a window
```
