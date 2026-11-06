import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { ImageResponse } from "next/og";

export const alt =
  "Headroom: know your headroom, before you hit the limit. A free Mac menu bar app for your AI usage limits and sessions: Claude, Codex and Copilot.";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

const root = process.cwd();
const font = (weight: string) => readFile(join(root, `node_modules/geist/dist/fonts/geist-sans/Geist-${weight}.ttf`));
const image = async (path: string) => `data:image/png;base64,${(await readFile(join(root, "public", path))).toString("base64")}`;

export default async function OpengraphImage() {
  const [medium, semibold, icon, panel, pill] = await Promise.all([
    font("Medium"),
    font("SemiBold"),
    image("images/app-icon.png"),
    image("images/hero-panel.png"),
    image("images/og-pill.png"),
  ]);

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          position: "relative",
          background:
            "radial-gradient(circle at 78% 34%, rgba(93,202,165,0.19) 0%, rgba(93,202,165,0.09) 22%, rgba(93,202,165,0.03) 38%, rgba(93,202,165,0) 52%), radial-gradient(circle at 100% 100%, rgba(239,159,39,0.12) 0%, rgba(239,159,39,0.04) 22%, rgba(239,159,39,0) 40%), #171819",
          color: "#f1f0eb",
          fontFamily: "Geist",
        }}
      >
        <div style={{ display: "flex", flexDirection: "column", padding: "64px 0 58px 72px", width: 660 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
            {/* eslint-disable-next-line jsx-a11y/alt-text */}
            <img src={icon} width={64} height={64} style={{ borderRadius: 15 }} />
            <span style={{ fontSize: 34, fontWeight: 600, letterSpacing: -1 }}>Headroom</span>
          </div>
          <div style={{ display: "flex", flexDirection: "column", marginTop: 88 }}>
            <span style={{ fontSize: 62, fontWeight: 500, letterSpacing: -2.6, lineHeight: 1 }}>Know your headroom.</span>
            <span style={{ fontSize: 40, fontWeight: 500, letterSpacing: -1.3, color: "#5dcaa5", marginTop: 16 }}>
              Before you hit the limit.
            </span>
          </div>
          <span style={{ fontSize: 23, lineHeight: 1.45, color: "#b3b2ac", marginTop: 28, maxWidth: 590 }}>
            A free Mac menu bar app for your AI usage limits and sessions: Claude, Codex and Copilot. No account. Local by default.
          </span>
          <span style={{ fontSize: 20, color: "#8f8e88", marginTop: "auto" }}>headroom.niomartinez.com</span>
        </div>
        <div style={{ display: "flex", position: "absolute", left: 869, top: 60 }}>
          {/* eslint-disable-next-line jsx-a11y/alt-text */}
          <img src={pill} width={291} height={66} />
        </div>
        <div
          style={{
            display: "flex",
            position: "absolute",
            left: 720,
            top: 152,
            borderRadius: 22,
            boxShadow: "0 40px 80px rgba(0,0,0,0.6)",
          }}
        >
          {/* eslint-disable-next-line jsx-a11y/alt-text */}
          <img src={panel} width={440} height={428} />
        </div>
      </div>
    ),
    {
      ...size,
      fonts: [
        { name: "Geist", data: await medium, weight: 500, style: "normal" },
        { name: "Geist", data: await semibold, weight: 600, style: "normal" },
      ],
    },
  );
}
