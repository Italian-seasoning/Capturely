#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Capturely"
BUNDLE_ID="com.italianseasoning.capturely"
VERSION="${CAPTURELY_VERSION:-0.1.3}"
VERSION="${VERSION#v}"
DIST_DIR="$ROOT/dist"
DIST_APP_DIR="$DIST_DIR/$APP_NAME.app"
# File Provider can restore Finder metadata while bundles in Documents are signed.
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/capturely.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
APP_DIR="$STAGING_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
ENTITLEMENTS_FILE="$DIST_DIR/$APP_NAME.entitlements"
XCODE_WORKSPACE="$ROOT/.swiftpm/xcode/package.xcworkspace"
DERIVED_DATA_DIR="$DIST_DIR/XcodeDerivedData"
XCODE_PRODUCT="$DERIVED_DATA_DIR/Build/Products/Release/$APP_NAME"

sign_app_bundle() {
  xattr -cr "$APP_DIR"
  # Keep the certificate associated with the existing Screen Recording approval.
  # Never switch identity just because another certificate is installed.
  local requested_identity="${CAPTURELY_CODE_SIGN_IDENTITY:-Capturely Local Development}"
  local signing_identity="$requested_identity"

  if [[ -z "$signing_identity" || "$signing_identity" == "-" || "$signing_identity" == "adhoc" ]]; then
    codesign --force --deep --sign - "$FRAMEWORKS_DIR/Sparkle.framework"
    codesign --force --sign - --entitlements "$ENTITLEMENTS_FILE" "$APP_DIR"
    cat <<'WARNING'
warning: Capturely was ad-hoc signed because no certificate-backed code signing identity was found.
warning: macOS may ask for Screen Recording permission again after code changes.
warning: Install an Apple Development/local code signing identity, or set CAPTURELY_CODE_SIGN_IDENTITY, for stable TCC permissions.
WARNING
    return
  fi

  local runtime_options=()
  if [[ "$signing_identity" == "Developer ID Application"* ]]; then
    runtime_options=(--options runtime)
  fi
  codesign --force --deep "${runtime_options[@]}" --sign "$signing_identity" "$FRAMEWORKS_DIR/Sparkle.framework"
  codesign --force "${runtime_options[@]}" --sign "$signing_identity" --entitlements "$ENTITLEMENTS_FILE" "$APP_DIR"
  echo "Signed $APP_DIR with $signing_identity"
}

cd "$ROOT"
if [[ ! -f "$XCODE_WORKSPACE/contents.xcworkspacedata" ]]; then
  mkdir -p "$XCODE_WORKSPACE"
  cat > "$XCODE_WORKSPACE/contents.xcworkspacedata" <<'WORKSPACE'
<?xml version="1.0" encoding="UTF-8"?>
<Workspace version="1.0"><FileRef location="self:"></FileRef></Workspace>
WORKSPACE
fi
xcodebuild \
  -workspace "$XCODE_WORKSPACE" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  ENABLE_CODE_COVERAGE=NO \
  build

test -x "$XCODE_PRODUCT"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"
cp "$XCODE_PRODUCT" "$MACOS_DIR/$APP_NAME"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME"
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
  <string>${CAPTURELY_BUILD_NUMBER:-2026101201}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
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
codesign --verify --strict --deep "$APP_DIR"
rm -rf "$DIST_APP_DIR"
ditto --norsrc --noextattr "$APP_DIR" "$DIST_APP_DIR"
# Keep verified staging authoritative; File Provider may re-stamp the Documents copy.

if [[ "${1:-}" == "--verify" ]]; then
  otool -l "$MACOS_DIR/$APP_NAME" | grep -q "@executable_path/../Frameworks"
  test -x "$MACOS_DIR/$APP_NAME"
  plutil -lint "$CONTENTS_DIR/Info.plist"
  codesign -dvv "$APP_DIR" 2>&1 | grep -E "Identifier=|Authority=|Signature="
  echo "Verified signed staging build; copied to $DIST_APP_DIR"
  exit 0
fi

# Keep runtime permission approval attached to one installed path across worktrees.
INSTALLED_APP="/Applications/$APP_NAME.app"
INSTALL_STAGING_DIR="$(mktemp -d "/Applications/.Capturely-install.XXXXXX")"
INSTALL_CANDIDATE="$INSTALL_STAGING_DIR/$APP_NAME.app"
INSTALL_BACKUP="$INSTALL_STAGING_DIR/previous.app"
INSTALL_COMMITTED=0
cleanup_install() {
  local rollback_failed=0
  if [[ "$INSTALL_COMMITTED" == 0 && ( -e "$INSTALL_BACKUP" || -L "$INSTALL_BACKUP" ) ]]; then
    if [[ -e "$INSTALLED_APP" || -L "$INSTALLED_APP" ]]; then
      mv "$INSTALLED_APP" "$INSTALL_STAGING_DIR/uncommitted.app" || rollback_failed=1
    fi
    if (( rollback_failed == 0 )); then
      mv "$INSTALL_BACKUP" "$INSTALLED_APP" || rollback_failed=1
    fi
    if (( rollback_failed )); then
      print -u2 "Rollback could not finish; previous app retained at $INSTALL_BACKUP"
      rm -rf "$STAGING_DIR"
      return 1
    fi
  fi
  rm -rf "$INSTALL_STAGING_DIR" "$STAGING_DIR"
}
trap cleanup_install EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
ditto --norsrc --noextattr "$APP_DIR" "$INSTALL_CANDIDATE" || exit 1
codesign --verify --strict --deep "$INSTALL_CANDIDATE" || exit 1
pkill -x "$APP_NAME" 2>/dev/null || true
if [[ -e "$INSTALLED_APP" || -L "$INSTALLED_APP" ]]; then
  mv "$INSTALLED_APP" "$INSTALL_BACKUP" || exit 1
fi
mv "$INSTALL_CANDIDATE" "$INSTALLED_APP" || exit 1
codesign --verify --strict --deep "$INSTALLED_APP" || exit 1
INSTALL_COMMITTED=1
open -n "$INSTALLED_APP"
