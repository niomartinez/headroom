import type { CSSProperties } from "react";
import { Rings, limitTone, toneColor } from "./rings";

export type Moment =
  | { kind: "finished"; name: string; status: string }
  | { kind: "needsInput"; name: string; status: string }
  | { kind: "limit"; text: string; percent: number };

export type DotState = "working" | "waiting" | "idle";

const dotColor: Record<DotState, string> = {
  working: "var(--color-teal)",
  waiting: "var(--color-amber)",
  idle: "var(--color-idle)",
};

/** Stand-ins for the SF Symbols the app uses for moments. */
export function MomentIcon({ moment }: { moment: Moment }) {
  if (moment.kind === "finished") {
    // The native pill draws a thin check on the same clock as its expansion.
    return (
      <svg viewBox="0 0 16 16" className="pill-icon" aria-hidden="true">
        <path className="pill-check" pathLength="1" d="M2.5 8l3.8 3.6L13.5 4" fill="none" stroke="var(--color-teal)" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    );
  }
  if (moment.kind === "needsInput") {
    // exclamationmark.circle.fill
    return (
      <svg viewBox="0 0 16 16" className="pill-icon" aria-hidden="true">
        <circle cx="8" cy="8" r="7.2" fill="var(--color-amber)" />
        <rect x="7.1" y="3.7" width="1.8" height="5.6" rx="0.9" fill="#000" />
        <circle cx="8" cy="11.6" r="1.05" fill="#000" />
      </svg>
    );
  }
  // gauge.with.needle
  const color = toneColor[limitTone(moment.percent)];
  return (
    <svg viewBox="0 0 16 16" className="pill-icon" aria-hidden="true">
      <circle cx="8" cy="8" r="6.4" fill="none" stroke={color} strokeWidth="1.5" />
      <path d="M8 8.6l3-3.2" stroke={color} strokeWidth="1.5" strokeLinecap="round" />
      <circle cx="8" cy="8.6" r="1.25" fill={color} />
    </svg>
  );
}

function momentText(moment: Moment) {
  return moment.kind === "limit" ? moment.text : `${moment.name} ${moment.status}`;
}

export function pillLabel({
  count,
  dot,
  weekly,
  fiveHour,
  moment,
}: {
  count: number;
  dot: DotState;
  weekly: number;
  fiveHour: number;
  moment?: Moment | null;
}) {
  const sessions =
    count === 0
      ? "No active sessions"
      : `${count} active session${count === 1 ? "" : "s"}${dot === "waiting" ? ", one needs input" : ""}`;
  const text = `${sessions}. Weekly ${weekly}%, 5-hour ${fiveHour}%.`;
  return moment ? `${momentText(moment)}. ${text}` : text;
}

/**
 * The menu bar pill as markup: dot and count, the two-ring gauge and the tightest limit's number
 * (from 75 %). With `moment` set it widens to show the moment instead, as the app does. Slots
 * open and close together over 0.3 s, without fading the contents or removing the usage badge.
 */
export function PillView({
  dot,
  count,
  weekly,
  fiveHour,
  moment = null,
  shownMoment,
  scale,
  className = "",
  style,
}: {
  dot: DotState;
  count: number;
  weekly: number;
  fiveHour: number;
  /** The moment being announced, or null. */
  moment?: Moment | null;
  /** What the moment slot holds while it opens or closes; defaults to `moment`. */
  shownMoment?: Moment | null;
  /** Size multiplier for the 22 pt pill; leave unset to take `--s` from CSS. */
  scale?: number;
  className?: string;
  style?: CSSProperties;
}) {
  const tightest = Math.max(weekly, fiveHour);
  const badgeTone = limitTone(tightest);
  const inSlot = shownMoment ?? moment;
  return (
    <span className={`pill ${className}`} data-kind={moment?.kind ?? "normal"} style={{ ...(scale != null ? { "--s": scale } : {}), ...style } as CSSProperties} aria-hidden="true">
      <span className="pill-slot" data-open={moment ? "true" : "false"}>
        <span>
          {inSlot && (
            <span className="pill-part pill-moment">
              <MomentIcon moment={inSlot} />
              <span>{inSlot.kind === "limit" ? inSlot.text : inSlot.name}</span>
            </span>
          )}
        </span>
      </span>
      <span className="pill-slot" data-open={moment ? "false" : "true"}>
        <span>
          <span className="pill-part pill-status">
            <span className="dot" style={{ "--dot-color": dotColor[dot] } as CSSProperties}>
              {dot === "working" && <span className="dot-ring" />}
            </span>
            {count > 0 && <span>{count}</span>}
          </span>
        </span>
      </span>
      <Rings weekly={weekly} fiveHour={fiveHour} className="pill-rings" />
      {badgeTone !== "normal" && (
        <span className="pill-slot pill-badge" data-open="true">
          <span>
            <span className="pill-part" style={{ color: toneColor[badgeTone] }}>
              {tightest}%
            </span>
          </span>
        </span>
      )}
    </span>
  );
}
