#!/bin/sh
# Removes Crow's Nest from this Mac: its hooks and status line entry in Claude Code's settings
# (restoring your previous status line), the "open at login" registration, the app in
# ~/Applications or /Applications, its helper folder, and its preferences.
# Settings backups (~/.claude/settings.json.crowsnest-backup-*) are left for you to delete;
# they are copies of your settings from before each change.
set -eu
cd "$(dirname "$0")/.."

APP=""
for candidate in "$HOME/Applications/Crow's Nest.app" "/Applications/Crow's Nest.app" "build/Crow's Nest.app"; do
  if [ -d "$candidate" ]; then APP="$candidate"; break; fi
done

pkill -x "Crow's Nest" 2>/dev/null || true
if [ -n "$APP" ]; then "$APP/Contents/MacOS/Crow's Nest" --unregister-login-item 2>/dev/null || true; fi

# Remove the hooks first. Use the installed helper, or the one inside the app if that is missing.
BRIDGE="$HOME/.crowsnest/bin/crowsnest-bridge"
if [ ! -x "$BRIDGE" ] && [ -n "$APP" ]; then BRIDGE="$APP/Contents/Helpers/crowsnest-bridge"; fi
if [ -x "$BRIDGE" ]; then
  "$BRIDGE" uninstall
elif grep -q "/.crowsnest/bin/crowsnest-bridge" "$HOME/.claude/settings.json" 2>/dev/null; then
  echo "Can't remove the hooks: no helper found to do it. ~/.crowsnest was left in place." >&2
  echo "Reinstall the app, or remove the entries mentioning crowsnest-bridge from ~/.claude/settings.json." >&2
  exit 1
fi

for installed in "$HOME/Applications/Crow's Nest.app" "/Applications/Crow's Nest.app"; do
  if [ -d "$installed" ]; then rm -rf "$installed" 2>/dev/null || echo "Couldn't remove $installed; drag it to the Bin." >&2; fi
done
rm -rf "$HOME/.crowsnest"
defaults delete io.github.goodguyej.crowsnest 2>/dev/null || true
defaults delete local.crowsnest.app 2>/dev/null || true
echo "Crow's Nest removed."
