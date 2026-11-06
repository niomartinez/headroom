import { site } from "@/content/site";
import { PillView } from "../pill-view";
import { StoreButton } from "../store-button";

export function Closing() {
  return (
    <section aria-labelledby="closing-title" className="wrap pb-16 pt-16 sm:pb-24 sm:pt-28 md:pb-32 md:pt-40 short:pb-16 short:pt-16">
      <div
        className="relative isolate overflow-hidden rounded-[32px] border border-white/[0.09] px-4 py-12 text-center min-[360px]:px-6 sm:px-12 sm:py-24 short:py-12"
        style={{
          background:
            "radial-gradient(60% 90% at 50% 120%, rgb(93 202 165 / 0.2), transparent 70%), radial-gradient(40% 60% at 85% -10%, rgb(239 159 39 / 0.12), transparent 70%), linear-gradient(180deg, #1c1d1f, #141516)",
        }}
      >
        <div className="flex justify-center">
          <PillView dot="working" count={2} weekly={89} fiveHour={14} scale={1.6} />
        </div>
        <h2 id="closing-title" className="display mx-auto mt-8 max-w-[14ch] text-[clamp(40px,6vw,88px)] max-sm:text-[36px] sm:mt-10">
          Know your headroom.
        </h2>
        <p className="lede mx-auto mt-4 max-w-[46ch] sm:mt-6">
          Free on the Mac App Store. Questions or ideas? Write to{" "}
          <a className="text-link" href={`mailto:${site.email}`}>
            {site.email}
          </a>
          .
        </p>
        <div className="mt-8 flex justify-center sm:mt-10">
          <StoreButton />
        </div>
      </div>
    </section>
  );
}
