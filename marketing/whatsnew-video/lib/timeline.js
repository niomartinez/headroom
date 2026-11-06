// The cue sheet: one tempo grid that both the pictures (scenes.js) and the soundtrack (audio.js) read,
// so re-timing a cue moves both. Bars and beats are 1-based: at(3) is the downbeat of bar 3.

export const BPM = 120;
export const BEAT = 60 / BPM;
export const BAR = BEAT * 4;
export const DURATION = 45;
export const FPS = 60;

export const at = (bar, beat = 1, fraction = 0) => (bar - 1) * BAR + (beat - 1 + fraction) * BEAT;

export const CUE = {
  hookA: at(1, 1, 0.5),
  hookB: at(2),
  swap1: at(2, 2),
  swap2: at(2, 3),
  riser1: at(2),
  drop1: at(3),
  stampClaude: at(3, 1),
  stampCodex: at(3, 2),
  stampCopilot: at(3, 3),
  pullback: at(3, 4),
  featureA: at(4),
  flight: at(6),
  featureA2: at(6, 2),
  zoomCopilot: at(8),
  riser2: at(9),
  silence: at(9, 3),
  strike: at(9, 4),
  drop2: at(10),
  featureB: at(10, 2),
  whip: at(13),
  featureC: at(13, 2),
  badgeClaude: at(13, 3),
  badgeCodex: at(13, 4),
  badgeCopilot: at(14, 1),
  interact: at(15),
  click: at(15, 2),
  hover: at(16, 1, 0.5),
  montage1: at(17),
  montage2: at(18),
  montage3: at(19),
  merge: at(20),
  fuse: at(20, 3),
  endCard: at(21),
  fadeOut: at(23, 2),
};

// The parts of the track: the soundtrack's arrangement follows these.
export const SECTIONS = [
  { name: "hook", from: 0, to: CUE.drop1 },
  { name: "drop1", from: CUE.drop1, to: CUE.silence },
  { name: "silence", from: CUE.silence, to: CUE.drop2 },
  { name: "drop2", from: CUE.drop2, to: CUE.montage1 },
  { name: "montage", from: CUE.montage1, to: CUE.merge },
  { name: "merge", from: CUE.merge, to: CUE.endCard },
  { name: "end", from: CUE.endCard, to: DURATION },
];
