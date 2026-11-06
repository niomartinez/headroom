import type { Metadata, Viewport } from "next";
import { GeistMono } from "geist/font/mono";
import { GeistSans } from "geist/font/sans";
import { GlowCards } from "@/components/glow-cards";
import { MotionRoot } from "@/components/motion-root";
import { RevealObserver } from "@/components/reveal-observer";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";
import { site } from "@/content/site";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL(site.url),
  title: {
    default: site.title,
    template: "%s · Headroom",
  },
  description: site.description,
  applicationName: site.name,
  authors: [{ name: site.owner, url: site.ownerUrl }],
  creator: site.owner,
  alternates: { canonical: "/" },
  robots: {
    index: true,
    follow: true,
    googleBot: { index: true, follow: true, "max-image-preview": "large", "max-snippet": -1 },
  },
  openGraph: {
    type: "website",
    locale: "en_US",
    url: "/",
    siteName: site.name,
    title: site.title,
    description: site.description,
  },
  twitter: {
    card: "summary_large_image",
    title: site.title,
    description: site.description,
  },
  formatDetection: { email: false, telephone: false, address: false },
};

export const viewport: Viewport = {
  themeColor: "#171819",
  colorScheme: "dark",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${GeistSans.variable} ${GeistMono.variable}`}>
      <body className="min-h-dvh">
        <a href="#main" className="skip-link">
          Skip to content
        </a>
        <MotionRoot>
          <SiteHeader />
          <main id="main" className="overflow-x-clip">
            {children}
          </main>
          <SiteFooter />
        </MotionRoot>
        <RevealObserver />
        <GlowCards />
      </body>
    </html>
  );
}
