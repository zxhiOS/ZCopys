#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Zcopys"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
BUILD_DIR="$ROOT_DIR/.build/release"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_FILE="$RESOURCES_DIR/Zcopys.icns"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.local.zcopys}"
MARKETING_VERSION="${MARKETING_VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
INSTALL_TO_APPLICATIONS="${INSTALL_TO_APPLICATIONS:-1}"

# Prefer a stable Apple Development identity so Accessibility TCC survives rebuilds.
# Ad-hoc (`codesign -s -`) changes CDHash every build and macOS forgets the toggle.
if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="$(
        security find-identity -v -p codesigning 2>/dev/null \
            | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
            | head -n 1
    )"
fi

cd "$ROOT_DIR"
swift "$ROOT_DIR/Scripts/generate_icon.swift"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$ROOT_DIR/dist/Zcopys.icns" "$ICON_FILE"
# Menu bar icons for Bundle.main
cp "$ROOT_DIR/Assets/StatusBarIcon.png" "$RESOURCES_DIR/StatusBarIcon.png"
cp "$ROOT_DIR/Assets/StatusBarIcon@2x.png" "$RESOURCES_DIR/StatusBarIcon@2x.png"
chmod +x "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Zcopys</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_IDENTIFIER}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Zcopys</string>
    <key>CFBundleDisplayName</key>
    <string>Zcopys</string>
    <key>CFBundleIconFile</key>
    <string>Zcopys</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
PLIST

if [[ -n "$SIGNING_IDENTITY" ]]; then
    echo "Signing with: $SIGNING_IDENTITY"
    codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_DIR"
else
    echo "Warning: no Apple Development identity found; using ad-hoc signature."
    echo "Accessibility permission will NOT persist across rebuilds."
    codesign --force --deep --sign - "$APP_DIR"
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
"$ROOT_DIR/Scripts/create_release_artifacts.sh"

# Install to /Applications so System Settings always points at a stable path.
if [[ "$INSTALL_TO_APPLICATIONS" == "1" ]]; then
    APP_INSTALL="/Applications/${APP_NAME}.app"
    rm -rf "/Applications/mac_tool.app" "$APP_INSTALL"
    cp -R "$APP_DIR" "$APP_INSTALL"
    echo "Installed $APP_INSTALL"
fi

echo "Created $APP_DIR"
