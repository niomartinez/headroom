"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";

const links = [
  { href: "/#features", label: "Features" },
  { href: "/support", label: "Support" },
  { href: "/privacy", label: "Privacy" },
];

export function SiteHeader() {
  const pathname = usePathname();
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    let frame = 0;
    const update = () => {
      frame = 0;
      setScrolled(window.scrollY > 8);
    };
    const schedule = () => {
      if (!frame) frame = requestAnimationFrame(update);
    };
    schedule();
    window.addEventListener("scroll", schedule, { passive: true });
    return () => {
      cancelAnimationFrame(frame);
      window.removeEventListener("scroll", schedule);
    };
  }, []);

  return (
    <header className="site-header" data-scrolled={scrolled ? "true" : "false"}>
      <div className="wrap flex h-16 items-center justify-between gap-4 sm:h-[72px] sm:gap-6 short:h-14">
        <Link href="/" className="group flex items-center gap-2 rounded-lg max-sm:min-h-11 sm:gap-2.5" aria-label="Headroom home">
          <Image
            src="/images/app-icon.png"
            alt=""
            width={34}
            height={34}
            className="size-[30px] rounded-[7px] transition-transform duration-500 ease-[cubic-bezier(.22,1,.36,1)] group-hover:-rotate-12 sm:size-[34px] sm:rounded-[8px]"
            loading="eager"
          />
          {/* Below 360 px the wordmark doesn't fit beside the links; the icon and aria-label stay. */}
          <span className="text-[17px] font-semibold tracking-[-0.03em] max-[359px]:hidden sm:text-[20px]">Headroom</span>
        </Link>
        <nav aria-label="Main" className="flex items-center gap-3.5 text-[14px] sm:gap-8 sm:text-[15px]">
          {links.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className="nav-link"
              aria-current={pathname === link.href ? "page" : undefined}
            >
              {link.label}
            </Link>
          ))}
        </nav>
      </div>
    </header>
  );
}
