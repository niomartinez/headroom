import Link from "next/link";
import { faq } from "@/content/faq";
import { FaqList } from "../faq-list";

export function Faq() {
  return (
    <section id="faq" aria-labelledby="faq-title" className="wrap pt-16 sm:pt-28 md:pt-40 short:pt-16">
      <div className="grid gap-6 border-t border-line pt-8 sm:gap-10 sm:pt-14 short:pt-8 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.6fr)] lg:gap-16">
        <div data-reveal>
          <p className="eyebrow">FAQ</p>
          <h2 id="faq-title" className="section-title mt-4 sm:mt-5">
            Questions, answered.
          </h2>
          <p className="lede mt-3 max-w-[34ch] sm:mt-6">
            More on the{" "}
            <Link href="/support" className="text-link">
              support page
            </Link>
            .
          </p>
        </div>
        <FaqList items={faq} />
      </div>
    </section>
  );
}
