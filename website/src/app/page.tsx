import { Closing } from "@/components/home/closing";
import { Faq } from "@/components/home/faq";
import { Features } from "@/components/home/features";
import { Hero } from "@/components/home/hero";
import { HowItWorks } from "@/components/home/how-it-works";
import { NewInOneOne } from "@/components/home/new-in-1-1";
import { Screenshots } from "@/components/home/screenshots";
import { faq } from "@/content/faq";
import { site } from "@/content/site";

const jsonLd = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "SoftwareApplication",
      "@id": `${site.url}/#app`,
      name: site.name,
      alternateName: site.storeName,
      url: site.url,
      downloadUrl: site.appStoreUrl,
      softwareVersion: site.releasedVersion,
      description: site.description,
      operatingSystem: "macOS",
      softwareRequirements: "macOS 14 or later",
      applicationCategory: "DeveloperApplication",
      image: `${site.url}/images/app-icon.png`,
      offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
      author: { "@id": `${site.url}/#author` },
      publisher: { "@id": `${site.url}/#author` },
      featureList: [
        "Claude's weekly and 5-hour plan limits as two rings in the menu bar, covering chat, Cowork and Claude Code",
        "OpenAI Codex limits and GitHub Copilot monthly usage next to Claude's",
        "Claude Code, Codex and connected Copilot desktop or CLI sessions grouped as working, needs you or idle",
        "Optional guided setup with a tool chooser and immediate sample preview",
        "Context window use per session, and a click to open a session",
        "Moments when a session finishes, needs input or a limit crosses 90%",
        "Limits and Sessions widgets for the desktop and Notification Center",
        "No account, no data collection; local by default, with Copilot usage the only opt-in network use",
      ],
    },
    {
      "@type": "Person",
      "@id": `${site.url}/#author`,
      name: site.owner,
      url: site.ownerUrl,
    },
    {
      "@type": "WebSite",
      "@id": `${site.url}/#website`,
      name: site.name,
      url: site.url,
      publisher: { "@id": `${site.url}/#author` },
    },
    {
      "@type": "FAQPage",
      "@id": `${site.url}/#faq`,
      mainEntity: faq.map((item) => ({
        "@type": "Question",
        name: item.question,
        acceptedAnswer: { "@type": "Answer", text: item.answer.join(" ") },
      })),
    },
  ],
};

export default function Home() {
  return (
    <>
      <script
        type="application/ld+json"
        // JSON.stringify output with "<" escaped, so the data can't close the script tag.
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd).replace(/</g, "\\u003c") }}
      />
      <Hero />
      <Features />
      <HowItWorks />
      <Screenshots />
      <NewInOneOne />
      <Faq />
      <Closing />
    </>
  );
}
