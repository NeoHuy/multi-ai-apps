#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

INSTALL=false
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=true ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 [--install]" >&2
      exit 1
      ;;
  esac
done

echo "==> Building MultiAI (release)..."
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="$BIN_DIR/MultiAI"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "Error: Release binary not found at $BIN_PATH" >&2
  exit 1
fi

APP_BUNDLE="$ROOT_DIR/build/MultiAI.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/MultiAI"
chmod +x "$MACOS_DIR/MultiAI"

echo "==> Generating MultiAI AppIcon.icns..."
"$MACOS_DIR/MultiAI" --generate-manager-icon "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>MultiAI</string>
    <key>CFBundleExecutable</key>
    <string>MultiAI</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.multiai.manager</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MultiAI</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> Signing $APP_BUNDLE..."
codesign --force --deep --sign - "$APP_BUNDLE"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ "$INSTALL" == true ]]; then
  DEST_DIR="$HOME/Applications"
  DEST_APP="$DEST_DIR/MultiAI.app"
  mkdir -p "$DEST_DIR"
  rm -rf "$DEST_APP"
  ditto "$APP_BUNDLE" "$DEST_APP"
  codesign --force --deep --sign - "$DEST_APP"
  if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$DEST_APP" || true
  fi
  echo "==> Installed to $DEST_APP"
else
  echo "==> Built at $APP_BUNDLE"
fi
