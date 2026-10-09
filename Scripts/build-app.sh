#!/bin/bash
#
# Assembles build/Code Editor.app from the SwiftPM release binary.
#
#   Scripts/build-app.sh [--debug] [--install] [--open]
#
# SwiftPM produces a bare Mach-O executable. macOS needs the bundle layout —
# Info.plist plus Contents/MacOS — before it will give the process a Dock tile,
# a menu bar and a document-based open-panel identity. This script builds the
# release binary, lays out the bundle, copies in every SwiftPM resource bundle
# (CodeEditLanguages grammars, CodeEditSymbols assets) and ad-hoc signs the
# result so it launches without a Gatekeeper prompt.
#
# Ad-hoc signing is enough for local use and for handing the bundle to another
# Mac. For distribution beyond the machine that built it, replace the signing
# identity with a Developer ID and notarize the zipped bundle.
set -euo pipefail

CONFIGURATION="release"
INSTALL=0
LAUNCH=0

for argument in "$@"; do
    case "$argument" in
        --debug) CONFIGURATION="debug" ;;
        --install) INSTALL=1 ;;
        --open) LAUNCH=1 ;;
        *) echo "unknown option: $argument" >&2; exit 2 ;;
    esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Code Editor"
BUNDLE_ID="com.yan123tech.codeeditor"
DESTINATION="$ROOT/build/$APP_NAME.app"
CONTENTS="$DESTINATION/Contents"
EXECUTABLE="CodeEditorApp"

cd "$ROOT"

echo "==> Building $EXECUTABLE ($CONFIGURATION)"
swift build -c "$CONFIGURATION" --product "$EXECUTABLE" --show-bin-path > /dev/null
BIN_PATH="$(swift build -c "$CONFIGURATION" --product "$EXECUTABLE" --show-bin-path)"

echo "==> Laying out $DESTINATION"
rm -rf "$DESTINATION"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

install -m 755 "$BIN_PATH/$EXECUTABLE" "$CONTENTS/MacOS/$EXECUTABLE"
install -m 644 "$ROOT/Resources/App-Info.plist" "$CONTENTS/Info.plist"

# SwiftPM writes resource bundles next to the binary and Bundle.module looks
# them up under Bundle.main.resourceURL, which is Contents/Resources here.
shopt -s nullglob
for bundle in "$BIN_PATH"/*.bundle; do
    echo "==> Embedding $(basename "$bundle")"
    cp -R "$bundle" "$CONTENTS/Resources/"
done
shopt -u nullglob

echo "==> Rendering icon"
TEMP_DIR="$(mktemp -d -t code-editor-app)"
trap 'rm -rf "$TEMP_DIR"' EXIT
ICON_PNG="$TEMP_DIR/AppIcon.png"
ICONSET="$TEMP_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"

swift "$ROOT/Scripts/make-icon.swift" "$ICON_PNG"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}.png" > /dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"

echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$DESTINATION"
codesign --verify --verbose=2 "$DESTINATION"

# LaunchServices caches the bundle identity, so a rebuild can keep showing the
# previous icon or menu-bar name until this runs.
touch "$DESTINATION"

echo "==> Built $DESTINATION"
if [[ "$INSTALL" == "1" ]]; then
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$DESTINATION" /Applications/
    echo "==> Installed /Applications/$APP_NAME.app"
    DESTINATION="/Applications/$APP_NAME.app"
fi

if [[ "$LAUNCH" == "1" ]]; then
    open "$DESTINATION"
fi

plutil -p "$CONTENTS/Info.plist" | grep -E "CFBundleIdentifier|CFBundleShortVersionString|CFBundleExecutable"
du -sh "$DESTINATION"
