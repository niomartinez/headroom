import { site } from "@/content/site";

/** Mac App Store ID of "Headroom: AI Usage Meter" (`site.storeName`). */
export const appStoreId = "6815808010";

/** The first version with Codex, Copilot and widgets: the "New in 1.1" badges read "New" from here on. */
export const newFeaturesVersion = "1.1.0";

/** Refresh and Just finished: their card reads "In review" until Apple's listing reaches this version. */
export const refreshVersion = "1.1.1";

/** Just finished clears when the session is opened in its own app. */
export const seenVersion = "1.1.2";

type Listing = { url: string; version: string | null } | null;

/**
 * Apple's public listing, checked at most once an hour for versions newer than the confirmed release.
 * A lookup failure never changes the confirmed store URL or released feature badges.
 */
async function getListing(): Promise<Listing> {
  try {
    const response = await fetch(`https://itunes.apple.com/lookup?id=${appStoreId}&country=us`, {
      next: { revalidate: 3600 },
    });
    if (!response.ok) return null;
    const data = (await response.json()) as { resultCount?: number; results?: { version?: unknown }[] };
    if (!data.resultCount) return null;
    const version = data.results?.[0]?.version;
    return { url: `https://apps.apple.com/app/id${appStoreId}`, version: typeof version === "string" ? version : null };
  } catch {
    return null;
  }
}

/** The App Store link once the app is live, else null. */
export async function getAppStoreUrl(): Promise<string | null> {
  if (site.appStoreUrl) return site.appStoreUrl;
  return (await getListing())?.url ?? null;
}

/** Confirmed releases stay live even if Apple's lookup API is unavailable. */
export async function isVersionLive(version: string): Promise<boolean> {
  if (compareVersions(site.releasedVersion, version) >= 0) return true;
  const live = (await getListing())?.version;
  return live ? compareVersions(live, version) >= 0 : false;
}

/** Compares dotted versions numerically: "1.10.0" > "1.9.2", "1.1" == "1.1.0". */
export function compareVersions(a: string, b: string): number {
  const parts = (v: string) => v.split(".").map((part) => Number.parseInt(part, 10) || 0);
  const [x, y] = [parts(a), parts(b)];
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const diff = (x[i] ?? 0) - (y[i] ?? 0);
    if (diff !== 0) return Math.sign(diff);
  }
  return 0;
}
