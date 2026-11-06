import Link from "next/link";
import { site, trademarkNotice } from "@/content/site";

export function SiteFooter() {
  return (
    <footer className="border-t border-line">
      <div className="wrap flex flex-col gap-6 py-10 sm:py-12">
        <div className="flex flex-col gap-1 text-[14px] text-muted sm:flex-row sm:items-center sm:justify-between sm:gap-4">
          {/* On phones the copyright gets its own line, so no line starts with a separator. */}
          <p className="flex flex-wrap items-center gap-x-2.5 gap-y-1 sm:gap-y-1.5">
            <span className="w-full sm:w-auto">© 2026 {site.owner}</span>
            <span aria-hidden="true" className="hidden sm:inline">
              ·
            </span>
            <a className="text-link max-sm:inline-flex max-sm:min-h-11 max-sm:items-center" href={site.ownerUrl}>
              niomartinez.com
            </a>
            <span aria-hidden="true">·</span>
            <Link className="text-link max-sm:inline-flex max-sm:min-h-11 max-sm:items-center" href="/privacy">
              Privacy
            </Link>
            <span aria-hidden="true">·</span>
            <Link className="text-link max-sm:inline-flex max-sm:min-h-11 max-sm:items-center" href="/support">
              Support
            </Link>
          </p>
          <a className="text-link w-fit max-sm:inline-flex max-sm:min-h-11 max-sm:items-center" href={`mailto:${site.email}`}>
            {site.email}
          </a>
        </div>
        <p className="max-w-[860px] text-[13px] leading-relaxed text-subtle">{trademarkNotice}</p>
      </div>
    </footer>
  );
}
