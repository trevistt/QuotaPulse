#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
exec "$ROOT_DIR/Scripts/install_open_at_login.sh" "$@"
