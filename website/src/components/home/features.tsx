import type { CSSProperties, ReactNode } from "react";
import { privacyLine } from "@/content/site";
import { PillView } from "../pill-view";
import { Rings } from "../rings";
import { SnapRow } from "../snap-row";
import { SectionHead } from "./section-head";

type Feature = { tag: string; title: string; body: string; visual: ReactNode };

const features: Feature[] = [
  {
    tag: "Limits",
    title: "Limits at a glance.",
    body: "Two rings in your menu bar: the outer one is your weekly limit, the inner one your 5-hour limit. Past 75%, the number shows. Track Codex or Copilot too, and pick the tool the rings show.",
    visual: <LimitsVisual />,
  },
  {
    tag: "Sessions",
    title: "Every session, sorted.",
    body: "Click the pill to see Claude Code, Codex and connected Copilot sessions grouped as working, needs you or idle. Tool icons make each session easy to recognize.",
    visual: <SessionsVisual />,
  },
  {
    tag: "Context",
    title: "Context before it compacts.",
    body: "A small bar on every session shows how full its context window is, so you can wrap up or start fresh before it gets compacted.",
    visual: <ContextVisual />,
  },
  {
    tag: "Moments",
    title: "Moments, not notifications.",
    body: "When a session finishes, needs your input, or a limit crosses 90%, the pill widens for a few seconds and says so. “Needs you” stays until you look. No sounds, no banners.",
    visual: <MomentVisual />,
  },
  {
    tag: "Anywhere",
    title: "Desktop apps and terminals.",
    body: "Setup guides you through folder access for Claude and Codex, and optional connections for Claude Code in a terminal or Copilot in its desktop app and CLI.",
    visual: <AnywhereVisual />,
  },
  {
    tag: "Private",
    title: "Private by design.",
    body: privacyLine,
    visual: <PrivateVisual />,
  },
  {
    tag: "Native",
    title: "Native and tiny.",
    body: "A small Swift app for macOS 14 and later, with widgets for the desktop. It lives in your menu bar, not your Dock, and stays out of the way.",
    visual: <NativeVisual />,
  },
  {
    tag: "Honest",
    title: "Honest numbers.",
    body: "An inferred reset time says so with a tilde. Old numbers say “as of” and how old they are. Headroom never guesses quietly.",
    visual: <HonestVisual />,
  },
];

export function Features() {
  return (
    <section id="features" aria-labelledby="features-title" className="wrap pt-16 sm:pt-24 md:pt-36 short:pt-16">
      <SectionHead
        id="features-title"
        eyebrow="What it shows"
        title="Everything you keep checking, one glance away."
        intro="Your plan limits, your sessions and their context, right where you already look: the menu bar."
      />
      {/* A swipeable row on phones, the 2- and 4-column grid from 640 px up. */}
      <SnapRow label="Features" noun="Feature" className="mt-8 sm:mt-12 md:mt-16 short:mt-8 sm:grid sm:grid-cols-2 sm:gap-4 lg:grid-cols-4">
        {features.map((feature, index) => (
          <li
            key={feature.tag}
            data-reveal
            className="glass-card flex flex-col p-5 sm:p-7"
            style={{ "--d": `${(index % 4) * 70}ms` } as CSSProperties}
          >
            <div className="flex h-20 items-center sm:h-[92px]" aria-hidden="true">
              {feature.visual}
            </div>
            <p className="label mt-5 sm:mt-6">
              <b>{String(index + 1).padStart(2, "0")}</b> / {feature.tag}
            </p>
            <h3 className="mt-2.5 text-[20px] font-medium leading-snug tracking-[-0.025em] sm:mt-3 sm:text-[21px]">{feature.title}</h3>
            <p className="mt-2 text-[16px] leading-relaxed text-muted sm:mt-2.5 sm:text-[15px]">{feature.body}</p>
          </li>
        ))}
      </SnapRow>
    </section>
  );
}

/* ---------- Small visuals, drawn in code ---------- */

function LimitsVisual() {
  return (
    <div className="flex items-center gap-4">
      <Rings weekly={89} fiveHour={14} variant="panel" className="size-[76px]" />
      <div className="flex flex-col gap-1.5 text-[13px] leading-none">
        <span className="flex items-baseline gap-2">
          <span className="text-muted">Weekly</span>
          <span className="font-medium tabular-nums text-amber">89%</span>
        </span>
        <span className="flex items-baseline gap-2">
          <span className="text-muted">5-hour</span>
          <span className="font-medium tabular-nums text-offwhite">14%</span>
        </span>
      </div>
    </div>
  );
}

function SessionsVisual() {
  const rows = [
    { name: "ledger", color: "var(--color-teal)", pulse: true },
    { name: "harbor", color: "var(--color-amber)", pulse: false },
    { name: "atlas", color: "var(--color-idle)", pulse: false },
  ];
  return (
    <div className="flex w-full flex-col gap-2.5">
      {rows.map((row) => (
        <div key={row.name} className="flex items-center gap-3 text-[13px]">
          <span className="dot" style={{ "--dot-color": row.color, "--s": 1.1 } as CSSProperties}>
            {row.pulse && <span className="dot-ring" />}
          </span>
          <span className="w-14 text-offwhite">{row.name}</span>
          <span className="h-1.5 flex-1 rounded-full bg-white/[0.07]" />
        </div>
      ))}
    </div>
  );
}

function ContextVisual() {
  const rows = [
    { value: 72, color: "var(--color-offwhite)" },
    { value: 85, color: "var(--color-amber)" },
    { value: 29, color: "var(--color-offwhite)" },
  ];
  return (
    <div className="flex w-full flex-col gap-3">
      {rows.map((row, index) => (
        <div key={index} className="flex items-center gap-3">
          <div
            className="bar flex-1"
            style={{ "--bar-color": row.color, "--bar-delay": `${0.3 + index * 0.12}s` } as CSSProperties}
          >
            <i style={{ "--w": `${row.value}%` } as CSSProperties} />
          </div>
          <span className="w-9 text-right text-[13px] tabular-nums" style={{ color: row.color === "var(--color-amber)" ? row.color : "var(--color-muted)" }}>
            {row.value}%
          </span>
        </div>
      ))}
    </div>
  );
}

function MomentVisual() {
  return (
    <PillView
      dot="working"
      count={2}
      weekly={89}
      fiveHour={14}
      moment={{ kind: "finished", name: "ledger", status: "finished" }}
      scale={1.25}
    />
  );
}

function AnywhereVisual() {
  return (
    <div className="flex flex-wrap items-center gap-2">
      <span className="chip">
        <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.3" aria-hidden="true">
          <rect x="1" y="1.5" width="12" height="11" rx="2.5" />
          <path d="M1 4.6h12" />
        </svg>
        Desktop app
      </span>
      <span className="text-subtle">+</span>
      <span className="chip">
        <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <rect x="1" y="1.5" width="12" height="11" rx="2.5" />
          <path d="M4 5.5l2 1.5-2 1.5M7.5 9h2.5" />
        </svg>
        Terminal
      </span>
    </div>
  );
}

function PrivateVisual() {
  return (
    <div className="flex items-center gap-4">
      <span className="grid size-[60px] place-items-center rounded-[18px] border border-white/10 bg-black/40">
        <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="var(--color-teal)" strokeWidth="1.7" strokeLinecap="round" aria-hidden="true">
          <rect x="4.5" y="10.5" width="15" height="10" rx="2.6" />
          <path d="M8 10.5V7.8a4 4 0 0 1 8 0v2.7" />
          <path d="M12 14.6v2" />
        </svg>
      </span>
      <div className="flex flex-col gap-1.5 text-[13px] leading-none text-muted">
        <span>No account</span>
        <span>Local by default</span>
        <span>No analytics</span>
      </div>
    </div>
  );
}

function NativeVisual() {
  return (
    <div className="flex flex-wrap gap-2">
      <span className="chip">Swift</span>
      <span className="chip">SwiftUI</span>
      <span className="chip">macOS 14+</span>
    </div>
  );
}

function HonestVisual() {
  return (
    <div className="w-full rounded-2xl border border-white/[0.07] bg-[#111] px-4 py-3">
      <div className="flex items-baseline justify-between text-[14px] font-medium">
        <span className="text-offwhite">Weekly</span>
        <span className="tabular-nums text-amber">89%</span>
      </div>
      <p className="mt-1 text-[12px] text-subtle">
        resets <span className="text-offwhite">~</span>Sun 7 PM · <span className="text-offwhite">as of 42m ago</span>
      </p>
    </div>
  );
}
