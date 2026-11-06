import Image from "next/image";
import type { CSSProperties, ReactNode } from "react";
import { isVersionLive, newFeaturesVersion, refreshVersion, seenVersion } from "@/lib/app-store";
import { SectionHead } from "./section-head";

/**
 * The 1.1 features. `image` is the feature snippet from `headroom-render --marketing` (synthetic data), copied to
 * public/images/snippets by scripts/release/refresh-marketing-assets.sh. `short` is the one-line version for phones.
 * Icons are neutral glyphs, never another company's logo.
 */
type Snippet = {
  src: string;
  alt: string;
  /** "peek" fills the card with the snippet's top at about its real size; "whole" shows all of it. */
  fit: "peek" | "whole";
};

const items: { title: string; body: string; short: string; image: Snippet; icon: ReactNode }[] = [
  {
    title: "OpenAI Codex",
    body: "Codex limits and sessions next to Claude's. Read from files on your Mac, still no login.",
    short: "Limits and sessions, still no login.",
    image: {
      src: "/images/snippets/codex.png",
      alt: "The Headroom panel with a Codex row under Claude's limits: weekly 94%, and Codex sessions tagged in the list. Sample data.",
      fit: "peek",
    },
    icon: (
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
        <rect x="3.5" y="4.5" width="17" height="15" rx="3" />
        <path d="M7.5 10l2.5 2-2.5 2M12.5 15h4" />
      </svg>
    ),
  },
  {
    title: "GitHub Copilot",
    body: "Connect GitHub for monthly usage, and connect desktop or CLI sessions separately. Only usage needs the network.",
    short: "Usage and desktop or CLI sessions, opt-in.",
    image: {
      src: "/images/snippets/copilot.png",
      alt: "A Copilot row reading 34% of monthly credits, 512 of 1,500, next to Headroom's GitHub account setting, connected with read-only billing access. Sample data.",
      fit: "whole",
    },
    icon: (
      // Stacked usage bars: a neutral glyph for "monthly usage".
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round">
        <path d="M5 7h14M5 12h9.5M5 17h5.5" />
      </svg>
    ),
  },
  {
    title: "Desktop widgets",
    body: "The rings and your sessions on the desktop and in Notification Center.",
    short: "Rings and sessions on the desktop.",
    image: {
      src: "/images/snippets/widgets.png",
      alt: "Three Headroom widgets: small Limits with Claude's rings at 89%, medium Sessions with three sessions, and large Sessions with every tool's limits and sessions. Sample data.",
      fit: "peek",
    },
    icon: (
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round">
        <rect x="3.5" y="3.5" width="7.5" height="7.5" rx="2" />
        <rect x="13" y="3.5" width="7.5" height="7.5" rx="2" />
        <rect x="3.5" y="13" width="17" height="7.5" rx="2" />
      </svg>
    ),
  },
];

/** Smaller 1.1 changes: chips under the cards, one sentence on phones. */
const alsoNew = [
  "Click a session to open it",
  "“Needs you” stays until you look",
  "A key for the two rings",
  "Pick the tool the rings show",
];
const alsoNewSentence =
  "Click a session to open it, “needs you” stays until you look, a key for the two rings, and you pick the tool the rings show.";

/**
 * "New in 1.1". Confirmed releases keep their "New" badges even during a lookup outage.
 */
export async function NewInOneOne() {
  const live = await isVersionLive(newFeaturesVersion);
  const refreshLive = await isVersionLive(refreshVersion);
  const seenLive = await isVersionLive(seenVersion);
  const badge = live ? "New" : "In review";
  const badgeClass = live ? "border-teal/35 text-teal" : "border-amber/35 text-amber";

  return (
    <section id="new-in-1-1" aria-labelledby="new-title" className="wrap pt-16 sm:pt-28 md:pt-40 short:pt-16">
      <SectionHead
        id="new-title"
        eyebrow="New in 1.1"
        title="More tools, the same glance."
        intro="Codex, Copilot and widgets, with the same privacy rules."
      />
      <p className="mt-4 text-[15px] text-muted">October 10, 2026 · Headroom 1.1 is now available free on the Mac App Store.</p>
      {/* Phones: one card of compact rows (icon, title and badge, one line of text). From 640 px up: cards with
          the feature snippet on top. */}
      <ul className="mt-8 grid rounded-[22px] border border-white/[0.1] sm:mt-12 md:mt-16 short:mt-8 sm:gap-4 sm:rounded-none sm:border-0 md:grid-cols-3">
        {items.map((item, index) => (
          <li
            key={item.title}
            data-reveal
            className="relative grid grid-cols-[40px_minmax(0,1fr)_auto] items-center gap-x-3.5 px-4 py-4 max-[379px]:grid-cols-[36px_minmax(0,1fr)_auto] max-[379px]:gap-x-3 max-[379px]:px-3.5 max-sm:[&+&]:border-t max-sm:[&+&]:border-white/[0.1] sm:flex sm:flex-col sm:items-stretch sm:overflow-hidden sm:rounded-[24px] sm:border sm:border-(--glass-border) sm:bg-(image:--glass) sm:p-0 sm:shadow-[inset_0_1px_0_rgb(255_255_255/0.04)]"
            style={{ "--d": `${index * 80}ms` } as CSSProperties}
          >
            <div className="relative hidden aspect-[4/3] border-b border-white/[0.06] sm:block" style={snippetBackdrop(index)}>
              <Image
                src={item.image.src}
                alt={item.image.alt}
                fill
                quality={90}
                sizes="(max-width: 767px) 90vw, 400px"
                className={
                  item.image.fit === "peek"
                    ? "object-cover object-top px-5 pt-5 md:px-6 md:pt-6"
                    : "object-contain p-4 drop-shadow-[0_18px_30px_rgb(0_0_0/0.5)]"
                }
              />
            </div>
            <div className="contents sm:flex sm:items-center sm:justify-between sm:gap-4 sm:px-7 sm:pt-6">
              <span className="row-span-2 grid size-10 place-items-center self-start rounded-xl bg-white/[0.05] text-muted max-[379px]:size-9 sm:size-11 sm:self-auto sm:rounded-2xl" aria-hidden="true">
                {item.icon}
              </span>
              <span className={`col-start-3 row-start-1 whitespace-nowrap rounded-full border px-2.5 py-0.5 text-[11px] font-medium tracking-[0.02em] max-[379px]:px-2 sm:px-3 sm:py-1 sm:text-[12px] ${badgeClass}`}>
                {badge}
              </span>
            </div>
            <h3 className="col-start-2 row-start-1 text-[17px] font-medium tracking-[-0.02em] max-sm:leading-snug max-[379px]:text-[16px] max-[379px]:text-balance sm:mt-5 sm:px-7 sm:text-[21px] sm:tracking-[-0.025em]">{item.title}</h3>
            <p className="col-span-2 col-start-2 mt-1 text-[15px] leading-normal text-muted max-[379px]:text-balance sm:mt-2.5 sm:px-7 sm:pb-7 sm:leading-relaxed">
              <span className="sm:hidden">{item.short}</span>
              <span className="hidden sm:inline">{item.body}</span>
            </p>
          </li>
        ))}
      </ul>
      <div data-reveal className="mt-6 flex flex-col gap-2 sm:mt-8 sm:flex-row sm:flex-wrap sm:items-center sm:gap-x-4 sm:gap-y-3">
        <p className="label">Also in 1.1</p>
        <p className="text-[15px] leading-normal text-muted sm:hidden">{alsoNewSentence}</p>
        <ul className="flex flex-wrap gap-2 max-sm:hidden">
          {alsoNew.map((text) => (
            <li key={text} className="chip">
              {text}
            </li>
          ))}
        </ul>
      </div>
      <div data-reveal className="mt-8 grid items-center gap-6 rounded-[22px] border border-line p-5 sm:mt-12 sm:grid-cols-2 sm:gap-10 sm:p-8">
        <div>
          <p className="label">October 5 · 1.1 refinements · {live ? "Available" : "In review"}</p>
          <h3 className="mt-3 text-[23px] font-medium tracking-[-0.025em]">An easier start. Clearer sessions.</h3>
          <p className="mt-3 text-[15px] leading-relaxed text-muted">
            Choose a tool in the new setup, connect what you need, or try sample data first.
            Small, colored session icons stay visible when you track several tools, even when
            only one currently has sessions.
          </p>
          <ul className="mt-4 space-y-3 text-[15px] leading-relaxed text-muted">
            <li><strong className="font-medium text-fg">Setup at your pace.</strong> Add another tool or finish later. Reopen setup anytime from Settings → General → Set up tools.</li>
            <li><strong className="font-medium text-fg">Copilot completions stay visible.</strong> A completed session can close immediately without losing its completion moment. Connect Session activity separately from GitHub usage, then start a new Copilot session.</li>
            <li><strong className="font-medium text-fg">Icons on the rings.</strong> When you track more than one tool, each ring shows its tool’s icon, in the menu bar and in the panel, so you can tell them apart at a glance.</li>
            <li><strong className="font-medium text-fg">Company Copilot seats.</strong> If your organization pays for a Business or Enterprise seat, Headroom shows its monthly AI credits as a percent.</li>
            <li><strong className="font-medium text-fg">A number for every warning.</strong> With one gauge per tool, Claude, Codex and Copilot each show their own percentage from 75% usage.</li>
            <li><strong className="font-medium text-fg">A fit for your menu bar.</strong> Automatic expands titles when there’s room and keeps your selected gauges. Always compact keeps one gauge and full titles in the panel.</li>
            <li><strong className="font-medium text-fg">Background work counts.</strong> A Claude session stays under Working while a background command or agent is still running, even between replies.</li>
            <li><strong className="font-medium text-fg">Codex fades only when it might be behind.</strong> With no Codex session running, an older Codex reading shows its age without fading.</li>
            <li><strong className="font-medium text-fg">Running tasks stay counted.</strong> Reopening Headroom picks up Codex tasks already in progress, including long sessions.</li>
            <li><strong className="font-medium text-fg">Calmer transitions.</strong> Titles, rings and numbers move together. Transitions finish even if the display stops sending frames, so updated notices can appear. A drawn check marks completion; a quiet row outline appears when you navigate by keyboard.</li>
          </ul>
        </div>
        <Image
          src="/images/snippets/session-tools.png"
          alt="Headroom with sample sessions: the Claude icon in its ring, a colored tool icon between each status dot and task title, and one small Claude, Codex and Copilot legend below the list."
          width={720}
          height={708}
          sizes="(max-width: 639px) calc(100vw - 88px), 420px"
          className="mx-auto h-auto w-full max-w-[360px]"
        />
      </div>
      <div data-reveal className="mt-6 grid items-center gap-6 rounded-[22px] border border-line p-5 sm:mt-8 sm:grid-cols-2 sm:gap-10 sm:p-8">
        <div>
          <p className="label">October 18 · 1.1.1 · {refreshLive ? "Available" : "In review"}</p>
          <h3 className="mt-3 text-[23px] font-medium tracking-[-0.025em]">Refresh on demand. Review what finished.</h3>
          <p className="mt-3 text-[15px] leading-relaxed text-muted">
            Pull fresh numbers when you want them, and look over finished work before it drops into Idle.
          </p>
          <ul className="mt-4 space-y-3 text-[15px] leading-relaxed text-muted">
            <li><strong className="font-medium text-fg">Refresh now.</strong> A button next to Settings reads your limits and sessions again right away and fetches Copilot usage. Claude and Codex numbers are as new as their apps last recorded them.</li>
            <li><strong className="font-medium text-fg">Just finished.</strong> A session that finishes gets its own section above Idle. It stays there until you open it from Headroom, dismiss it, clear the section, or continue the session.</li>
            <li><strong className="font-medium text-fg">Cleared once you’ve seen it.</strong> Opening the session in the Claude or Codex app, or bringing its terminal or the Copilot app forward, moves it to Idle too, the way Needs you clears when you answer in the app. <span className="whitespace-nowrap text-[13px]">1.1.2 · {seenLive ? "Available" : "In review"}</span></li>
          </ul>
        </div>
        <Image
          src="/images/snippets/just-finished.png"
          alt="Headroom with sample sessions: a Just finished section with two sessions and a Clear button between Working and Idle, and a Refresh button beside the gear in the footer."
          width={720}
          height={725}
          sizes="(max-width: 639px) calc(100vw - 88px), 420px"
          className="mx-auto h-auto w-full max-w-[360px]"
        />
      </div>
    </section>
  );
}

/** A soft glow behind each snippet, in the app's own colors. */
function snippetBackdrop(index: number): CSSProperties {
  const glow = ["rgb(93 202 165 / 0.16)", "rgb(239 159 39 / 0.12)", "rgb(93 202 165 / 0.12)"][index % 3];
  return { background: `radial-gradient(70% 80% at 50% 30%, ${glow}, transparent 70%), linear-gradient(180deg, #1b1c1e, #141516)` };
}
