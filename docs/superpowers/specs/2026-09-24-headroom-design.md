# Headroom — design spec

2026-09-24 · status: built; see docs/app-store.md for release

Headroom is a macOS menu bar app that shows, at a glance, how much of your Claude plan you have
left and which Claude Code sessions are running. It is a native Swift app built to Mac App Store
rules from day one. "Headroom" is a working name: the App Store name, icon and copy must not use
"Claude" or Anthropic's marks (nominative "works with Claude Code" in the description only).

## 1. What the user sees

### 1.1 The pill (menu bar, always visible)

A black capsule in the menu bar, styled like an iPhone Live Activity shown in the macOS Tahoe menu
bar.

```
 ( ● 2  ◎ 89% )
   │ │  │  └─ number of the tightest limit, only when it is ≥ 75 %, colored by severity
   │ │  └──── two-ring gauge: OUTER ring = weekly limit, INNER ring = 5-hour limit
   │ └─────── count of active sessions (working + waiting); hidden when 0
   └───────── status dot: pulsing green = some session working, steady amber = some session
              needs input (wins over green), steady gray = all idle / none
```

- Height 22 pt, horizontal padding 9 pt, 7 pt gaps, 12 pt medium monospaced-digit text.
- Ring gauge: 18 pt box. Outer ring radius 7, inner radius 3.5, line width 2, round caps, starts at
  12 o'clock, clockwise. Track color `#444441`.
- Severity colors (limits): normal `#F1EFE8` (off-white), warning (≥ 75 %) `#EF9F27` amber,
  critical (≥ 95 %) `#E24B4A` red. Context bars use warning ≥ 75 %, critical ≥ 90 %.
- Working dot: `#5DCAA5` with a ring that expands to 2.6× and fades over 1.6 s, repeating.
  Waiting dot: `#EF9F27`, no pulse. Idle dot: `#5F5E5A`.
- Stale data (newest reading older than 30 min): rings drawn at 45 % opacity.
- No data at all: rings show only tracks, no number.
- Moments: on an event the pill briefly widens (spring animation) to show an SF Symbol and a short
  text for 4 s, then returns. Events: a session finished (working → idle), a session needs input,
  a limit crossed 90 % or reached 100 %. Queued, one at a time, can be turned off in Settings.

### 1.2 The panel (click the pill)

A dark panel (always dark: background `#111111`, corner radius 18, width 360, padding 14/16) drops
below the pill. Click outside or press Esc to close.

1. Header: a 72 pt version of the ring gauge (line width 5, outer r 26, inner r 17 in a 64-unit
   viewBox) next to two rows:
   - `Weekly` … `89%` (colored by severity), sub-line `resets Sun 7 PM` (exact) /
     `resets ~Sun 7 PM` (inferred) / plus ` · as of 42m ago` when stale.
   - `5-hour` … `14%`, sub-line `resets in 2h 50m` / `resets ~in 2h 50m` / `not started`.
   - If extra usage is reported and > 0: a small `Extra usage 12%` line.
2. Sessions, grouped: `Working`, `Needs you`, `Idle` (section labels 11 pt gray `#888780`). Row: status dot,
   name, project folder (11 pt gray; omitted for scratch workspaces or when equal to the name),
   a small `terminal` SF Symbol for terminal sessions, a 44×4 pt context bar and the percentage
   (a token count without a percent when the window size is only assumed, §2.3). Hover shows
   `724k of 1M tokens · claude-opus-5-5`. Idle sessions collapse to 3 with a `Show N more`
   toggle. Order inside a group: most recent activity first.
3. Empty states: no sessions → `No Claude Code sessions running`. Missing folder access → a row with
   a `Give access` button.
4. Footer: left, 11 pt gray: `Updated 2m ago · from the Claude app` (or `· from the terminal`);
   right, a gear menu: `Settings…`, `Connect terminal` / `Disconnect terminal`, `Quit Headroom`.

### 1.3 Settings window

Launch at login (SMAppService), Show moments, folder access status with `Grant access` buttons,
terminal connection (Connect / Disconnect + explanation), About (version, "Headroom isn't made by or
affiliated with Anthropic."). Opened automatically on first launch (onboarding).

## 2. Where the data comes from (verified on the developer's Mac, 2026-09-24)

| Shown | Desktop-app users | Terminal users | Source |
|---|---|---|---|
| Rings (5-hour, weekly) | automatic | after "Connect terminal" | §2.1, §2.4 |
| Sessions, dot, count | automatic | automatic with CLI ≥ 2.1.281, else after "Connect terminal" | §2.2, §2.5 |
| Context bars | automatic | as sessions | §2.3 (+ §2.4 exact window size) |

Mixed users get both; readings are merged (§3). Nothing here uses a login token or network call.

### 2.1 Claude desktop app usage history (desktop users, zero setup)

`~/Library/Application Support/Claude/plan-usage-history.json`, written by the Claude desktop app
about every 15 minutes while it runs:

```json
{"version":"2","samples":[{"t":1788802193411,"org":"<org uuid>","u":{"fh":8,"sd":87,"xu":null}}]}
```

- `t` epoch **milliseconds**; `fh` 5-hour % used; `sd` 7-day (weekly) % used; `xu` extra usage %
  (number or null). Values are integers today — parse as Double.
- Several orgs can appear (account switches). Use the org of the newest sample and only its samples.
- No reset times. Infer them (§3.2) and mark them estimated.
- `version` 2 expected — the current app writes it as a JSON **number**; accept the string "2" too.
  Unknown version or shape → `DataIssue.desktopUsageUnrecognized`, no rings from this source (never
  show wrong numbers). The file may be caught mid-write: keep the last good reading for up to 5 min
  before reporting the issue.
- `DataIssue.desktopFolderUnavailable` is reported only when the Claude desktop app is installed
  (`AccessState.desktopAppInstalled`) and its folder can't be read. Terminal-only users never see it.

### 2.2 Claude Code session registry (desktop and newer terminal sessions, zero setup)

`~/.claude/sessions/<pid>.json`, one per running session. Other files (`*.key`, sockets) live
there too: read only `*.json`.

```json
{"pid":46250,"sessionId":"<uuid>","cwd":"/Users/me/code/app","entrypoint":"claude-desktop",
 "kind":"interactive","name":"Fix login bug","status":"busy","startedAt":1790244362000,
 "statusUpdatedAt":1790249955821,"updatedAt":1790249955821,"version":"2.1.280",
 "procStart":"Thu Sep 24 10:06:01 2026","nameSource":"auto", "...": "..."}
```

- Include only entries whose `entrypoint` starts with `claude-desktop`, or equals `cli`.
  **Exclude** `sdk-cli`, `sdk-ts` and anything else: plugins (e.g. claude-mem) run background SDK
  sessions that register here.
- CLI 2.1.278 terminal sessions did not register here; CLI ≥ 2.1.281 does (entrypoint `"cli"`,
  kind `"interactive"`), with a name derived from the folder (`nameSource` `"derived"`, non-ASCII
  dropped plus a random suffix, e.g. `hr-e2e-caf-59` for `hr-e2e café`). The file is removed on a
  clean exit. `cli` entries are shown as terminal sessions, named as in §2.5.
- `status`: `busy` → working; strings containing `wait`, `permission`, `input` or `action` →
  waitingForInput; everything else → idle. Exception (1.1 §14.1): CLI ≥ 2.1.281 also writes
  `waitingFor` with a waiting status (`"permission prompt"`, `"input needed"`, `"sandbox request"`,
  `"goal proposal"`, `"dialog open"`; undocumented). `waiting` with `waitingFor` `"dialog open"`
  written less than 60 s after `startedAt` is a startup dialog → idle (a CLI can sit on one for
  hours); every other waiting, including unknown `waitingFor` values, stays waitingForInput.
- Also read: `version` (the Claude Code version) and, for desktop entries, `hostSessionId` (the
  desktop app's own `local_<uuid>` id, used by 1.1 §14.3's click-to-open).
- Liveness: `kill(pid, 0) == 0 || errno == EPERM`, and the pid must still be the session's
  process: `procStart` (Claude Code writes `LC_ALL=C TZ=UTC ps -o lstart=`, whole seconds UTC;
  `procStartFt` as fallback) must be within 2 s of the process start time (`sysctl`
  `KERN_PROC_PID` `p_starttime`). Without `procStart`, the process must have started no later than
  2 s after the entry's newest time (`startedAt`/`statusUpdatedAt`). If the start time cannot be
  read, `kill` alone decides. Skip entries that fail. A plugin (excluded) entry claims its pid only
  while its process holds it.
- Times are epoch milliseconds (`procStart` aside).

### 2.3 Transcripts (context %, everyone)

`~/.claude/projects/<encoded cwd>/<sessionId>.jsonl`. Directory names may start with `-`. Files can be
80 MB+: **read only the tail** (start with the last 256 KB, grow ×4 up to 8 MB until a usable line is
found). Scan lines from the end for:

```json
{"type":"assistant","isSidechain":false,"timestamp":"2026-09-24T12:36:01.123Z",
 "message":{"model":"claude-opus-5-5","usage":{"input_tokens":4,"cache_creation_input_tokens":1200,
 "cache_read_input_tokens":134000,"output_tokens":350}}}
```

- Skip `isSidechain == true`, missing usage, and `model == "<synthetic>"`.
- used tokens = input + cache_creation_input + cache_read_input + output.
- Window size, first match wins:
  1. exact `context_window_size` from that session's status line (§2.4);
  2. a size learned for the same model id from any status line;
  3. the model id ends with `[1m]` → 1,000,000;
  4. used tokens > 200,000, or a main-thread reply from the same model id has used > 200,000
     (earlier in this transcript's tail, up to 256 KB back, or in any transcript read since
     launch) → 1,000,000;
  5. the model id contains `fable-5`, `mythos-5`, `opus-5`, `sonnet-5`, `opus-4-6`, `opus-4-7` or
     `opus-4-8` → 1,000,000;
  6. Haiku (`haiku-4`, `3-5-haiku`, `3-haiku`) → 200,000;
  7. otherwise 200,000, assumed: shown as a token count without a percent
     (`ContextUsage.windowIsAssumed`).

  From rule 3 on, model ids are compared ignoring case. (Fable 5.x, Mythos 5.x, Opus 5.x and
  Sonnet 5 are 1M-only, and Claude Code runs Opus 4.6–4.8 at 1M; Haiku 4.5 has 200k.) Caveat:
  if the desktop app, which has no status line, runs Opus 4.6–4.8 at 200k, their context bars
  read too low until a status line reports the exact size for that model id.
- Cache results by (path, file size, mtime).

### 2.4 Terminal bridge — status line (terminal users, one-time setup)

Only terminal sessions run a status line command (the desktop app runs Claude Code headless and
never calls it — verified). Payload verified with CLI 2.1.278 (top-level keys): `context_window`,
`cost`, `cwd`, `exceeds_200k_tokens`, `fast_mode`, `model`, `output_style`, `prompt_cache`,
`prompt_id`, `rate_limits`, `scratchpad_dir`, `session_id`, `thinking`, `transcript_path`, `version`,
`workspace`.

```json
{"session_id":"<uuid>","transcript_path":"/Users/me/.claude/projects/-Users-me-app/<uuid>.jsonl",
 "cwd":"/Users/me/app","model":{"id":"claude-haiku-4-5","display_name":"Haiku 4.5"},
 "workspace":{"current_dir":"/Users/me/app","project_dir":"/Users/me/app"},
 "context_window":{"used_percentage":26,"context_window_size":200000},
 "rate_limits":{"five_hour":{"used_percentage":20,"resets_at":1790263800},
                "seven_day":{"used_percentage":90,"resets_at":1790506800}}}
```

- `resets_at` is epoch **seconds**. `rate_limits` is absent before the session's first API reply.
- `model` may be an object (`id`, `display_name`) or a string — accept both.

The bridge script writes (all atomic: a temp file `.<name>.<pid>.tmp` in the same dir, then
`mv -f`; a run stopped mid-write by HUP, INT or TERM removes its temp file, and the hooks clean
up the rest, §2.5):
- `~/.claude/headroom/statusline-latest.json` — the raw payload, only when it contains `"rate_limits"`.
- `~/.claude/headroom/sessions/<session_id>.statusline.json` —
  `{"v":1,"ts":<epoch s>,"pid":<claude pid>,"payload":<raw payload>}`.

It then prints the status line: if the user had their own status line before connecting, it runs
the command saved byte for byte in `~/.claude/headroom/original-statusline.cmd` (§2.6) with the
same stdin, the user's locale and stderr, and prints its output (nothing else); otherwise it
prints `5h 20% · wk 90% · ctx 26%` (omit parts it can't find).

The bridge (status line and hooks) never creates `~/.claude/headroom` (only Connect does, §2.6),
just `sessions/` inside it, so a run still in flight after Disconnect can't bring the folder back.
Once Headroom is uninstalled, that is when none of these exists: the app at the path Connect
recorded in `~/.claude/headroom`, `/Applications/Headroom.app`, the app's container
(`~/Library/Containers/com.niomartinez.headroom`), the bridge is a no-op: it writes nothing,
and the status line prints only the user's own chained status line, if any.

### 2.5 Terminal bridge — hooks (terminal users, one-time setup)

Hooks: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Notification`, `Stop`, `SessionEnd`.
(`PostToolUse` clears "needs you" after the user approves a permission prompt.)
Common payload fields: `session_id`, `transcript_path`, `cwd`, `hook_event_name`; `Notification`
adds `message` and (newer versions) `notification_type`. **Never persist prompt text.** The bridge
extracts only these string fields with a bash regex (value kept JSON-escaped, so it can be
re-embedded verbatim) and writes `~/.claude/headroom/sessions/<session_id>.hook.json`:

```json
{"v":1,"ts":1790250000,"pid":12345,"event":"Stop","session_id":"<uuid>","cwd":"/Users/me/app",
 "transcript_path":"/Users/me/.claude/projects/-Users-me-app/<uuid>.jsonl","notification_type":""}
```

- Event → activity: `UserPromptSubmit`, `PreToolUse`, `PostToolUse` → working; `Notification` by
  `notification_type` (1.1 §14.1): `permission_prompt`, `elicitation_dialog`,
  `elicitation_url_dialog`, `agent_needs_input`, or a missing/empty type (CLIs from before the
  field) → waitingForInput; `elicitation_complete`, `elicitation_response` → working;
  `idle_prompt`, `auth_success`, `agent_completed`, `quota_auto_resume_*` and unknown types →
  idle. `Stop`, `SessionStart` → idle; `SessionEnd` → delete `sessions/<id>.*`, that session's
  temp files included.
- A terminal session's activity dates from its newest hook event (`lastEventAt`), falling back to
  the status line's time only without one, so status line writes don't restart a waiting episode.
- Hooks print nothing, never fail (always `exit 0`), finish in < 100 ms, and never read stdin twice.
- Hooks also fire in desktop-app sessions. Merge by session id: registry data wins; a newer hook
  `Notification` of a needs-you type may upgrade the activity to waitingForInput. The hook's `ts`
  is whole seconds, so it counts as newer unless its whole second lies at or before the registry's
  `statusUpdatedAt`; when the entry reports waits itself (it has `waitingFor`, or `version` ≥
  2.1.281), a status written at or after the notification's second already covers it (1.1 §14.1). A bridge record is not shown on its own when
  its session id belongs to a shown registry session or a plugin entry, or its pid to a shown
  registry session or a plugin entry whose process still holds it (§2.2).
- Claude pid: walk up from `$PPID` (max 6 levels) to the first process whose `ps -o comm=` basename
  is `claude`; fall back to `$PPID`.
- On `SessionStart` prune files in `sessions/` older than 7 days, and the bridge's `.*.tmp` files
  (in `~/.claude/headroom` and `sessions/`) older than an hour.
- A terminal session is shown while its pid is alive and that process started no later than 2 s
  after the record's newest `ts` (a SIGKILLed session skips `SessionEnd` and leaves its files, and
  the pid may be reused); without a pid, while its newest `ts` is < 30 min old. When records share
  a pid, only the most recently written one is shown.
- Name for terminal sessions: the project folder name (last path component of `cwd`). A registry
  name with `nameSource` `"derived"` is ignored in favour of the folder name; real titles (`auto`,
  `user`, or no `nameSource`) are kept.

### 2.6 Installing the bridge ("Connect terminal")

Edits `~/.claude/settings.json` (create if missing), creates `~/.claude/headroom/` (mode 700) and
writes `~/.claude/headroom/bridge.sh`.
- Back up the original to `~/.claude/settings.json.headroom-backup` first (keep the first backup
  ever made; do not overwrite it).
- The installed commands are no-ops without the script (settings.json can reach a Mac without it,
  through dotfiles say) and otherwise `exec` the bridge, so its parent is Claude Code:
  `[ ! -f "$HOME/.claude/headroom/bridge.sh" ] || exec /bin/bash "$HOME/.claude/headroom/bridge.sh" statusline`
  and the same ending in `hook`.
- `statusLine` = `{"type":"command","command":<statusline command>}`, keeping the user's other keys
  (`refreshInterval`, `padding`, `hideVimModeIndicator`) from the entry it replaces; only `type`
  and `command` decide whether it is current. An existing different statusLine is saved to
  `~/.claude/headroom/original-statusline.json` (restored on Disconnect), and its command, byte for
  byte, to `~/.claude/headroom/original-statusline.cmd`, which the bridge runs (§2.4).
- For each hook event add (once) an entry `{"hooks":[{"type":"command","command":<hook command>,"timeout":5}]}`
  (plus `"matcher":""` for `PreToolUse` and `PostToolUse`). Leave all other hooks and keys untouched.
  Entries are recognised as Headroom's by the bridge path in their command, so ones written by
  older versions are repaired and removed too.
- Disconnect removes exactly what was added, restores the original statusLine, and deletes
  `~/.claude/headroom/`: it first renames it to `~/.claude/.headroom-removing-<uuid>`, so bridge
  runs still in flight can't write into it, then deletes that (and any copy an earlier Disconnect
  couldn't finish deleting).
- State detection: installed (status line and every hook current, script header
  `# headroom-bridge v<N>` with `N` at least the current `BridgeScript.version`), outdated (some
  entry present but not current, or an older or missing script), not installed, or settings
  unreadable.
- New hooks apply to sessions started after connecting; say so in the UI.
- Deleting Headroom without Disconnect leaves the entries in settings.json; the bridge then writes
  nothing (§2.4), but only Disconnect removes them.

## 3. Merging and inference rules

### 3.1 Plan usage
- Candidates per limit kind: the desktop reading (newest sample, §2.1) and the terminal reading
  (`statusline-latest.json`, observedAt = min(file mtime, timestamp of the newest assistant entry
  that is not `<synthetic>` in the payload's `transcript_path`, read from the tail like §2.3 but
  starting with the last 64 KB, subagent replies included); mtime alone when the transcript is
  missing or has no such entry). Claude Code re-runs the status line from cached rate limits
  without an API call (at the earliest `resets_at`, at prompt-cache expiry, on UI changes), so the
  mtime can be much newer than the numbers. The newest `observedAt` wins; ties go to the terminal
  reading.
- Reset time for a desktop winner: use the terminal reading's exact `resetsAt` if that window was
  still open at the desktop reading's `observedAt`, the desktop app was on the newest org from the
  sample nearest the terminal reading on (the newest at or before it, else the oldest; the
  terminal reading names no account), the last newest-org sample at or before the terminal
  reading, when it lies inside the terminal's window (`resetsAt` − 5 h / 7 d), is not a
  reset-sized amount (10 points weekly, 1 point 5-hour) above the terminal value, and the desktop
  history shows no reset-sized fall after the terminal reading; otherwise the inferred time
  (§3.2), `resetIsEstimated = true`. With no desktop samples, nothing is borrowed.
- After `resetsAt` passes: 5-hour → used 0, resetsAt nil ("not started"); weekly → used 0,
  resetsAt += 7 days (keeps its estimated flag). With `resetsAt` unknown, a reading a whole window
  (5 h / 7 d) old → used 0, reset still unknown.
- Stale when `now - observedAt > 30 min`.

### 3.2 Reset inference from desktop history (same org only)
Resets are inferred as of the newest sample (not `now`), so a reset that passed since the last sample
is rolled over by §3.1 instead of showing pre-reset usage next to the following reset.
- Weekly (revised after replaying the developer's real history, where a one-off mid-week reset on
  2026-09-22 did not move the Sunday 11:00 UTC schedule): every drop `sd[i] <= sd[i-1] - 10` is an
  event, estimated at `t[i-1]` rounded up to the next full hour, clamped to `≤ t[i]`. The anchor is the
  event estimate whose weekly repeats fall inside the most events' sample intervals (newest 52 events;
  ties → newest), with a check that a schedule whose predicted reset visibly did not happen is
  abandoned. Next reset = anchor + 7 days × k, first one after the newest sample. No event → nil.
  `UsageKit/WeeklyResetInference.swift` is the reference.
- 5-hour: newest `fh == 0` → no active window (nil). Otherwise walk back from the newest sample while
  the previous sample has `fh > 0`, did not fall at all (5-hour usage never falls inside a window, so a
  fall of ≥ 1 point is a reset), and is < 5 h earlier. The first sample of that run is `j`;
  start ≈ `t[j] - min(t[j] - t[j-1], 15 min) / 2` (or `t[j]` if `j` is the first sample);
  reset = start + 5 h. Known limit: late when the window started during a sampling gap.
- A reading whose reset is unknown (nil) but whose usage is > 0 shows "reset unknown", not
  "not started".

### 3.3 Sessions
Sort: working, then waitingForInput, then idle; inside a group by `activitySince` descending.

### 3.4 Moments (previous snapshot → current)
- `sessionFinished`: same id was working ≥ 5 s and is now idle.
- `sessionNeedsInput`: same id became waitingForInput.
- `limitCrossed`: a limit went from < 90 to ≥ 90 (percent 90) or from < 100 to ≥ 100 (percent 100),
  announcing only the highest one crossed. Both snapshots must have the reading, the current one
  a newer observation, and it must have risen by at most 25 points (more is a data correction).
  A desktop account switch never produces one: when the desktop org (§2.1) differs between the
  snapshots, two desktop readings are not compared.
- No moments on the first snapshot.

## 4. Architecture

```
Packages/HeadroomKit (SwiftPM, Swift 6 language mode, macOS 14+)
  HeadroomModel   value types, paths, thresholds — no I/O
  UsageKit        §2.1, §2.4 (limits), §3.1, §3.2
  SessionKit      §2.2, §2.5 (records), liveness, §3.3
  ContextKit      §2.3 transcript tail reading and window sizes
  SetupKit        §2.6 installer + the bridge.sh source as a Swift string
  HeadroomStore   SnapshotBuilder (composes the kits, caches), MomentDetector (§3.4)
  HeadroomUI      SwiftUI: RingGauge, PulsingDot, PillView, PanelView, formatters, theme
  headroom-dump   CLI: prints the live snapshot as JSON (verification against real data)
  headroom-render CLI: renders PillView/PanelView states to PNG with ImageRenderer
App/ (XcodeGen project.yml → Headroom.xcodeproj)
  NSStatusItem hosting PillView, borderless NSPanel hosting PanelView, Settings/onboarding,
  AccessManager (security-scoped bookmarks), polling loop, moments queue, launch at login.
```

- Polling: every 2 s on a background task; files are re-parsed only when (size, mtime) changed.
  Read size/mtime with `FileManager.attributesOfItem` (or `stat`), never `URL.resourceValues`, which
  caches per URL and returns a stale mtime in a long-lived poller without a run loop.
- Sandbox: Release builds are sandboxed (`app-sandbox`, `files.user-selected.read-write`,
  `files.bookmarks.app-scope`). The user grants `~/.claude` (read-write, needed for Connect terminal)
  and `~/Library/Application Support/Claude` (read) once via NSOpenPanel pre-pointed at the real
  home (`getpwuid(getuid())`, since `NSHomeDirectory()` is the container). Debug builds are not
  sandboxed and read the paths directly, so the app can be tested without clicking through panels.
- Privacy manifest (`PrivacyInfo.xcprivacy`): no tracking, no collected data; file timestamp API
  reason `3B52.1` (files the user granted access to) and `C617.1`.
- Failure handling: any unreadable/unknown source becomes a `DataIssue`; the UI hides numbers it
  can't trust instead of guessing.

## 5. Testing
- Unit tests (Swift Testing) per kit with **synthetic** fixtures (no real session names, paths or
  prompts). Required cases are listed per module in the build plan.
- `bridge.sh` tested by running it with `HOME` pointed at a temp dir and fixture payloads.
- `headroom-dump` run against the developer's real data; `headroom-render` PNGs reviewed by eye
  against the mockups; `Headroom --render-live <dir>` writes the live pill and panel as PNGs plus
  the snapshot as JSON, without showing any UI, for checking the running app by eye.
- App logic tests (`scripts/test-app.sh`) and a launch smoke test (`scripts/smoke-test.sh`).
- The installer is tested only against temp directories. It is never run against the developer's real
  `~/.claude` without their click.
