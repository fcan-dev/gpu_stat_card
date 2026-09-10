#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="GPUStatCard"
DIST="dist/$APP_NAME.app"
CONTENTS="$DIST/Contents"

rm -rf "$DIST"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"
cp "$BIN_PATH" "$CONTENTS/MacOS/$APP_NAME"
cp packaging/Info.plist "$CONTENTS/Info.plist"

# Ad-hoc sign so it launches cleanly locally (no Gatekeeper prompt).
codesign --force --sign - "$DIST"

echo "Built $DIST"
