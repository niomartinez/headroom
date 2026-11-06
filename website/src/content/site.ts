export const site = {
  name: "Headroom",
  /** The Mac App Store name ("Headroom" alone is taken there). */
  storeName: "Headroom: AI Usage Meter",
  url: "https://headroom.niomartinez.com",
  title: "Headroom: AI usage limits and sessions in your Mac menu bar",
  description:
    "Headroom is a free Mac menu bar app for your AI usage: Claude's 5-hour and weekly limits, Codex and Copilot usage, and what every session is doing, at a glance. No account, local by default.",
  email: "hello@niomartinez.com",
  owner: "Nio Martinez",
  ownerUrl: "https://niomartinez.com",
  /** The public source repository (MIT). */
  sourceUrl: "https://github.com/niomartinez/headroom",
  minimumSystem: "macOS 14 or later",
  /** The App Store build's sandbox container (bundle ID com.niomartinez.headroom). */
  containerPath: "~/Library/Containers/com.niomartinez.headroom",
  /** The App Group container the app writes the widgets' summary to (team L237BMXGB6). */
  groupContainerPath: "~/Library/Group Containers/L237BMXGB6.com.niomartinez.headroom",
  /** Where people revoke Headroom's GitHub authorization. */
  githubAuthorizationsUrl: "https://github.com/settings/apps/authorizations",
  /** Confirmed public listing; availability does not depend on Apple's lookup API. */
  appStoreUrl: "https://apps.apple.com/app/headroom-ai-usage-meter/id6815808010",
  releasedVersion: "1.1.1",
  privacyEffectiveDate: "September 26, 2026",
  lastUpdated: "2026-10-20",
} as const;

/** The line every "private" claim on the site comes back to (1.1: Copilot usage is the one opt-in network use). */
export const privacyLine =
  "No account. Claude and Codex work from files on your Mac; Copilot usage is optional and talks only to GitHub.";

export const trademarkNotice =
  "Claude and Claude Code are trademarks of Anthropic, PBC. GitHub Copilot is a trademark of GitHub, Inc. OpenAI Codex is a trademark of OpenAI. Headroom is not affiliated with them.";
