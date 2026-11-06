#!/bin/bash
# Runs the app's hostless logic tests (HeadroomLogicTests: App/Tests against App/Sources/Logic).
# The HeadroomKit package has its own tests: `swift test` in Packages/HeadroomKit.
set -euo pipefail

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

cd "$(dirname "$0")/.."
root="$(pwd)"

xcodegen generate --spec "$root/project.yml" --project "$root"

xcodebuild \
    -project "$root/Headroom.xcodeproj" \
    -scheme Headroom \
    -destination "platform=macOS,arch=$(uname -m)" \
    -derivedDataPath "$root/build/DerivedData" \
    test
