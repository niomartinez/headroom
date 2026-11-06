#!/bin/bash
# Launches build/Headroom.app, checks that it stays up for ~6 s without writing a crash report,
# then quits the instance it started. Build first with scripts/build-app.sh Debug.
# Production builds must be opened from Finder to keep macOS menu-bar ownership independent.
set -euo pipefail

cd "$(dirname "$0")/.."
app="$(pwd)/build/Headroom.app"
reports="$HOME/Library/Logs/DiagnosticReports"

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist")"
if [ "$bundle_id" != "com.niomartinez.headroom.dev" ]; then
    echo "smoke-test: requires Headroom Dev; build with scripts/build-app.sh Debug. Open Release from Finder." >&2
    exit 1
fi

if [ ! -d "$app/Contents/PlugIns/HeadroomWidgets.appex" ]; then
    echo "smoke-test: $app has no widget extension (Contents/PlugIns/HeadroomWidgets.appex)" >&2
    exit 1
fi

if pgrep -x Headroom >/dev/null; then
    echo "smoke-test: Headroom is already running; quit it first so this test only touches its own instance." >&2
    exit 1
fi

marker="$(mktemp -t headroom-smoke)"
trap 'rm -f "$marker"' EXIT

open -n "$app"

pid=""
for _ in $(seq 1 100); do
    pid="$(pgrep -nx Headroom || true)"
    [ -n "$pid" ] && break
    sleep 0.1
done
if [ -z "$pid" ]; then
    echo "smoke-test: Headroom did not start" >&2
    exit 1
fi
echo "smoke-test: started pid $pid"

alive=yes
for _ in $(seq 1 60); do
    if ! pgrep -x Headroom | grep -qx "$pid"; then
        alive=no
        break
    fi
    sleep 0.1
done

crashes="$(find "$reports" -maxdepth 1 -name 'Headroom*' -newer "$marker" 2>/dev/null || true)"

if [ "$alive" = yes ]; then
    kill -TERM "$pid"
    echo "smoke-test: pid $pid was alive after ~6 s; quit it"
else
    echo "smoke-test: pid $pid exited early" >&2
fi

if [ -n "$crashes" ]; then
    echo "smoke-test: new crash report(s):" >&2
    echo "$crashes" >&2
    exit 1
fi
echo "smoke-test: no new Headroom crash reports"
[ "$alive" = yes ]
