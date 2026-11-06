"use client";

import { useMotionValue, useReducedMotion, useSpring } from "motion/react";
import * as m from "motion/react-m";
import type { ReactNode } from "react";

/** Pulls its child a little toward the mouse pointer, on a spring (niomartinez.com's links). */
export function Magnetic({
  children,
  className = "",
  strength = 0.18,
}: {
  children: ReactNode;
  className?: string;
  strength?: number;
}) {
  const reduce = useReducedMotion();
  const x = useMotionValue(0);
  const y = useMotionValue(0);
  const sx = useSpring(x, { stiffness: 230, damping: 19 });
  const sy = useSpring(y, { stiffness: 230, damping: 19 });
  return (
    <m.div
      className={`inline-flex ${className}`}
      style={{ x: sx, y: sy }}
      onPointerMove={(event) => {
        if (reduce || event.pointerType !== "mouse") return;
        const rect = event.currentTarget.getBoundingClientRect();
        x.set((event.clientX - rect.left - rect.width / 2) * strength);
        y.set((event.clientY - rect.top - rect.height / 2) * strength);
      }}
      onPointerLeave={() => {
        x.set(0);
        y.set(0);
      }}
    >
      {children}
    </m.div>
  );
}
