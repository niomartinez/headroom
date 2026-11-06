# Headroom — "what's new" motion graphic (45 s, 16:9)

The October 2 update as a motion piece: tool icons on every ring, organization-paid Copilot seats counted, and a
number for every warning. Sample data only. No skill: own pipeline, per the vault's `Practices/Motion Design.md`.

- **Idea:** three anonymous rings ("Which is which?") get their tool symbols stamped in, then pull back into the
  menu bar pill. The symbols fly into the panel, a struck-out "No usage billed…" turns into an Enterprise seat's
  credits on the second drop, and the three rings finally merge into the app icon.
- **Grid:** 120 BPM, 22.5 bars (45.0 s). Every cue is `at(bar, beat)` in `lib/timeline.js`; the pictures and the
  soundtrack both read it.
- **End card:** "Free on the Mac App Store". Post it only after Apple approves 1.1.0.

## Files

- `lib/timeline.js` cue sheet · `lib/engine.js` eases, spring, seeded noise, shake · `lib/ui.js` the app's UI in HTML/SVG
  (ring geometry and the centered-or-badge symbol rule from `RingGauge.swift`) · `scenes.js` `window.__render(t)`
- `audio.js` the soundtrack in Web Audio, rendered offline · `master.sh` ffmpeg mastering to -14 LUFS / -2 dBTP target
- `render.mjs` Playwright + ffmpeg: 60 fps, 6 sub-frames over a 180° shutter per frame, parallel browser workers
- `make.sh` audio → master → frames → mux → `out/headroom-whats-new-16x9.mp4` (TV-range yuv420p, BT.709; `out/` is not committed)

## Commands

```sh
export NODE_PATH="$(npm root -g)"          # Playwright is installed globally
./make.sh --workers 10                     # the whole piece (~10 min on 12 cores)
node render.mjs stills 4.1 18.2 40.7       # single frames → out/stills/
node render.mjs sheet 0 44 1               # one still per second: the reading-time check
open "http://localhost:<port>/index.html?preview"   # scrub with the soundtrack (serve the folder first)
```

The 1 fps sheet lands at about k + 0.45 s and misses hand-offs. Also check stills either side of every hard cut and
headline hand-off: `node render.mjs stills 1.95 2.05 31.95 32.02 33.95 34.02 35.95 36.02 37.95 38.02`. Montage
captions hold until their cut and leave with it (`cutAt`); the caption band is opaque so the UI never ghosts behind them.
