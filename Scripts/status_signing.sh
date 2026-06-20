#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_DIR="$ROOT_DIR/dist/QuotaPulse.app"
REQUIRE_CODESIGN="${QUOTA_PULSE_REQUIRE_CODESIGN:-0}"
REQUESTED_IDENTITY="${QUOTA_PULSE_CODESIGN_IDENTITY:-}"

if [ ! -d "$APP_DIR" ]; then
    echo "Signing: app not found at $APP_DIR"
    exit 1
fi

details=$(codesign -dv "$APP_DIR" 2>&1 || true)
requirements=$(codesign -d -r- "$APP_DIR" 2>&1 || true)

identifier=$(printf '%s\n' "$details" | sed -n 's/^Identifier=//p' | head -n 1)
signature=$(printf '%s\n' "$details" | sed -n 's/^Signature=//p' | head -n 1)
team=$(printf '%s\n' "$details" | sed -n 's/^TeamIdentifier=//p' | head -n 1)
authority=$(printf '%s\n' "$details" | sed -n 's/^Authority=//p' | head -n 1)

echo "Signing: app=$APP_DIR"
echo "Identifier: ${identifier:-unknown}"
echo "Signature: ${signature:-unknown}"
if [ -n "$authority" ]; then
    echo "Authority: $authority"
fi
echo "TeamIdentifier: ${team:-not set}"

if printf '%s\n' "$requirements" | grep -q 'cdhash H"'; then
    echo "Designated requirement: cdhash-only"
else
    echo "Designated requirement: stable requirement present"
fi

if codesign --verify --deep --strict --verbose=2 "$APP_DIR" >/tmp/quota-pulse-codesign-verify.$$ 2>&1; then
    echo "Verify: PASS"
    rm -f /tmp/quota-pulse-codesign-verify.$$
else
    echo "Verify: FAIL"
    sed -n '1,12p' /tmp/quota-pulse-codesign-verify.$$
    rm -f /tmp/quota-pulse-codesign-verify.$$
    if [ "$REQUIRE_CODESIGN" = "1" ]; then
        exit 1
    fi
fi

if [ -n "$REQUESTED_IDENTITY" ]; then
    if security find-identity -v -p codesigning 2>/dev/null | grep -F "$REQUESTED_IDENTITY" >/dev/null 2>&1; then
        echo "Requested identity: found"
    else
        echo "Requested identity: not found"
        if [ "$REQUIRE_CODESIGN" = "1" ]; then
            exit 1
        fi
    fi
fi

if [ "$REQUIRE_CODESIGN" = "1" ] && [ "$signature" = "adhoc" ]; then
    echo "Signing: required stable signing, but app is ad-hoc."
    exit 1
fi
