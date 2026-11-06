import { Fragment, type CSSProperties, type ReactNode } from "react";
import { site } from "@/content/site";
import { PillView } from "../pill-view";
import { SectionHead } from "./section-head";

type Step = { title: string; body: ReactNode; visual: ReactNode };

const steps: Step[] = [
  {
    title: "Install",
    body: <>Get Headroom free from the <a href={site.appStoreUrl} className="text-link">Mac App Store</a> and open it. It lives in your menu bar, next to the clock.</>,
    visual: (
      <div className="flex items-center gap-3">
        <span className="chip">Mac App Store</span>
        <span className="chip border-teal/30 text-teal">Free</span>
      </div>
    ),
  },
  {
    title: "Choose your tools",
    body: (
      <>
        Choose Claude, Codex or Copilot. Setup shows the connections for that tool and asks for
        the folder access it needs. Add another tool, set up later, or choose{" "}
        <strong className="font-medium text-fg">Try sample data</strong> to look around first.
      </>
    ),
    visual: (
      <div className="flex w-full flex-col gap-2 font-mono text-[12px]">
        <FolderRow path="~/.claude" />
        <FolderRow path="~/Library/Application Support/Claude" />
        <FolderRow path="~/.codex" />
      </div>
    ),
  },
  {
    title: "Glance",
    body: "That's it. The pill keeps count and the rings keep score. Click it whenever you want the details.",
    visual: <PillView dot="working" count={2} weekly={89} fiveHour={14} scale={1.3} />,
  },
];

function FolderRow({ path }: { path: string }) {
  const parts = path.split("/");
  return (
    <span className="flex min-w-0 items-center gap-2.5 rounded-xl border border-white/[0.07] bg-black/30 px-3 py-2 max-sm:px-2.5">
      <svg width="14" height="14" viewBox="0 0 14 14" aria-hidden="true" className="shrink-0">
        <circle cx="7" cy="7" r="6.3" fill="var(--color-teal)" />
        <path d="M4.3 7.2l1.8 1.8 3.6-4" fill="none" stroke="#000" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
      {/* From 640 px up the path is one line, cut with an ellipsis if need be. Phones let it wrap,
          but only after a slash, never at the space in "Application Support". */}
      <span className="truncate text-[#d9d8d2] max-sm:whitespace-normal">
        <span className="max-sm:hidden">{path}</span>
        <span className="sm:hidden">
          {parts.map((part, index) => (
            <Fragment key={index}>
              {index > 0 && <wbr />}
              <span className="whitespace-nowrap">
                {part}
                {index < parts.length - 1 && "/"}
              </span>
            </Fragment>
          ))}
        </span>
      </span>
    </span>
  );
}

export function HowItWorks() {
  return (
    <section id="how-it-works" aria-labelledby="how-title" className="wrap pt-16 sm:pt-28 md:pt-40 short:pt-16">
      <SectionHead
        id="how-title"
        eyebrow="How it works"
        title="Three steps, then just glance."
        intro="A short setup gets you started. Every connection is optional, and you can add more tools anytime."
      />
      <div className="relative mt-8 sm:mt-12 md:mt-16 short:mt-8">
        <span data-reveal className="steps-line hidden md:block" aria-hidden="true" />
        <ol className="relative grid gap-6 sm:gap-10 md:grid-cols-3 md:gap-8">
        {steps.map((step, index) => (
          // Phones: a two-column row, the number beside the title and a line down to the next step.
          <li
            key={step.title}
            data-reveal
            className="step relative max-sm:grid max-sm:grid-cols-[36px_minmax(0,1fr)] max-sm:gap-x-3.5"
            style={{ "--d": `${index * 120}ms` } as CSSProperties}
          >
            <span className="relative z-[1] grid size-9 place-items-center rounded-full border border-teal/40 bg-ink text-[14px] font-medium text-teal sm:size-12 sm:text-[15px]">
              {index + 1}
            </span>
            <h3 className="self-center text-[21px] font-medium tracking-[-0.03em] sm:mt-6 sm:self-auto sm:text-[24px]">{step.title}</h3>
            <p className="mt-1.5 max-w-[36ch] text-[16px] leading-relaxed text-muted max-sm:col-start-2 sm:mt-3 sm:text-[15px]">{step.body}</p>
            {/* Phones show only the folders: the badge and the pill are already in the hero. */}
            <div className={`mt-4 flex items-center max-sm:col-start-2 sm:mt-6 sm:min-h-[64px] ${index === 1 ? "" : "max-sm:hidden"}`}>
              {step.visual}
            </div>
          </li>
        ))}
        </ol>
      </div>
    </section>
  );
}
