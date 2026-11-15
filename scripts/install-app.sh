#!/bin/sh
# Builds Raven Island and copies it to ~/Applications so it has a permanent home
# (needed for "Open Raven Island when I log in" to keep working).
set -eu
cd "$(dirname "$0")/.."
./scripts/build-app.sh
mkdir -p "$HOME/Applications"
pkill -x "Raven Island" 2>/dev/null || true
rm -rf "$HOME/Applications/Raven Island.app"
cp -R "build/Raven Island.app" "$HOME/Applications/Raven Island.app"
"$HOME/Applications/Raven Island.app/Contents/Helpers/ravenisland-bridge" install
open "$HOME/Applications/Raven Island.app"
echo "Installed to ~/Applications/Raven Island.app"
