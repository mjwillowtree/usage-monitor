#!/bin/zsh
# Builds UsageMonitor.app into ./dist and (optionally) installs it.
#   ./build-app.sh            build only
#   ./build-app.sh install    build + copy to /Applications + launch
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=dist/UsageMonitor.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp .build/release/UsageMonitor "$APP/Contents/MacOS/UsageMonitor"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>UsageMonitor</string>
    <key>CFBundleIdentifier</key><string>com.michaelchapman.claude-usage-monitor</string>
    <key>CFBundleName</key><string>Usage Monitor</string>
    <key>CFBundleDisplayName</key><string>Claude Usage Monitor</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string></string>
</dict>
</plist>
PLIST

# Prefer a locally-generated code-signing certificate ("UsageMonitor Local
# Signing", see README) over ad-hoc (`--sign -`). Ad-hoc identities are keyed
# to the exact binary hash, so macOS Keychain ACL's "Always Allow" grant
# doesn't survive a rebuild; a real certificate keeps the same identity across
# rebuilds, so the grant actually sticks. The certificate is optional: without
# it the build still works, you just re-approve the Keychain prompt after a
# rebuild.
IDENTITY="UsageMonitor Local Signing"
if ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "note: no \"$IDENTITY\" certificate found — signing ad-hoc instead."
    IDENTITY="-"
fi
codesign --force --sign "$IDENTITY" "$APP"

echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
    osascript -e 'quit app "Usage Monitor"' 2>/dev/null || true
    rm -rf "/Applications/UsageMonitor.app"
    cp -R "$APP" /Applications/
    open /Applications/UsageMonitor.app
    echo "Installed and launched /Applications/UsageMonitor.app"
    echo "To start it at login: System Settings → General → Login Items → add UsageMonitor."
fi
