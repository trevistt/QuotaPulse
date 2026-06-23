#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

echo "Starting QuotaPulse attended Claude login repair mode."
echo "Open the dashboard and click Fix Claude Login when you are ready to approve macOS Keychain access."

export QUOTA_PULSE_LAUNCHER_ALLOW_KEYCHAIN_PROMPT=1
exec "$ROOT_DIR/Scripts/run_practical.sh"
