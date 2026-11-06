// Pure timing math. Nothing here reads a clock or keeps state, so every frame is a function of time alone.

export const clamp = (x, lo = 0, hi = 1) => Math.min(hi, Math.max(lo, x));
export const lerp = (a, b, t) => a + (b - a) * t;
export const progress = (t, t0, t1) => clamp((t - t0) / (t1 - t0));
export const smoothstep = (x) => { x = clamp(x); return x * x * (3 - 2 * x); };

// Expo eases normalised to start at exactly 0 and end at exactly 1 (the textbook form is off by 1/1024).
const E = Math.pow(2, -10);
export const outExpo = (x) => (x <= 0 ? 0 : x >= 1 ? 1 : (1 - Math.pow(2, -10 * x)) / (1 - E));
export const inExpo = (x) => (x <= 0 ? 0 : x >= 1 ? 1 : (Math.pow(2, 10 * x - 10) - E) / (1 - E));
export const inOutExpo = (x) => (x < 0.5 ? inExpo(x * 2) / 2 : 0.5 + outExpo(x * 2 - 1) / 2);
export const outCubic = (x) => 1 - Math.pow(1 - clamp(x), 3);
export const inOutCubic = (x) => { x = clamp(x); return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2; };
export const outBack = (x, s = 1.6) => { x = clamp(x) - 1; return 1 + (s + 1) * x * x * x + s * x * x; };

// A SwiftUI-style spring from 0 to 1, `dt` seconds after it starts. response 0.45 / damping 0.78 is the pill's own.
export function spring(dt, response = 0.45, damping = 0.78) {
  if (dt <= 0) return 0;
  const w = (2 * Math.PI) / response;
  if (damping < 1) {
    const wd = w * Math.sqrt(1 - damping * damping);
    return 1 - Math.exp(-damping * w * dt) * (Math.cos(wd * dt) + ((damping * w) / wd) * Math.sin(wd * dt));
  }
  return 1 - Math.exp(-w * dt) * (1 + w * dt);
}

// A value that moves between keyframes [[time, value, ease?], …]; holds before the first and after the last.
export function keys(t, frames) {
  if (t <= frames[0][0]) return frames[0][1];
  for (let i = 1; i < frames.length; i++) {
    const [t1, v1, ease = outExpo] = frames[i];
    const [t0, v0] = frames[i - 1];
    if (t < t1) return lerp(v0, v1, ease((t - t0) / (t1 - t0)));
  }
  return frames[frames.length - 1][1];
}

// Seeded PRNG (mulberry32): the same seed gives the same sequence on every worker.
export function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Smooth 1D value noise in -1…1, for drift and shake.
const LATTICE = (() => { const r = rng(7); return Array.from({ length: 512 }, () => r() * 2 - 1); })();
export function noise(x, seed = 0) {
  const i = Math.floor(x);
  const f = x - i;
  const a = LATTICE[(i + seed * 97) & 511];
  const b = LATTICE[(i + 1 + seed * 97) & 511];
  return lerp(a, b, f * f * (3 - 2 * f));
}

// Camera shake from a list of hits [{t, amp}]: decaying noise, nothing before a hit.
export function shake(t, hits, axisSeed) {
  let v = 0;
  for (const h of hits) {
    const dt = t - h.t;
    if (dt < 0 || dt > 0.6) continue;
    v += h.amp * Math.exp(-dt / (h.decay ?? 0.12)) * noise(dt * (h.rate ?? 38), axisSeed + Math.round(h.t * 10));
  }
  return v;
}

// 0 → 1 → 0 over [t0, t0 + attack, t1 - release, t1].
export function window(t, t0, t1, attack = 0.3, release = 0.3, easeIn = outExpo, easeOut = outCubic) {
  if (t < t0 || t > t1) return 0;
  if (t < t0 + attack) return easeIn((t - t0) / attack);
  if (t > t1 - release) return 1 - easeOut((t - (t1 - release)) / release);
  return 1;
}
