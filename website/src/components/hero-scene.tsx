"use client";

import { useInView, useMotionValue, useReducedMotion, useSpring, useTransform } from "motion/react";
import * as m from "motion/react-m";
import Image from "next/image";
import { useEffect, useRef, useState } from "react";
import { PillView, pillLabel, type Moment } from "./pill-view";

/** Sample data only: made-up session names, as in the app's own renders. */
const MOMENTS: Moment[] = [
  { kind: "finished", name: "ledger", status: "finished" },
  { kind: "needsInput", name: "harbor", status: "needs you" },
  { kind: "limit", text: "Weekly at 90%", percent: 90 },
];

const FIRST_MOMENT_MS = 4600;
const MOMENT_MS = 3200;
const BETWEEN_MS = 3300;

/**
 * The hero: a faux desktop with a live replica of the menu bar pill (pulsing dot, rings that sweep
 * in, the amber number, and a "moment" every ~6.5 s) above the panel, which tilts with the pointer.
 */
export function HeroScene() {
  const reduce = useReducedMotion();
  const sceneRef = useRef<HTMLDivElement>(null);
  const panelRef = useRef<HTMLDivElement>(null);
  const menubarRef = useRef<HTMLDivElement>(null);
  // Moments only play while the menu bar (and so the pill) is on screen.
  const inView = useInView(menubarRef, { amount: 0.6 });

  const [intro, setIntro] = useState(true);
  const [open, setOpen] = useState(true);
  const [paused, setPaused] = useState(false);
  const [moment, setMoment] = useState<Moment | null>(null);
  const [shownMoment, setShownMoment] = useState<Moment>(MOMENTS[0]);
  const [weekly, setWeekly] = useState(89);
  const step = useRef(0);

  // The load sequence (rings, badge, panel) is CSS keyed on data-intro; after it, transitions take over.
  useEffect(() => {
    const timer = setTimeout(() => setIntro(false), 2700);
    return () => clearTimeout(timer);
  }, []);

  const animate = !reduce && !paused && inView;

  useEffect(() => {
    if (!animate) return;
    let showTimer: ReturnType<typeof setTimeout> | undefined;
    let hideTimer: ReturnType<typeof setTimeout> | undefined;
    const schedule = (delay: number) => {
      showTimer = setTimeout(() => {
        if (document.hidden) return schedule(1500);
        const next = MOMENTS[step.current % MOMENTS.length];
        step.current += 1;
        setShownMoment(next);
        setMoment(next);
        // The "Weekly at 90%" moment leaves the ring at 90; start the loop over from 89.
        if (next.kind === "finished") setWeekly(89);
        hideTimer = setTimeout(() => {
          setMoment(null);
          if (next.kind === "limit") setWeekly(next.percent);
          schedule(BETWEEN_MS);
        }, MOMENT_MS);
      }, delay);
    };
    schedule(step.current === 0 ? FIRST_MOMENT_MS : 1800);
    return () => {
      clearTimeout(showTimer);
      clearTimeout(hideTimer);
    };
  }, [animate]);

  const visibleMoment = animate ? moment : null;

  // Pointer tilt for the panel, a little parallax for the window behind it.
  const rotateX = useMotionValue(0);
  const rotateY = useMotionValue(0);
  const springX = useSpring(rotateX, { stiffness: 130, damping: 19 });
  const springY = useSpring(rotateY, { stiffness: 130, damping: 19 });
  const windowX = useTransform(springY, (value) => value * -1.6);
  const windowY = useTransform(springX, (value) => value * 1.2);

  const state = { dot: "working" as const, count: 2, weekly, fiveHour: 14 };
  const label = `Headroom menu bar pill, sample data. ${pillLabel({ ...state, moment: visibleMoment })}`;

  return (
    <div className="intro-scene">
      <div
        ref={sceneRef}
        className="scene"
        data-intro={intro ? "true" : "false"}
        data-paused={paused ? "true" : "false"}
        onPointerMove={(event) => {
          if (reduce || event.pointerType !== "mouse") return;
          const rect = event.currentTarget.getBoundingClientRect();
          const x = (event.clientX - rect.left) / rect.width - 0.5;
          const y = (event.clientY - rect.top) / rect.height - 0.5;
          rotateY.set(x * 10);
          rotateX.set(-y * 8);
          const panel = panelRef.current;
          if (panel) {
            const box = panel.getBoundingClientRect();
            panel.style.setProperty("--glare-x", `${((event.clientX - box.left) / box.width) * 100}%`);
            panel.style.setProperty("--glare-y", `${((event.clientY - box.top) / box.height) * 100}%`);
            panel.style.setProperty("--glare-opacity", "1");
          }
        }}
        onPointerLeave={() => {
          rotateX.set(0);
          rotateY.set(0);
          panelRef.current?.style.setProperty("--glare-opacity", "0");
        }}
      >
        <div ref={menubarRef} className="menubar">
          <div className="menubar-menus hidden md:flex" aria-hidden="true">
            <MenuGlyph />
            <b>Terminal</b>
            <span>Shell</span>
            <span>Edit</span>
            <span className="hidden lg:inline">View</span>
            <span className="hidden lg:inline">Window</span>
            <span className="hidden lg:inline">Help</span>
          </div>
          <div className="menubar-status">
            <button
              type="button"
              className="pill-button"
              aria-label={`${label} ${open ? "Hide" : "Show"} the panel.`}
              aria-expanded={open}
              aria-controls="hero-panel"
              onClick={() => setOpen((value) => !value)}
            >
              <PillView {...state} moment={visibleMoment} shownMoment={shownMoment} />
            </button>
            <span className="hidden sm:inline-flex" aria-hidden="true">
              <ControlCenterIcon />
            </span>
            <span className="inline-flex max-[399px]:hidden" aria-hidden="true">
              <WifiIcon />
            </span>
            <span className="hidden sm:inline-flex" aria-hidden="true">
              <BatteryIcon />
            </span>
            <span className="tabular-nums" aria-hidden="true">
              <span className="hidden sm:inline">Thu Sep 24&nbsp;&nbsp;</span>2:10 PM
            </span>
          </div>
        </div>

        <div className="relative flex min-h-[300px] justify-center px-3 pb-5 pt-3 sm:justify-end sm:px-6 sm:pb-12 sm:pt-4 md:min-h-[520px] short:min-h-0 short:pb-6">
          <m.div className="desktop-window hidden md:block" style={{ x: windowX, y: windowY }} aria-hidden="true">
            <DesktopWindow />
          </m.div>

          <div className="panel-stage relative z-[2] w-full max-w-[440px] short:max-w-[360px]">
            <m.div style={{ rotateX: springX, rotateY: springY }}>
              <div id="hero-panel" className="panel-open" data-open={open ? "true" : "false"}>
                <div ref={panelRef} className="panel-card">
                  <Image
                    src="/images/hero-panel.png"
                    width={1080}
                    height={1050}
                    quality={90}
                    loading="eager"
                    fetchPriority="high"
                    sizes="(max-width: 520px) calc(100vw - 64px), 440px"
                    alt="The Headroom panel with sample data: weekly limit 89 percent, resets Sunday 7 PM; 5-hour limit 14 percent, resets in 2 hours 50 minutes; two sessions working and five idle, each with a context bar."
                    className="block h-auto w-full select-none"
                    draggable={false}
                  />
                  <span className="panel-pulse" style={{ left: "5.28%", top: "40.29%" }} aria-hidden="true">
                    <span className="dot-ring" />
                  </span>
                  <span className="panel-pulse" style={{ left: "5.28%", top: "47.14%" }} aria-hidden="true">
                    <span className="dot-ring" />
                  </span>
                  <span className="panel-glare" aria-hidden="true" />
                </div>
              </div>
            </m.div>
          </div>
        </div>
      </div>

      <div className="mt-3 flex items-center justify-between gap-4 px-1 text-[13px] leading-snug text-subtle sm:mt-4 sm:items-start">
        {/* Whole sentences, so the mouse version is one unbroken line of text, as it always was. */}
        <p>
          <span className="pointer-coarse:hidden">A live replica with sample data. Click the pill to {open ? "close" : "open"} the panel.</span>
          <span className="hidden pointer-coarse:inline">A live replica with sample data. Tap the pill to {open ? "close" : "open"} the panel.</span>
        </p>
        <button
          type="button"
          onClick={() => setPaused((value) => !value)}
          aria-pressed={paused}
          // With reduced motion nothing in the scene moves, so there is nothing to pause.
          // On touch screens the ::after keeps the tap target 44 px tall around the small chip.
          className="inline-flex shrink-0 motion-reduce:hidden items-center gap-2 rounded-full border border-line px-3 py-1.5 text-muted transition-colors hover:border-white/25 hover:text-fg pointer-coarse:relative pointer-coarse:after:absolute pointer-coarse:after:-inset-x-1 pointer-coarse:after:-inset-y-2"
        >
          {paused ? <PlayIcon /> : <PauseIcon />}
          <span>{paused ? "Play" : "Pause"}</span>
          <span className="sr-only"> animation</span>
        </button>
      </div>
    </div>
  );
}

function DesktopWindow() {
  const lines = [
    ["w-[58%]", "teal"],
    ["w-[76%]", ""],
    ["w-[44%]", ""],
    ["w-[64%]", "teal"],
    ["w-[52%]", ""],
    ["w-[70%]", ""],
    ["w-[36%]", "teal"],
  ] as const;
  return (
    <>
      <div className="flex h-10 items-center gap-2 border-b border-white/5 px-4">
        <i className="size-3 rounded-full bg-white/12" />
        <i className="size-3 rounded-full bg-white/12" />
        <i className="size-3 rounded-full bg-white/12" />
        <span className="mx-auto pr-12 font-mono text-[12px] text-white/35">ledger</span>
      </div>
      <div className="flex flex-col gap-3.5 px-5 pb-6 pt-5">
        {lines.map(([width, tone], index) => (
          <div key={index} className="flex items-center gap-3">
            <i className={`size-2 shrink-0 rounded-full ${tone ? "bg-teal/70" : "bg-white/10"}`} />
            <i className={`h-2 rounded-full bg-white/[0.09] ${width}`} />
          </div>
        ))}
        <div className="flex items-center gap-3 pt-1">
          <span className="font-mono text-[13px] text-white/40">›</span>
          <span className="caret" />
        </div>
      </div>
    </>
  );
}

function MenuGlyph() {
  return (
    <svg width="15" height="15" viewBox="0 0 16 16" aria-hidden="true">
      <circle cx="8" cy="8" r="6.5" fill="none" stroke="currentColor" strokeWidth="1.6" opacity="0.85" />
      <circle cx="8" cy="8" r="2.6" fill="currentColor" opacity="0.85" />
    </svg>
  );
}

function WifiIcon() {
  return (
    <svg width="17" height="13" viewBox="0 0 17 13" aria-hidden="true" fill="currentColor">
      <path d="M8.5 2.6c2.4 0 4.6.9 6.3 2.4l1.1-1.2A10.7 10.7 0 0 0 8.5 1 10.7 10.7 0 0 0 1.1 3.8l1.1 1.2A9.1 9.1 0 0 1 8.5 2.6Z" />
      <path d="M8.5 5.9c1.5 0 2.9.6 4 1.5l1.1-1.2a7.6 7.6 0 0 0-10.2 0l1.1 1.2c1.1-.9 2.5-1.5 4-1.5Z" />
      <path d="M8.5 9.1c.7 0 1.3.2 1.8.6L8.5 11.6 6.7 9.7c.5-.4 1.1-.6 1.8-.6Z" />
    </svg>
  );
}

function BatteryIcon() {
  return (
    <svg width="26" height="13" viewBox="0 0 26 13" aria-hidden="true">
      <rect x="0.75" y="0.75" width="21.5" height="11.5" rx="3.4" fill="none" stroke="currentColor" strokeOpacity="0.55" strokeWidth="1.2" />
      <rect x="2.6" y="2.6" width="14" height="7.8" rx="1.8" fill="currentColor" />
      <path d="M23.6 4.4v4.2c.8-.3 1.3-1.1 1.3-2.1s-.5-1.8-1.3-2.1Z" fill="currentColor" fillOpacity="0.55" />
    </svg>
  );
}

function ControlCenterIcon() {
  return (
    <svg width="16" height="14" viewBox="0 0 16 14" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="1.4">
      <rect x="0.7" y="0.7" width="14.6" height="5.2" rx="2.6" />
      <rect x="0.7" y="8.1" width="14.6" height="5.2" rx="2.6" />
      <circle cx="12.7" cy="3.3" r="1.3" fill="currentColor" stroke="none" />
      <circle cx="3.3" cy="10.7" r="1.3" fill="currentColor" stroke="none" />
    </svg>
  );
}

function PauseIcon() {
  return (
    <svg width="10" height="10" viewBox="0 0 10 10" aria-hidden="true" fill="currentColor">
      <rect x="1.5" y="1" width="2.4" height="8" rx="0.8" />
      <rect x="6.1" y="1" width="2.4" height="8" rx="0.8" />
    </svg>
  );
}

function PlayIcon() {
  return (
    <svg width="10" height="10" viewBox="0 0 10 10" aria-hidden="true" fill="currentColor">
      <path d="M2.2 1.3v7.4c0 .5.5.8.9.5l5.6-3.7a.6.6 0 0 0 0-1L3.1.8c-.4-.3-.9 0-.9.5Z" />
    </svg>
  );
}
