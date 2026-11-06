# Marketing assets

Rendered from made-up data (`Packages/HeadroomKit/Sources/HeadroomSamples`), never from a real
Mac's sessions. Regenerate everything, the App Store screenshots and the website's images included,
with `scripts/release/refresh-marketing-assets.sh`.

| File | What |
|---|---|
| `assets/pill-*@3x.png` | The menu bar pill at 3× (66 px tall = 22 pt), transparent: `calm`, `working`, `working-two`, `waiting` (a session needs you), `near-limit` (amber number), `critical` (red), and the widened moments `moment-finished`, `moment-input`, `moment-limit`. |
| `assets/panel-*@2x.png` | The dropdown panel at 2× (720 px wide = 360 pt), transparent corners: `overview`, `near-limit`, `calm`. |
| `assets/app-icon-1024.png` | The app icon, 1024 px (from `App/Assets.xcassets`). |
| `social/1.1/snippets/snippet-*@2x.png` | The 1.1 feature snippets at 2×, transparent: `codex` (panel with the Codex row and sessions), `copilot` (Copilot row and the GitHub account setting), `widgets` (the three widgets). The website's "New in 1.1" cards and the social posts use them. |
| `social/1.1/captions.md` | Suggested captions for the 1.1 posts. |
| `../fastlane/screenshots/en-US/*.png` | The seven App Store screenshots, 2880×1800. |

Colors, for matching a page to the app: pill `#000000`, panel `#111111`, text `#F1EFE8`, secondary
text `#888780`, working `#5DCAA5`, waiting and warning `#EF9F27`, critical `#E24B4A`, idle
`#5F5E5A`, ring track `#444441`. The working dot's pulse: a ring that grows to 2.6× the dot and fades out over 1.6 s,
repeating.
