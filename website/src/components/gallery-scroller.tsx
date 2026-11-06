"use client";

import { Children, useEffect, useRef, useState, type ReactNode } from "react";
import { SnapDots, scrollToItem, useSnapIndex } from "./snap-row";

/** A native horizontal scroller with snap points, plus previous and next buttons. */
export function GalleryScroller({ children, label }: { children: ReactNode; label: string }) {
  const ref = useRef<HTMLDivElement>(null);
  const [edges, setEdges] = useState({ start: true, end: false });
  const active = useSnapIndex(ref);

  useEffect(() => {
    const element = ref.current;
    if (!element) return;
    let frame = 0;
    const update = () => {
      frame = 0;
      const max = element.scrollWidth - element.clientWidth;
      setEdges({ start: element.scrollLeft <= 4, end: element.scrollLeft >= max - 4 });
    };
    const schedule = () => {
      if (!frame) frame = requestAnimationFrame(update);
    };
    schedule();
    element.addEventListener("scroll", schedule, { passive: true });
    const observer = new ResizeObserver(schedule);
    observer.observe(element);
    return () => {
      cancelAnimationFrame(frame);
      element.removeEventListener("scroll", schedule);
      observer.disconnect();
    };
  }, []);

  const go = (direction: 1 | -1) => {
    const element = ref.current;
    if (!element) return;
    const card = element.querySelector("figure");
    const step = card ? card.getBoundingClientRect().width + 20 : element.clientWidth * 0.8;
    const smooth = !matchMedia("(prefers-reduced-motion: reduce)").matches;
    element.scrollBy({ left: direction * step, behavior: smooth ? "smooth" : "auto" });
  };

  return (
    <div>
      <div
        ref={ref}
        className="gallery"
        role="region"
        aria-label={label}
        tabIndex={0}
      >
        {children}
      </div>
      {/* Phones: dots on the left, right under the caption; from 640 px up only the arrows. */}
      <div className="wrap mt-4 flex items-center justify-between gap-3 sm:mt-6 sm:justify-end">
        <SnapDots
          count={Children.count(children)}
          active={active}
          noun="Screenshot"
          onSelect={(index) => scrollToItem(ref.current, index)}
          className="-ml-[9px] sm:hidden"
        />
        <div className="flex gap-3">
          <ArrowButton direction={-1} disabled={edges.start} onClick={() => go(-1)} />
          <ArrowButton direction={1} disabled={edges.end} onClick={() => go(1)} />
        </div>
      </div>
    </div>
  );
}

function ArrowButton({ direction, disabled, onClick }: { direction: 1 | -1; disabled: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-label={direction === 1 ? "Next screenshot" : "Previous screenshot"}
      className="grid size-11 place-items-center rounded-full sm:size-12 border border-white/15 text-fg transition-[background-color,border-color,opacity] duration-300 hover:border-teal/60 hover:bg-teal/10 disabled:cursor-default disabled:opacity-30 disabled:hover:border-white/15 disabled:hover:bg-transparent"
    >
      <svg width="18" height="18" viewBox="0 0 18 18" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" style={{ transform: direction === -1 ? "scaleX(-1)" : undefined }}>
        <path d="M3 9h12M10 4l5 5-5 5" />
      </svg>
    </button>
  );
}
