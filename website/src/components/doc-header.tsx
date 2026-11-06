import type { CSSProperties, ReactNode } from "react";

export function DocHeader({ eyebrow, title, children }: { eyebrow: string; title: string; children?: ReactNode }) {
  return (
    <div className="relative isolate pb-12 pt-14 sm:pb-16 sm:pt-24">
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -top-40 left-1/2 -z-10 h-[560px] w-screen -translate-x-1/2"
        style={{
          background:
            "radial-gradient(34% 60% at 22% 34%, rgb(93 202 165 / 0.09), transparent 70%), radial-gradient(28% 50% at 72% 20%, rgb(239 159 39 / 0.05), transparent 70%)",
        }}
      />
      <p className="eyebrow intro-rise">{eyebrow}</p>
      <h1 className="display intro-rise mt-5 max-w-[14ch] text-[clamp(44px,6.4vw,92px)]" style={{ "--d": "60ms" } as CSSProperties}>
        {title}
      </h1>
      {children && (
        <div className="lede intro-rise mt-7 max-w-[620px]" style={{ "--d": "140ms" } as CSSProperties}>
          {children}
        </div>
      )}
    </div>
  );
}

export function Toc({ items }: { items: { id: string; label: string }[] }) {
  return (
    <nav aria-label="On this page" className="toc hidden lg:block">
      <div className="sticky top-28">
        <p className="label mb-3">On this page</p>
        {items.map((item) => (
          <a key={item.id} href={`#${item.id}`}>
            {item.label}
          </a>
        ))}
      </div>
    </nav>
  );
}
