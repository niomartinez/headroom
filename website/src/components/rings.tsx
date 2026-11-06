import type { CSSProperties } from "react";

export type Tone = "normal" | "warning" | "critical";

/** The app's limit thresholds: warning at 75 %, critical at 95 %. */
export function limitTone(percent: number): Tone {
  if (percent >= 95) return "critical";
  if (percent >= 75) return "warning";
  return "normal";
}

export const toneColor: Record<Tone, string> = {
  normal: "var(--color-offwhite)",
  warning: "var(--color-amber)",
  critical: "var(--color-red)",
};

const geometry = {
  /** The 18 pt menu bar gauge. */
  pill: { box: 18, outer: 7, inner: 3.5, line: 2 },
  /** The 72 pt panel header gauge (a 64-unit view box). */
  panel: { box: 64, outer: 26, inner: 17, line: 5 },
} as const;

/**
 * Two concentric rings, as in the app: outer = weekly limit, inner = 5-hour limit. Round caps,
 * from 12 o'clock, clockwise, over a #444441 track.
 */
export function Rings({
  weekly,
  fiveHour,
  variant = "pill",
  className,
  style,
}: {
  weekly: number;
  fiveHour: number;
  variant?: keyof typeof geometry;
  className?: string;
  style?: CSSProperties;
}) {
  const g = geometry[variant];
  const c = g.box / 2;
  return (
    <svg viewBox={`0 0 ${g.box} ${g.box}`} className={className} style={style} aria-hidden="true" focusable="false">
      {[
        { r: g.outer, value: weekly },
        { r: g.inner, value: fiveHour },
      ].map(({ r, value }) => {
        const tone = limitTone(value);
        const v = Math.max(0, Math.min(100, value));
        return (
          <g key={r}>
            <circle cx={c} cy={c} r={r} fill="none" stroke="var(--color-track)" strokeWidth={g.line} />
            {v > 0 && (
              <circle
                className="ring-arc"
                data-tone={tone}
                cx={c}
                cy={c}
                r={r}
                pathLength={100}
                transform={`rotate(-90 ${c} ${c})`}
                strokeWidth={g.line}
                style={{ stroke: toneColor[tone], strokeDasharray: `${v} 100` }}
              />
            )}
          </g>
        );
      })}
    </svg>
  );
}
