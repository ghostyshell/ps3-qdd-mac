#!/bin/sh
# Builds PS3QDD.app from source and opens it.
#
#   ./run.sh              build the app bundle and launch it
#   ./run.sh --decrypt <input.iso> <keys> <output-dir>
#                         run headlessly, without opening a window (still builds first)
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

APP="$ROOT/PS3QDD.app"
BUNDLE_ID="link.game-debrid.ps3qdd"
VERSION="1.0"

die() {
    printf 'run.sh: %s\n' "$*" >&2
    exit 1
}

command -v swift >/dev/null 2>&1 || die "swift not found; install the Xcode Command Line Tools"

printf 'Building...\n'
swift build -c release || die "build failed"

BIN="$(swift build -c release --show-bin-path)/PS3QDD"
[ -x "$BIN" ] || die "no executable at $BIN"

if [ "${1:-}" = "--decrypt" ]; then
    exec "$BIN" "$@"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PS3QDD"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>PS3 Quick Disc Decryptor</string>
	<key>CFBundleDisplayName</key><string>PS3 Quick Disc Decryptor</string>
	<key>CFBundleExecutable</key><string>PS3QDD</string>
	<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>$VERSION</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint "$APP/Contents/Info.plist" >/dev/null || die "generated Info.plist is malformed"

# On Apple Silicon, a bundle whose signature does not match its contents is killed at
# launch, so sign after assembling rather than relying on the linker's signature.
codesign --force --sign - "$APP" >/dev/null 2>&1 \
    || printf 'warning: ad-hoc signing failed; the app may not launch\n' >&2

printf 'Built %s\n' "$APP"
open "$APP"
