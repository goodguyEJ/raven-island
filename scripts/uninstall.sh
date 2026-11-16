#!/bin/sh
# Removes Raven Island from this Mac: its hooks in Claude Code's settings (and gives back a status
# line an older version borrowed), the "open at login" registration, the app in
# ~/Applications or /Applications, its helper folder, its preferences, and its Calendar and
# Automation permissions.
# Settings backups (~/.claude/settings.json.ravenisland-backup-*) are left for you to delete;
# they are copies of your settings from before each change.
set -eu
cd "$(dirname "$0")/.."

APP=""
for candidate in "$HOME/Applications/Raven Island.app" "/Applications/Raven Island.app" "build/Raven Island.app"; do
  if [ -d "$candidate" ]; then APP="$candidate"; break; fi
done

pkill -x "Raven Island" 2>/dev/null || true
if [ -n "$APP" ]; then "$APP/Contents/MacOS/Raven Island" --unregister-login-item 2>/dev/null || true; fi
# The app's earlier name: quit it and remove its "open at login" registration too.
pkill -x "Crow's Nest" 2>/dev/null || true
for old in "$HOME/Applications/Crow's Nest.app" "/Applications/Crow's Nest.app"; do
  if [ -d "$old" ]; then "$old/Contents/MacOS/Crow's Nest" --unregister-login-item 2>/dev/null || true; fi
done

# Remove the hooks first. Use the installed helper, or the one inside the app if that is missing.
BRIDGE="$HOME/.ravenisland/bin/ravenisland-bridge"
if [ ! -x "$BRIDGE" ] && [ -n "$APP" ]; then BRIDGE="$APP/Contents/Helpers/ravenisland-bridge"; fi
if [ -x "$BRIDGE" ]; then
  "$BRIDGE" uninstall
elif grep -q -e "/.ravenisland/bin/ravenisland-bridge" -e "/.crowsnest/bin/crowsnest-bridge" "$HOME/.claude/settings.json" 2>/dev/null; then
  echo "Can't remove the hooks: no helper found to do it. ~/.ravenisland and ~/.crowsnest were left in place." >&2
  echo "Reinstall the app, or remove the entries mentioning ravenisland-bridge or crowsnest-bridge from ~/.claude/settings.json." >&2
  exit 1
fi

for installed in "$HOME/Applications/Raven Island.app" "/Applications/Raven Island.app" "$HOME/Applications/Crow's Nest.app" "/Applications/Crow's Nest.app"; do
  if [ -d "$installed" ]; then rm -rf "$installed" 2>/dev/null || echo "Couldn't remove $installed; drag it to the Bin." >&2; fi
done
rm -rf "$HOME/.ravenisland"
defaults delete io.github.goodguyej.ravenisland 2>/dev/null || true
tccutil reset Calendar io.github.goodguyej.ravenisland >/dev/null 2>&1 || true
tccutil reset AppleEvents io.github.goodguyej.ravenisland >/dev/null 2>&1 || true
# Earlier names of the app.
rm -rf "$HOME/.crowsnest"
defaults delete io.github.goodguyej.crowsnest 2>/dev/null || true
defaults delete local.crowsnest.app 2>/dev/null || true
echo "Raven Island removed."
