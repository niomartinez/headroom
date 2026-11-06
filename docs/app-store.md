# Mac App Store submission checklist

Headroom is built to Mac App Store rules from day one (spec §4, 1.1 spec §8): Release builds are
sandboxed, read only the folders the user grants, collect no data, and make no network connections
except to GitHub, and only after the user connects GitHub for Copilot usage. This is what's left to
do before a submission, and what to tell App Review.

The release itself is scripted with fastlane: `scripts/release/README.md` has the order of the steps
and the commands. This file is the checklist behind them.

| | |
|---|---|
| Store name | **Headroom: AI Usage Meter** (display name under the icon: Headroom). "Headroom" alone is taken. |
| Apple ID | 6815808010 |
| Bundle IDs | `com.niomartinez.headroom` (app), `com.niomartinez.headroom.widgets` (widget extension) |
| App Group | `L237BMXGB6.com.niomartinez.headroom` (`$(TeamIdentifierPrefix)com.niomartinez.headroom`) |
| Team | Nio Martinez, `L237BMXGB6` |
| Source version | `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml` |
| GitHub App | "Headroom for Mac", Client ID `Iv23liEA5ZycifEXDZCT` (§1) |
| Price | Free |
| Website | https://headroom.niomartinez.com (`/privacy`, `/support`) |
| Support | hello@niomartinez.com |

## Released version and setup checks

Version 1.1.0 is live and free on the Mac App Store, verified October 10, 2026.
Apple's approval email accepts the recorded build-16 submission.
On first launch, choose Claude, Codex or Copilot; connections are optional. **Set up later**
closes setup, and **Try sample data** immediately previews synthetic sessions. Existing users
can reopen it through **Settings > General > Set up tools…**.

For Copilot, **GitHub account** connects usage. **Session activity > Connect sessions…**
connects desktop and CLI activity separately, with folder access and an explicit confirmation
before hook files are written. Start a new Copilot session afterward; use **Update…** first
if the existing connection is outdated. Completed sessions retain their final event so
Headroom can show its completion moment even if Copilot immediately closes the session.

TestFlight launch, retained grants, reopened setup and sample/live switching were checked.
First-run selection and completion are unit-tested; no fresh macOS user was created. The
Copilot completion regression passes, but a live completion after connecting remains pending.

## 0. What still needs the browser

fastlane covers building, signing, uploading, the listing and the submission. These steps have no
API-key route and are done on appstoreconnect.apple.com:

- [x] **Create the app record** (done for 1.0: Apps › + › New App, macOS, English (U.S.), bundle ID
      above). The App Store Connect API can't create apps.
- [x] **Version 1.1.0 exists.** It replaced the original 1.0.0 submission. Retain this version
      record when replacing a pending build.
- [ ] **App Privacy: re-confirm Data Not Collected** (fastlane can only set it with an Apple ID login).
      1.1 adds network use, so open the questionnaire again and publish the same answer (rationale
      in §4).
- [x] **Price: Free**, 174 storefronts with China mainland excluded (verified October 1).
- [x] **Automatic release after approval** is configured in App Store Connect. Preserve
      `AFTER_APPROVAL` when replacing the submission; the generic `fastlane mac submit` lane's
      manual-release default does not match this app's current release choice.
- [x] Only once: the App Store Connect API key (Admin: the automatic-signing export uses
      cloud-managed distribution certificates, which App Manager keys can't), saved as
      `~/.appstoreconnect/api_key.json` (`scripts/release/README.md` §0).

## 1. Team, bundle IDs and the GitHub App

- [x] Apple Developer Program membership: team `L237BMXGB6`.
- [ ] Two explicit App IDs (Certificates, Identifiers & Profiles › Identifiers): the app
      `com.niomartinez.headroom` and the widget extension `com.niomartinez.headroom.widgets`. Both
      need the **App Groups** capability for `L237BMXGB6.com.niomartinez.headroom`. Team-prefixed
      groups need no group registration on macOS, but the provisioning profiles must authorize the
      group; `scripts/verify-build.sh` checks that they do. `fastlane mac build` lets Xcode register
      a missing App ID and turn on the capability through the API key (`-allowProvisioningUpdates`;
      Nio approved this, and registering this Mac as a device, for 1.1).
- [x] The app record (§0). The name must not contain "Claude", "Anthropic", "Codex", "Copilot" or
      other companies' names (see §5).
- [ ] The Team ID is in `fastlane/Appfile`, `fastlane/ExportOptions.plist` and the build lane. For
      signing from Xcode instead, it goes in `Config/Signing.local.xcconfig` (§2). `project.yml`
      never holds a team.
- [x] **GitHub App for Copilot usage** (1.1 spec §4.2, owner task O1, done 2026-09-25):
      "Headroom for Mac", owner @niomartinez, App ID 5071739, **Client ID `Iv23liEA5ZycifEXDZCT`**,
      settings at https://github.com/settings/apps/headroom-for-mac. Public (any account can
      authorize it), account permission **Plan: read-only** and nothing else, device flow on,
      expiring user tokens on, webhook off, no callback URL. No client secret and no private key
      exist, and none may be generated: the device flow needs neither.
  - The Client ID isn't a secret. It is `HEADROOM_GITHUB_CLIENT_ID` in `project.yml`, which puts it
    in Info.plist (`HeadroomGitHubClientID`) and picks the entitlements with `network.client` (§3).
  - **If the GitHub App is deleted or its Client ID changes, Copilot sign-in breaks for every
    installed copy until an update ships with the new ID.** Keep the app on Nio's account.
  - Shipping without Copilot usage (the spec's fallback): set `HEADROOM_GITHUB_CLIENT_ID` to empty.
    The build then drops `network.client`, Settings shows no Connect GitHub, and the store text must
    drop the GitHub/network lines (description, release notes, review notes, website).

## 2. Signing and building

**With fastlane** (the normal route): `fastlane mac build` runs `xcodegen generate`, archives Release
with `DEVELOPMENT_TEAM=L237BMXGB6 CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development"
HEADROOM_APP_GROUP=YES` on the command line (outranking the xcconfig defaults below, for the app and
the widget extension alike) and `-allowProvisioningUpdates` with the API key
(`-authenticationKeyPath`, `-authenticationKeyID`, `-authenticationKeyIssuerID`), then exports
`build/export/Headroom.pkg` with `fastlane/ExportOptions.plist` (method `app-store-connect`,
automatic signing) and runs `scripts/verify-build.sh --group YES` on the .pkg. The build number is
one more than App Store Connect's newest for the version unless `build_number:` is given.
`fastlane mac check` archives the same Release build ad hoc (`CODE_SIGN_IDENTITY=-`,
`HEADROOM_APP_GROUP=NO`), without Apple, and runs `verify-build.sh --group NO` on it.

**From Xcode or `scripts/build-app.sh`**: signing for the app and widget targets lives in `Config/`,
not in `project.yml`:

| Configuration | Signing |
|---|---|
| Debug | Always ad-hoc (`CODE_SIGN_IDENTITY = -`), from `Config/Headroom-Debug.xcconfig`. No App Group. |
| Release | Ad-hoc by default, from `Config/Headroom-Release.xcconfig`, so `scripts/build-app.sh Release` works without a team, and without the App Group. When `Config/Signing.local.xcconfig` exists, its values replace the defaults. |

**Keep development and production menu-bar identities separate.** Debug is Headroom Dev
(`com.niomartinez.headroom.dev`), with widget bundle `com.niomartinez.headroom.dev.widgets` and
its own panel URL scheme. Release retains both production identifiers. Install the verified
Release archive in Applications and open it through Finder; launching it from an agent or IDE
can leave macOS associating its menu-bar permission with that launcher. Do not register a
worktree build at login. Settings > General links to the website's missing-pill troubleshooting.

**The App Group only on team-signed builds.** A group claimed without a Team ID is rejected, the
widget exits and the app can hang (1.1 spec §5.1). `HEADROOM_APP_GROUP` (default `NO`, in
`Config/Headroom-Variants.xcconfig`) picks the entitlements: `YES` comes from `fastlane mac build`
and from `Config/Signing.local.xcconfig`; Debug, ad-hoc Release and `fastlane mac check` stay `NO`.
At runtime `WidgetShare.groupIdentifier()` also checks the signed entitlements, so a build without
the group never touches the container.

`Signing.local.xcconfig` is git-ignored (`Config/.gitignore`), so a Team ID never lands in the
repository. Leave `DEVELOPMENT_TEAM`, `CODE_SIGN_STYLE` and `CODE_SIGN_IDENTITY` in `project.yml`
alone: the ad-hoc values there only sign the logic test bundle, and the same keys set on the
`Headroom` target there would override the xcconfig files.

- [ ] `cp Config/Signing.example.xcconfig Config/Signing.local.xcconfig`. It sets `DEVELOPMENT_TEAM`,
      `HEADROOM_APP_GROUP = YES` and automatic signing (`CODE_SIGN_STYLE = Automatic`,
      `CODE_SIGN_IDENTITY = Apple Development`), which needs your Apple ID in Xcode › Settings ›
      Accounts; Xcode creates and renews the profiles, and `scripts/build-app.sh Release` passes
      `-allowProvisioningUpdates` whenever the local file exists. Archive › Distribute App re-signs
      for the store. Manual signing (1.0's option B) no longer fits: the file applies to the app and
      the widget extension alike, and one `PROVISIONING_PROFILE_SPECIFIER` can't name both profiles.
- [ ] Check what Release resolves to:
      `xcodebuild -project Headroom.xcodeproj -target Headroom -configuration Release -showBuildSettings | grep -E ' (DEVELOPMENT_TEAM|CODE_SIGN_STYLE|CODE_SIGN_IDENTITY|HEADROOM_APP_GROUP|HEADROOM_GITHUB_CLIENT_ID) = '`
      (run `xcodegen generate` or `scripts/build-app.sh` first). Debug must still show `-`.
- [ ] Bump `MARKETING_VERSION` (user-visible) in `project.yml` for every new version, never on the
      widget target: the app and the extension must match. The build number
      (`CURRENT_PROJECT_VERSION`) must increase with every upload; `fastlane mac build` takes care of
      it.
- [ ] Archive and upload: `fastlane mac build`, then `fastlane mac upload` (deliver with `pkg:`, or
      `altool:true` for `xcrun altool --upload-app` with the same key). By hand: Xcode › Product ›
      Archive › Distribute App › App Store Connect, which reads the local signing file.
- [ ] Check the build with `scripts/verify-build.sh [--group YES|NO] <Headroom.app | Headroom.pkg>`
      (both fastlane lanes run it). It replaces 1.0's manual `codesign -d --entitlements` check and
      fails unless: `Contents/PlugIns` holds exactly `HeadroomWidgets.appex`; app and extension carry
      the same version and build, and the version is `project.yml`'s; the signed entitlements are
      exactly the chosen variant's (§3), with `network.client` if and only if Info.plist's
      `HeadroomGitHubClientID` is set; team-signed builds carry only the two identifiers the profile
      adds (`com.apple.application-identifier`, `com.apple.developer.team-identifier`) and no
      `get-task-allow`; `HeadroomAppGroup` in both Info.plists names the claimed group; every
      embedded profile authorizes the group and the bundle's application identifier; both bundles
      have the hardened runtime and pass `codesign --verify --deep --strict`.
- [ ] Install through TestFlight for Mac and run the grant flows and the widgets once (1.1 spec
      §11.2, L5): TestFlight builds are signed like the store build, so the sandbox and the App
      Group behave the same. `pluginkit -m -v -i com.niomartinez.headroom.widgets` should print
      exactly one line, and `log stream --predicate 'process == "containermanagerd" OR process ==
      "chronod"'` should show no `REJECTED`.

## 3. Sandbox entitlements and why each is needed

Debug uses `App/Headroom-Debug.entitlements`, which is not sandboxed so the app can be tested
without clicking through open panels. Release picks one of four app variants, and one of two for the
widget extension, in `Config/Headroom-Variants.xcconfig`: the App Group comes with
`HEADROOM_APP_GROUP = YES`, and `network.client` with a non-empty `HEADROOM_GITHUB_CLIENT_ID`.

| File | Used for | Entitlements |
|---|---|---|
| `App/Headroom.entitlements` | **The store build**: team-signed, Copilot usage on | the three sandbox keys + App Group + `network.client` |
| `App/Headroom-Offline.entitlements` | team-signed, no Client ID | the three sandbox keys + App Group |
| `App/Headroom-NoGroup.entitlements` | ad-hoc Release, `fastlane mac check` | the three sandbox keys + `network.client` |
| `App/Headroom-NoGroup-Offline.entitlements` | ad-hoc, no Client ID (1.0's set) | the three sandbox keys |
| `Widgets/HeadroomWidgets.entitlements` | the extension, team-signed | `app-sandbox` + App Group |
| `Widgets/HeadroomWidgets-NoGroup.entitlements` | the extension, Debug and ad-hoc | `app-sandbox` |

| Entitlement | Why |
|---|---|
| `com.apple.security.app-sandbox` | Required for the Mac App Store (app and extension). |
| `com.apple.security.files.user-selected.read-write` | The user grants folders in an open panel: the Claude app's folder (only when the Claude desktop app is installed) and `~/.codex` (only when Codex is installed and the user tracks it), both bookmarked read-only (`securityScopeAllowOnlyReadAccess`); `~/.claude` read-write, because the optional Connect terminal edits `~/.claude/settings.json` and writes `~/.claude/headroom/bridge.sh`, only after a confirmation dialog; and `~/.copilot` read-write, only when the user clicks Connect sessions, which writes `~/.copilot/hooks/headroom.json` and `~/.copilot/headroom/`. |
| `com.apple.security.files.bookmarks.app-scope` | Remembers the grants across launches (security-scoped bookmarks in the app's UserDefaults). App-scoped bookmarks can't be resolved by the widget extension, which is why the widgets read only the app's summary file. |
| `com.apple.security.application-groups` = `[$(TeamIdentifierPrefix)com.niomartinez.headroom]` | The app writes a small, scrubbed summary (`widget-snapshot.json`: limits, and sessions without pids, paths or, if the user hides them, names) into the group container; the widget extension only reads it (1.1 spec §5). Team-signed builds only (§2). |
| `com.apple.security.network.client` | Copilot usage (1.1 spec §4): only after the user clicks Connect GitHub, Headroom talks to `github.com` (device-flow sign-in and token refresh) and `api.github.com` (this month's usage, about every 15 minutes). There if and only if the GitHub Client ID is set; the widget extension never has it. |

There are no temporary exceptions, no network server entitlement, no Apple Events, no Accessibility
and no login items helper. Launch at login uses `SMAppService.mainApp`, which needs no entitlement.
The Keychain item for the GitHub token needs no entitlement either: Headroom tries the data
protection keychain first and falls back to the login keychain on ad-hoc builds (1.1 spec §4.3).
Clicking a session (1.1 spec §14.3) opens `claude://` and `codex://` links or brings the session's
terminal app forward through Launch Services (`NSWorkspace`): no entitlement, no Apple Events.

## 4. Privacy

- [ ] `App/PrivacyInfo.xcprivacy` ships in the app, unchanged from 1.0: `NSPrivacyTracking` false,
      no tracking domains, no collected data types. Required-reason APIs:
  - File timestamp: `3B52.1` (modification dates of files inside folders the user granted:
    `~/.claude`, the Claude app's folder, `~/.codex` and `~/.copilot`, used to re-read files only
    when they change) and `C617.1` (files in the app's own container and its App Group container).
  - UserDefaults: `CA92.1` (the app's own settings and folder bookmarks; no shared suite).
  - Reviewed for 1.1: the new code calls no other required-reason API. Process lookups (`sysctl`,
    `proc_pidinfo`), Keychain and URLSession aren't on Apple's list, and `clock_gettime_nsec_np`
    (ContextKit) already shipped in 1.0.
- [ ] `Widgets/PrivacyInfo.xcprivacy` ships in the widget extension: `NSPrivacyTracking` false, no
      domains, no collected data types and no required-reason APIs. The widgets decode one JSON file
      from the group container and take its age from `writtenAt` inside it, never from file dates.
      If they ever read file dates or sizes, add FileTimestamp `C617.1`.
- [ ] **App Store Connect › App Privacy: Data Not Collected** (browser, §0), re-confirmed for 1.1.
      Why this stays true with GitHub sign-in: Apple counts data as collected when it leaves the
      device in a way the developer or its partners can access. Headroom's GitHub traffic goes only
      between the user's Mac and GitHub, with the user's own sign-in, to fetch the user's own usage
      for display on that Mac. Nothing reaches the developer or anyone else, there is no Headroom
      server, no account and no analytics, and the token stays in the user's keychain. The privacy
      policy says so (1.1 spec §8).
- [ ] **Sign in with Apple** isn't required (guideline 4.8): Connect GitHub signs in to a specific
      third-party service to read the user's own data there, and creates no Headroom account.
- [ ] **Export compliance** stays "no non-exempt encryption" (`ITSAppUsesNonExemptEncryption = NO`,
      and `fastlane mac submit` answers the same): the only encryption is HTTPS to GitHub through
      Apple's URLSession, which is exempt.
- [ ] Privacy policy URL (required for every app): https://headroom.niomartinez.com/privacy
      (`fastlane/metadata/en-US/privacy_url.txt`). For 1.1 it adds what the app reads in `~/.codex`
      (never `auth.json` or config) and `~/.copilot`, what it writes (the widget summary in the group
      container, the Copilot CLI hook files, the GitHub token in the keychain), and exactly what goes
      to GitHub and when. **Deploy it before submitting 1.1**: reviewers read it.

## 5. Naming and trademarks

- [ ] The app name, subtitle, icon, keywords, screenshots and promotional text don't use "Claude",
      "Anthropic", "OpenAI", "Codex", "GitHub", "Copilot" or their logos (App Review Guidelines
      5.2.1, 2.3.7). `scripts/release/check-metadata.rb` refuses those and other companies' names
      (ChatGPT, GPT, Apple, Mac, …) in the name, subtitle, keywords and promotional text. The
      screenshots name the tools only nominatively ("Works with Claude Code." under the fourth
      caption, Codex and Copilot in the sixth) and otherwise only in the app's own UI text. No
      third-party logo appears anywhere; tools are named in text.
- [ ] Name **"Headroom: AI Usage Meter"** (1.1; Nio's choice, replacing "Headroom: AI Coding Meter"),
      subtitle "Your limits, one glance away". Headroom is about AI usage and plan limits, not only
      coding (1.1 spec §14.7): Claude's limits cover chat, Cowork and Claude Code. `check-metadata.rb`
      refuses "AI coding" in the listing and the review notes.
- [ ] The description says what Headroom works with, nominatively ("Works with Claude Code, the
      Claude desktop app, OpenAI Codex and GitHub Copilot."), describes only what the submitted build
      contains, discloses the widget extension (guideline 4.4), and ends with "Headroom is an
      independent app. It isn't made by, affiliated with or endorsed by Anthropic, OpenAI or GitHub."
      plus the three trademark lines. `check-metadata.rb` refuses a non-affiliation line that leaves
      out OpenAI or GitHub while the description names Codex or Copilot. The app shows the notice in
      Settings › About and in both bundles' copyright string, "© 2026 Nio Martinez. Headroom isn't
      made by or affiliated with Anthropic, OpenAI or GitHub."
- [ ] If Copilot doesn't ship (no Client ID and no Copilot CLI), the listing, website and review notes
      drop Copilot entirely (1.1 spec §0).
- [ ] The icon (`scripts/make-icon.swift`) is an original two-ring gauge and uses no third-party
      artwork. The website's Copilot card uses a neutral stacked-bars glyph, not a face.

## 6. Screenshots and metadata

Everything the listing says lives in `fastlane/`, and `fastlane mac metadata` uploads it (never
submitting):

| File | Content |
|---|---|
| `metadata/en-US/name.txt` | Headroom: AI Usage Meter |
| `metadata/en-US/subtitle.txt` | Your limits, one glance away (≤ 30) |
| `metadata/en-US/promotional_text.txt` | ≤ 170 characters, no trademarks |
| `metadata/en-US/description.txt` | ≤ 4000; only what the build contains; the widgets; the non-affiliation and trademark lines |
| `metadata/en-US/keywords.txt` | ≤ 100, comma separated, no trademarks or other apps' names, no word of the name or subtitle again (1.1 drops "usage", now in the name) |
| `metadata/en-US/release_notes.txt` | New in 1.1: Codex, Copilot usage, Copilot CLI, widgets, the rings' tool, click to open, "needs you" until seen, the ring key, the startup-dialog fix |
| `metadata/en-US/{support,marketing,privacy}_url.txt` | headroom.niomartinez.com `/support`, `/`, `/privacy` |
| `metadata/copyright.txt` | 2026 Nio Martinez (App Store Connect adds the ©) |
| `metadata/{primary,secondary}_category.txt` | DEVELOPER_TOOLS, PRODUCTIVITY |
| `metadata/review_information/notes.txt` | Notes for App Review (§7), ≤ 4000 |
| `rating_config.json` | 4+: every content level NONE, every yes/no question false |
| `screenshots/en-US/*.png` | 7 screenshots, 2880×1800 |

- [ ] `ruby scripts/release/check-metadata.rb` passes (the metadata lane runs it first): lengths,
      trademarks, keywords that repeat the name or subtitle, "AI coding", the non-affiliation line,
      URLs, categories, copyright format, the rating, screenshot sizes and no alpha.
      `--self-test` checks that the script catches each kind of mistake.
- [ ] Screenshots and every other product image: `scripts/release/refresh-marketing-assets.sh`
      renders them with `headroom-render --store`, `--assets` and `--marketing` from synthetic data
      only (`HeadroomSamples`): no real session names, project paths or prompt text. It copies them
      to `fastlane/screenshots/en-US`, `marketing/assets`, `marketing/social/1.1/snippets` and the
      website (screenshot JPEGs with phone crops, the snippets, the hero panel), then runs
      `check-metadata.rb`. Re-run it after any UI change (the 1.1 feedback work, spec §14, changes the
      panel and the pill) and look at every PNG before uploading. Each screenshot is a procedural dark
      desktop (no wallpaper, no third-party logos), a menu bar with neutral glyphs and the pill, the
      open panel or the widgets, and a caption:
      1. "Your AI limits, one glance away." (the panel, and what the two rings mean)
      2. "Every session, working or waiting." (Working / Needs you / Idle, context bars)
      3. "Know before you hit the limit." (amber and red, the 90 % moment in the menu bar)
      4. "Desktop app and terminal." (terminal sessions, Settings › Terminal connected)
      5. "No account. Local by default." (no account; only Copilot usage talks to GitHub; no data
         collected)
      6. "More tools, one panel." (the multi-tool panel with Codex and Copilot rows, sample data)
      7. "Widgets for your desktop." (small Limits, medium and large Sessions widgets)
      `headroom-render <dir>` renders every pill, panel and widget state on gray for review,
      including sample data mode.
- [ ] Category: Developer Tools (matches `LSApplicationCategoryType`), secondary Productivity.
- [ ] Age rating: `fastlane/rating_config.json`, uploaded by `fastlane mac metadata`.

## 7. Notes for App Review

No test account is needed: Headroom has no account and no server. Copilot usage needs the
reviewer's own GitHub account and is optional; sample data mode shows it without one. The notes App
Review gets are `fastlane/metadata/review_information/notes.txt` (≤ 4000 characters, checked),
uploaded by `fastlane mac metadata` and again by `fastlane mac submit`. For 1.1 they cover:

- What Headroom is, in terms of AI usage and plan limits (Claude's limits cover chat, Cowork and
  Claude Code; Codex's limits; Copilot's monthly usage), and that no demo account is needed.
- Menu bar only: no Dock icon, Settings opens on first launch and when Headroom is opened again.
- **Settings › General › Show sample data** (or "Preview with sample data" in the empty panel): the
  pill, panel and widgets show every tool with made-up data.
- Folder access in Settings › Tools: `~/.claude` (read-write only for Connect terminal), the Claude
  app's folder and `~/.codex` (read only), `~/.copilot` only for Connect sessions.
- **CODEX:** read-only `~/.codex`, never Codex's sign-in file, no connection to OpenAI.
- **COPILOT:** Connect GitHub with GitHub's device flow and Headroom's own GitHub App (Plan: read),
  GitHub's documented billing API every 15 minutes, the app's only network use and the reason for
  `network.client`; tokens in Headroom's keychain item, nothing sent to the developer.
- **CONNECT TERMINAL and CONNECT SESSIONS:** optional, a confirmation dialog listing every change,
  a backup of `~/.claude/settings.json`, Copilot CLI's documented user hooks in their own file,
  scripts bundled in the app (never downloaded) that record no prompts, Disconnect removes exactly
  what was added.
- **WIDGETS:** how to add them, that they read only the summary in Headroom's App Group container, no
  other files, no network, no data collected; "Sample data" with sample data on; a click opens the
  panel.
- **OPENING SESSIONS:** "Clicking a session opens it with standard URL schemes (claude://, codex://)
  or brings its terminal app forward; no Apple Events or Accessibility."

The contact (first and last name, phone, email) is read from `HEADROOM_REVIEW_FIRST_NAME`,
`HEADROOM_REVIEW_LAST_NAME`, `HEADROOM_REVIEW_PHONE` and `HEADROOM_REVIEW_EMAIL` when uploading
(`fastlane/.env.example`), so it never lands in the repository; `submit` refuses to run without it.

### Sample data mode

A reviewer's Mac probably has none of Claude Code, the Claude app, Codex or Copilot, so Headroom has
a sample data mode (`SampleDataMode` in the app, the snapshots in
`Packages/HeadroomKit/Sources/HeadroomSamples`):

- Turned on by Settings › General › **Show sample data**, or by **Preview with sample data**, which
  the panel's empty state offers when Headroom found no Claude data at all (neither folder
  readable, no sessions, no usage). Remembered across launches (`showSampleData` in UserDefaults).
- While it's on, the pill and panel show made-up sessions in every state for all three tools (1.1
  spec §6.5: Claude's limits, Codex Plus at 5-hour 20 % and weekly 94 %, Copilot Pro at 512 of 1,500
  credits, a Codex session), relative to the current time; the panel footer reads **Sample data ·
  Turn off**, VoiceOver says "Showing sample data", and the widgets show the same data with the
  footer "Sample data". The 2 s poll reads no files, no moments are shown, Copilot isn't polled,
  clicking a session opens nothing, and "needs you" doesn't stay in the menu bar. A folder grant or
  Connect terminal still checks the real folders so Settings stays true, and the panel's Connect /
  Disconnect terminal item follows the real bridge. When Headroom launches with sample data on, the
  first tick checks the real folders and the terminal bridge once for the same reason (otherwise
  Settings › Terminal would say "Checking…" for good); nothing that check reads is shown.
- Turning it off shows the last real snapshot at once and polls; the first real poll is a fresh
  baseline for moments, so nothing that changed meanwhile is announced.
- `Headroom --render-live` ignores the setting and always renders real data.

Optionally attach a short screen recording of the folder grant flow, Connect terminal and the
widgets (App Review Information › Attachment) made with sample data or a spare macOS user, never
with real sessions on screen.

## 8. Known review risks

- **2.4.5(iv), installing code.** Connect terminal writes a small shell script (bundled in the app
  as source, never downloaded) that Claude Code runs as its status line and hooks. It's opt-in,
  explained in a dialog before anything changes, and fully reversible. Say so in the notes, as
  above. If review objects, the fallback is to ship Connect terminal only in a notarized direct
  download and keep the store build read-only (it would then need only
  `files.user-selected.read-only`).
- **2.5.2 and 2.4.5(i), (ii), changing another app.** The same feature edits another app's
  configuration directly (`~/.claude/settings.json`: a `statusLine` plus hooks for the seven Claude
  Code events in `BridgeInstaller.hookEvents`) instead of through an API, and puts a script in a
  location another app reads (`~/.claude/headroom/bridge.sh`), which Claude Code then runs on
  every hook event and status line refresh. That is code that changes another app's
  functionality (2.5.2), another app's data modified without an API made for it (2.4.5(i)) and
  code installed in a shared location (2.4.5(ii)). The answer is the one above: opt-in, a dialog
  that lists every change first, a backup, and Disconnect. The fallback is the same too.
- **Code that keeps running after the app is deleted.** Only Disconnect removes the entries from
  `~/.claude/settings.json`, so if someone deletes Headroom.app while connected, Claude Code keeps
  starting the bridge on every hook event and status line refresh. Reviewers look for this under
  2.4.5(iii) ("processes that continue to run without consent"). The Connect dialog, the review
  notes (§7) and the README tell users to Disconnect before deleting Headroom, and the bridge
  stops collecting anything once Headroom is gone:
  - Every run first checks that Headroom is still installed, meaning that one of these exists: the
    app bundle at the path Connect records in `~/.claude/headroom/app-path`,
    `/Applications/Headroom.app`, or the app's sandbox container
    `~/Library/Containers/com.niomartinez.headroom` (bridge version 5; version 4 checked the
    pre-release bundle ID's container and reads as outdated, so Connect updates it). When none does, the bridge writes and
    deletes nothing: a hook run exits at once, and a status line run only runs the user's own
    status line, if they had one before connecting, and otherwise prints nothing (spec §2.4).
    All that's left is a short bash start-up per event, until the user removes the entries or
    reinstalls Headroom and chooses Disconnect. The App needs no code for this: Connect (SetupKit)
    records the path, and the check is in `bridge.sh` itself.
  - The installed commands are no-ops without the script (the `[ ! -f … ] ||` guard, see
    "Sandbox file quarantine" below), so deleting `~/.claude/headroom` also silences them.
  - While Headroom is installed, what the bridge writes stays small: SessionEnd deletes a
    session's files and SessionStart prunes files older than 7 days.
  - Moving an app to the Trash doesn't delete its container, and while the container exists the
    bridge still counts Headroom as installed, so it keeps writing until the user deletes the
    container too. What to tell App Review, if asked: "If Headroom is deleted without
    disconnecting, the script it added stops collecting anything once Headroom and its data
    (its container, `~/Library/Containers/com.niomartinez.headroom`) are gone: each run checks
    for them first and otherwise exits without writing, only running the status line the user had
    before connecting, if any. Reinstalling Headroom and choosing Disconnect removes the entries."
  - [ ] On the TestFlight build, delete the app from Launchpad, and separately with Finder › Move
        to Trash, and check each time whether the container is still there. Once the app and the
        container are gone, start a new `claude` session and check that nothing in
        `~/.claude/headroom` changes and that a status line of the user's own still shows. Adjust
        the answer above to what you see.
- **Decision: the Mac App Store build keeps Connect terminal.** It therefore keeps
  `com.apple.security.files.user-selected.read-write` for `~/.claude` (§3), and the three risks
  above (2.4.5(iv); 2.5.2 and 2.4.5(i), (ii); code that keeps running) apply to it; the answers
  are the ones given for each. Only if App Review rejects the feature does the fallback in the
  first bullet apply: Connect terminal ships only in a notarized direct download, and the store
  build drops to `files.user-selected.read-only`.
- **`settings.json` linked outside `~/.claude` (App Sandbox).** Some people keep settings.json in
  a dotfiles repository and link it into `~/.claude`. The sandboxed build may open only the folder
  the user granted, so it can neither read nor edit a link target outside `~/.claude`. A link to
  another file inside `~/.claude` works, and the unsandboxed Debug build follows any link.
  Headroom never replaces, edits or removes the link. What the user sees:
  - Settings › Terminal: "Can't read ~/.claude/settings.json (settings.json links to
    <target>, outside the folders Headroom can access)", and no Connect button.
  - Connect terminal in the panel's gear menu: an alert, "Headroom couldn't connect the terminal",
    that says Headroom can't read the file, so it can't add its status line and hooks, and that
    nothing was changed. It doesn't show the Connect dialog and doesn't tell the user to fix the
    file, because the file is fine.
  - A Connect or Disconnect that runs before Headroom has noticed the link (right after the folder
    grant, say) fails with "~/.claude/settings.json links to <target>, outside the folders
    Headroom can access, so Headroom can't read or change it. Nothing was changed."
  - Sessions, context and limits still work. Only the terminal bridge is unavailable. A reviewer
    would see this only with such a setup, so the notes (§7) don't mention it.
- **2.4.5(iii), launching at login.** Off by default; the user turns it on in Settings.
- **Sandbox file quarantine.** Files a sandboxed app creates get the `com.apple.quarantine`
  attribute. The installed commands are
  `[ ! -f "$HOME/.claude/headroom/bridge.sh" ] || exec /bin/bash "$HOME/.claude/headroom/bridge.sh" statusline`
  for the status line and the same with `hook` for the hooks (`BridgeInstaller.statusLineCommand`
  and `hookCommand`). The `[ ! -f … ] ||` guard makes them no-ops when the script is missing
  (settings.json can reach a Mac without it, through dotfiles say, and Claude Code would otherwise
  report a hook error in every session), and `exec` hands the shell over to bash, so the bridge's
  parent is Claude Code. `bridge.sh` is always an argument to `/bin/bash`, never executed itself,
  so bash reads it as data and Gatekeeper never evaluates it. Test Connect terminal from the
  TestFlight build anyway.

**New in 1.1** (1.1 spec §13):

- **Connect sessions: the same three guidelines as Connect terminal** (2.4.5(iv), 2.5.2,
  2.4.5(i)/(ii)). It writes a bundled script to `~/.copilot/headroom/bridge.sh` and its own file
  `~/.copilot/hooks/headroom.json`, which Copilot CLI's documented user hooks run in every session.
  The answers are the same: opt-in, a dialog that lists every change, Headroom's own file (the user's
  Copilot settings stay untouched), Disconnect removes both. The hooks never include `preToolUse`
  (a failing command hook there would block the user's tools), always exit 0 within a 5 s timeout,
  record no prompts (Copilot sends prompt text to `userPromptSubmitted` and `sessionStart`; the
  bridge drops it), and do nothing once Headroom and its container are gone, like the terminal
  bridge. The fallback if review objects is also the same: drop Connect sessions from the store
  build (remove the `HEADROOM_COPILOT_CLI` define in `Packages/HeadroomKit/Package.swift` and
  `project.yml`, which compiles it out) and the Copilot CLI lines from the listing.
- **Network use in a "private" app.** 1.0 said "no network" everywhere; 1.1 talks to GitHub after
  Connect GitHub. The listing, review notes, privacy policy and website all say so ("No network
  connections, unless you connect GitHub to see Copilot usage"). `network.client` is in the build if
  and only if the Client ID is set, and `verify-build.sh` checks it.
- **The GitHub billing API and GitHub App tokens.** G1 passed (200 with `plan=read` for a GitHub App
  user token), but Nio's account returns no usage items, so the real item strings are unconfirmed.
  An unknown format shows as a status, never a guess. Organization-paid seats can't be read; the app
  says so ("No usage billed to you this month"; builds up to 1.1.0 (10) said "No usage billed to @… this
  month", which a long login cut off).
- **Granting `~/.codex` technically exposes `auth.json` to the process.** The bookmark is read-only,
  CodexKit builds paths only through `CodexPaths` and a test fails if its sources mention
  `auth.json`, `config.toml`, `.sqlite` or `flock`; the Settings caption and the review notes say
  Headroom never opens the sign-in file.
- **Widgets and the App Group.** A group claimed without a Team ID is rejected and the widget exits,
  so ad-hoc builds carry no group (§2) and `verify-build.sh` checks the store build's profiles. The
  kind strings (`com.niomartinez.headroom.limits`, `.sessions`) and the group id are permanent:
  changing them later orphans the widgets people have placed. Widgets refresh on macOS's budget
  (roughly 40–70 reloads a day), so they can lag the pill by 15–60 minutes; they show "as of" ages
  and "Headroom isn't running" instead of stale numbers.
- **Codex's local format is undocumented and changes often.** Decoding is lenient, windows map by
  their length, and a format Headroom doesn't recognise becomes "unknown format", never a guess.
- **`claude://code/continue` and `codex://threads/` are other apps' URL routes** (clicking a
  session). They are opened like any link, through Launch Services; if they stop working, the app
  just comes forward. No Apple Events, no Accessibility, no new entitlements.
- **1.1 can't be submitted while 1.0.0 waits for review** (§0): withdraw 1.0.0 and submit 1.1.0 in its
  place, per Nio's decision.

## 9. Before each upload

- [ ] `swift test` in `Packages/HeadroomKit`, and `scripts/test-app.sh` for the app's logic tests.
- [ ] `fastlane mac check`: the metadata check and an ad-hoc Release archive checked by
      `scripts/verify-build.sh --group NO`, without Apple.
- [ ] `scripts/build-app.sh Debug`, then `scripts/smoke-test.sh` (requires Headroom Dev).
- [ ] Open the verified sandboxed Release from Finder and check its menu-bar item independently
      of the Claude and Codex menu-bar switches.
- [ ] After any UI change: `scripts/release/refresh-marketing-assets.sh`, then look at every image.
- [ ] The website's privacy page matches the build (Copilot network use on or off), and is deployed
      before the submission.
- [ ] Look at the live UI without screenshots: `scripts/build-app.sh Debug`, then
      `build/Headroom.app/Contents/MacOS/Headroom --render-live /tmp/headroom-live`. It polls real
      data for about 5 s, writes `live-pill.png` (plus `live-pill-moment.png` when a moment is
      showing or queued), `live-panel.png` and `live-snapshot.json`, and quits. It never shows the
      pill, the panel or onboarding. A sandboxed Release build can only write inside its container.
- [ ] Manual pass of the sandboxed build: grant the Claude folders and `~/.codex`, quit and relaunch
      (the grants must persist), Connect GitHub and Disconnect (the keychain item goes), Connect and
      Disconnect under Session activity against a spare `~/.copilot`, add each widget and check "Sample data"
      with sample data on, Connect and Disconnect against a spare macOS user's `~/.claude` (check the
      `settings.json.headroom-backup` file), Connect with that user's settings.json linked to a
      file outside `~/.claude` (expect the messages in §8, and the link untouched), Launch at
      login from `/Applications`, and a run on macOS 14, the deployment target.
