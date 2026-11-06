# Headroom website

The one-page site for Headroom, plus `/privacy` and `/support`, served at
https://headroom.niomartinez.com. Next.js 16 (App Router, TypeScript), Tailwind CSS 4 and
`motion`. Every page is static.

```sh
npm install
npm run dev      # http://localhost:3000
npm run lint
npm run build    # must pass before a deploy
npm start        # serves the production build
```

## Where things live

| Path | What |
|---|---|
| `src/app/page.tsx` | The one-pager: hero, features, how it works, screenshots, New in 1.1, FAQ. Also the JSON-LD (`SoftwareApplication`, `FAQPage`). |
| `src/app/privacy`, `src/app/support` | The privacy policy (effective date in `src/content/site.ts`) and support page. |
| `src/app/opengraph-image.tsx` | The 1200 x 630 social card, drawn with `next/og` at build time. `privacy/` and `support/` reuse it. |
| `src/app/sitemap.ts`, `robots.ts` | Sitemap and robots.txt for the canonical domain. |
| `src/app/icon.png`, `apple-icon.png`, `favicon.ico` | Made from the app icon (`App/Assets.xcassets`). |
| `src/content/site.ts` | Name, store name, URL, email, container paths, `privacyLine`, and `appStoreUrl` (null until the app is live). |
| `src/lib/app-store.ts` | Apple's lookup API, checked hourly: the store button's link and the live version, which flips the "New in 1.1" badges from `In review` to `New` once the store has 1.1.0. |
| `src/components/home/new-in-1-1.tsx` | "New in 1.1": Codex, Copilot and widgets cards with the feature snippets (`public/images/snippets`), and the smaller changes. |
| `src/content/faq.ts` | FAQ, shared by the home and support pages. |
| `src/content/screenshots.ts` | The files the screenshots strip shows. |
| `src/components/pill-view.tsx`, `rings.tsx` | The menu bar pill and ring gauge, rebuilt in HTML/SVG with the app's own sizes, colors and thresholds (`Packages/HeadroomKit/Sources/HeadroomUI`). |
| `src/components/hero-scene.tsx` | The hero: faux menu bar, live pill, moments loop, panel with pointer tilt. |

## When the app is live

Nothing to do: the hero and closing buttons switch to "Download on the Mac App Store" within an hour
of the app going live, and the "New in 1.1" badges switch to "New" once the store lists 1.1.0.
Setting `appStoreUrl` in `src/content/site.ts` forces the link.

## Screenshots

The strip shows whatever `src/content/screenshots.ts` lists: the Mac App Store screenshots 01–07 as
JPEGs with their phone crops, then the pill states. `scripts/release/refresh-marketing-assets.sh` (at
the repository root) renders them and writes every JPEG. Use synthetic sample data only: no real
session names or project folders.

## Images

All product images come from synthetic data, never from a real `~/.claude`, `~/.codex` or
`~/.copilot`. `scripts/release/refresh-marketing-assets.sh` does everything below as well as the
screenshots and the 1.1 feature snippets; by hand:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
(cd ../Packages/HeadroomKit && swift run headroom-render /tmp/headroom-render)   # pills and panels on gray
(cd scripts/hero-render && swift run hero-render /tmp/headroom-hero)             # hero panel at 3x, transparent
python3 scripts/prepare-assets.py /tmp/headroom-render /tmp/headroom-hero        # needs Pillow
```

The October 1 refinements block uses `public/images/snippets/session-tools.png`, rendered by
`headroom-render --marketing` as `snippet-session-tools@2x.png`. Its synthetic mixed-tool panel shows
the status dot, colored tool icon, title and folder, with one compact footer legend. The refresh
script copies this snippet alongside Codex, Copilot and widgets; no manual screenshot is needed.

`prepare-assets.py` keys out the gray canvas of the `headroom-render` PNGs, builds the pill-states
composite, copies the hero panel and makes the icons. The hero panel is rendered without its pulse
ring, because the page draws a live one over each working dot (`.panel-pulse` in
`hero-scene.tsx`, positioned from the render's dot centers).

## October 1 refinements

The home-page refinement block and support page describe Automatic / Always compact sizing,
selected-gauge preservation, recovery of already-running Codex tasks after relaunch, and the
neutral keyboard-navigation outline. Build 9 adds a percentage beside each tool's warning gauge
from 75% usage, including simultaneous warnings, with matching guidance on the support page. Build 10
adds missing-pill help at `/support#pill-not-visible` and explains clearing resolved requests. The
refinements describe the fallback that finishes transitions when display callbacks stop. Store status
and CTA still come from Apple’s public version lookup; the site does not claim a release before
it is listed. The sitemap date is October 1, 2026. Existing synthetic images and motion remain.

## Design

A sibling of niomartinez.com: charcoal `#171819`, warm silver `#f1f0eb`, Geist, overscale headlines
and spring interactions (magnetic buttons, a tilting panel). Headroom's own colors come from the
app: teal `#5DCAA5` (working), amber `#EF9F27` (warning), red `#E24B4A` (critical), off-white
`#F1EFE8`, ring track `#444441`.

Motion rules:

- Everything honors `prefers-reduced-motion`: no pulse, no sweeps, no moments loop, no reveals,
  no tilt.
- The hero has a Pause button, and the moments loop only runs while the pill is on screen.
- Section reveals only hide elements that start below the fold, so nothing flashes and the page
  reads fine without JavaScript.
- Custom CSS sits in `@layer components` (`src/app/globals.css`), so Tailwind utilities win.

Copy is in sentence case and plain words, about AI usage and plan limits (Claude's limits cover chat,
Cowork and Claude Code), never "AI coding". Claude, Claude Code, GitHub Copilot and OpenAI Codex are
named only to say what Headroom works with, with no logos (the Copilot card uses stacked bars); the
footer carries the trademark notice. Privacy claims come back to `privacyLine`: no account, local by
default, and Copilot usage as the one opt-in network use.

## Deploying

Live at https://headroom.niomartinez.com: Vercel project `headroom`, deployed with the Vercel CLI from
this folder (`vercel deploy --prod --yes`), no environment variables. The 1.1 copy (privacy page
included) goes live when 1.1 is submitted for review, so App Review reads the new privacy policy;
the badges then say `In review` until the store has 1.1.0.
