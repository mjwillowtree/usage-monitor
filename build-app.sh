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

# Ad-hoc signature gives the app a stable identity so the Keychain
# "Always Allow" choice sticks across rebuilds of the same source.
codesign --force --sign - "$APP"

echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
    osascript -e 'quit app "Usage Monitor"' 2>/dev/null || true
    rm -rf "/Applications/UsageMonitor.app"
    cp -R "$APP" /Applications/
    open /Applications/UsageMonitor.app
    echo "Installed and launched /Applications/UsageMonitor.app"
    echo "To start it at login: System Settings → General → Login Items → add UsageMonitor."
fi
