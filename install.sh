#!/bin/bash
# install.sh: builds tbfloor and starts it in the background at every login.
#
#   bash install.sh                 build, then install with floor 1.0 (maximum)
#   bash install.sh 0.6             build, then install with a floor of 0.6
#   bash install.sh --build-only    only build (to test first with: tbfloor status / set)
#
# No sudo needed. Remove everything with: bash uninstall.sh

set -e
cd "$(dirname "$0")"

LABEL="local.touchbarfloor"
DEST_DIR="$HOME/Library/Application Support/TouchBarFloor"
BIN="$DEST_DIR/tbfloor"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/TouchBarFloor.log"

BUILD_ONLY=0
FLOOR="1.0"
if [ "$1" = "--build-only" ]; then
  BUILD_ONLY=1
elif [ -n "$1" ]; then
  FLOOR="$1"
fi

if ! command -v clang >/dev/null 2>&1; then
  echo "clang not found. Install Xcode Command Line Tools with: xcode-select --install"
  exit 1
fi

echo "Building..."
mkdir -p "$DEST_DIR"
clang -fobjc-arc -Wall -Wextra -framework Foundation -framework IOKit tbfloor.m -o "$BIN"
codesign --force --sign - "$BIN"
echo "Built: $BIN"
echo
echo "Current Touch Bar status:"
"$BIN" status || true
echo

if [ "$BUILD_ONLY" = "1" ]; then
  echo "Build only. Test it with:"
  echo "  \"$BIN\" set 1.0"
  echo "  \"$BIN\" status"
  exit 0
fi

# Check the floor value before installing
if ! echo "$FLOOR" | grep -Eq '^(0(\.[0-9]+)?|1(\.0+)?)$'; then
  echo "Invalid floor value: $FLOOR (use a number from 0.0 to 1.0, like 0.6)"
  exit 1
fi

# Stop a previous copy if one is running
if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  launchctl bootout "gui/$(id -u)/$LABEL" || true
fi

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN</string>
        <string>run</string>
        <string>$FLOOR</string>
        <string>0.5</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardOutPath</key>
    <string>$LOG</string>
    <key>StandardErrorPath</key>
    <string>$LOG</string>
</dict>
</plist>
PLISTEOF

launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed and running with floor $FLOOR."
echo "Log: $LOG"
echo "Remove with: bash uninstall.sh"
