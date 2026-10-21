#!/bin/bash
# uninstall.sh: stops tbfloor and removes everything install.sh created.
# Brightness writes were temporary, so macOS takes back control on its own.

LABEL="local.touchbarfloor"

if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  launchctl bootout "gui/$(id -u)/$LABEL" || true
fi
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$HOME/Library/Application Support/TouchBarFloor"
rm -f "$HOME/Library/Logs/TouchBarFloor.log"
echo "TouchBarFloor removed."
