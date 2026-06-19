#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_NAME="QuotaPulse"
BUNDLE_ID="${QUOTA_PULSE_BUNDLE_ID:-app.quotapulse.local}"
APP_VERSION="${QUOTA_PULSE_APP_VERSION:-0.1.0}"
APP_BUILD="${QUOTA_PULSE_APP_BUILD:-1}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BINARY_NAME="QuotaPulse"
COMMAND_LAUNCHER="$DIST_DIR/Run QuotaPulse.command"

cd "$ROOT_DIR"
swift build --product "$BINARY_NAME"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/.build/debug/$BINARY_NAME" "$MACOS_DIR/$BINARY_NAME"
chmod 755 "$MACOS_DIR/$BINARY_NAME"

if [ -d "$ROOT_DIR/Sources/QuotaPulse/Resources/BrandIcons" ]; then
    mkdir -p "$RESOURCES_DIR/BrandIcons"
    cp "$ROOT_DIR"/Sources/QuotaPulse/Resources/BrandIcons/* "$RESOURCES_DIR/BrandIcons/"
fi

RESOURCE_BUNDLE="$ROOT_DIR/.build/debug/QuotaPulse_QuotaPulse.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$BINARY_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_BUILD</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

cat > "$COMMAND_LAUNCHER" <<EOF
#!/bin/sh
cd "$ROOT_DIR"
exec "$ROOT_DIR/Scripts/run_practical.sh"
EOF
chmod 755 "$COMMAND_LAUNCHER"

echo "Packaged unsigned app: $APP_DIR"
echo "Bundle identifier: $BUNDLE_ID"
echo "Double-click launcher: $COMMAND_LAUNCHER"
