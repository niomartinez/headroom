// Renders the piece with headless Chromium (Playwright) and ffmpeg.
//
//   NODE_PATH="$(npm root -g)" node render.mjs stills 0.5 4.2 …         out/stills/t-04.200.png
//   NODE_PATH="$(npm root -g)" node render.mjs sheet 0 45 1              one still per second (reading-time check)
//   NODE_PATH="$(npm root -g)" node render.mjs video [--from s] [--to s] [--workers n]   out/frames.mp4 (no audio)
//   NODE_PATH="$(npm root -g)" node render.mjs audio                     out/audio-raw.wav
//
// Video: each output frame (60 fps) averages 6 sub-frames over half a frame (a 180° shutter): real motion blur.
// Each worker is its own browser, renders a contiguous part of the timeline into its own segment, and the
// segments are joined without re-encoding.

import http from "node:http";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const { chromium } = require("@playwright/test");
const ROOT = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.join(ROOT, "out");
const FPS = 60;
const SUB = 6;
const SHUTTER = 0.5;
const DURATION = 45;

const TYPES = { ".html": "text/html", ".js": "text/javascript", ".png": "image/png", ".wav": "audio/wav", ".json": "application/json" };
function serve() {
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      const rel = decodeURIComponent(new URL(req.url, "http://x").pathname);
      const file = path.join(ROOT, rel === "/" ? "index.html" : rel);
      if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
      res.writeHead(200, { "content-type": TYPES[path.extname(file)] || "application/octet-stream", "cache-control": "no-store" });
      fs.createReadStream(file).pipe(res);
    });
    server.listen(0, "127.0.0.1", () => resolve(server));
  });
}

async function openPage(port, page = "index.html") {
  const browser = await chromium.launch({ args: ["--disable-gpu-vsync", "--disable-frame-rate-limit", "--font-render-hinting=none", "--autoplay-policy=no-user-gesture-required"] });
  const tab = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  tab.on("pageerror", (e) => console.error("pageerror:", e.message));
  tab.on("console", (m) => { if (m.type() === "error" || m.type() === "warning") console.error("console:", m.text()); });
  await tab.goto(`http://127.0.0.1:${port}/${page}`);
  if (page === "index.html") await tab.waitForFunction(() => window.__loaded === true, null, { timeout: 60000 });
  const cdp = await tab.context().newCDPSession(tab);
  return { browser, tab, cdp };
}

async function shot(p, t, format = "jpeg") {
  await p.tab.evaluate((tt) => window.__render(tt), t);
  const r = await p.cdp.send("Page.captureScreenshot", {
    format, ...(format === "jpeg" ? { quality: 93 } : {}), optimizeForSpeed: true,
    clip: { x: 0, y: 0, width: 1920, height: 1080, scale: 1 },
  });
  return Buffer.from(r.data, "base64");
}

const arg = (name, fallback) => { const i = process.argv.indexOf(name); return i > 0 ? process.argv[i + 1] : fallback; };

async function stills(times, dir = path.join(OUT, "stills")) {
  fs.mkdirSync(dir, { recursive: true });
  const server = await serve();
  const p = await openPage(server.address().port);
  for (const t of times) {
    const file = path.join(dir, `t-${t.toFixed(3).padStart(6, "0")}.png`);
    fs.writeFileSync(file, await shot(p, t, "png"));
    console.log(file);
  }
  await p.browser.close();
  server.close();
}

function ffmpegSegment(file) {
  const ff = spawn("ffmpeg", [
    "-y", "-loglevel", "error", "-f", "image2pipe", "-framerate", String(FPS * SUB), "-c:v", "mjpeg", "-i", "-",
    "-vf", `tmix=frames=${SUB},select='eq(mod(n\\,${SUB})\\,${SUB - 1})',setpts=N/${FPS}/TB,format=yuv420p`,
    "-r", String(FPS), "-c:v", "libx264", "-preset", "medium", "-crf", "10", "-pix_fmt", "yuv420p", file,
  ], { stdio: ["pipe", "inherit", "inherit"] });
  return ff;
}

async function video() {
  const from = Number(arg("--from", 0));
  const to = Number(arg("--to", DURATION));
  const workers = Number(arg("--workers", Math.max(2, Math.min(8, os.cpus().length - 2))));
  const outFile = arg("--out", path.join(OUT, "frames.mp4"));
  const f0 = Math.round(from * FPS);
  const f1 = Math.round(to * FPS);
  const segDir = path.join(OUT, "segments");
  fs.rmSync(segDir, { recursive: true, force: true });
  fs.mkdirSync(segDir, { recursive: true });
  const server = await serve();
  const port = server.address().port;
  const per = Math.ceil((f1 - f0) / workers);
  const started = Date.now();
  let done = 0;
  const jobs = Array.from({ length: workers }, async (_, w) => {
    const a = f0 + w * per;
    const b = Math.min(f1, a + per);
    if (a >= b) return null;
    const file = path.join(segDir, `seg-${String(w).padStart(2, "0")}.mp4`);
    const p = await openPage(port);
    const ff = ffmpegSegment(file);
    const closed = new Promise((res, rej) => ff.on("close", (code) => (code === 0 ? res() : rej(new Error(`ffmpeg ${code}`)))));
    for (let f = a; f < b; f++) {
      for (let k = 0; k < SUB; k++) {
        const t = (f + (k / SUB) * SHUTTER) / FPS;
        const buf = await shot(p, t);
        if (!ff.stdin.write(buf)) await new Promise((r) => ff.stdin.once("drain", r));
      }
      done++;
      if (done % 120 === 0) {
        const s = (Date.now() - started) / 1000;
        console.log(`${done}/${f1 - f0} frames, ${s.toFixed(0)} s, ~${(((f1 - f0 - done) * s) / done).toFixed(0)} s left`);
      }
    }
    ff.stdin.end();
    await closed;
    await p.browser.close();
    return file;
  });
  const files = (await Promise.all(jobs)).filter(Boolean);
  server.close();
  const list = path.join(segDir, "list.txt");
  fs.writeFileSync(list, files.map((f) => `file '${f}'`).join("\n"));
  await new Promise((res, rej) => spawn("ffmpeg", ["-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", list, "-c", "copy", outFile], { stdio: "inherit" })
    .on("close", (c) => (c === 0 ? res() : rej(new Error("concat failed")))));
  console.log(`${outFile} (${((Date.now() - started) / 1000).toFixed(0)} s)`);
}

async function audio() {
  fs.mkdirSync(OUT, { recursive: true });
  const server = await serve();
  const p = await openPage(server.address().port, "audio.html");
  await p.tab.waitForFunction(() => window.__audio !== undefined, null, { timeout: 600000 });
  const b64 = await p.tab.evaluate(() => window.__audio);
  const file = path.join(OUT, "audio-raw.wav");
  fs.writeFileSync(file, Buffer.from(b64, "base64"));
  console.log(file);
  await p.browser.close();
  server.close();
}

const cmd = process.argv[2];
if (cmd === "stills") await stills(process.argv.slice(3).map(Number));
else if (cmd === "sheet") {
  const [a, b, step] = process.argv.slice(3).map(Number);
  const times = [];
  for (let t = a; t <= b + 1e-9; t += step) times.push(Math.round(t * 1000) / 1000);
  await stills(times, path.join(OUT, "sheet"));
} else if (cmd === "video") await video();
else if (cmd === "audio") await audio();
else { console.error("usage: render.mjs stills|sheet|video|audio"); process.exit(64); }
