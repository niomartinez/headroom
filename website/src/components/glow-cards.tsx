"use client";

import { useEffect } from "react";

/** Lets `.glass-card` hover glows follow the mouse, through --mx / --my. */
export function GlowCards() {
  useEffect(() => {
    if (!matchMedia("(hover: hover) and (pointer: fine)").matches) return;
    const onMove = (event: PointerEvent) => {
      const card = (event.target as Element | null)?.closest?.<HTMLElement>(".glass-card");
      if (!card) return;
      const rect = card.getBoundingClientRect();
      card.style.setProperty("--mx", `${event.clientX - rect.left}px`);
      card.style.setProperty("--my", `${event.clientY - rect.top}px`);
    };
    document.addEventListener("pointermove", onMove, { passive: true });
    return () => document.removeEventListener("pointermove", onMove);
  }, []);
  return null;
}
