#!/bin/bash
# Builds "build/Copy That.app". Pass --install to copy it to /Applications, --run to launch it.
# Set UNIVERSAL=1 to build for both Apple Silicon and Intel Macs (used for releases).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Copy That.app"

VERSION="$(cat VERSION)"
if [ "${UNIVERSAL:-0}" = "1" ]; then
    swift build -c release --arch arm64 --arch x86_64
else
    swift build -c release
fi
BIN="$(swift build -c release ${UNIVERSAL:+--arch arm64 --arch x86_64} --show-bin-path)"

if [ ! -f Resources/AppIcon.icns ]; then
    TMP="$(mktemp -d)"
    swift scripts/make-icon.swift "$TMP/icon.png"
    mkdir "$TMP/AppIcon.iconset"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
        sips -z $((s * 2)) $((s * 2)) "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
    rm -rf "$TMP"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/PastePlus" "$APP/Contents/MacOS/PastePlus"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%Y%m%d%H%M%S)" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
# An ad-hoc signature is normally identified by its hash, which changes with every build, so macOS
# would forget the Accessibility permission after each rebuild or update. Naming the app by its
# identifier instead keeps the permission. PASTEPLUS_SIGN_IDENTITY="Apple Development: ..." signs
# with a real certificate, which needs no such rule.
if [ -n "${PASTEPLUS_SIGN_IDENTITY:-}" ]; then
    codesign --force --sign "$PASTEPLUS_SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - --requirements '=designated => identifier "local.pasteplus"' "$APP"
fi
echo "Built $APP"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
for arg in "$@"; do
    case "$arg" in
        --install)
            pkill -x PastePlus 2>/dev/null || true
            # Wait for the old copy to quit, otherwise the relaunch below can fail.
            for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x PastePlus >/dev/null || break; /bin/sleep 0.3; done
            rm -rf "/Applications/Copy That.app"
            # The app used to be called Paste Plus: remove that copy so only one is left.
            if [ -d "/Applications/Paste Plus.app" ]; then
                "$LSREGISTER" -u "/Applications/Paste Plus.app" >/dev/null 2>&1 || true
                rm -rf "/Applications/Paste Plus.app"
            fi
            cp -R "$APP" "/Applications/Copy That.app"
            # Keep one copy only, so Spotlight never opens a stale one from the build folder.
            "$LSREGISTER" -u "$PWD/$APP" >/dev/null 2>&1 || true
            rm -rf "$APP"
            APP="/Applications/Copy That.app"
            "$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true
            echo "Installed $APP"
            ;;
        --run) open "$APP" || { /bin/sleep 2; open "$APP"; } ;;
    esac
done
