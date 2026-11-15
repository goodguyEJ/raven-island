#!/bin/sh
# Builds Crow's Nest and copies it to ~/Applications so it has a permanent home
# (needed for "Open Crow's Nest when I log in" to keep working).
set -eu
cd "$(dirname "$0")/.."
./scripts/build-app.sh
mkdir -p "$HOME/Applications"
pkill -x "Crow's Nest" 2>/dev/null || true
rm -rf "$HOME/Applications/Crow's Nest.app"
cp -R "build/Crow's Nest.app" "$HOME/Applications/Crow's Nest.app"
"$HOME/Applications/Crow's Nest.app/Contents/Helpers/crowsnest-bridge" install
open "$HOME/Applications/Crow's Nest.app"
echo "Installed to ~/Applications/Crow's Nest.app"
