#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/mac_tool.app"
ZIP_FILE="$ROOT_DIR/dist/mac_tool.zip"
KEYCHAIN_PROFILE="${NOTARYTOOL_PROFILE:-}"

if [[ ! -d "$APP_DIR" ]]; then
    echo "Missing $APP_DIR. Run Scripts/package_app.sh first."
    exit 1
fi

if [[ -z "$KEYCHAIN_PROFILE" ]]; then
    echo "Set NOTARYTOOL_PROFILE to a saved notarytool keychain profile."
    echo "Example: xcrun notarytool store-credentials \"mac_tool\" --apple-id ... --team-id ... --password ..."
    exit 1
fi

SIGNATURE_INFO="$(codesign -dvvv "$APP_DIR" 2>&1)"
if [[ "$SIGNATURE_INFO" != *"Authority=Developer ID Application"* ]]; then
    echo "Notarization requires a Developer ID Application signature."
    echo "Re-run Scripts/package_app.sh with SIGNING_IDENTITY set."
    exit 1
fi

"$ROOT_DIR/Scripts/create_release_artifacts.sh"

xcrun notarytool submit "$ZIP_FILE" --keychain-profile "$KEYCHAIN_PROFILE" --wait
xcrun stapler staple "$APP_DIR"
xcrun stapler validate "$APP_DIR"
"$ROOT_DIR/Scripts/create_release_artifacts.sh"

echo "Notarized, stapled, and repackaged $APP_DIR"
