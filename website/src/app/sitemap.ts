import type { MetadataRoute } from "next";
import { site } from "@/content/site";

export default function sitemap(): MetadataRoute.Sitemap {
  const lastModified = new Date(site.lastUpdated);
  return [
    { url: site.url, lastModified, changeFrequency: "monthly", priority: 1 },
    { url: `${site.url}/support`, lastModified, changeFrequency: "monthly", priority: 0.6 },
    { url: `${site.url}/privacy`, lastModified, changeFrequency: "yearly", priority: 0.4 },
  ];
}
