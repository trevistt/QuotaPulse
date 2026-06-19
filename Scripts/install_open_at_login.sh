#!/bin/sh
set -eu

LABEL="${QUOTA_PULSE_LAUNCH_AGENT_LABEL:-app.quotapulse.local}"
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_DIR="$ROOT_DIR/dist/QuotaPulse.app"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST="$PLIST_DIR/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/QuotaPulse"
DOMAIN="gui/$(id -u)"
SERVICE="$DOMAIN/$LABEL"

if [ "$(id -u)" -eq 0 ]; then
    echo "Do not install Open at Login with sudo or as root."
    exit 1
fi

if [ ! -d "$APP_DIR" ]; then
    echo "Packaged app not found: $APP_DIR"
    echo "Run Scripts/package_app.sh first."
    exit 1
fi

xml_escape() {
    printf '%s' "$1" | sed \
        -e 's/&/\&amp;/g' \
        -e 's/</\&lt;/g' \
        -e 's/>/\&gt;/g' \
        -e 's/"/\&quot;/g' \
        -e "s/'/\&apos;/g"
}

write_open_plist() {
    APP_DIR_XML=$(xml_escape "$APP_DIR")
    LOG_OUT_XML=$(xml_escape "$LOG_DIR/open-at-login.out.log")
    LOG_ERR_XML=$(xml_escape "$LOG_DIR/open-at-login.err.log")
    APP_OUT_XML=$(xml_escape "$LOG_DIR/open-at-login.app.out.log")
    APP_ERR_XML=$(xml_escape "$LOG_DIR/open-at-login.app.err.log")

    tmp_plist="$PLIST.tmp.$$"
    cat > "$tmp_plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-g</string>
        <string>--stdout</string>
        <string>$APP_OUT_XML</string>
        <string>--stderr</string>
        <string>$APP_ERR_XML</string>
        <string>--env</string>
        <string>QUOTA_PULSE_ENABLE_CLAUDE_KEYCHAIN=1</string>
        <string>--env</string>
        <string>QUOTA_PULSE_ENABLE_CLAUDE_CLI=</string>
        <string>$APP_DIR_XML</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>StandardOutPath</key>
    <string>$LOG_OUT_XML</string>
    <key>StandardErrorPath</key>
    <string>$LOG_ERR_XML</string>
</dict>
</plist>
EOF

    plutil -lint "$tmp_plist" >/dev/null
    mv "$tmp_plist" "$PLIST"
    chmod 644 "$PLIST"
}

load_open_at_login() {
    launchctl bootout "$DOMAIN" "$PLIST" >/dev/null 2>&1 || true
    launchctl bootstrap "$DOMAIN" "$PLIST"
    launchctl kickstart -k "$SERVICE"
}

mkdir -p "$PLIST_DIR" "$LOG_DIR"
: > "$LOG_DIR/open-at-login.out.log"
: > "$LOG_DIR/open-at-login.err.log"

write_open_plist
load_open_at_login

echo "Open at Login enabled: $PLIST"
echo "Service: $SERVICE"
echo "Logs: $LOG_DIR"
echo "Claude OAuth Keychain discovery is enabled; Claude CLI fallback is not enabled."
