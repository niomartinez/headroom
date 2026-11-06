// The piece: window.__render(t) draws any frame as a pure function of time. No clocks, no unseeded randomness,
// no state carried between frames, so frames render alone, in any order, on any worker.

import { CUE, DURATION } from "./lib/timeline.js";
import {
  clamp, lerp, progress, outExpo, inExpo, inOutExpo, outCubic, inOutCubic, spring, rng, noise, shake, window as win,
} from "./lib/engine.js";
import {
  pt, COLORS, TINT, TOOLS, NAMES, DISPLAY, FONT, h, svg, show, icon, measure, Gauge, Pill, MenuBar, Panel, Cursor, Tooltip, PILL_RIGHT, PILL_CY, PANEL,
} from "./lib/ui.js";

const W = 1920;
const H = 1080;
const stage = document.getElementById("stage");
const rgba = (hex, a) => { const n = parseInt(hex.slice(1), 16); return `rgba(${n >> 16},${(n >> 8) & 255},${n & 255},${a})`; };
const layer = (cls, style = {}) => h("div", `layer ${cls}`, stage, style);

// MARK: Layers (back to front)

const bgLayer = layer("bg");
const world = h("div", "world", stage, { position: "absolute", left: "0", top: "0", width: W + "px", height: H + "px", transformOrigin: "0 0" });
const fxLayer = layer("fx");
const calloutLayer = layer("callouts");
const scrim = layer("scrim", { background: "linear-gradient(to top, rgb(4,4,6) 0%, rgb(4,4,6) 22%, rgba(4,4,6,0.9) 27%, rgba(4,4,6,0.62) 33%, rgba(4,4,6,0.25) 40%, rgba(4,4,6,0) 47%)" });
const typeLayer = layer("type");
const endLayer = layer("end");
const flashLayer = layer("flash", { background: "radial-gradient(ellipse at 50% 45%, rgba(255,255,255,0.9), rgba(255,255,255,0.45) 70%, rgba(255,255,255,0.25))" });
layer("vignette", { background: "radial-gradient(ellipse at 50% 50%, transparent 56%, rgba(0,0,0,0.55) 100%)" });
const fadeLayer = layer("fade", { background: "#000" });

// MARK: Background: deep ink, and a light field per tool that its moments brighten.

h("div", "", bgLayer, { position: "absolute", inset: "0", background: "radial-gradient(ellipse at 50% 32%, #12141C 0%, #08090D 62%, #040406 100%)" });
const FIELD_HOME = { claude: [0.16, 0.86], codex: [0.88, 0.16], copilot: [0.7, 0.96] };
const fields = TOOLS.map((tool) => h("div", "", bgLayer, {
  position: "absolute", left: "0", top: "0", width: "1700px", height: "1700px", marginLeft: "-850px", marginTop: "-850px",
  borderRadius: "50%", background: `radial-gradient(closest-side, ${rgba(TINT[tool], 0.5)}, ${rgba(TINT[tool], 0)})`,
}));

// MARK: World: the menu bar, the pill and the panel, laid out once and moved by one camera transform.

const menu = new MenuBar(world);
const pill = new Pill(world);
const panel = new Panel(world);
const cursor = new Cursor(world);
const tooltip = new Tooltip(world, ["Enterprise plan · @octocat", "Monthly resets Nov 1, 2026 at 8:00 AM", "As of 2m ago"]);
const flyers = TOOLS.map((tool) => icon(tool, 100, world, { position: "absolute", left: "0", top: "0", transformOrigin: "50% 50%" }));

// Pill geometry without badges (the hook, the stamps).
const HOOK_LAYOUT = pill.layout([]);
const pillLeftHook = PILL_RIGHT - pt(HOOK_LAYOUT.width);
const GAUGE_X = HOOK_LAYOUT.gauges.map((g) => pillLeftHook + pt(g));
const GAUGE_MID = { x: (GAUGE_X[0] + GAUGE_X[2]) / 2, y: PILL_CY };
const BADGE_OFF = pt(20) / 2 - pt(10) / 2 - pt(20 * 0.36); // Claude's badge, from the gauge's top-left
const badgeCenter = () => ({ x: GAUGE_X[0] - pt(10) + BADGE_OFF + pt(5), y: PILL_CY - pt(10) + BADGE_OFF + pt(5) });
// Gauge x with all three percentages showing (the warning beat on). Measured on first use, once fonts are in.
let warnGauges;
const warnGaugeX = () => {
  if (!warnGauges) {
    const L = pill.layout(["89%", "94%", "96%"].map((text) => ({ p: 1, text })));
    warnGauges = L.gauges.map((g) => PILL_RIGHT - pt(L.width) + pt(g));
  }
  return warnGauges;
};
const stampTarget = (i) => (i === 0 ? badgeCenter() : { x: GAUGE_X[i], y: PILL_CY });

// MARK: Camera: translate, a 0.03° tilt, scale, translate. Zoom moves on a log scale.

const CAM = {
  hook: { fx: GAUGE_MID.x, fy: GAUGE_MID.y, z: 9.2, sx: 960, sy: 470 },
  pillA: { fx: GAUGE_X[1] - pt(4), fy: PILL_CY, z: 4.4, sx: 1250, sy: 230 },
  panel: { fx: PANEL.x + PANEL.w / 2, fy: 330, z: 1.45, sx: 1350, sy: 470 },
  panelI: { fx: PANEL.x + PANEL.w / 2, fy: 300, z: 1.6, sx: 1400, sy: 520 },
  row: { fx: PANEL.x + pt(190), fy: PANEL.y + pt(176.5), z: 2.35, sx: 1540, sy: 600 },
  pillC: { fx: PILL_RIGHT - pt(104), fy: PILL_CY, z: 3.2, sx: 1200, sy: 300 },
};
const blend = (a, b, u) => ({
  fx: lerp(a.fx, b.fx, u), fy: lerp(a.fy, b.fy, u), sx: lerp(a.sx, b.sx, u), sy: lerp(a.sy, b.sy, u),
  z: Math.exp(lerp(Math.log(a.z), Math.log(b.z), u)),
});
const push = (c, k) => ({ ...c, z: c.z * k });

const HITS = [
  { t: CUE.stampClaude, amp: 13 }, { t: CUE.stampCodex, amp: 11 }, { t: CUE.stampCopilot, amp: 13 },
  { t: CUE.pullback, amp: 16, decay: 0.16 }, { t: CUE.drop2, amp: 22, decay: 0.18 },
  { t: CUE.badgeClaude, amp: 4 }, { t: CUE.badgeCodex, amp: 4 }, { t: CUE.badgeCopilot, amp: 5 },
  { t: CUE.montage1, amp: 9 }, { t: CUE.montage2, amp: 9 }, { t: CUE.montage3, amp: 9 }, { t: CUE.fuse, amp: 15, decay: 0.16 },
];

function camera(t) {
  let c;
  if (t < CUE.pullback) {
    c = push(CAM.hook, 0.94 + 0.06 * progress(t, 0, CUE.pullback));
  } else if (t < CUE.pullback + 1.1) {
    c = blend(CAM.hook, CAM.pillA, inOutExpo(progress(t, CUE.pullback, CUE.pullback + 1.1)));
  } else if (t < CUE.flight) {
    c = push(CAM.pillA, 1 + 0.03 * progress(t, CUE.pullback + 1.1, CUE.flight));
  } else if (t < CUE.flight + 1.0) {
    c = blend(push(CAM.pillA, 1.03), CAM.panel, outExpo(progress(t, CUE.flight, CUE.flight + 1.0)));
  } else if (t < CUE.zoomCopilot) {
    c = push(CAM.panel, 1 + 0.035 * progress(t, CUE.flight + 1.0, CUE.zoomCopilot));
  } else if (t < CUE.zoomCopilot + 0.9) {
    c = blend(push(CAM.panel, 1.035), CAM.row, inOutExpo(progress(t, CUE.zoomCopilot, CUE.zoomCopilot + 0.9)));
  } else if (t < CUE.drop2) {
    c = push(CAM.row, 1 + 0.04 * outCubic(progress(t, CUE.zoomCopilot + 0.9, CUE.silence)));
  } else if (t < CUE.whip) {
    const punch = Math.exp(-(t - CUE.drop2) / 0.22) * (1 - Math.exp(-(t - CUE.drop2) / 0.03));
    c = push(CAM.row, (1.04 - 0.1 * progress(t, CUE.drop2, CUE.whip)) * (1 + 0.1 * punch));
  } else if (t < CUE.whip + 0.42) {
    c = blend(push(CAM.row, 0.94), CAM.pillC, inOutExpo(progress(t, CUE.whip, CUE.whip + 0.42)));
  } else if (t < CUE.interact) {
    c = push(CAM.pillC, 1 + 0.04 * progress(t, CUE.whip + 0.42, CUE.interact));
  } else if (t < CUE.interact + 0.8) {
    c = blend(push(CAM.pillC, 1.04), CAM.panelI, inOutExpo(progress(t, CUE.interact, CUE.interact + 0.8)));
  } else if (t < CUE.montage1) {
    c = push(CAM.panelI, 1 + 0.02 * progress(t, CUE.interact + 0.8, CUE.montage1));
  } else if (t < CUE.montage2) {
    // Pans from Claude's ring (badge in frame) to Copilot's, on the pill as it is now: all three percentages.
    const u = inOutCubic(progress(t, CUE.montage1, CUE.montage2));
    const g = warnGaugeX();
    c = { fx: lerp(g[0] + pt(37), g[2] + pt(13), u), fy: PILL_CY, z: 7.2, sx: 960, sy: 520 };
  } else if (t < CUE.montage3) {
    const u = outCubic(progress(t, CUE.montage2, CUE.montage3));
    c = { fx: PANEL.x + pt(118), fy: PANEL.y + pt(176.5), z: 4.4 + 0.5 * u, sx: 760, sy: 560 };
  } else {
    const u = inOutCubic(progress(t, CUE.montage3, CUE.merge));
    c = { fx: PANEL.x + pt(150), fy: PANEL.y + pt(lerp(290, 400, u)), z: 2.5, sx: 1010, sy: 540 };
  }
  const drift = t < CUE.merge ? 1 : 0;
  return {
    ...c,
    shx: shake(t, HITS, 3) + drift * 2.2 * noise(t * 0.35, 11),
    shy: shake(t, HITS, 5) + drift * 2.2 * noise(t * 0.35, 13),
  };
}
let CAMERA = camera(0);
const project = (p) => ({ x: CAMERA.sx + CAMERA.z * (p.x - CAMERA.fx) + CAMERA.shx, y: CAMERA.sy + CAMERA.z * (p.y - CAMERA.fy) + CAMERA.shy });

// MARK: Kinetic type: words rise into clip boxes, one at a time, and leave the same way.

class Headline {
  constructor(lines, { x, y, size = 92, weight = 700, align = "left", tints = {}, parent = typeLayer, color = COLORS.text, tracking = -0.034 }) {
    this.align = align;
    this.el = h("div", "headline", parent, {
      position: "absolute", left: x + "px", top: y + "px", font: `${weight} ${size}px/1.06 ${DISPLAY}`,
      letterSpacing: `${tracking}em`, color, whiteSpace: "nowrap", textAlign: align,
    });
    this.words = [];
    for (const line of lines) {
      const row = h("div", "", this.el);
      for (const word of line.split(" ")) {
        const clip = h("span", "", row, { display: "inline-block", overflow: "hidden", verticalAlign: "top", padding: "0.04em 0.02em 0.16em", margin: "-0.04em 0.2em -0.16em -0.02em" });
        const w = h("span", "", clip, { display: "inline-block", color: tints[word] || color });
        w.textContent = word;
        this.words.push(w);
      }
    }
  }
  set(t, tIn, tOut, { stagger = 0.07, dur = 0.65, outStagger = 0.03, outDur = 0.34, cutAt = Infinity } = {}) {
    const end = tOut + outDur + outStagger * this.words.length;
    const on = t >= tIn && t <= end && t < cutAt;
    show(this.el, on);
    if (!on) return;
    this.el.style.transform = `${this.align === "center" ? "translateX(-50%) " : ""}rotate(0.03deg)`;
    this.words.forEach((w, i) => {
      const p = outExpo((t - tIn - i * stagger) / dur);
      const q = inExpo((t - tOut - i * outStagger) / outDur);
      w.style.visibility = p > 0 && q < 1 ? "visible" : "hidden";
      w.style.transform = `translateY(${((1 - p) * 115 - q * 115).toFixed(3)}%)`;
    });
  }
}

const HL = {
  rings: new Headline(["Three rings."], { x: 960, y: 760, size: 88, align: "center" }),
  which: new Headline(["Which is which?"], { x: 960, y: 760, size: 88, align: "center" }),
  icons: new Headline(["Now every ring", "wears its icon."], { x: 130, y: 470 }),
  panel: new Headline(["Same icons,", "in the panel."], { x: 130, y: 440 }),
  company: new Headline(["Copilot paid by", "your company?"], { x: 130, y: 400, tints: { "Copilot": TINT.copilot } }),
  counted: new Headline(["Your company’s", "seat, counted."], { x: 130, y: 380, tints: { "counted.": TINT.copilot } }),
  warning: new Headline(["A number for", "every warning."], { x: 130, y: 560, tints: { "warning.": COLORS.warning } }),
  hover: new Headline(["Hover for the details."], { x: 130, y: 470, size: 72 }),
  m1: new Headline(["Icons on every ring."], { x: 130, y: 900, size: 64, weight: 600 }),
  m2: new Headline(["Company seats, counted."], { x: 130, y: 900, size: 64, weight: 600 }),
  m3: new Headline(["Every session, tagged."], { x: 130, y: 900, size: 64, weight: 600 }),
};

// MARK: Callouts: leader lines from a label to the UI they explain.

const calloutSvg = svg("svg", { width: W, height: H, viewBox: `0 0 ${W} ${H}` }, calloutLayer);
calloutSvg.style.position = "absolute";
class Callout {
  constructor(text, tool) {
    this.line = svg("path", { fill: "none", stroke: "rgba(241,239,232,0.62)", "stroke-width": 2, "stroke-linecap": "round" }, calloutSvg);
    this.dot = svg("circle", { r: 6, fill: tool ? TINT[tool] : COLORS.text }, calloutSvg);
    this.ring = svg("circle", { r: 12, fill: "none", stroke: tool ? TINT[tool] : COLORS.text, "stroke-width": 2 }, calloutSvg);
    this.label = h("div", "callout", calloutLayer, {
      position: "absolute", left: "0", top: "0", display: "flex", alignItems: "center", gap: "12px",
      font: `600 36px ${FONT}`, color: COLORS.text, whiteSpace: "nowrap", letterSpacing: "-0.01em",
    });
    if (tool) icon(tool, 36, this.label);
    h("span", "", this.label).textContent = text;
  }
  set(p, label, target) {
    const on = p > 0.001;
    show(this.line, on); show(this.dot, on); show(this.ring, on); show(this.label, on);
    if (!on) return;
    const len = Math.hypot(target.x - label.x, target.y - label.y);
    this.line.setAttribute("d", `M${label.x.toFixed(2)} ${label.y.toFixed(2)} L${target.x.toFixed(2)} ${target.y.toFixed(2)}`);
    this.line.setAttribute("stroke-dasharray", `${len} ${len}`);
    this.line.setAttribute("stroke-dashoffset", `${(1 - outExpo(p)) * len}`);
    const d = clamp((p - 0.35) / 0.65);
    this.dot.setAttribute("cx", target.x); this.dot.setAttribute("cy", target.y); this.dot.setAttribute("r", 6 * outExpo(d));
    this.ring.setAttribute("cx", target.x); this.ring.setAttribute("cy", target.y);
    this.ring.setAttribute("r", 6 + 10 * outExpo(d)); this.ring.setAttribute("opacity", 1 - outCubic(d) * 0.7);
    const lp = outExpo(clamp(p / 0.6));
    this.label.style.opacity = lp;
    this.label.style.transform = `translate(${label.lx ?? label.x}px, ${(label.ly ?? label.y) + (1 - lp) * 18}px) rotate(0.03deg)`;
  }
}
const SEAT_W = measure("Business and Enterprise seats", `600 36px ${FONT}`);
const CALL = {
  claude: new Callout("Claude", "claude"),
  codex: new Callout("Codex", "codex"),
  copilot: new Callout("Copilot", "copilot"),
  seat: new Callout("Business and Enterprise seats", null),
  credits: new Callout("AI credits used this month", null),
};

// MARK: FX: shockwaves and particle bursts pinned to the UI (screen space, projected each frame).

const BURSTS = [
  { t: CUE.stampClaude, tool: "claude", at: () => stampTarget(0), n: 18 },
  { t: CUE.stampCodex, tool: "codex", at: () => stampTarget(1), n: 18 },
  { t: CUE.stampCopilot, tool: "copilot", at: () => stampTarget(2), n: 18 },
  { t: CUE.drop2, tool: "copilot", at: () => panel.point(28, 176.5), n: 26, big: true },
  { t: CUE.fuse, tool: null, at: () => null, n: 30, big: true, screen: { x: 960, y: 470 } },
];
const waves = BURSTS.map(() => [0, 1].map(() => h("div", "", fxLayer, { position: "absolute", left: "0", top: "0", borderRadius: "50%", boxSizing: "border-box" })));
const sparks = BURSTS.map((b, bi) => {
  const r = rng(101 + bi * 17);
  return Array.from({ length: b.n }, () => {
    const a = r() * Math.PI * 2;
    const speed = (b.big ? 700 : 520) * (0.45 + r() * 0.75);
    const size = 5 + r() * 9;
    const el = h("div", "", fxLayer, { position: "absolute", left: "0", top: "0", width: size + "px", height: size + "px", borderRadius: "50%" });
    return { el, a, speed, size, life: 0.45 + r() * 0.45 };
  });
});
function drawFx(t) {
  BURSTS.forEach((b, bi) => {
    const dt = t - b.t;
    const on = dt >= 0 && dt < 1.0;
    const origin = on ? (b.screen || project(b.at())) : { x: 0, y: 0 };
    const tint = b.tool ? TINT[b.tool] : COLORS.text;
    waves[bi].forEach((w, k) => {
      const d = dt - k * 0.08;
      const live = on && d >= 0 && d < 0.7;
      show(w, live);
      if (!live) return;
      const p = outExpo(d / 0.7);
      const r = (b.big ? 360 : 230) * p + 10;
      w.style.width = w.style.height = 2 * r + "px";
      w.style.border = `${Math.max(0.5, (b.big ? 10 : 7) * (1 - p))}px solid ${k ? COLORS.text : tint}`;
      w.style.opacity = (1 - p) * (k ? 0.5 : 0.9);
      w.style.transform = `translate(${origin.x - r}px, ${origin.y - r}px)`;
    });
    sparks[bi].forEach((s) => {
      const live = on && dt < s.life;
      show(s.el, live);
      if (!live) return;
      const travel = (s.speed * (1 - Math.exp(-dt * 7))) / 7;
      const life = dt / s.life;
      const size = s.size * (1 - life * 0.7);
      s.el.style.width = s.el.style.height = size + "px";
      s.el.style.background = tint;
      s.el.style.opacity = 1 - outCubic(life);
      s.el.style.transform = `translate(${origin.x + Math.cos(s.a) * travel - size / 2}px, ${origin.y + Math.sin(s.a) * travel - size / 2}px)`;
    });
  });
}

// MARK: The merge and the end card.

const MERGE_VALUES = { claude: [58, 41], codex: [36], copilot: [8] };
const bigRings = TOOLS.map((tool) => new Gauge(endLayer, { style: "pill", sizePt: 180, tool, twoRings: tool === "claude", background: "#000", iconPx: 104 }));
const endIcon = h("img", "", endLayer, { position: "absolute", left: "0", top: "0", width: "300px", height: "300px", transformOrigin: "50% 50%" });
endIcon.src = "assets/app-icon-1024.png";
const endGlyphs = TOOLS.map((tool) => icon(tool, 104, endLayer, { position: "absolute", left: "0", top: "0", transformOrigin: "50% 50%" }));
const wordmark = new Headline(["Headroom"], { x: 960, y: 420, size: 112, align: "center", parent: endLayer, tracking: -0.04 });
const tagline = new Headline(["Every ring, named."], { x: 960, y: 642, size: 46, weight: 500, align: "center", parent: endLayer, color: "#D9D7CF", tracking: -0.02 });
const cta = h("div", "", endLayer, {
  position: "absolute", left: "0", top: "0", padding: "20px 40px", borderRadius: "999px", background: COLORS.text, color: "#0B0C10",
  font: `600 32px ${FONT}`, whiteSpace: "nowrap", letterSpacing: "-0.01em",
});
cta.textContent = "Free on the Mac App Store";
const url = h("div", "", endLayer, { position: "absolute", left: "0", top: "0", font: `500 27px ${FONT}`, color: "#A9A79F", whiteSpace: "nowrap" });
url.textContent = "headroom.niomartinez.com";
const fine = h("div", "", endLayer, { position: "absolute", left: "0", top: "0", font: `400 18px ${FONT}`, color: "#6F6E68", whiteSpace: "nowrap" });
fine.textContent = "Headroom isn’t made by or affiliated with Anthropic, OpenAI or GitHub.";
const centerEl = (el, x, y, extra = "") => {
  el.style.transform = `translate(${x}px, ${y}px) translate(-50%, -50%) ${extra} rotate(0.03deg)`;
};

function drawEnd(t) {
  const SLOT = [623, 960, 1297];
  const merging = t >= CUE.merge && t < CUE.fuse + 0.02;
  bigRings.forEach((g, i) => {
    show(g.el, merging);
    if (!merging) return;
    const enter = outExpo(progress(t, CUE.merge, CUE.merge + 0.45));
    const slide = inOutExpo(progress(t, CUE.merge + 0.5, CUE.fuse));
    const x = lerp(SLOT[i], 960, slide);
    const s = (0.82 + 0.18 * enter) * lerp(1, 0.62, slide);
    g.set({ x, y: 470, values: MERGE_VALUES[TOOLS[i]], icon: 1 - progress(t, CUE.merge + 0.55, CUE.merge + 0.6) });
    g.el.style.transform += ` scale(${s})`;
    g.el.style.opacity = enter;
  });
  // The symbols lift off the rings and land in a row under the wordmark.
  endGlyphs.forEach((el, i) => {
    const t0 = CUE.merge + 0.55 + i * 0.06;
    const on = t >= t0 && t < DURATION;
    show(el, on);
    if (!on) return;
    const u = inOutExpo(progress(t, t0, CUE.fuse + 0.35 + i * 0.06));
    const x = lerp(SLOT[i], 960 + (i - 1) * 86, u);
    const y = lerp(470, 590, u) - Math.sin(Math.PI * u) * 190;
    const s = lerp(1, 0.4, u);
    el.style.transform = `translate(${x - 52}px, ${y - 52}px) scale(${s}) rotate(0.03deg)`;
  });
  const iconOn = t >= CUE.fuse;
  show(endIcon, iconOn);
  if (iconOn) {
    const sp = spring(t - CUE.fuse, 0.5, 0.72);
    const move = inOutExpo(progress(t, CUE.fuse + 0.25, CUE.endCard + 0.5));
    centerEl(endIcon, 960, lerp(470, 270, move), `scale(${lerp(0.55, 1, sp) * lerp(1, 0.8, move)})`);
  }
  wordmark.set(t, CUE.endCard + 0.05, DURATION + 5, { stagger: 0.05 });
  tagline.set(t, CUE.endCard + 0.45, DURATION + 5, { stagger: 0.08 });
  const ctaP = spring(t - (CUE.endCard + 0.8), 0.5, 0.7);
  show(cta, t >= CUE.endCard + 0.8);
  if (t >= CUE.endCard + 0.8) { centerEl(cta, 960, 780, `scale(${lerp(0.7, 1, ctaP)})`); cta.style.opacity = clamp(ctaP * 1.5); }
  const urlP = outExpo(progress(t, CUE.endCard + 1.05, CUE.endCard + 1.6));
  show(url, urlP > 0);
  if (urlP > 0) { centerEl(url, 960, 868 + (1 - urlP) * 14); url.style.opacity = urlP; }
  const fineP = outExpo(progress(t, CUE.endCard + 1.2, CUE.endCard + 1.8));
  show(fine, fineP > 0);
  if (fineP > 0) { centerEl(fine, 960, 1030); fine.style.opacity = fineP; }
}

// MARK: The state of the pill and the panel over time.

function stampIn(t, cue) {
  // The glyph falls into place: 0 before, 1 from the hit.
  return inExpo(progress(t, cue - 0.24, cue));
}

function pillState(t) {
  const draw = outExpo(progress(t, 0.15, 1.4));
  const rampC = (from, to, t0) => lerp(from, to, outExpo(progress(t, t0, t0 + 0.42)));
  const claudeW = t < CUE.featureC ? 58 * draw : rampC(58, 89, CUE.badgeClaude - 0.42);
  const codexW = t < CUE.featureC ? 36 * draw : rampC(36, 94, CUE.badgeCodex - 0.42);
  const copilotW = t < CUE.featureC ? 8 * draw : rampC(8, 96, CUE.badgeCopilot - 0.42);
  const badge = (cue, value, text) => ({ p: Math.min(1, spring(t - cue, 0.42, 0.7)), text, color: value >= 95 ? COLORS.critical : COLORS.warning });
  const badges = t < CUE.featureC ? [] : [badge(CUE.badgeClaude, 89, "89%"), badge(CUE.badgeCodex, 94, "94%"), badge(CUE.badgeCopilot, 96, "96%")];
  const stamps = [CUE.stampClaude, CUE.stampCodex, CUE.stampCopilot];
  // The shell game: two swaps and a settle, back to Claude, Codex, Copilot.
  const SW = [
    { t0: CUE.swap1, t1: CUE.swap1 + 0.36, from: [0, 1, 2], to: [2, 1, 0] },
    { t0: CUE.swap2, t1: CUE.swap2 + 0.36, from: [2, 1, 0], to: [2, 0, 1] },
    { t0: CUE.swap2 + 0.5, t1: CUE.swap2 + 0.92, from: [2, 0, 1], to: [0, 1, 2] },
  ];
  const offsets = [0, 1, 2].map((i) => {
    for (const s of SW) {
      if (t >= s.t0 && t < s.t1) {
        const u = inOutCubic(progress(t, s.t0, s.t1));
        const x = lerp(GAUGE_X[s.from[i]], GAUGE_X[s.to[i]], u) - GAUGE_X[i];
        const dir = s.to[i] > s.from[i] ? -1 : 1;
        return { x, y: s.from[i] === s.to[i] ? 0 : dir * Math.sin(Math.PI * u) * pt(13) };
      }
      if (t >= s.t1 && (s === SW[SW.length - 1] || t < SW[SW.indexOf(s) + 1].t0)) {
        return { x: GAUGE_X[s.to[i]] - GAUGE_X[i], y: 0 };
      }
    }
    return { x: 0, y: 0 };
  });
  const revealUI = outExpo(progress(t, CUE.pullback + 0.05, CUE.pullback + 0.6));
  return {
    right: PILL_RIGHT, cy: PILL_CY,
    values: { claude: [claudeW, 41 * draw], codex: [codexW], copilot: [copilotW] },
    badges,
    icons: stamps.map((s) => (t >= s ? 1 : 0)),
    iconScale: stamps.map((s) => (t >= s ? 1 + 0.35 * Math.exp(-(t - s) / 0.09) : 1)),
    offsets,
    bg: revealUI,
    lead: revealUI,
  };
}

function panelState(t) {
  const opening = t >= CUE.flight && t < CUE.whip;
  const reopen = t >= CUE.click + 0.05 && t < CUE.merge && !(t >= CUE.montage1 && t < CUE.montage2);
  const reveal = opening ? outExpo(progress(t, CUE.flight + 0.15, CUE.flight + 0.7)) : reopen ? outExpo(progress(t, CUE.click + 0.05, CUE.click + 0.5)) : 0;
  const scale = opening ? lerp(0.965, 1, outExpo(progress(t, CUE.flight + 0.05, CUE.flight + 0.7))) : lerp(0.94, 1, spring(t - CUE.click - 0.05, 0.45, 0.78));
  const lands = [0, 1, 2].map((i) => CUE.flight + 0.62 + i * 0.1);
  const icons = opening && t < lands[2] + 0.01 ? lands.map((l) => (t >= l ? 1 : 0)) : [1, 1, 1];
  const iconScale = lands.map((l) => (t >= l && t < l + 0.5 ? 1 + 0.3 * Math.exp(-(t - l) / 0.08) : 1));
  const afterC = t >= CUE.featureC;
  const seat = t < CUE.drop2 ? 0 : spring(t - CUE.drop2, 0.42, 0.74);
  const used = afterC ? 48000 : 4120 * outExpo(progress(t, CUE.drop2 + 0.05, CUE.drop2 + 1.3));
  return {
    opacity: 1, reveal, scale,
    claude: afterC ? [89, 41] : [58, 41],
    codex: afterC ? 94 : 36,
    copilot: { seat: Math.min(1.04, seat), percent: (used / 50000) * 100 * Math.min(1, seat * 1.2), used, strike: outExpo(progress(t, CUE.strike, CUE.strike + 0.22)) },
    icons, iconScale,
  };
}

// The glyphs fly from the pill down to their rings in the panel.
function drawFlyers(t, pillOut) {
  const targets = [panel.point(52, 61), panel.point(28, 136), panel.point(28, 176.5)];
  const sizes = [pt(16) * 1.08, pt(9.9) * 1.08, pt(9.9) * 1.08];
  const startSize = [pt(10) * 0.68, pt(8) * 1.08, pt(8) * 1.08];
  flyers.forEach((el, i) => {
    // Stamps: from far above, into the pill.
    const sc = [CUE.stampClaude, CUE.stampCodex, CUE.stampCopilot][i];
    let on = false;
    let x = 0, y = 0, size = 0, rot = 0;
    if (t >= sc - 0.24 && t < sc) {
      const u = stampIn(t, sc);
      const target = stampTarget(i);
      x = target.x; y = target.y - pt(26) * (1 - u);
      size = startSize[i] * lerp(4.2, 1, u);
      rot = lerp(-28, 0, u);
      on = true;
    }
    const t0 = CUE.flight + i * 0.06;
    const t1 = CUE.flight + 0.62 + i * 0.1;
    if (t >= t0 && t < t1) {
      const u = inOutExpo(progress(t, t0, t1));
      const from = i === 0 ? { x: pillOut.centers[0].x - pt(10) + BADGE_OFF + pt(5), y: pillOut.centers[0].y - pt(10) + BADGE_OFF + pt(5) } : pillOut.centers[i];
      const to = targets[i];
      x = lerp(from.x, to.x, u) + Math.sin(Math.PI * u) * pt(30) * (i - 1);
      y = lerp(from.y, to.y, u);
      size = lerp(startSize[i], sizes[i], u) * (1 + 0.6 * Math.sin(Math.PI * u));
      rot = Math.sin(Math.PI * u) * 22 * (i === 1 ? -1 : 1);
      on = true;
    }
    show(el, on);
    if (on) el.style.transform = `translate(${x - 50}px, ${y - 50}px) scale(${size / 100}) rotate(${rot}deg)`;
  });
}

function drawBackground(t) {
  const boost = (tool) => {
    let b = 0;
    const hits = { claude: [CUE.stampClaude, CUE.fuse], codex: [CUE.stampCodex, CUE.fuse], copilot: [CUE.stampCopilot, CUE.drop2, CUE.fuse] }[tool];
    for (const ht of hits) if (t >= ht) b += Math.exp(-(t - ht) / 0.6);
    return b;
  };
  const base = t < CUE.drop1 ? 0.18 + 0.12 * progress(t, 0, CUE.drop1) : 0.34;
  fields.forEach((el, i) => {
    const tool = TOOLS[i];
    const [hx, hy] = FIELD_HOME[tool];
    const x = hx * W + 90 * noise(t * 0.12, 21 + i);
    const y = hy * H + 70 * noise(t * 0.1, 31 + i);
    const focus = (tool === "copilot" && t >= CUE.zoomCopilot && t < CUE.whip) ? 0.25 : 0;
    el.style.opacity = clamp(base + focus + 0.55 * boost(tool), 0, 1);
    el.style.transform = `translate(${x}px, ${y}px)`;
  });
}

// MARK: The frame.

window.__render = (t) => {
  t = clamp(t, 0, DURATION);
  CAMERA = camera(t);
  const c = CAMERA;
  const worldOn = t < CUE.merge;
  show(world, worldOn);
  drawBackground(t);
  if (worldOn) {
    world.style.transform = `translate(${c.sx + c.shx}px, ${c.sy + c.shy}px) rotate(0.03deg) scale(${c.z}) translate(${-c.fx}px, ${-c.fy}px)`;
    const ps = pillState(t);
    const pillOut = pill.set(ps);
    menu.set({ pillLeft: pillOut.left, opacity: outExpo(progress(t, CUE.pullback, CUE.pullback + 0.7)) });
    const pn = panelState(t);
    panel.set(pn);
    drawFlyers(t, pillOut);

    // The interaction: the pointer clicks the pill, then rests on Copilot's ring.
    const ci = t >= CUE.interact + 0.1 && t < CUE.montage1;
    const press = clamp(1 - Math.abs(t - CUE.click) / 0.09);
    let cx = 0, cy = 0;
    if (ci) {
      const pillMid = { x: pillOut.left + pillOut.width * 0.62, y: PILL_CY + pt(2) };
      const ring = panel.point(30, 179);
      const enter = outExpo(progress(t, CUE.interact + 0.1, CUE.click - 0.05));
      const toRing = inOutCubic(progress(t, CUE.click + 0.45, CUE.hover));
      cx = lerp(lerp(pillMid.x + 260, pillMid.x, enter), ring.x, toRing);
      cy = lerp(lerp(pillMid.y + 420, pillMid.y, enter), ring.y, toRing);
    }
    cursor.set({ x: cx, y: cy, press, opacity: ci ? 1 : 0 });
    const tipOn = t >= CUE.hover + 0.55 && t < CUE.montage1;
    tooltip.set({ x: cx + pt(10), y: cy + pt(20), opacity: tipOn ? outExpo(progress(t, CUE.hover + 0.55, CUE.hover + 0.75)) : 0 });

    // Callouts.
    const gauges = pillOut.centers;
    const pA = (k) => win(t, CUE.featureA + 0.5 + k * 0.12, CUE.flight + 0.1, 0.7, 0.3);
    const labelBelow = (g, dy, dx = -40) => { const p = project(g); return { x: p.x + dx, y: p.y + dy, lx: p.x + dx - 12, ly: p.y + dy + 6 }; };
    const gp = gauges.map((g) => project(g));
    const below = (i) => ({ x: gp[i].x, y: gp[i].y + pt(10) * c.z + 8 });
    CALL.claude.set(pA(0), labelBelow(gauges[0], 170, -10), below(0));
    CALL.codex.set(pA(1), labelBelow(gauges[1], 250, -10), below(1));
    CALL.copilot.set(pA(2), labelBelow(gauges[2], 170, -10), below(2));
    // One callout, in the empty column under the headline, pointing at Copilot's ring.
    const seatRing = project(panel.point(16, 176.5));
    const pB = win(t, CUE.featureB + 1.0, CUE.whip - 0.05, 0.7, 0.3);
    CALL.seat.set(pB, { x: 130 + SEAT_W + 26, y: 748, lx: 130, ly: 724 }, seatRing);
    CALL.credits.set(0);
  } else {
    Object.values(CALL).forEach((cl) => cl.set(0));
  }
  drawFx(t);
  // The montage's caption band: on and off with its hard cuts.
  const sc = t >= CUE.montage1 && t < CUE.merge ? 1 : 0;
  show(scrim, sc > 0);
  scrim.style.opacity = sc;

  // Type.
  // Gone by 1.98 s, before "Which is which?" rises in the same spot.
  HL.rings.set(t, CUE.hookA, CUE.hookB - 0.3, { outDur: 0.24, outStagger: 0.02 });
  HL.which.set(t, CUE.hookB + 0.02, CUE.drop1 - 0.32);
  HL.icons.set(t, CUE.featureA + 0.25, CUE.flight - 0.3);
  HL.panel.set(t, CUE.featureA2 + 0.15, CUE.zoomCopilot - 0.1);
  HL.company.set(t, CUE.zoomCopilot + 0.7, CUE.drop2 - 0.08, { outDur: 0.2, outStagger: 0.015 });
  HL.counted.set(t, CUE.featureB - 0.15, CUE.whip - 0.1);
  HL.warning.set(t, CUE.featureC + 0.05, CUE.interact + 0.05);
  // Held through the hard cuts and taken away by them.
  HL.hover.set(t, CUE.hover - 0.25, CUE.montage1, { cutAt: CUE.montage1 });
  HL.m1.set(t, CUE.montage1 + 0.08, CUE.montage2, { dur: 0.5, cutAt: CUE.montage2 });
  HL.m2.set(t, CUE.montage2 + 0.08, CUE.montage3, { dur: 0.5, cutAt: CUE.montage3 });
  HL.m3.set(t, CUE.montage3 + 0.08, CUE.merge, { dur: 0.5, cutAt: CUE.merge });

  endLayer.style.transform = t >= CUE.merge ? `translate(${c.shx}px, ${c.shy}px)` : "none";
  drawEnd(t);

  // Flashes on the drops and the fuse; the fade at the very end.
  const flashes = [[CUE.pullback, 0.32], [CUE.drop2, 0.55], [CUE.fuse, 0.6], [CUE.montage1, 0.14], [CUE.montage2, 0.14], [CUE.montage3, 0.14], [CUE.merge, 0.22]];
  let f = 0;
  for (const [ft, amp] of flashes) if (t >= ft) f += amp * Math.exp(-(t - ft) / 0.07);
  show(flashLayer, f > 0.003);
  flashLayer.style.opacity = clamp(f);
  const out = progress(t, CUE.fadeOut, DURATION);
  show(fadeLayer, out > 0.001);
  fadeLayer.style.opacity = out;
};

window.__ready = true;
