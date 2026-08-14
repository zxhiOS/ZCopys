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

# Entitlements: CloudKit is a restricted entitlement — macOS kills the app at
# launch (RBS/163) unless the App ID has CloudKit enabled AND signing uses a
# matching provisioning profile. Default: sign without iCloud so local installs
# still launch. Set ENABLE_ICLOUD_ENTITLEMENTS=1 after Developer portal setup.
ENTITLEMENTS_SRC="$ROOT_DIR/Resources/Zcopys.entitlements"
ENTITLEMENTS_OUT="$CONTENTS_DIR/Zcopys.entitlements"
ICLOUD_CONTAINER="iCloud.${BUNDLE_IDENTIFIER}"
ENABLE_ICLOUD_ENTITLEMENTS="${ENABLE_ICLOUD_ENTITLEMENTS:-0}"

# Always keep the full CloudKit entitlements file in Resources for reference /
# when ENABLE_ICLOUD_ENTITLEMENTS=1.
cat > "$ENTITLEMENTS_SRC" <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.get-task-allow</key>
	<true/>
	<key>com.apple.developer.icloud-container-identifiers</key>
	<array>
		<string>${ICLOUD_CONTAINER}</string>
	</array>
	<key>com.apple.developer.icloud-services</key>
	<array>
		<string>CloudKit</string>
	</array>
</dict>
</plist>
ENT

if [[ "$ENABLE_ICLOUD_ENTITLEMENTS" == "1" ]]; then
    cp "$ENTITLEMENTS_SRC" "$ENTITLEMENTS_OUT"
else
    # Launch-safe entitlements (no restricted iCloud keys).
    cat > "$ENTITLEMENTS_OUT" <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.get-task-allow</key>
	<true/>
</dict>
</plist>
ENT
fi

if [[ -n "$SIGNING_IDENTITY" ]]; then
    echo "Signing with: $SIGNING_IDENTITY"
    if [[ "$ENABLE_ICLOUD_ENTITLEMENTS" == "1" ]]; then
        echo "iCloud entitlements ON (container: $ICLOUD_CONTAINER)"
        echo "Requires App ID CloudKit + matching provisioning profile, or launch will fail."
    else
        echo "iCloud entitlements OFF (set ENABLE_ICLOUD_ENTITLEMENTS=1 after Apple Developer CloudKit setup)."
    fi
    codesign --force --deep --entitlements "$ENTITLEMENTS_OUT" --sign "$SIGNING_IDENTITY" "$APP_DIR"
else
    echo "Warning: no Apple Development identity found; using ad-hoc signature."
    echo "Accessibility permission will NOT persist across rebuilds."
    echo "CloudKit sync requires a real Apple Development / Developer ID signature."
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
