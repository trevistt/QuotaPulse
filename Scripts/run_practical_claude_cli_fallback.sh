#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

echo "Starting QuotaPulse with explicit Claude CLI fallback."
echo "Claude CLI fallback may update Claude local state file ~/.claude.json."

export QUOTA_PULSE_LAUNCHER_ENABLE_CLAUDE_CLI=1
exec "$ROOT_DIR/Scripts/run_practical.sh"
