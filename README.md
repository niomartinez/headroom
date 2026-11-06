# Headroom

A macOS menu bar app showing usage limits and running sessions for Claude, OpenAI Codex and
GitHub Copilot. Claude and Codex data come from files on your Mac; optional Copilot usage connects
to GitHub. Native Swift 6 (SwiftUI and AppKit), macOS 14+, with desktop widgets and sandboxed
Mac App Store builds.

[Download Headroom free on the Mac App Store](https://apps.apple.com/app/headroom-ai-usage-meter/id6815808010).

Choose one tool's rings or a gauge for each tool. Each warning gauge shows its own highest usage
percentage from 75%, including simultaneous warnings. Automatic sizing preserves your selected
gauges; Always compact uses one gauge.

- Spec: `docs/superpowers/specs/2026-09-24-headroom-design.md`
- Multi-tool spec and amendments: `docs/superpowers/specs/2026-09-25-headroom-1.1-design.md`
- Release checklist: `docs/app-store.md`
- Package: `Packages/HeadroomKit` (the kits plus the `headroom-dump` and `headroom-render` tools)
- App: `App/` and `project.yml` (XcodeGen generates `Headroom.xcodeproj`, which isn't committed)

## Getting started

On first launch, choose Claude, Codex or Copilot and connect what you use. Each connection is
optional: choose **Set up later** or **Try sample data** to explore without granting access.
Use **Add another tool** to connect more, or **Done** to return to the menu bar. Reopen setup
from **Settings > General > Set up tools…**.

Copilot has separate connections: **GitHub account** for usage, and **Session activity >
Connect sessions…** for desktop and CLI activity. After connecting or updating session
activity, start a new Copilot session so it loads the hooks. GitHub sign-in alone does not
enable session completion moments.

## Requirements

- macOS 14 or later, Xcode in `/Applications/Xcode.app`, and XcodeGen (`brew install xcodegen`).
- Use Xcode's toolchain for every `swift`, `xcodebuild`, `xcrun` and `xcodegen` command. The
  scripts set it themselves; in your own shell run
  `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` first.

## Build

```sh
scripts/build-app.sh            # Debug (the default)
scripts/build-app.sh Release
```

The script generates the Xcode project, builds into `build/DerivedData` and copies the app to
`build/Headroom.app`. Debug appears as **Headroom Dev**, with its own bundle identifier,
preferences and widget URL scheme (`com.niomartinez.headroom.dev`). Release keeps the production
identity (`com.niomartinez.headroom`). Launch Release from Finder, not an agent or IDE: macOS can
otherwise associate its menu-bar permission with the launching app. Debug builds aren't sandboxed and read `~/.claude` and
`~/Library/Application Support/Claude` directly. Release builds are sandboxed and ask for those
two folders once. Debug builds are always signed ad hoc; Release builds are too, unless
`Config/Signing.local.xcconfig` exists (see [Mac App Store signing](#mac-app-store-signing)).

## Test

```sh
(cd Packages/HeadroomKit && swift test)   # package tests
scripts/test-app.sh                       # app logic tests: xcodegen generate, then xcodebuild test
scripts/smoke-test.sh                     # runs build/Headroom.app for ~6 s, checks for a crash report, quits it
```

`scripts/test-app.sh` runs `xcodebuild test -project Headroom.xcodeproj -scheme Headroom
-derivedDataPath build/DerivedData` for the Mac it runs on. `scripts/smoke-test.sh` needs a
Debug build from `scripts/build-app.sh Debug`, and refuses to run while another Headroom is running.

## Looking at real data

`headroom-dump` prints the live snapshot (limits, sessions, context, data issues) as JSON. It reads
the real `~/.claude` and `~/Library/Application Support/Claude` and never writes to them.

```sh
cd Packages/HeadroomKit
swift run headroom-dump [--timing] [--watch N] [--claude-dir PATH] [--desktop-dir PATH]
```

| Flag | Effect |
|---|---|
| `--timing` | Prints the cold (first) build time and the median, min and max of 20 warm (cached) builds to stderr. |
| `--watch N` | After the snapshot, rebuilds every 2 s, N times. Moments go to stdout as they happen, and a one-line summary per poll goes to stderr. |
| `--claude-dir PATH` | Reads another `~/.claude`, for end-to-end tests with a throwaway home. |
| `--desktop-dir PATH` | Reads another Claude desktop app folder in place of `~/Library/Application Support/Claude`. |

`swift run headroom-render <dir>` renders pill and panel states from synthetic data to PNG files
in `<dir>`.

The app can also show what it would display right now, without opening any window:

```sh
build/Headroom.app/Contents/MacOS/Headroom --render-live /tmp/headroom-live
```

It polls real data for about 5 s, writes `live-pill.png`, `live-panel.png` and
`live-snapshot.json` (plus `live-pill-moment.png` when a moment is showing or queued) to the
directory, and quits. It never shows the pill, the panel or onboarding. Use a Debug build for
this, because a sandboxed Release build can only write inside its container.

## Mac App Store signing

Signing for Release builds lives in `Config/`, not in `project.yml`. To sign for the store:

1. Copy `Config/Signing.example.xcconfig` to `Config/Signing.local.xcconfig`. The copy is
   git-ignored, so your Team ID never lands in the repository.
2. Set `DEVELOPMENT_TEAM` in it and keep one of its two options: automatic signing (needs your
   Apple ID in Xcode › Settings › Accounts) or manual signing with a Mac App Store provisioning
   profile.
3. Run `scripts/build-app.sh Release`. When the local file exists, the script uses it and passes
   `-allowProvisioningUpdates`.

Debug builds are always signed ad hoc. Delete the local file to go back to ad hoc Release builds.
`docs/app-store.md` has the full submission checklist (entitlements, privacy, metadata and notes
for App Review).

## Uninstalling

If you used Connect terminal, choose Disconnect terminal in Headroom before you delete the app.
Connect adds a status line and hooks to `~/.claude/settings.json` that run
`~/.claude/headroom/bridge.sh`. Once Headroom is gone (the app and its data container,
`~/Library/Containers/com.niomartinez.headroom`) the bridge stops writing anything; a status
line of your own, if you had one, keeps showing. Only Disconnect removes those entries and the
`~/.claude/headroom` folder.
`~/.claude/settings.json.headroom-backup` holds your settings from before the first Connect.

## Contributing

Issues and pull requests are welcome. Read `CONTRIBUTING.md` first, and report security problems
privately as described in `SECURITY.md`.

## License

The source code is available under the MIT License (`LICENSE`). The Headroom name and app icon
identify the Mac App Store app: if you ship a fork, give it your own name, icon and bundle
identifiers.

## Disclaimer

Headroom isn't made by or affiliated with Anthropic, OpenAI or GitHub. Claude and Claude Code are
Anthropic's products, Codex is OpenAI's and Copilot is GitHub's. Headroom reads the files they
write on your Mac and, once you connect GitHub, your Copilot usage.
