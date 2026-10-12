#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPOSITORY="Italian-seasoning/Capturely"
SPARKLE_BIN="${SPARKLE_BIN_OVERRIDE:-$ROOT/dist/XcodeDerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin}"
"$ROOT/script/build_and_run.sh" --verify
APP="$ROOT/dist/Capturely.app"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
RELEASE_DIR="$ROOT/dist/releases/$VERSION"
ARCHIVE="Capturely-$VERSION-macOS.zip"
mkdir -p "$RELEASE_DIR"
strip -S "$APP/Contents/MacOS/Capturely"
codesign --force --sign "${CAPTURELY_CODE_SIGN_IDENTITY:-Capturely Local Development}" --entitlements "$ROOT/dist/Capturely.entitlements" "$APP"
ditto -c -k --norsrc --keepParent "$APP" "$RELEASE_DIR/$ARCHIVE"
"$SPARKLE_BIN/generate_appcast" --account Capturely --download-url-prefix "https://github.com/$REPOSITORY/releases/download/v$VERSION/" --maximum-versions 1 --maximum-deltas 0 "$RELEASE_DIR"
python3 "$ROOT/script/verify_update.py" "$APP" "$RELEASE_DIR/$ARCHIVE" "$RELEASE_DIR/appcast.xml" --sparkle-bin "$SPARKLE_BIN" --account Capturely --repository "$REPOSITORY" --require-newer
cp "$RELEASE_DIR/appcast.xml" "$ROOT/appcast.xml"
echo "Verified release ready: $RELEASE_DIR"
