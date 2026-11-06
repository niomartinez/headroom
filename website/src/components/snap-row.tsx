"use client";

import { Children, useEffect, useRef, useState, useSyncExternalStore, type ReactNode, type RefObject } from "react";

const PHONE = "(max-width: 639px)";

function useMediaQuery(query: string) {
  return useSyncExternalStore(
    (onChange) => {
      const list = matchMedia(query);
      list.addEventListener("change", onChange);
      return () => list.removeEventListener("change", onChange);
    },
    () => matchMedia(query).matches,
    () => false,
  );
}

/**
 * The index of the item a horizontal scroll-snap row is showing: the one nearest the start edge,
 * or the last one once the row is scrolled to its end. Updates at most once per frame.
 */
export function useSnapIndex(ref: RefObject<HTMLElement | null>) {
  const [index, setIndex] = useState(0);

  useEffect(() => {
    const row = ref.current;
    if (!row) return;
    let frame = 0;
    const update = () => {
      frame = 0;
      const items = row.children;
      if (items.length < 2) return setIndex(0);
      const max = row.scrollWidth - row.clientWidth;
      if (max > 4 && row.scrollLeft >= max - 4) return setIndex(items.length - 1);
      const step = (items[1] as HTMLElement).offsetLeft - (items[0] as HTMLElement).offsetLeft;
      setIndex(step > 0 ? Math.min(items.length - 1, Math.round(row.scrollLeft / step)) : 0);
    };
    const schedule = () => {
      if (!frame) frame = requestAnimationFrame(update);
    };
    schedule();
    row.addEventListener("scroll", schedule, { passive: true });
    const observer = new ResizeObserver(schedule);
    observer.observe(row);
    return () => {
      cancelAnimationFrame(frame);
      row.removeEventListener("scroll", schedule);
      observer.disconnect();
    };
  }, [ref]);

  return index;
}

/** Scrolls a snap row so item `index` sits at the start edge (the last ones stop at the end). */
export function scrollToItem(row: HTMLElement | null, index: number) {
  const items = row?.children;
  if (!row || !items?.length) return;
  const target = items[Math.min(index, items.length - 1)] as HTMLElement;
  const smooth = !matchMedia("(prefers-reduced-motion: reduce)").matches;
  row.scrollTo({ left: target.offsetLeft - (items[0] as HTMLElement).offsetLeft, behavior: smooth ? "smooth" : "auto" });
}

/**
 * Pagination dots for a snap row. Each dot is a button (a 24 px target around the 6 px dot) that
 * scrolls to its item; swiping and the arrow keys still work too.
 */
export function SnapDots({
  count,
  active,
  noun,
  onSelect,
  className = "",
}: {
  count: number;
  active: number;
  /** Names the items for screen readers: "Feature 3 of 8". */
  noun: string;
  onSelect: (index: number) => void;
  className?: string;
}) {
  return (
    <div className={`flex items-center ${className}`}>
      {Array.from({ length: count }, (_, index) => (
        <button
          key={index}
          type="button"
          className="snap-dot-button"
          aria-label={`${noun} ${index + 1} of ${count}`}
          aria-current={index === active ? "true" : undefined}
          onClick={() => onSelect(index)}
        >
          <span className="snap-dot" data-active={index === active ? "true" : "false"} />
        </button>
      ))}
    </div>
  );
}

/**
 * A list that is a swipeable carousel on phones (below 640 px: cards snap to the start edge, the
 * next one peeks in, dots show where you are) and whatever grid `className` sets from 640 px up.
 * The `snap-row` styles in globals.css do the phone layout, so the server render is already right.
 */
export function SnapRow({
  children,
  className = "",
  label,
  noun,
}: {
  children: ReactNode;
  className?: string;
  label: string;
  /** One item, for the dots' labels ("Feature"). */
  noun: string;
}) {
  const ref = useRef<HTMLUListElement>(null);
  const active = useSnapIndex(ref);
  const phone = useMediaQuery(PHONE);

  // On phones the cards fade in together when the row scrolls into view. Left to the page-wide
  // RevealObserver, the ones beyond the right edge would only fade in mid-swipe. Keyed on the
  // breakpoint, so it also arms when a phone turns from landscape to portrait.
  useEffect(() => {
    const row = ref.current;
    if (!row || !phone || matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const observer = new IntersectionObserver(
      (entries) => {
        if (!entries.some((entry) => entry.isIntersecting)) return;
        for (const item of row.querySelectorAll<HTMLElement>(":scope > [data-reveal]")) {
          item.classList.add("is-revealed");
          item.classList.remove("reveal-pending");
        }
        observer.disconnect();
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.12 },
    );
    observer.observe(row);
    return () => observer.disconnect();
  }, [phone]);

  return (
    <>
      <ul
        ref={ref}
        className={`snap-row ${className}`}
        aria-label={label}
        // A scroller needs a tab stop so the arrow keys can move it; the grid above 640 px doesn't.
        tabIndex={phone ? 0 : undefined}
      >
        {children}
      </ul>
      <SnapDots
        count={Children.count(children)}
        active={active}
        noun={noun}
        onSelect={(index) => scrollToItem(ref.current, index)}
        className="mt-3 justify-center sm:hidden"
      />
    </>
  );
}
