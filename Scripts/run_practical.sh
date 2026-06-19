#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_DIR="$ROOT_DIR/dist/QuotaPulse.app"
APP_BIN="$ROOT_DIR/dist/QuotaPulse.app/Contents/MacOS/QuotaPulse"

env_value() {
    name="$1"
    eval "value=\${$name:-}"
    printf '%s' "$value"
}

LOG_DIR_OVERRIDE=$(env_value QUOTA_PULSE_LOG_DIR)
LOG_DIR="${LOG_DIR_OVERRIDE:-$HOME/Library/Logs/QuotaPulse}"
LOG_FILE="$LOG_DIR/practical.log"
LOCK_DIR="$LOG_DIR/run_practical.lock"

timestamp() {
    date '+%Y-%m-%d %H:%M:%S %Z'
}

log() {
    printf '%s %s\n' "$(timestamp)" "$*" >> "$LOG_FILE"
}

mkdir -p "$LOG_DIR"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    log "Another launcher invocation is active; not starting duplicate."
    echo "QuotaPulse launcher is already starting; not starting a duplicate."
    echo "Log: $LOG_FILE"
    exit 0
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT HUP INT TERM

if [ ! -x "$APP_BIN" ]; then
    log "ERROR packaged app binary not found: $APP_BIN"
    echo "QuotaPulse packaged app was not found."
    echo "Run Scripts/package_app.sh first."
    echo "Log: $LOG_FILE"
    exit 1
fi

running_pids=$(pgrep -x QuotaPulse || true)
if [ -n "$running_pids" ]; then
    log "Already running; not starting duplicate. PIDs: $running_pids"
    echo "QuotaPulse is already running; not starting a duplicate."
    echo "Log: $LOG_FILE"
    exit 0
fi

credentials_path=$(env_value QUOTA_PULSE_CLAUDE_CREDENTIALS_PATH)
oauth_cache_path=$(env_value QUOTA_PULSE_CLAUDE_OAUTH_CACHE_PATH)
show_notch=$(env_value QUOTA_PULSE_SHOW_NOTCH)
cli_fallback="${QUOTA_PULSE_LAUNCHER_ENABLE_CLAUDE_CLI:-}"

log "Starting practical mode from $APP_DIR"
echo "Starting QuotaPulse practical mode."
echo "Log: $LOG_FILE"

unset QUOTA_PULSE_FIXTURE
unset QUOTA_PULSE_CLAUDE_FIXTURE
unset QUOTA_PULSE_ENABLE_CLAUDE_LIVE
unset QUOTA_PULSE_DISABLE_CLAUDE_OAUTH
export QUOTA_PULSE_ENABLE_CLAUDE_KEYCHAIN=1
unset QUOTA_PULSE_ENABLE_CLAUDE_CLI
if [ "$cli_fallback" = "1" ]; then
    export QUOTA_PULSE_ENABLE_CLAUDE_CLI=1
fi

set -- -g --env QUOTA_PULSE_ENABLE_CLAUDE_KEYCHAIN=1
if [ "$cli_fallback" = "1" ]; then
    set -- "$@" --env QUOTA_PULSE_ENABLE_CLAUDE_CLI=1
else
    set -- "$@" --env QUOTA_PULSE_ENABLE_CLAUDE_CLI=
fi
if [ -n "$credentials_path" ]; then
    set -- "$@" --env QUOTA_PULSE_CLAUDE_CREDENTIALS_PATH="$credentials_path"
fi
if [ -n "$oauth_cache_path" ]; then
    set -- "$@" --env QUOTA_PULSE_CLAUDE_OAUTH_CACHE_PATH="$oauth_cache_path"
fi
if [ "$show_notch" = "1" ]; then
    set -- "$@" --env QUOTA_PULSE_SHOW_NOTCH=1
fi

if [ "$cli_fallback" = "1" ]; then
    log "Claude OAuth Keychain discovery enabled; Claude CLI fallback explicitly enabled by fallback launcher."
    echo "Claude CLI fallback is explicitly enabled. Claude CLI may update Claude local state."
else
    log "Claude OAuth Keychain discovery enabled for daily launcher; Claude CLI fallback disabled."
fi
/usr/bin/open "$@" "$APP_DIR"

sleep 4
started_pids=$(pgrep -x QuotaPulse || true)
if [ -z "$started_pids" ]; then
    log "ERROR app launch returned but QuotaPulse is not running"
    echo "QuotaPulse launch returned, but the app is not running."
    echo "Log: $LOG_FILE"
    exit 1
fi

log "Started practical mode. PIDs: $started_pids"
echo "QuotaPulse is running."
