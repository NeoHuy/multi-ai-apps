#!/usr/bin/env zsh
set -euo pipefail

VERSION="${APP_VERSION:-0.0.1}"
ARCH="arm64"
APP_BUNDLE="build/MultiAI.app"
OUTPUT_DIR="build/release"

usage() {
  echo "Usage: $0 [--version <X.Y.Z>] [--arch <arch>] [--app <path>] [--output-dir <dir>]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      if [[ $# -lt 2 ]]; then
        echo "Error: --version requires a value" >&2
        usage
        exit 1
      fi
      VERSION="$2"
      shift 2
      ;;
    --arch)
      if [[ $# -lt 2 ]]; then
        echo "Error: --arch requires a value" >&2
        usage
        exit 1
      fi
      ARCH="$2"
      shift 2
      ;;
    --app)
      if [[ $# -lt 2 ]]; then
        echo "Error: --app requires a value" >&2
        usage
        exit 1
      fi
      APP_BUNDLE="$2"
      shift 2
      ;;
    --output-dir)
      if [[ $# -lt 2 ]]; then
        echo "Error: --output-dir requires a value" >&2
        usage
        exit 1
      fi
      OUTPUT_DIR="$2"
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

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Error: App bundle not found at $APP_BUNDLE" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/multiai-dmg-staging.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

ZIP_NAME="MultiAI-${VERSION}-${ARCH}.zip"
DMG_NAME="MultiAI-${VERSION}-${ARCH}.dmg"

echo "==> Creating $OUTPUT_DIR/$ZIP_NAME..."
rm -f "$OUTPUT_DIR/$ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$OUTPUT_DIR/$ZIP_NAME"

echo "==> Staging DMG contents..."
ditto "$APP_BUNDLE" "$STAGING_DIR/MultiAI.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Creating $OUTPUT_DIR/$DMG_NAME..."
rm -f "$OUTPUT_DIR/$DMG_NAME"
DMG_CREATED=false
for attempt in 1 2 3; do
  if hdiutil create -volname "MultiAI" -srcfolder "$STAGING_DIR" -ov -format UDZO -imagekey zlib-level=9 "$OUTPUT_DIR/$DMG_NAME"; then
    DMG_CREATED=true
    break
  fi
  echo "Warning: hdiutil create failed on attempt $attempt/3; retrying in 3s..." >&2
  rm -f "$OUTPUT_DIR/$DMG_NAME"
  sleep 3
done

if [[ "$DMG_CREATED" != true ]]; then
  echo "Error: Failed to create DMG after 3 attempts" >&2
  exit 1
fi

echo "==> Writing $OUTPUT_DIR/SHA256SUMS.txt..."
(cd "$OUTPUT_DIR" && shasum -a 256 "$DMG_NAME" "$ZIP_NAME" > SHA256SUMS.txt)

echo "==> Packaged release artifacts in $OUTPUT_DIR:"
ls -lh "$OUTPUT_DIR/$DMG_NAME" "$OUTPUT_DIR/$ZIP_NAME" "$OUTPUT_DIR/SHA256SUMS.txt"
