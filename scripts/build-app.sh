#!/bin/bash
# Builds Headroom.app, with its widget extension in Contents/PlugIns, with Xcode's toolchain and copies it
# to build/Headroom.app. Release builds are then checked with scripts/verify-build.sh.
# Usage: scripts/build-app.sh [Debug|Release]   (default: Debug)
#
# Signing: Debug is always ad-hoc. Release is ad-hoc too (no App Group), unless
# Config/Signing.local.xcconfig (git-ignored; start from Config/Signing.example.xcconfig) sets a team for
# the Mac App Store, and with it HEADROOM_APP_GROUP = YES.
set -euo pipefail

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

cd "$(dirname "$0")/.."
root="$(pwd)"
configuration="${1:-Debug}"

case "$configuration" in
    Debug|Release) ;;
    *) echo "usage: scripts/build-app.sh [Debug|Release]" >&2; exit 64 ;;
esac

signing_args=()
if [ "$configuration" = Release ] && [ -f "$root/Config/Signing.local.xcconfig" ]; then
    echo "build-app: Release signing from Config/Signing.local.xcconfig"
    # Lets automatic signing create or renew the profile (needs an Apple ID in Xcode's accounts).
    signing_args+=(-allowProvisioningUpdates)
fi

xcodegen generate --spec "$root/project.yml" --project "$root"

# ${array[@]+...}: bash 3.2 (macOS) treats an empty array as unset under `set -u`.
xcodebuild \
    -project "$root/Headroom.xcodeproj" \
    -scheme Headroom \
    -configuration "$configuration" \
    -destination "platform=macOS,arch=$(uname -m)" \
    -derivedDataPath "$root/build/DerivedData" \
    ${signing_args[@]+"${signing_args[@]}"} \
    build

product="$root/build/DerivedData/Build/Products/$configuration/Headroom.app"
destination="$root/build/Headroom.app"
rm -rf "$destination"
ditto "$product" "$destination"

if [ "$configuration" = Release ]; then
    # The App Group switch this build used (Config/Headroom-Variants.xcconfig, Signing.local.xcconfig).
    group="$(xcodebuild -project "$root/Headroom.xcodeproj" -target Headroom -configuration Release \
        -showBuildSettings 2>/dev/null | sed -n 's/^[[:space:]]*HEADROOM_APP_GROUP = //p' | head -n 1)"
    "$root/scripts/verify-build.sh" --group "${group:-NO}" "$destination"
fi

echo "$destination"
