#!/bin/bash
set -euo pipefail

# Prato local packaging — ad-hoc signed .app + .dmg for manual distribution.
# Does not use Developer ID, notarization, or Palmier provisioning.
# Official Palmier release pipeline: scripts/bundle.sh
#
# Usage:
#   scripts/prato-pack.sh [release|debug]     # build .app + .dmg (default: release)
#   scripts/prato-pack.sh debug --fast        # build .app only (daily dev)

CONFIG="release"
BUILD_DMG=true
for arg in "$@"; do
  case "$arg" in
    release|debug) CONFIG="$arg" ;;
    --fast)        BUILD_DMG=false ;;
    *) echo "unknown arg: $arg" >&2; exit 1 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

ENV_FILE=".env"
if [ "$CONFIG" = "release" ] && [ -f "$ROOT/.env.prod" ]; then
  ENV_FILE=".env.prod"
fi
if [ -f "$ROOT/$ENV_FILE" ]; then
  echo "==> Loading $ENV_FILE"
  set -a
  # shellcheck disable=SC1091
  . "$ROOT/$ENV_FILE"
  set +a
fi

RESOURCES="$ROOT/Sources/PalmierPro/Resources"
APP="$ROOT/.build/Prato.app"
DMG="$ROOT/.build/Prato.dmg"
SPM_BUNDLE="PalmierPro_PalmierPro.bundle"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/PalmierPro"
SPARKLE_FW="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/PalmierPro"
cp "$RESOURCES/Info.plist" "$APP/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Prato" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Prato" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUEnableAutomaticChecks false" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$APP/Contents/Info.plist" 2>/dev/null || true

if [ -n "${SENTRY_DSN:-}" ]; then
  echo "==> Injecting SentryDSN into Info.plist"
  /usr/libexec/PlistBuddy -c "Delete :SentryDSN" "$APP/Contents/Info.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :SentryDSN string $SENTRY_DSN" "$APP/Contents/Info.plist"
fi

inject_plist() {
  local key="$1" value="$2"
  if [ -z "$value" ]; then
    echo "!! $key not set in $ENV_FILE — account features may be unavailable" >&2
    return
  fi
  /usr/libexec/PlistBuddy -c "Delete :$key" "$APP/Contents/Info.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :$key string $value" "$APP/Contents/Info.plist"
}

echo "==> Injecting Prato backend config into Info.plist"
inject_plist PratoClerkPublishableKey "${CLERK_PUBLISHABLE_KEY:-}"
inject_plist PratoConvexDeploymentURL "${CONVEX_DEPLOYMENT_URL:-}"
inject_plist PratoConvexHttpURL "${CONVEX_HTTP_URL:-}"

cp "$RESOURCES/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"

RES_BUNDLE="$(dirname "$BIN")/$SPM_BUNDLE"
if [ -d "$RES_BUNDLE/Fonts" ]; then
  cp -R "$RES_BUNDLE/Fonts" "$APP/Contents/Resources/"
else
  echo "!! missing Fonts/ in SwiftPM resource bundle at $RES_BUNDLE" >&2
  exit 1
fi
if [ -f "$RES_BUNDLE/palmier-pro.mcpb" ]; then
  cp "$RES_BUNDLE/palmier-pro.mcpb" "$APP/Contents/Resources/"
else
  echo "!! missing palmier-pro.mcpb in SwiftPM resource bundle at $RES_BUNDLE" >&2
  exit 1
fi
if [ -d "$RES_BUNDLE/Images" ]; then
  cp -R "$RES_BUNDLE/Images" "$APP/Contents/Resources/"
fi
if [ -d "$RES_BUNDLE/Changelog" ]; then
  cp -R "$RES_BUNDLE/Changelog" "$APP/Contents/Resources/"
fi

install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/PalmierPro"
touch "$APP"

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP"
codesign --verify --strict --verbose=2 "$APP"

if ! $BUILD_DMG; then
  echo "==> Done: $APP"
  exit 0
fi

echo "==> Building DMG"
rm -f "$DMG"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/Prato.app"
ln -s /Applications "$STAGING/Applications"
cp "$RESOURCES/AppIcon.icns" "$STAGING/.VolumeIcon.icns"
hdiutil create \
  -volname "Prato" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG"
rm -rf "$STAGING"

echo ""
echo "==> Done"
echo "   App: $APP"
echo "   DMG: $DMG"
echo ""
echo "Install on another Mac:"
echo "  1. Open the DMG and drag Prato to Applications"
echo "  2. First launch: Control-click Prato → Open"
echo "     Or run: xattr -cr /Applications/Prato.app"
