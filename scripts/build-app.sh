#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

INSTALL=false
APP_VERSION="${APP_VERSION:-0.0.1}"
APP_BUILD_NUMBER="${APP_BUILD_NUMBER:-1}"
ARCH=""

usage() {
  echo "Usage: $0 [--install] [--version <X.Y.Z>] [--build-number <N>] [--arch <arm64|x86_64>]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      INSTALL=true
      shift
      ;;
    --version)
      if [[ $# -lt 2 ]]; then
        echo "Error: --version requires a value" >&2
        usage
        exit 1
      fi
      APP_VERSION="$2"
      shift 2
      ;;
    --build-number)
      if [[ $# -lt 2 ]]; then
        echo "Error: --build-number requires a value" >&2
        usage
        exit 1
      fi
      APP_BUILD_NUMBER="$2"
      shift 2
      ;;
    --arch)
      if [[ $# -lt 2 ]]; then
        echo "Error: --arch requires a value" >&2
        usage
        exit 1
      fi
      case "$2" in
        arm64|x86_64) ARCH="$2" ;;
        *)
          echo "Error: Unsupported architecture '$2' (expected arm64 or x86_64)" >&2
          usage
          exit 1
          ;;
      esac
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

BUILD_ARGS=(-c release)
if [[ -n "$ARCH" ]]; then
  BUILD_ARGS+=(--arch "$ARCH")
fi

echo "==> Building MultiAI (release${ARCH:+, arch: $ARCH}, version: $APP_VERSION, build: $APP_BUILD_NUMBER)..."
swift build "${BUILD_ARGS[@]}"

BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
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

cat > "$CONTENTS_DIR/Info.plist" << PLIST
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
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_BUILD_NUMBER}</string>
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
