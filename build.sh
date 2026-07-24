#!/usr/bin/env bash
set -euo pipefail

SCHEME="${1:-boringNotch}"
CONFIGURATION="${2:-Release}"
ARCHIVE_DIR=".build"
OUTPUT_DIR=".output"

PRODUCT_NAME="boringNotch.app"
ARCHIVE_PATH="$ARCHIVE_DIR/$PRODUCT_NAME"
ZIP_PATH="$OUTPUT_DIR/boringNotch.zip"

mkdir -p "$ARCHIVE_DIR" "$OUTPUT_DIR"

echo "==> Building $SCHEME ($CONFIGURATION)..."
xcodebuild -scheme "$SCHEME" -configuration "$CONFIGURATION" -derivedDataPath "$ARCHIVE_DIR" -quiet

echo "==> Locating built app..."
APP=$(find "$ARCHIVE_DIR" -name "$PRODUCT_NAME" -type d -path "*/Build/Products/$CONFIGURATION/*" | head -1)
if [ -z "$APP" ]; then
  echo "Error: app not found" >&2
  exit 1
fi

echo "==> Codesigning $APP ..."
codesign --force --sign "boringNotchDev" --deep "$APP"

echo "==> Creating $ZIP_PATH ..."
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP" "$ZIP_PATH"

echo "==> Done! $ZIP_PATH"
open .output
