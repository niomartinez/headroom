# Headroom 1.1 posts: images and suggested captions

One hero post plus three feature posts (Codex, Copilot, widgets), per the 1.1 spec §10.

**Final images (made in ChatGPT from the renders, 2026-09-26):** `hero-1536x1024.png` (3:2), `square-codex.png`, `square-copilot.png`, `square-widgets.png` (1254×1254). All synthetic data, no Apple or brand logos. The raw renders in `snippets/` are the fallback. Every image
shows synthetic sample data from `HeadroomSamples` (made-up session names like "ledger" and
"harbor", the account "@octocat"), never anything from a real Mac, and no third-party or Apple logos.
Nothing is posted without Nio.

The images come from `scripts/release/refresh-marketing-assets.sh`, so they can be re-rendered after
any UI change. They can be used as they are, or as references for polished squares made in ChatGPT
in Nio's Chrome, as for 1.0 (`../README.md`); if so, keep the data synthetic and the menu bar free of
logos.

Wording: Headroom is about AI usage and plan limits, not only coding. Claude's limits cover chat,
Cowork and Claude Code. Never "AI coding".

## Hero

- **Image:** `../../../fastlane/screenshots/en-US/06-tools.png` (2880×1800, "More tools, one
  panel."), or a 3:2 hero made from it. For a second image, `07-widgets.png`.
- **Alt text:** The Headroom panel in the Mac menu bar with Claude's weekly and 5-hour limits, compact
  rows for OpenAI Codex and GitHub Copilot, and sessions from all three tools. Sample data.

**While 1.1 is in review:**
> Headroom 1.1 is on its way to the Mac App Store. Your AI usage limits and sessions, one glance away:
> Claude's limits (they cover chat, Cowork and Claude Code), plus OpenAI Codex limits and GitHub
> Copilot usage, in the menu bar and now in desktop widgets. Free, no account, local by default.
> headroom.niomartinez.com

**Once 1.1 is live:**
> Headroom 1.1 is out, free on the Mac App Store. Claude, Codex and Copilot limits in one menu bar
> glance, plus Limits and Sessions widgets. Click a session to jump to it.
> headroom.niomartinez.com

## Codex

- **Image:** `snippets/snippet-codex@2x.png` (720×749, transparent): the panel with the Codex row
  under Claude's limits and Codex sessions in the list.
- **Title / body:** Codex, same glance. / Limits and sessions from the Codex app and CLI.
- **Alt text:** Headroom's panel showing Claude's limits, a Codex row at weekly 94% and 5-hour 20%,
  and Claude and Codex sessions side by side. Sample data.

> Codex, same glance. Headroom 1.1 shows your OpenAI Codex limits and running Codex sessions next to
> Claude's, from the Codex app and CLI. It reads Codex's session files on your Mac: no sign-in, and
> nothing leaves your Mac.
> headroom.niomartinez.com

## Copilot

- **Image:** `snippets/snippet-copilot@2x.png` (1512×653, transparent): the Copilot row (512 of
  1,500 credits) and the GitHub account setting.
- **Title / body:** Copilot usage, opt-in. / Your monthly credits, with your own GitHub sign-in.
- **Alt text:** A Copilot row at 34% of monthly credits, 512 of 1,500, next to Headroom's GitHub
  account setting, connected with read-only billing access. Sample data.

> Copilot usage, opt-in. Connect GitHub in Headroom 1.1 and see this month's Copilot credits next to
> your other limits. It uses Headroom's own read-only GitHub sign-in, only if you turn it on, and
> talks to nothing but GitHub. Copilot CLI sessions show up too.
> headroom.niomartinez.com

## Widgets

- **Image:** `snippets/snippet-widgets@2x.png` (1100×1136, transparent): small Limits, medium and
  large Sessions widgets. For a desktop scene, `../../../fastlane/screenshots/en-US/07-widgets.png`.
- **Title / body:** On your desktop. / Limits and Sessions widgets, always dark.
- **Alt text:** Three Headroom widgets: Limits with Claude's rings at 89%, a medium Sessions widget
  with three sessions, and a large one with every tool's limits and sessions. Sample data.

> On your desktop. Headroom 1.1 adds Limits and Sessions widgets for the desktop and Notification
> Center: the same rings and sessions as the menu bar, always dark.
> headroom.niomartinez.com

## Footer line for every post

> Headroom isn't made by or affiliated with Anthropic, OpenAI or GitHub.

## The pill

- **Image:** `square-pill-states.png` (1254×1254, made in ChatGPT from the renders): calm, working, near the limit, critical, session finished, needs you, "stays until you look" and one gauge per tool. Transparent 3× snippets of every pill state are in `snippets/pill/` (from `headroom-render --assets`).
- **Alt text:** Eight Headroom menu bar pills in a column, from calm to critical, with a finished moment, a "needs you" moment, the needs-you rest state and one gauge per tool. Sample data.

> The pill, in every state. Headroom sits in your menu bar as a small black pill: a dot and a count for your sessions, two rings for your limits. It widens for a moment when a session finishes or needs you, and in 1.1 "needs you" stays until you look.
> headroom.niomartinez.com
