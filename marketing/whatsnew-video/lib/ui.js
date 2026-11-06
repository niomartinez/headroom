// Headroom's UI as HTML and SVG, matching the app (HeadroomUI): ring geometry, the tool symbols' rule (centered
// when the gauge's middle is at least 10 pt, else a badge on the outer ring's upper left), the panel's grid.
// Sample data only. Everything is laid out once; scenes.js sets each frame's state.

export const K = 1.5; // px per pt
export const pt = (v) => v * K;
export const FONT = '-apple-system, "SF Pro Text", "Helvetica Neue", sans-serif';
export const DISPLAY = '-apple-system, "SF Pro Display", "Helvetica Neue", sans-serif';

export const COLORS = {
  pill: "#000000",
  panel: "#111111",
  track: "#444441",
  text: "#F1EFE8",
  muted: "#888780",
  sep: "rgba(241,239,232,0.08)",
  warning: "#EF9F27",
  critical: "#E24B4A",
  working: "#5DCAA5",
  idle: "#5F5E5A",
};
export const TINT = { claude: "#DFA78F", codex: "#9DBEDB", copilot: "#C4ACE4" };
export const TOOLS = ["claude", "codex", "copilot"];
export const NAMES = { claude: "Claude", codex: "Codex", copilot: "Copilot" };
export const toneColor = (p) => (p >= 95 ? COLORS.critical : p >= 75 ? COLORS.warning : COLORS.text);

const NS = "http://www.w3.org/2000/svg";
export function h(tag, cls, parent, style) {
  const el = document.createElement(tag);
  if (cls) el.className = cls;
  if (style) Object.assign(el.style, style);
  if (parent) parent.appendChild(el);
  return el;
}
export function svg(tag, attrs, parent) {
  const el = document.createElementNS(NS, tag);
  for (const k in attrs) el.setAttribute(k, attrs[k]);
  if (parent) parent.appendChild(el);
  return el;
}
export function show(el, on) {
  const v = on ? "" : "none";
  if (el.style.display !== v) el.style.display = v;
}

// Neutral glyphs in the spirit of the app's symbols: asterisk, </> and sparkles. Never a company's logo.
export const ICON_PATHS = {
  claude: '<g fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"><path d="M12 3.4V20.6"/><path d="M4.55 7.7L19.45 16.3"/><path d="M4.55 16.3L19.45 7.7"/></g>',
  codex: '<g fill="none" stroke="currentColor" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"><path d="M7.4 6.2L2.2 12L7.4 17.8"/><path d="M16.6 6.2L21.8 12L16.6 17.8"/><path d="M13.7 4.4L10.3 19.6"/></g>',
  copilot: '<g fill="currentColor"><path d="M14.4 4.8C15.1 10.6 16.2 11.7 22 12.4C16.2 13.1 15.1 14.2 14.4 20C13.7 14.2 12.6 13.1 6.8 12.4C12.6 11.7 13.7 10.6 14.4 4.8Z"/><path d="M6.2 2.2C6.56 5.06 7.14 5.64 10 6C7.14 6.36 6.56 6.94 6.2 9.8C5.84 6.94 5.26 6.36 2.4 6C5.26 5.64 5.84 5.06 6.2 2.2Z"/></g>',
};
export function icon(tool, sizePx, parent, style = {}) {
  const el = h("div", "icon", parent, { width: sizePx + "px", height: sizePx + "px", color: TINT[tool], ...style });
  el.innerHTML = `<svg viewBox="0 0 24 24" width="100%" height="100%" style="display:block;overflow:visible">${ICON_PATHS[tool]}</svg>`;
  return el;
}

// Text width, measured once on a canvas after the fonts load (deterministic per run).
const measureCanvas = document.createElement("canvas").getContext("2d");
export function measure(text, font) {
  measureCanvas.font = font;
  return measureCanvas.measureText(text).width;
}

// MARK: Gauge

const STYLES = {
  pill: { box: 18, outer: 7, inner: 3.5, line: 2 },
  compact: { box: 24, outer: 9.5, inner: 5, line: 2.5 },
  panel: { box: 64, outer: 26, inner: 17, line: 5 },
};

export class Gauge {
  constructor(parent, { style, sizePt, tool, twoRings, background, iconPx }) {
    const g = STYLES[style];
    this.size = pt(sizePt);
    this.tool = tool;
    this.el = h("div", "gauge", parent, { position: "absolute", left: "0", top: "0", width: this.size + "px", height: this.size + "px" });
    const s = svg("svg", { viewBox: `0 0 ${g.box} ${g.box}`, width: "100%", height: "100%" }, this.el);
    s.style.overflow = "visible";
    s.style.display = "block";
    const c = g.box / 2;
    this.rings = (twoRings ? [g.outer, g.inner] : [g.outer]).map((r) => {
      svg("circle", { cx: c, cy: c, r, fill: "none", stroke: COLORS.track, "stroke-width": g.line }, s);
      const arc = svg("circle", {
        cx: c, cy: c, r, fill: "none", stroke: COLORS.text, "stroke-width": g.line,
        "stroke-linecap": "round", transform: `rotate(-90 ${c} ${c})`,
      }, s);
      return { C: 2 * Math.PI * r, arc };
    });
    // GaugeToolIcon's rule, in points.
    const scale = sizePt / g.box;
    const middle = 2 * ((twoRings ? g.inner : g.outer) * scale - (g.line * scale) / 2);
    this.isBadge = middle < 10 && !iconPx;
    if (this.isBadge) {
      const d = pt(sizePt / 2);
      const off = this.size / 2 - d / 2 - pt(sizePt * 0.36);
      this.iconWrap = h("div", "badge", this.el, {
        position: "absolute", left: off + "px", top: off + "px", width: d + "px", height: d + "px",
        borderRadius: "50%", background, display: "flex", alignItems: "center", justifyContent: "center",
      });
      this.iconCenter = { x: off + d / 2, y: off + d / 2 };
      icon(tool, d * 0.68, this.iconWrap);
    } else {
      const f = iconPx || pt(Math.min(middle * 0.6, 16)) * 1.08;
      this.iconWrap = h("div", "mid", this.el, {
        position: "absolute", left: (this.size - f) / 2 + "px", top: (this.size - f) / 2 + "px", width: f + "px", height: f + "px",
      });
      this.iconCenter = { x: this.size / 2, y: this.size / 2 };
      icon(tool, f, this.iconWrap);
    }
  }

  // values: percents, outer first. icon: 0…1 visibility. stale dims the rings only.
  set({ x, y, values, icon = 1, iconScale = 1, stale = false, opacity = 1 }) {
    this.el.style.transform = `translate(${x - this.size / 2}px, ${y - this.size / 2}px)`;
    this.el.style.opacity = opacity;
    this.rings.forEach((ring, i) => {
      const p = values[i] ?? 0;
      const f = Math.max(0, Math.min(1, p / 100));
      show(ring.arc, f > 0.001);
      if (f > 0.001) {
        ring.arc.setAttribute("stroke-dasharray", `${(f * ring.C).toFixed(3)} ${ring.C.toFixed(3)}`);
        ring.arc.setAttribute("stroke", toneColor(p));
      }
    });
    this.el.querySelector("svg").style.opacity = stale ? 0.45 : 1;
    show(this.iconWrap, icon > 0.001);
    if (icon > 0.001) {
      this.iconWrap.style.opacity = Math.min(1, icon);
      this.iconWrap.style.transform = `scale(${iconScale})`;
    }
  }
}

// MARK: Pill

export class Pill {
  constructor(parent) {
    this.el = h("div", "pill", parent, { position: "absolute", left: "0", top: "0", height: pt(24) + "px" });
    this.bg = h("div", "pill-bg", this.el, { position: "absolute", left: "0", top: "0", height: "100%", borderRadius: pt(12) + "px", background: COLORS.pill });
    this.dot = h("div", "pill-dot", this.el, { position: "absolute", width: pt(8) + "px", height: pt(8) + "px", borderRadius: "50%", background: COLORS.warning });
    this.font = `500 ${pt(13)}px ${FONT}`;
    this.count = h("div", "pill-text", this.el, { position: "absolute", font: this.font, color: COLORS.text, lineHeight: "1" });
    this.count.textContent = "4";
    this.countW = measure("4", this.font) / K;
    this.gauges = TOOLS.map((tool) => new Gauge(this.el, { style: "pill", sizePt: 20, tool, twoRings: tool === "claude", background: COLORS.pill }));
    this.badges = TOOLS.map(() => {
      const clip = h("div", "pill-badge", this.el, { position: "absolute", overflow: "hidden", height: pt(24) + "px" });
      const tx = h("div", "pill-text", clip, { position: "absolute", left: "0", font: this.font, lineHeight: pt(24) + "px", whiteSpace: "nowrap" });
      return { clip, tx, text: "" };
    });
  }

  // Positions in pt from the pill's left edge. badge[i] = { p: 0…1, text }.
  layout(badges) {
    let x = 10 + 8 + 5 + this.countW + 8;
    const gauges = [];
    const badgeX = [];
    TOOLS.forEach((_, i) => {
      if (i > 0) x += 5;
      gauges.push(x + 10);
      x += 20;
      const b = badges[i];
      const w = b && b.p > 0 ? measure(b.text, this.font) / K : 0;
      badgeX.push(x + 5);
      x += b ? b.p * (5 + w + (i < 2 ? 2 : 0)) : 0;
    });
    return { width: x + 10, gauges, badgeX };
  }

  // right/cy in world px. Returns gauge centers in world px.
  set({ right, cy, values, badges = [], stale = [], icons = [1, 1, 1], iconScale = [1, 1, 1], offsets = [], bg = 1, lead = 1, opacity = 1 }) {
    const L = this.layout(badges);
    const left = right - pt(L.width);
    const top = cy - pt(12);
    this.el.style.transform = `translate(${left}px, ${top}px)`;
    this.el.style.width = pt(L.width) + "px";
    this.el.style.opacity = opacity;
    this.bg.style.width = pt(L.width) + "px";
    show(this.bg, bg > 0.001);
    this.bg.style.opacity = bg;
    show(this.dot, lead > 0.001);
    show(this.count, lead > 0.001);
    this.dot.style.opacity = lead;
    this.count.style.opacity = lead;
    this.dot.style.transform = `translate(${pt(10)}px, ${pt(8)}px)`;
    this.count.style.transform = `translate(${pt(23)}px, ${pt(12) - pt(13) * 0.5}px)`;
    const centers = [];
    TOOLS.forEach((tool, i) => {
      const o = offsets[i] || { x: 0, y: 0 };
      const gx = pt(L.gauges[i]) + o.x;
      const gy = pt(12) + o.y;
      this.gauges[i].set({ x: gx, y: gy, values: values[tool], icon: icons[i], iconScale: iconScale[i], stale: !!stale[i] });
      centers.push({ x: left + gx, y: top + gy });
      const b = badges[i];
      const bb = this.badges[i];
      const on = b && b.p > 0.001;
      show(bb.clip, on);
      if (on) {
        if (bb.text !== b.text) { bb.tx.textContent = b.text; bb.text = b.text; }
        bb.tx.style.color = b.color;
        const w = measure(b.text, this.font);
        bb.clip.style.transform = `translate(${pt(L.badgeX[i])}px, 0px)`;
        bb.clip.style.width = Math.max(0, w * b.p) + "px";
        bb.tx.style.opacity = Math.min(1, b.p * 1.4);
        bb.tx.style.transform = `translateY(${(1 - Math.min(1, b.p)) * pt(6)}px)`;
      }
    });
    return { left, top, width: pt(L.width), centers, badgeX: L.badgeX.map((x) => left + pt(x)) };
  }
}

// MARK: Menu bar

function wifiSVG() {
  return '<svg viewBox="0 0 24 18" width="100%" height="100%"><g fill="none" stroke="#F1EFE8" stroke-width="2.2" stroke-linecap="round"><path d="M2.5 6.5a14 14 0 0 1 19 0"/><path d="M6 10.2a9 9 0 0 1 12 0"/><path d="M9.4 13.8a4 4 0 0 1 5.2 0"/></g><circle cx="12" cy="16.4" r="1.4" fill="#F1EFE8"/></svg>';
}
function batterySVG() {
  return '<svg viewBox="0 0 30 14" width="100%" height="100%"><rect x="1" y="1" width="25" height="12" rx="3.5" fill="none" stroke="rgba(241,239,232,0.55)" stroke-width="1.4"/><rect x="3" y="3" width="17" height="8" rx="1.8" fill="#F1EFE8"/><path d="M27.8 5v4" stroke="rgba(241,239,232,0.55)" stroke-width="1.6" stroke-linecap="round"/></svg>';
}
function controlSVG() {
  return '<svg viewBox="0 0 22 18" width="100%" height="100%"><g fill="none" stroke="#F1EFE8" stroke-width="1.7"><rect x="1.5" y="1.5" width="19" height="6" rx="3"/><rect x="1.5" y="10.5" width="19" height="6" rx="3"/></g><circle cx="16.5" cy="4.5" r="1.9" fill="#F1EFE8"/><circle cx="5.5" cy="13.5" r="1.9" fill="#F1EFE8"/></svg>';
}
function flowerSVG() {
  let petals = "";
  for (let i = 0; i < 6; i++) petals += `<ellipse cx="12" cy="6.2" rx="3.2" ry="4.6" transform="rotate(${i * 60} 12 12)" fill="#F1EFE8"/>`;
  return `<svg viewBox="0 0 24 24" width="100%" height="100%">${petals}<circle cx="12" cy="12" r="2.6" fill="#16171C"/></svg>`;
}

export class MenuBar {
  constructor(parent) {
    this.el = h("div", "menubar", parent, { position: "absolute", left: "0", top: "0", width: "1920px", height: pt(30) + "px", background: "rgba(22,23,28,0.78)" });
    const font = `${pt(13)}px ${FONT}`;
    const row = h("div", "menu-left", this.el, { position: "absolute", left: pt(14) + "px", top: "0", height: "100%", display: "flex", alignItems: "center", gap: pt(19) + "px", font, color: COLORS.text });
    const flower = h("div", "", row, { width: pt(15) + "px", height: pt(15) + "px" });
    flower.innerHTML = flowerSVG();
    ["Editor", "File", "Edit", "View", "Window", "Help"].forEach((t, i) => {
      const s = h("span", "", row, { fontWeight: i === 0 ? "700" : "400" });
      s.textContent = t;
    });
    this.wifi = h("div", "", this.el, { position: "absolute", top: pt(8) + "px", width: pt(17) + "px", height: pt(13) + "px" });
    this.wifi.innerHTML = wifiSVG();
    this.battery = h("div", "", this.el, { position: "absolute", top: pt(9) + "px", width: pt(25) + "px", height: pt(12) + "px" });
    this.battery.innerHTML = batterySVG();
    this.control = h("div", "", this.el, { position: "absolute", top: pt(8) + "px", left: 1920 - pt(118) + "px", width: pt(17) + "px", height: pt(14) + "px" });
    this.control.innerHTML = controlSVG();
    this.clock = h("div", "", this.el, { position: "absolute", top: "0", right: pt(14) + "px", height: "100%", display: "flex", alignItems: "center", font, color: COLORS.text });
    this.clock.textContent = "Thu 2:10 PM";
  }
  set({ pillLeft, opacity = 1 }) {
    this.el.style.opacity = opacity;
    show(this.el, opacity > 0.001);
    this.battery.style.transform = `translate(${pillLeft - pt(37)}px, 0)`;
    this.wifi.style.transform = `translate(${pillLeft - pt(66)}px, 0)`;
  }
}

// The pill's right edge sits left of Control Center (world px), on the menu bar's centre line.
export const PILL_RIGHT = 1920 - pt(126);
export const PILL_CY = pt(15);

// MARK: Panel

function terminalSVG() {
  return '<svg viewBox="0 0 16 12" width="100%" height="100%"><rect x="0.8" y="0.8" width="14.4" height="10.4" rx="2" fill="none" stroke="#888780" stroke-width="1.2"/><path d="M3.6 4.2l2.2 1.8-2.2 1.8M7.6 8.2h3.4" fill="none" stroke="#888780" stroke-width="1.1" stroke-linecap="round" stroke-linejoin="round"/></svg>';
}
function gearSVG() {
  let teeth = "";
  for (let i = 0; i < 8; i++) teeth += `<rect x="10.6" y="1.4" width="2.8" height="5" rx="0.9" transform="rotate(${i * 45} 12 12)" fill="#888780"/>`;
  return `<svg viewBox="0 0 24 24" width="100%" height="100%">${teeth}<circle cx="12" cy="12" r="6.9" fill="#888780"/><circle cx="12" cy="12" r="2.9" fill="#111111"/></svg>`;
}
function keySVG(which) {
  // RingKeyGlyph: both rings, the named one drawn solid.
  return `<svg viewBox="0 0 20 20" width="100%" height="100%"><circle cx="10" cy="10" r="8" fill="none" stroke="currentColor" stroke-width="2.2" opacity="${which === "outer" ? 1 : 0.35}"/><circle cx="10" cy="10" r="3.6" fill="${which === "inner" ? "currentColor" : "none"}" stroke="currentColor" stroke-width="2" opacity="${which === "inner" ? 1 : 0.35}"/></svg>`;
}

const SESSIONS = [
  { group: "Working", y: 224 },
  { name: "Refactor invoice export", tool: "claude", project: "ledger", ctx: 72, dot: "working", y: 247.5 },
  { name: "website", tool: "codex", ctx: 41, dot: "working", y: 271 },
  { group: "Needs you", y: 302 },
  { name: "harbor", tool: "claude", terminal: true, ctx: 66, dot: "waiting", y: 325 },
  { name: "billing", tool: "copilot", terminal: true, dot: "waiting", y: 349 },
  { group: "Idle", y: 380 },
  { name: "Fix flaky upload test", tool: "claude", project: "atlas", ctx: 85, dot: "idle", y: 403.5 },
  { name: "Update pricing table", tool: "claude", project: "website", ctx: 71, dot: "idle", y: 427 },
  { name: "atlas", tool: "codex", terminal: true, ctx: 21, dot: "idle", y: 451 },
];

export const PANEL = { x: 1920 - pt(126) - pt(360), y: pt(30) + pt(6), w: pt(360), h: pt(540) };

export class Panel {
  constructor(parent) {
    this.el = h("div", "panel", parent, {
      position: "absolute", left: PANEL.x + "px", top: PANEL.y + "px", width: PANEL.w + "px", height: PANEL.h + "px",
      background: COLORS.panel, borderRadius: pt(14) + "px", boxShadow: "0 40px 120px rgba(0,0,0,0.55), inset 0 0 0 1px rgba(241,239,232,0.09)",
      overflow: "hidden", transformOrigin: "50% 0%",
    });
    const text = (str, x, y, size, opts = {}) => {
      const el = h("div", "t", this.el, {
        position: "absolute", left: pt(x) + "px", top: pt(y) - pt(size) * 0.62 + "px", font: `${opts.weight || 400} ${pt(size)}px ${FONT}`,
        color: opts.color || COLORS.text, whiteSpace: "nowrap", lineHeight: "1.24", fontVariantNumeric: "tabular-nums", ...(opts.style || {}),
      });
      el.textContent = str;
      if (opts.right) { el.style.left = "auto"; el.style.right = PANEL.w - pt(x) + "px"; }
      return el;
    };
    this.text = text;

    // Header: Claude, two rings, the symbol in the middle (multi-tool panel).
    this.header = new Gauge(this.el, { style: "panel", sizePt: 72, tool: "claude", twoRings: true, background: COLORS.panel });
    text("Claude", 104, 21, 11, { color: COLORS.muted });
    this.keyW = h("div", "", this.el, { position: "absolute", left: pt(104) + "px", top: pt(44) - pt(5) + "px", width: pt(10) + "px", height: pt(10) + "px" });
    this.keyW.innerHTML = keySVG("outer");
    this.keyH = h("div", "", this.el, { position: "absolute", left: pt(104) + "px", top: pt(84) - pt(5) + "px", width: pt(10) + "px", height: pt(10) + "px" });
    this.keyH.innerHTML = keySVG("inner");
    text("Weekly", 122, 44, 13, { weight: 500 });
    text("resets Sun 7 PM", 122, 61, 11, { color: COLORS.muted });
    text("5-hour", 122, 84, 13, { weight: 500 });
    text("resets in 2h 50m", 122, 101, 11, { color: COLORS.muted });
    this.pW = text("", 344, 44, 13, { weight: 600, right: true });
    this.pH = text("", 344, 84, 13, { weight: 600, right: true });

    // Codex: weekly only.
    this.codex = new Gauge(this.el, { style: "compact", sizePt: 24, tool: "codex", twoRings: false, background: COLORS.panel });
    text("Codex", 50, 136, 13, { weight: 500 });
    text("Weekly", 122, 136, 11, { color: COLORS.muted });
    this.pCodex = text("", 202, 136, 12, { weight: 600, right: true });
    text("resets Wed 9 AM", 210, 136, 11, { color: COLORS.muted });

    // Copilot: the message, or the organization seat's month.
    this.copilot = new Gauge(this.el, { style: "compact", sizePt: 24, tool: "copilot", twoRings: false, background: COLORS.panel });
    this.copilotName = text("Copilot", 50, 168.5, 13, { weight: 500 });
    this.noUsage = text("No usage billed to you this month", 108, 176.5, 11, { color: COLORS.muted });
    this.strike = h("div", "", this.el, { position: "absolute", height: "2px", background: COLORS.muted, transformOrigin: "0 50%" });
    this.seat = h("div", "", this.el, { position: "absolute", left: "0", top: "0", width: "100%", height: "100%" });
    const seatText = (str, x, y, size, opts) => { const el = text(str, x, y, size, opts); this.seat.appendChild(el); return el; };
    seatText("Monthly", 122, 168.5, 11, { color: COLORS.muted });
    this.pCopilot = seatText("", 202, 168.5, 12, { weight: 600, right: true });
    seatText("resets Nov 1", 210, 168.5, 11, { color: COLORS.muted });
    this.credits = seatText("", 122, 184.5, 11, { color: COLORS.muted });
    this.noUsageW = measure("No usage billed to you this month", `${pt(11)}px ${FONT}`);

    h("div", "", this.el, { position: "absolute", left: pt(16) + "px", top: pt(204) + "px", width: pt(328) + "px", height: "1px", background: COLORS.sep });

    // Sessions with their tool symbols, and the legend.
    this.rows = [];
    for (const s of SESSIONS) {
      if (s.group) { text(s.group, 16, s.y, 11, { weight: 500, color: COLORS.muted }); continue; }
      const row = h("div", "", this.el, { position: "absolute", left: "0", top: "0", width: "100%", height: "100%" });
      const dotSize = s.dot === "idle" ? 6 : 7;
      const dotColor = s.dot === "working" ? COLORS.working : s.dot === "waiting" ? COLORS.warning : COLORS.idle;
      h("div", "", row, { position: "absolute", left: pt(19.5 - dotSize / 2) + "px", top: pt(s.y - dotSize / 2) + "px", width: pt(dotSize) + "px", height: pt(dotSize) + "px", borderRadius: "50%", background: dotColor });
      if (s.dot === "working") h("div", "", row, { position: "absolute", left: pt(19.5 - 6) + "px", top: pt(s.y - 6) + "px", width: pt(12) + "px", height: pt(12) + "px", borderRadius: "50%", boxShadow: `inset 0 0 0 ${pt(1.3)}px ${COLORS.working}` });
      icon(s.tool, pt(11.5), row, { position: "absolute", left: pt(30.5) + "px", top: pt(s.y - 5.75) + "px" });
      const name = text(s.name, 51, s.y, 13);
      row.appendChild(name);
      let x = 51 + measure(s.name, `${pt(13)}px ${FONT}`) / K + 8;
      if (s.project) { const p = text(s.project, x, s.y, 11, { color: COLORS.muted }); row.appendChild(p); x += measure(s.project, `${pt(11)}px ${FONT}`) / K + 8; }
      if (s.terminal) { const term = h("div", "", row, { position: "absolute", left: pt(x) + "px", top: pt(s.y - 4.5) + "px", width: pt(12) + "px", height: pt(9) + "px" }); term.innerHTML = terminalSVG(); }
      if (s.ctx != null) {
        h("div", "", row, { position: "absolute", left: pt(262) + "px", top: pt(s.y - 2) + "px", width: pt(44) + "px", height: pt(4) + "px", borderRadius: pt(2) + "px", background: "rgba(241,239,232,0.16)" });
        h("div", "", row, { position: "absolute", left: pt(262) + "px", top: pt(s.y - 2) + "px", width: pt(44 * s.ctx / 100) + "px", height: pt(4) + "px", borderRadius: pt(2) + "px", background: s.ctx >= 75 ? COLORS.warning : COLORS.text });
        const pc = text(`${s.ctx}%`, 344, s.y, 11, { color: s.ctx >= 75 ? COLORS.warning : COLORS.muted, right: true });
        row.appendChild(pc);
      }
      this.rows.push({ ...s, el: row });
    }
    h("div", "", this.el, { position: "absolute", left: pt(16) + "px", top: pt(475) + "px", width: pt(328) + "px", height: "1px", background: COLORS.sep });
    let lx = 16;
    for (const tool of TOOLS) {
      icon(tool, pt(10.5), this.el, { position: "absolute", left: pt(lx) + "px", top: pt(494.5 - 5.25) + "px" });
      text(NAMES[tool], lx + 15, 494.5, 11, { color: COLORS.muted });
      lx += 15 + measure(NAMES[tool], `${pt(11)}px ${FONT}`) / K + 18;
    }
    text("Updated 2m ago", 16, 519, 11, { color: COLORS.muted });
    const gear = h("div", "", this.el, { position: "absolute", left: pt(334) + "px", top: pt(519 - 7) + "px", width: pt(14) + "px", height: pt(14) + "px" });
    gear.innerHTML = gearSVG();
  }

  // state: claude [w, h], codex, copilot { seat: 0…1, percent, used, strike: 0…1 }, reveal 0…1, icons 0…1.
  set({ opacity = 1, reveal = 1, scale = 1, claude, codex, copilot, icons = [1, 1, 1], iconScale = [1, 1, 1] }) {
    show(this.el, opacity > 0.001 && reveal > 0.001);
    if (opacity <= 0.001 || reveal <= 0.001) return;
    this.el.style.opacity = opacity;
    this.el.style.clipPath = reveal < 1 ? `inset(0 0 ${((1 - reveal) * 100).toFixed(3)}% 0 round ${pt(14)}px)` : "none";
    this.el.style.transform = `scale(${scale})`;
    this.header.set({ x: pt(52), y: pt(61), values: claude, icon: icons[0], iconScale: iconScale[0] });
    this.pW.textContent = `${Math.round(claude[0])}%`;
    this.pW.style.color = toneColor(claude[0]);
    this.pH.textContent = `${Math.round(claude[1])}%`;
    this.pH.style.color = toneColor(claude[1]);
    this.keyW.style.color = toneColor(claude[0]);
    this.keyH.style.color = toneColor(claude[1]);
    this.codex.set({ x: pt(28), y: pt(136), values: [codex], icon: icons[1], iconScale: iconScale[1] });
    this.pCodex.textContent = `${Math.round(codex)}%`;
    this.pCodex.style.color = toneColor(codex);

    const s = copilot.seat;
    this.copilot.set({ x: pt(28), y: pt(176.5), values: [s > 0 ? copilot.percent : 0], icon: icons[2], iconScale: iconScale[2] });
    const nameY = 176.5 - 8 * Math.min(1, s);
    this.copilotName.style.top = pt(nameY) - pt(13) * 0.62 + "px";
    show(this.noUsage, s < 0.999);
    this.noUsage.style.opacity = 1 - Math.min(1, s * 1.6);
    show(this.strike, copilot.strike > 0.001 && s < 0.999);
    if (copilot.strike > 0.001) {
      this.strike.style.left = pt(108) + "px";
      this.strike.style.top = pt(176.5) + "px";
      this.strike.style.width = this.noUsageW + "px";
      this.strike.style.transform = `scaleX(${copilot.strike})`;
      this.strike.style.opacity = 1 - Math.min(1, s * 1.6);
    }
    show(this.seat, s > 0.001);
    if (s > 0.001) {
      this.seat.style.opacity = Math.min(1, s);
      this.seat.style.transform = `translateY(${(1 - Math.min(1, s)) * pt(6)}px)`;
      this.pCopilot.textContent = `${Math.round(copilot.percent)}%`;
      this.pCopilot.style.color = toneColor(copilot.percent);
      this.credits.textContent = `${Math.round(copilot.used).toLocaleString("en-US")} of 50,000 credits`;
    }
  }

  // Panel-local pt → world px.
  point(xPt, yPt) {
    return { x: PANEL.x + pt(xPt), y: PANEL.y + pt(yPt) };
  }
}

// MARK: Cursor and tooltip

export class Cursor {
  constructor(parent) {
    this.el = h("div", "cursor", parent, { position: "absolute", left: "0", top: "0", width: pt(17) + "px", height: pt(25) + "px" });
    this.el.innerHTML = '<svg viewBox="0 0 17 25" width="100%" height="100%"><path d="M1.5 1.5v19.2l4.6-4.5 3.2 7.1 3.1-1.4-3.1-6.9h6.4z" fill="#111" stroke="#F7F6F2" stroke-width="1.4" stroke-linejoin="round"/></svg>';
  }
  set({ x, y, press = 0, opacity = 1 }) {
    show(this.el, opacity > 0.001);
    this.el.style.opacity = opacity;
    this.el.style.transform = `translate(${x}px, ${y}px) scale(${1 - 0.12 * press})`;
  }
}

export class Tooltip {
  constructor(parent, lines) {
    this.el = h("div", "tooltip", parent, {
      position: "absolute", left: "0", top: "0", padding: `${pt(4)}px ${pt(7)}px`, background: "rgba(48,48,52,0.97)",
      borderRadius: pt(5) + "px", boxShadow: "0 10px 30px rgba(0,0,0,0.45), inset 0 0 0 1px rgba(241,239,232,0.12)",
      font: `${pt(11)}px/1.35 ${FONT}`, color: COLORS.text, whiteSpace: "pre",
    });
    this.el.textContent = lines.join("\n");
  }
  set({ x, y, opacity }) {
    show(this.el, opacity > 0.001);
    this.el.style.opacity = opacity;
    this.el.style.transform = `translate(${x}px, ${y}px)`;
  }
}
