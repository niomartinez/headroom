// The soundtrack, synthesized with Web Audio and rendered offline from the cue sheet, so every hit lands on its
// picture. Seeded noise: the same file every run. Mastering is ffmpeg's job (master.sh), not a Web Audio compressor.

import { BPM, BEAT, BAR, DURATION, CUE, at } from "./lib/timeline.js";
import { rng } from "./lib/engine.js";

const SR = 48000;
const ctx = new OfflineAudioContext(2, Math.round(SR * DURATION), SR);
const STEP = BEAT / 4;
const SWING = 0.022;
const mtof = (m) => 440 * Math.pow(2, (m - 69) / 12);
const rand = rng(4242);

// MARK: Buses: music (sidechained to the kick), drums, FX, and one reverb.

const master = ctx.createGain();
master.gain.value = 0.72;
master.connect(ctx.destination);
const music = ctx.createGain();
music.connect(master);
const drums = ctx.createGain();
drums.connect(master);
const fx = ctx.createGain();
fx.connect(master);
// The strike in the silence bypasses the muted master.
const solo = ctx.createGain();
solo.gain.value = 0.72;
solo.connect(ctx.destination);

function impulse(seconds, decay, seed) {
  const r = rng(seed);
  const len = Math.round(SR * seconds);
  const buf = ctx.createBuffer(2, len, SR);
  for (let c = 0; c < 2; c++) {
    const d = buf.getChannelData(c);
    for (let i = 0; i < len; i++) d[i] = (r() * 2 - 1) * Math.pow(1 - i / len, decay) * (i < SR * 0.012 ? i / (SR * 0.012) : 1);
  }
  return buf;
}
const reverb = ctx.createConvolver();
reverb.buffer = impulse(3.2, 2.6, 9);
const reverbOut = ctx.createGain();
reverbOut.gain.value = 0.42;
reverb.connect(reverbOut).connect(master);
const send = (node, amount) => { const g = ctx.createGain(); g.gain.value = amount; node.connect(g).connect(reverb); };

const NOISE = (() => {
  const r = rng(77);
  const buf = ctx.createBuffer(1, SR * 2, SR);
  const d = buf.getChannelData(0);
  for (let i = 0; i < d.length; i++) d[i] = r() * 2 - 1;
  return buf;
})();
function noise(t, dur) {
  const s = ctx.createBufferSource();
  s.buffer = NOISE;
  s.loop = true;
  s.start(t, rand() * 1.5, dur + 0.05);
  return s;
}
function env(t, peak, attack, decay, curve = "exp") {
  const g = ctx.createGain();
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(peak, t + attack);
  if (curve === "exp") g.gain.exponentialRampToValueAtTime(0.0001, t + attack + decay);
  else g.gain.linearRampToValueAtTime(0, t + attack + decay);
  return g;
}
function pan(node, value) { const p = ctx.createStereoPanner(); p.pan.value = value; node.connect(p); return p; }

// MARK: Drums

const kicks = [];
function kick(t, amp = 0.95) {
  kicks.push(t);
  const o = ctx.createOscillator();
  o.frequency.setValueAtTime(155, t);
  o.frequency.exponentialRampToValueAtTime(46, t + 0.11);
  const g = env(t, amp, 0.002, 0.42);
  o.connect(g).connect(drums);
  o.start(t); o.stop(t + 0.5);
  const n = noise(t, 0.02);
  const hp = ctx.createBiquadFilter(); hp.type = "highpass"; hp.frequency.value = 2500;
  n.connect(hp).connect(env(t, amp * 0.18, 0.001, 0.012)).connect(drums);
}
function clap(t, amp = 0.42) {
  const n = noise(t, 0.3);
  const bp = ctx.createBiquadFilter(); bp.type = "bandpass"; bp.frequency.value = 1350; bp.Q.value = 0.9;
  const g = ctx.createGain();
  g.gain.setValueAtTime(0, t);
  for (const d of [0, 0.011, 0.023]) { g.gain.setValueAtTime(amp, t + d); g.gain.exponentialRampToValueAtTime(amp * 0.2, t + d + 0.009); }
  g.gain.exponentialRampToValueAtTime(0.0001, t + 0.24);
  n.connect(bp).connect(g);
  g.connect(drums);
  send(g, 0.35);
  const o = ctx.createOscillator(); o.frequency.value = 196;
  o.connect(env(t, amp * 0.35, 0.002, 0.1)).connect(drums);
  o.start(t); o.stop(t + 0.15);
}
function hat(t, amp = 0.12, open = false, p = 0.2) {
  const n = noise(t, open ? 0.3 : 0.06);
  const hp = ctx.createBiquadFilter(); hp.type = "highpass"; hp.frequency.value = 7800;
  const g = env(t, amp, 0.001, open ? 0.24 : 0.035);
  pan(n.connect(hp).connect(g), p).connect(drums);
}

// MARK: Tonal instruments

function bass(t, dur, midi, amp = 0.36) {
  const f = mtof(midi);
  const sub = ctx.createOscillator(); sub.frequency.value = f;
  const saw = ctx.createOscillator(); saw.type = "sawtooth"; saw.frequency.value = f * 2;
  const lp = ctx.createBiquadFilter(); lp.type = "lowpass"; lp.frequency.setValueAtTime(900, t); lp.frequency.exponentialRampToValueAtTime(260, t + dur); lp.Q.value = 3;
  const g = ctx.createGain();
  g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(amp, t + 0.008);
  g.gain.setValueAtTime(amp, t + dur - 0.04); g.gain.exponentialRampToValueAtTime(0.0001, t + dur + 0.05);
  const sg = ctx.createGain(); sg.gain.value = 0.22;
  saw.connect(sg).connect(lp);
  sub.connect(lp);
  lp.connect(g).connect(music);
  sub.start(t); saw.start(t); sub.stop(t + dur + 0.08); saw.stop(t + dur + 0.08);
}
function pad(t, dur, notes, amp = 0.05, cutoff = [700, 2200], release = 0.9) {
  const lp = ctx.createBiquadFilter(); lp.type = "lowpass"; lp.Q.value = 0.7;
  lp.frequency.setValueAtTime(cutoff[0], t); lp.frequency.exponentialRampToValueAtTime(cutoff[1], t + dur * 0.6);
  const g = ctx.createGain();
  g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(amp, t + 0.25);
  g.gain.setValueAtTime(amp, t + dur); g.gain.exponentialRampToValueAtTime(0.0001, t + dur + release);
  for (const m of notes) for (const d of [-8, 7]) {
    const o = ctx.createOscillator(); o.type = "sawtooth"; o.frequency.value = mtof(m); o.detune.value = d;
    o.connect(lp); o.start(t); o.stop(t + dur + release + 0.1);
  }
  lp.connect(g);
  g.connect(music);
  send(g, 0.6);
}
function bell(t, midi, amp = 0.1, dur = 1.4, ratio = 3.5, p = 0) {
  const f = mtof(midi);
  const car = ctx.createOscillator(); car.frequency.value = f;
  const mod = ctx.createOscillator(); mod.frequency.value = f * ratio;
  const idx = ctx.createGain(); idx.gain.setValueAtTime(f * 2.4, t); idx.gain.exponentialRampToValueAtTime(f * 0.05, t + dur * 0.5);
  mod.connect(idx).connect(car.frequency);
  const g = env(t, amp, 0.003, dur);
  const out = pan(car.connect(g), p);
  out.connect(music);
  send(out, 0.5);
  car.start(t); mod.start(t); car.stop(t + dur + 0.1); mod.stop(t + dur + 0.1);
}

// MARK: FX

function stamp(t, midi, p) {
  const o = ctx.createOscillator(); o.frequency.setValueAtTime(140, t); o.frequency.exponentialRampToValueAtTime(42, t + 0.22);
  o.connect(env(t, 0.9, 0.002, 0.45)).connect(fx); o.start(t); o.stop(t + 0.5);
  const n = noise(t, 0.05);
  const bp = ctx.createBiquadFilter(); bp.type = "bandpass"; bp.frequency.value = 1100; bp.Q.value = 2;
  n.connect(bp).connect(env(t, 0.5, 0.001, 0.03)).connect(fx);
  bell(t, midi, 0.16, 1.8, 2.76, p);
  bell(t, midi + 12, 0.07, 1.2, 3.5, p);
}
function impact(t, amp = 0.9, big = false) {
  const o = ctx.createOscillator(); o.frequency.setValueAtTime(big ? 78 : 92, t); o.frequency.exponentialRampToValueAtTime(27, t + (big ? 1.4 : 0.8));
  o.connect(env(t, amp, 0.003, big ? 1.7 : 0.9)).connect(fx); o.start(t); o.stop(t + 1.9);
  const n = noise(t, 0.9);
  const lp = ctx.createBiquadFilter(); lp.type = "lowpass"; lp.frequency.setValueAtTime(7000, t); lp.frequency.exponentialRampToValueAtTime(300, t + 0.6);
  const g = env(t, amp * (big ? 0.42 : 0.28), 0.002, big ? 0.9 : 0.5);
  n.connect(lp).connect(g).connect(fx);
  send(g, 0.8);
}
function riser(t0, t1, amp = 0.3) {
  const n = noise(t0, t1 - t0);
  const bp = ctx.createBiquadFilter(); bp.type = "bandpass"; bp.Q.value = 3.5;
  bp.frequency.setValueAtTime(300, t0); bp.frequency.exponentialRampToValueAtTime(9000, t1);
  const g = ctx.createGain(); g.gain.setValueAtTime(0.0001, t0); g.gain.exponentialRampToValueAtTime(amp, t1 - 0.02); g.gain.linearRampToValueAtTime(0, t1);
  n.connect(bp).connect(g).connect(fx);
  send(g, 0.5);
  const o = ctx.createOscillator(); o.type = "sawtooth"; o.frequency.setValueAtTime(mtof(43), t0); o.frequency.exponentialRampToValueAtTime(mtof(79), t1);
  const lp = ctx.createBiquadFilter(); lp.type = "lowpass"; lp.frequency.value = 1800;
  const og = ctx.createGain(); og.gain.setValueAtTime(0.0001, t0); og.gain.exponentialRampToValueAtTime(amp * 0.25, t1 - 0.02); og.gain.linearRampToValueAtTime(0, t1);
  o.connect(lp).connect(og).connect(fx); o.start(t0); o.stop(t1);
}
function whoosh(t, dur, up = true, amp = 0.28, p0 = -0.6, p1 = 0.6) {
  const n = noise(t, dur);
  const bp = ctx.createBiquadFilter(); bp.type = "bandpass"; bp.Q.value = 1.8;
  bp.frequency.setValueAtTime(up ? 500 : 6000, t); bp.frequency.exponentialRampToValueAtTime(up ? 6000 : 400, t + dur);
  const g = ctx.createGain(); g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(amp, t + dur * 0.6); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  const p = ctx.createStereoPanner(); p.pan.setValueAtTime(p0, t); p.pan.linearRampToValueAtTime(p1, t + dur);
  n.connect(bp).connect(g).connect(p).connect(fx);
  send(p, 0.3);
}
function tick(t, freq = 2600, amp = 0.12, out = fx) {
  const o = ctx.createOscillator(); o.frequency.value = freq;
  o.connect(env(t, amp, 0.001, 0.012)).connect(out); o.start(t); o.stop(t + 0.03);
}
function scratch(t, dur = 0.22, out = fx) {
  const n = noise(t, dur);
  const bp = ctx.createBiquadFilter(); bp.type = "bandpass"; bp.frequency.setValueAtTime(2400, t); bp.frequency.linearRampToValueAtTime(3600, t + dur); bp.Q.value = 3;
  const g = ctx.createGain(); g.gain.setValueAtTime(0, t);
  for (let k = 0; k < 9; k++) g.gain.setValueAtTime(0.1 + 0.12 * rand(), t + (k * dur) / 9);
  g.gain.linearRampToValueAtTime(0, t + dur);
  n.connect(bp).connect(g).connect(out);
}
function blip(t, midi, amp = 0.14) {
  const o = ctx.createOscillator(); o.type = "triangle";
  o.frequency.setValueAtTime(mtof(midi - 5), t); o.frequency.exponentialRampToValueAtTime(mtof(midi), t + 0.05);
  o.connect(env(t, amp, 0.002, 0.16)).connect(fx); o.start(t); o.stop(t + 0.2);
  bell(t + 0.01, midi + 12, 0.05, 0.6);
}

// MARK: Arrangement (bars are 0-based here)

const CH = {
  Cm9: { root: 36, pad: [58, 60, 62, 63, 67] },
  Ab: { root: 32, pad: [55, 58, 60, 63, 67] },
  Eb: { root: 39, pad: [58, 62, 63, 65, 67] },
  Bb: { root: 34, pad: [58, 60, 62, 65, 67] },
};
const PROG = ["Eb", "Bb", "Cm9", "Ab", "Eb", "Bb", "Cm9", "Ab", "Bb", "Cm9", "Ab", "Eb", "Bb", "Cm9", "Ab", "Bb", "Cm9", "Ab", "Eb", "Bb", "Eb", "Eb", "Eb"];
const bars = Math.ceil(DURATION / BAR);
const stepT = (bar, step) => bar * BAR + step * STEP + (step % 2 ? SWING : 0);
const inSilence = (t) => t >= CUE.silence && t < CUE.drop2;
const grooveBar = (b) => (b >= 2 && b <= 8) || (b >= 9 && b <= 18);

for (let b = 0; b < bars; b++) {
  const chord = CH[PROG[b]];
  const t0 = b * BAR;
  // Pads: low and closed in the hook, open in the drops, a long swell on the end card.
  if (b < 2) pad(t0, BAR, chord.pad, 0.02, [380, 1100]);
  else if (b < 20 && b !== 8) pad(t0, BAR, chord.pad, 0.042, [900, 2600]);
  else if (b === 8) pad(t0, BAR / 2 - 0.05, chord.pad, 0.042, [900, 3200], 0.05);
  else if (b === 20) pad(t0, BAR * 2.4, CH.Eb.pad.concat([70, 74]), 0.05, [800, 3000]);

  // Bass: 2-step figure.
  if (grooveBar(b) || b === 19) {
    const fig = b === 19 ? [[0, 0, 6]] : [[0, 0, 2.6], [3, 12, 1], [6, 0, 1.8], [10, 7, 2.4], [14, 12, 1]];
    for (const [s, off, len] of fig) {
      const t = stepT(b, s);
      if (inSilence(t)) continue;
      bass(t, len * STEP * 0.95, chord.root + off);
    }
  } else if (b === 1) bass(t0 + BEAT * 2, BEAT * 1.6, chord.root, 0.22);

  // Drums.
  if (b < 2) {
    for (const s of [0, 8]) kick(stepT(b, s), 0.36);
    if (b === 1) for (const s of [10, 12, 13, 14, 15]) hat(stepT(b, s), 0.05 + s * 0.006);
  } else if (grooveBar(b)) {
    for (let s = 0; s < 16; s++) {
      const t = stepT(b, s);
      if (inSilence(t)) continue;
      if ([0, 7, 10].includes(s)) kick(t);
      if (s === 4 || s === 12) clap(t);
      if ([2, 6, 10, 14].includes(s)) hat(t, s === 14 && b % 2 ? 0.1 : 0.13, s === 14 && b % 2 === 1, 0.25);
      else hat(t, 0.045, false, -0.3);
    }
  } else if (b === 19) {
    kick(t0, 0.9);
  }

  // Glass arpeggio in the features; a question-and-answer motif in the hook.
  if ((b >= 3 && b <= 7) || (b >= 10 && b <= 17)) {
    const notes = chord.pad.map((m) => m + 12);
    const order = [0, 2, 4, 3, 1, 3, 4, 2];
    for (let s = 0; s < 16; s += 2) {
      const t = stepT(b, s);
      if (inSilence(t)) continue;
      bell(t, notes[order[(s / 2) % 8]], 0.045, 0.7, 3.5, ((s / 2) % 2 ? 0.35 : -0.35));
    }
  }
}
// The hook's motif: "Three rings." / "Which is which?" (rising, unresolved).
[[0.5, 79], [1.0, 82], [1.5, 86], [2.0, 87], [2.5, 86], [3.0, 89], [3.5, 91]].forEach(([t, m]) => bell(t, m, 0.065, 1.6, 3.5, (m % 3) / 3 - 0.3));

// The shell game, the stamps and the pull-back.
[CUE.swap1, CUE.swap2, CUE.swap2 + 0.5].forEach((t, i) => whoosh(t - 0.02, 0.36, i % 2 === 0, 0.16, i % 2 ? 0.7 : -0.7, i % 2 ? -0.7 : 0.7));
riser(CUE.riser1, CUE.drop1 - 0.24, 0.26);
stamp(CUE.stampClaude, 67, -0.45);
stamp(CUE.stampCodex, 70, 0);
stamp(CUE.stampCopilot, 74, 0.45);
impact(CUE.pullback, 0.9);
whoosh(CUE.pullback - 0.05, 0.9, false, 0.3, 0, 0);

// The glyphs fly to the panel and land.
[0, 1, 2].forEach((i) => {
  whoosh(CUE.flight + i * 0.06, 0.62, false, 0.18, -0.4 + i * 0.4, -0.4 + i * 0.4);
  bell(CUE.flight + 0.62 + i * 0.1, [79, 82, 86][i], 0.1, 1.2, 2.76, -0.4 + i * 0.4);
});
whoosh(CUE.zoomCopilot - 0.05, 0.8, true, 0.22);

// Silence, the strike, drop 2 and the counter.
riser(CUE.riser2, CUE.silence, 0.3);
scratch(CUE.strike, 0.22, solo);
tick(CUE.strike - 0.25, 1800, 0.06, solo);
impact(CUE.drop2, 1.15, true);
pad(CUE.drop2, 0.5, [60, 63, 67, 70, 74], 0.08, [2500, 4000]);
for (let k = 0; k < 26; k++) {
  const t = CUE.drop2 + 0.05 + 1.25 * (1 - Math.pow(1 - k / 26, 2.2));
  tick(t, 3000 + k * 40, 0.05);
}

// The whip, the badges, the interaction.
whoosh(CUE.whip - 0.04, 0.46, true, 0.3, 0.5, -0.5);
[[CUE.badgeClaude, 79], [CUE.badgeCodex, 82], [CUE.badgeCopilot, 86]].forEach(([t, m]) => blip(t, m));
whoosh(CUE.interact, 0.7, false, 0.16);
tick(CUE.click - 0.01, 1500, 0.16); tick(CUE.click + 0.06, 1200, 0.1);
whoosh(CUE.click + 0.04, 0.45, true, 0.12, 0, 0);
tick(CUE.hover + 0.55, 2400, 0.07);

// The montage hits, the merge and the end card.
[CUE.montage1, CUE.montage2, CUE.montage3].forEach((t, i) => { impact(t, 0.55); bell(t, [74, 77, 79][i], 0.08, 1.4); });
whoosh(CUE.merge + 0.45, 0.6, true, 0.26, -0.5, 0.5);
impact(CUE.merge, 0.5);
impact(CUE.fuse, 1.15, true);
[63, 67, 70, 74, 77].forEach((m, i) => bell(CUE.fuse + i * 0.07, m + 12, 0.08, 2.6, 3.5, (i - 2) * 0.25));
[[CUE.endCard + 0.45, 82], [CUE.endCard + 0.8, 86], [CUE.endCard + 1.05, 87], [CUE.endCard + 1.6, 91]].forEach(([t, m]) => bell(t, m, 0.07, 2.2));

// Sidechain: the music ducks under each kick.
kicks.sort((a, b) => a - b);
music.gain.setValueAtTime(1, 0);
for (const k of kicks) {
  music.gain.setValueAtTime(1, k);
  music.gain.linearRampToValueAtTime(0.55, k + 0.012);
  music.gain.linearRampToValueAtTime(1, k + 0.24);
}
// The beat of silence before drop 2, and the fade at the end.
master.gain.setValueAtTime(0.72, CUE.silence - 0.012);
master.gain.linearRampToValueAtTime(0.0, CUE.silence + 0.004);
master.gain.setValueAtTime(0.0, CUE.drop2 - 0.006);
master.gain.linearRampToValueAtTime(0.72, CUE.drop2);
master.gain.setValueAtTime(0.72, DURATION - 0.6);
master.gain.linearRampToValueAtTime(0.0, DURATION - 0.02);

// MARK: Render and hand over as a float WAV (base64).

const buffer = await ctx.startRendering();
const n = buffer.length;
const ab = new ArrayBuffer(44 + n * 8);
const dv = new DataView(ab);
const str = (o, s) => { for (let i = 0; i < s.length; i++) dv.setUint8(o + i, s.charCodeAt(i)); };
str(0, "RIFF"); dv.setUint32(4, 36 + n * 8, true); str(8, "WAVE"); str(12, "fmt ");
dv.setUint32(16, 16, true); dv.setUint16(20, 3, true); dv.setUint16(22, 2, true); dv.setUint32(24, SR, true);
dv.setUint32(28, SR * 8, true); dv.setUint16(32, 8, true); dv.setUint16(34, 32, true); str(36, "data"); dv.setUint32(40, n * 8, true);
const L = buffer.getChannelData(0), R = buffer.getChannelData(1);
for (let i = 0; i < n; i++) { dv.setFloat32(44 + i * 8, L[i], true); dv.setFloat32(48 + i * 8, R[i], true); }
const b64 = await new Promise((res) => { const fr = new FileReader(); fr.onload = () => res(String(fr.result).split(",")[1]); fr.readAsDataURL(new Blob([ab])); });
window.__audio = b64;
