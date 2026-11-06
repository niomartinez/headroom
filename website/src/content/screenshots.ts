/**
 * The screenshots strip on the home page shows these files, in this order.
 *
 * To use the Mac App Store screenshots (2880 x 1800), drop them into `public/screenshots/` and
 * list them here with `fit: "cover"`, for example:
 *
 *   { src: "/screenshots/01-menu-bar.png", width: 2880, height: 1800, fit: "cover",
 *     alt: "…", caption: "…" },
 *
 * `width` and `height` are the file's pixel size. `fit: "contain"` (the default) floats a
 * transparent render on a soft background; `"cover"` fills the 16:10 card edge to edge.
 * Use synthetic sample data only: no real session names or project folders.
 *
 * `phone` is an optional crop for screens below 640 px, where a whole 2880 x 1800 screenshot
 * shrinks to about 330 px wide and its text can't be read. The store screenshots use a 4:5 crop of
 * the panel and the pill (x 49.5-89.5 %, y 0-80 % of the original, in `public/screenshots/phone/`;
 * 07 crops the medium and large widgets instead).
 *
 * `scripts/release/refresh-marketing-assets.sh` renders the store screenshots and writes both JPEGs.
 */
export type Screenshot = {
  src: string;
  width: number;
  height: number;
  alt: string;
  caption: string;
  fit?: "contain" | "cover";
  phone?: { src: string; width: number; height: number };
};

/** The 4:5 phone crop of a store screenshot. */
const phoneCrop = (name: string) => ({ src: `/screenshots/phone/${name}`, width: 1152, height: 1440 });

export const screenshots: Screenshot[] = [
  {
    src: "/screenshots/01-glance.jpg",
    width: 2880,
    height: 1800,
    fit: "cover",
    phone: phoneCrop("01-glance.jpg"),
    alt: "A Mac desktop with the Headroom pill in the menu bar and its panel open: weekly and 5-hour limits with reset times, then sessions with context bars. All data is sample data.",
    caption: "Your AI limits, one glance away.",
  },
  {
    src: "/screenshots/02-sessions.jpg",
    width: 2880,
    height: 1800,
    fit: "cover",
    phone: phoneCrop("02-sessions.jpg"),
    alt: "The Headroom panel listing sample sessions grouped as working, needs you and idle, each with a context bar.",
    caption: "Every session, working or waiting.",
  },
  {
    src: "/screenshots/03-near-limit.jpg",
    width: 2880,
    height: 1800,
    fit: "cover",
    phone: phoneCrop("03-near-limit.jpg"),
    alt: "The pill with an amber ring and number as the weekly limit nears, and a moment announcing the limit.",
    caption: "Know before you hit the limit.",
  },
  {
    src: "/screenshots/04-terminal.jpg",
    width: 2880,
    height: 1800,
    fit: "cover",
    phone: phoneCrop("04-terminal.jpg"),
    alt: "Terminal sessions next to desktop app sessions in the panel, and the Connect terminal setting.",
    caption: "Desktop app and terminal.",
  },
  {
    src: "/screenshots/05-privacy.jpg",
    width: 2880,
    height: 1800,
    fit: "cover",
    phone: phoneCrop("05-privacy.jpg"),
    alt: "Headroom works from files already on your Mac: no account, local by default, and no data collected. Only Copilot usage talks to GitHub, and only if you connect it.",
    caption: "No account. Local by default.",
  },
  {
    src: "/screenshots/06-tools.jpg",
    width: 2880,
    height: 1800,
    fit: "cover",
    phone: phoneCrop("06-tools.jpg"),
    alt: "The panel with Claude's limits on top, compact rows for Codex and Copilot, and Claude, Codex and Copilot sessions tagged by tool. Beside it, the pill showing Claude, Codex, or one gauge per tool. All data is sample data.",
    caption: "More tools, one panel.",
  },
  {
    src: "/screenshots/07-widgets.jpg",
    width: 2880,
    height: 1800,
    fit: "cover",
    phone: phoneCrop("07-widgets.jpg"),
    alt: "A desktop with three Headroom widgets: small Limits with Claude's rings, medium Sessions, and large Sessions with every tool's limits and sessions. All data is sample data.",
    caption: "Widgets for your desktop.",
  },
  {
    src: "/images/renders/pill-states.png",
    width: 884,
    height: 424,
    alt: "Eight menu bar pills: working, a session that needs you, near the limit, critical, faded rings for old data, and moments that read 'Update pricing table finished', 'harbor needs you' and 'Weekly at 90%'.",
    caption: "The pill, in every state. Moments widen it for a few seconds.",
  },
];
