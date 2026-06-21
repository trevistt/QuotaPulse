#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_NAME="QuotaPulse"
BUNDLE_ID="${QUOTA_PULSE_BUNDLE_ID:-app.quotapulse.local}"
APP_VERSION="${QUOTA_PULSE_APP_VERSION:-0.3.0}"
APP_BUILD="${QUOTA_PULSE_APP_BUILD:-3}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
STAGE_APP_DIR="$DIST_DIR/.$APP_NAME.app.stage.$$"
CONTENTS_DIR="$STAGE_APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BINARY_NAME="QuotaPulse"
COMMAND_LAUNCHER="$DIST_DIR/Run QuotaPulse.command"
CODESIGN_IDENTITY="${QUOTA_PULSE_CODESIGN_IDENTITY:-}"
REQUIRE_CODESIGN="${QUOTA_PULSE_REQUIRE_CODESIGN:-0}"

cleanup() {
    rm -rf "$STAGE_APP_DIR"
}
trap cleanup EXIT HUP INT TERM

cd "$ROOT_DIR"
swift build --product "$BINARY_NAME"

rm -rf "$STAGE_APP_DIR"
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

if [ -n "$CODESIGN_IDENTITY" ]; then
    echo "Signing app with local identity: $CODESIGN_IDENTITY"
    codesign --force --deep --sign "$CODESIGN_IDENTITY" \
        --identifier "$BUNDLE_ID" \
        --timestamp=none \
        "$STAGE_APP_DIR"
elif [ "$REQUIRE_CODESIGN" = "1" ]; then
    echo "ERROR: QUOTA_PULSE_REQUIRE_CODESIGN=1 but QUOTA_PULSE_CODESIGN_IDENTITY is not set." >&2
    exit 1
else
    echo "Signing app ad-hoc. Set QUOTA_PULSE_CODESIGN_IDENTITY for stable local signing."
    codesign --force --deep --sign - \
        --identifier "$BUNDLE_ID" \
        --timestamp=none \
        "$STAGE_APP_DIR"
fi

codesign --verify --deep --strict --verbose=2 "$STAGE_APP_DIR"

rm -rf "$APP_DIR"
mv "$STAGE_APP_DIR" "$APP_DIR"

cat > "$COMMAND_LAUNCHER" <<EOF
#!/bin/sh
cd "$ROOT_DIR"
exec "$ROOT_DIR/Scripts/run_practical.sh"
EOF
chmod 755 "$COMMAND_LAUNCHER"

if [ -n "$CODESIGN_IDENTITY" ]; then
    echo "Packaged local-signed app: $APP_DIR"
else
    echo "Packaged ad-hoc signed app: $APP_DIR"
fi
echo "Bundle identifier: $BUNDLE_ID"
codesign -dv "$APP_DIR" 2>&1 | sed -n '/^Identifier=/p;/^Signature=/p;/^Authority=/p;/^TeamIdentifier=/p'
echo "Double-click launcher: $COMMAND_LAUNCHER"
