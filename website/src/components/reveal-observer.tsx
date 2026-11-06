"use client";

import { usePathname } from "next/navigation";
import { useEffect } from "react";

/**
 * Reveals `[data-reveal]` elements as they scroll into view. Only elements that start below the
 * fold are hidden first, so nothing already on screen flashes, and without JavaScript (or with
 * reduced motion) everything simply shows.
 */
export function RevealObserver() {
  const pathname = usePathname();
  useEffect(() => {
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const elements = Array.from(document.querySelectorAll<HTMLElement>("[data-reveal]:not(.is-revealed)"));
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          const element = entry.target as HTMLElement;
          element.classList.add("is-revealed");
          element.classList.remove("reveal-pending");
          observer.unobserve(element);
        }
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.12 },
    );
    const fold = window.innerHeight * 0.92;
    for (const element of elements) {
      if (element.getBoundingClientRect().top < fold) continue;
      element.classList.add("reveal-pending");
      observer.observe(element);
    }
    return () => {
      observer.disconnect();
      for (const element of elements) element.classList.remove("reveal-pending");
    };
  }, [pathname]);
  return null;
}
