#!/bin/sh
# Rebuild, stop any running instance, and launch.
set -eu
cd "$(dirname "$0")/.."
./scripts/build-app.sh
pkill -x "Raven Island" 2>/dev/null || true
open "build/Raven Island.app"
