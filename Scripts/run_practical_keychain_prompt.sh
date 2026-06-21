#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

echo "Starting QuotaPulse with Keychain prompts explicitly allowed."
echo "Use this only when you are at the Mac and can approve macOS Keychain access."

export QUOTA_PULSE_LAUNCHER_ALLOW_KEYCHAIN_PROMPT=1
exec "$ROOT_DIR/Scripts/run_practical.sh"
