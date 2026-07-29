#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Zcopys"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
ZIP_FILE="$ROOT_DIR/dist/$APP_NAME.zip"
DMG_FILE="$ROOT_DIR/dist/$APP_NAME.dmg"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/$APP_NAME-release.XXXXXX")"

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

if [[ ! -d "$APP_DIR" ]]; then
    echo "Missing $APP_DIR. Run Scripts/package_app.sh first."
    exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

rm -f "$ZIP_FILE" "$DMG_FILE"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_FILE"
ditto "$APP_DIR" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_FILE" >/dev/null

echo "Created $ZIP_FILE"
echo "Created $DMG_FILE"
