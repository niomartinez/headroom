# Headroom

macOS menu bar app (Swift 6, SwiftUI/AppKit, macOS 14+) showing AI plan limits and running Claude Code, Codex and Copilot sessions. Spec: `docs/superpowers/specs/2026-09-24-headroom-design.md`, with the multi-tool amendments in `docs/superpowers/specs/2026-09-25-headroom-1.1-design.md`. Release checklist: `docs/app-store.md`. Bundle ID `com.niomartinez.headroom`, website https://headroom.niomartinez.com (`website/`).

- Package tests: `cd Packages/HeadroomKit && swift test`. App: `scripts/build-app.sh [Debug|Release]`; app tests via `scripts/test-app.sh` (or `xcodebuild test -project Headroom.xcodeproj -scheme Headroom -destination 'platform=macOS'` after `xcodegen generate`).
- Run `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` before `swift`, `xcodebuild` or `xcrun`. Don't change `xcode-select`.
- `headroom-render <dir>` renders synthetic UI states; the app's `--render-live <dir>` renders real data. Never put real session names or paths in screenshots, test fixtures or marketing.
- Never install the terminal bridge into a real `~/.claude/settings.json` from a test or an agent run. Only the user's own click on Connect terminal does that.
- Maintainer-only notes (accounts, the release log and handoffs) aren't in this repository. If `CLAUDE.local.md` exists at the repository root, read it.

## Silent QA

Nobody should ever hear a test run, on any platform. Sound stays testable through its traces, never through the Mac's speakers.

- The app makes no sound (checked 31 October 2026): no audio frameworks, system sounds or sound assets in the app or `Packages/HeadroomKit`, so app and package tests are silent.
- The one place audio exists is the What's New video in `marketing/whatsnew-video`. Its audio is rendered offline to `out/audio.wav` (`audio.js`) and muxed by ffmpeg, and `render.mjs` captures frames in headless Chromium, which is muted. Opening `index.html?preview` and pressing Play plays that file through the Mac's speakers, so do not press Play during checks; scrub the timeline instead, or measure the file with ffmpeg (`master.sh`).
- Silence belongs to the build, not to each launch remembering a flag. Quiet only the owned test surfaces; never mute the Mac itself.
