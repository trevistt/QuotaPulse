#!/bin/sh
set -eu

LABEL="${QUOTA_PULSE_LAUNCH_AGENT_LABEL:-app.quotapulse.local}"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"
SERVICE="$DOMAIN/$LABEL"

if [ -e "$PLIST" ]; then
    echo "Open at Login: installed at $PLIST"
else
    echo "Open at Login: not installed"
fi

if launchctl print "$SERVICE" >/dev/null 2>&1; then
    echo "Service: loaded ($SERVICE)"
else
    echo "Service: not loaded ($SERVICE)"
fi

running_pids=$(pgrep -x QuotaPulse || true)
if [ -n "$running_pids" ]; then
    echo "App: running ($running_pids)"
else
    echo "App: not running"
fi

claude_pids=$(pgrep -x claude || true)
if [ -n "$claude_pids" ]; then
    echo "Claude CLI process: running ($claude_pids)"
else
    echo "Claude CLI process: not running"
fi
