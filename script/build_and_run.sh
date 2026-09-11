#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Capturely"
BUNDLE_ID="com.italianseasoning.capturely"
VERSION="${CAPTURELY_VERSION:-0.1.0}"
VERSION="${VERSION#v}"
DIST_DIR="$ROOT/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
ENTITLEMENTS_FILE="$DIST_DIR/$APP_NAME.entitlements"
XCODE_WORKSPACE="$ROOT/.swiftpm/xcode/package.xcworkspace"
DERIVED_DATA_DIR="$DIST_DIR/XcodeDerivedData"
XCODE_PRODUCT="$DERIVED_DATA_DIR/Build/Products/Release/$APP_NAME"

sign_app_bundle() {
  # Keep the certificate associated with the existing Screen Recording approval.
  # Never switch identity just because another certificate is installed.
  local requested_identity="${CAPTURELY_CODE_SIGN_IDENTITY:-Capturely Local Development}"
  local signing_identity="$requested_identity"

  if [[ -z "$signing_identity" || "$signing_identity" == "-" || "$signing_identity" == "adhoc" ]]; then
    codesign --force --deep --sign - --entitlements "$ENTITLEMENTS_FILE" "$APP_DIR"
    cat <<'WARNING'
warning: Capturely was ad-hoc signed because no certificate-backed code signing identity was found.
warning: macOS may ask for Screen Recording permission again after code changes.
warning: Install an Apple Development/local code signing identity, or set CAPTURELY_CODE_SIGN_IDENTITY, for stable TCC permissions.
WARNING
    return
  fi

  codesign --force --deep --options runtime --sign "$signing_identity" --entitlements "$ENTITLEMENTS_FILE" "$APP_DIR"
  echo "Signed $APP_DIR with $signing_identity"
}

cd "$ROOT"
xcodebuild \
  -workspace "$XCODE_WORKSPACE" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build

test -x "$XCODE_PRODUCT"

pkill -x "$APP_NAME" 2>/dev/null || true
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"
cp "$XCODE_PRODUCT" "$MACOS_DIR/$APP_NAME"
cp "$ROOT/Assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

SPARKLE_FRAMEWORK="$(find "$DERIVED_DATA_DIR/Build/Products/Release" -name Sparkle.framework -type d -print -quit)"
test -n "$SPARKLE_FRAMEWORK"
cp -R "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Capturely</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>Capturely</string>
  <key>CFBundleDisplayName</key>
  <string>Capturely</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>${CAPTURELY_BUILD_NUMBER:-1}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>SUFeedURL</key>
  <string>https://raw.githubusercontent.com/Italian-seasoning/Capturely/main/appcast.xml</string>
  <key>SUPublicEDKey</key>
  <string>LXzdQ7YZl2J2rc7b3KI9UGcZjR4Z3OFLndxdMJOYvVE=</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Capturely can record microphone audio when you include your mic in clips.</string>
  <key>NSScreenCaptureUsageDescription</key>
  <string>Capturely records configured game windows so you can save replay clips.</string>
</dict>
</plist>
PLIST

cat > "$ENTITLEMENTS_FILE" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.get-task-allow</key>
  <true/>
</dict>
</plist>
PLIST

sign_app_bundle

if [[ "${1:-}" == "--verify" ]]; then
  test -x "$MACOS_DIR/$APP_NAME"
  plutil -lint "$CONTENTS_DIR/Info.plist"
  codesign --verify --strict --deep "$APP_DIR"
  codesign -dvv "$APP_DIR" 2>&1 | grep -E "Identifier=|Authority=|Signature="
  echo "Verified $APP_DIR"
  exit 0
fi

open -n "$APP_DIR"
