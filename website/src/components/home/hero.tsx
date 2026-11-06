import type { CSSProperties } from "react";
import { HeroScene } from "../hero-scene";
import { Magnetic } from "../magnetic";
import { StoreButton } from "../store-button";

/*
 * Phones (below 640 px) and landscape phones (the `short` variant) get a leaner hero, so the live
 * pill makes the first screen: no eyebrow, the short lede, and the store badge after the scene.
 * From 640 px up in portrait, and on every desktop, the hero is unchanged.
 */
export function Hero() {
  return (
    <section aria-labelledby="hero-title" className="relative isolate">
      <div className="hero-glow" aria-hidden="true" />
      <div className="wrap pt-7 sm:pt-20 lg:pt-24 short:pt-6">
        <p className="eyebrow intro-rise max-sm:hidden short:hidden">For your AI plan limits</p>
        <h1
          id="hero-title"
          className="display intro-rise text-[clamp(36px,10.6vw,46px)] sm:mt-6 sm:text-[clamp(44px,7.6vw,112px)] short:mt-0 short:text-[clamp(36px,6.4vw,52px)]"
          style={{ "--d": "60ms" } as CSSProperties}
        >
          Know your headroom.
          <span className="block text-teal">Before you hit the limit.</span>
        </h1>

        <div className="mt-5 grid gap-6 sm:mt-10 sm:gap-8 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-end lg:gap-16 short:mt-4">
          <p className="lede intro-rise max-w-[560px] short:max-w-[680px]" style={{ "--d": "140ms" } as CSSProperties}>
            <span className="sm:hidden short:inline">
              A free menu bar app for your Mac. See how much of your Claude, Codex and Copilot plans
              is left, and what every session is doing. No account, local by default.
            </span>
            <span className="hidden sm:inline short:hidden">
              A free menu bar app for your Mac. It shows how much of your Claude plan is left this
              week and in the current 5-hour window, across chat, Cowork and Claude Code, with Codex
              and Copilot alongside, and what every session is doing right now. No account, and
              local by default.
            </span>
          </p>
          <div className="flex flex-col gap-3 max-sm:hidden short:hidden">
            <div className="flex flex-wrap items-center gap-x-6 gap-y-3">
              <StoreButton />
              <Magnetic>
                <a href="#how-it-works" className="round-link">
                  <span className="circle" aria-hidden="true">
                    <svg width="18" height="18" viewBox="0 0 18 18" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <path d="M9 3v12M4 10l5 5 5-5" />
                    </svg>
                  </span>
                  See how it works
                </a>
              </Magnetic>
            </div>
            <p className="pl-1 text-[13px] text-subtle">Now on the Mac App Store · Free · macOS 14 or later</p>
          </div>
        </div>

        <div className="mt-6 sm:mt-16 short:mt-5">
          <HeroScene />
        </div>

        {/* Phones: the product first, then the store badge. */}
        <div
          className="mt-7 flex flex-col items-start gap-3 sm:hidden short:flex short:flex-row short:flex-wrap short:items-center short:gap-x-6"
        >
          <StoreButton />
          <p className="pl-1 text-[13px] text-subtle">Now on the Mac App Store · Free · macOS 14 or later</p>
        </div>
      </div>
    </section>
  );
}
