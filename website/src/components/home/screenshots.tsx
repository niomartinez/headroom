import Image, { getImageProps } from "next/image";
import { screenshots, type Screenshot } from "@/content/screenshots";
import { GalleryScroller } from "../gallery-scroller";
import { SectionHead } from "./section-head";

const SIZES = "(max-width: 800px) 84vw, 680px";

export function Screenshots() {
  return (
    <section id="screenshots" aria-labelledby="screenshots-title" className="pt-16 sm:pt-28 md:pt-40 short:pt-16">
      <div className="wrap">
        <SectionHead
          id="screenshots-title"
          eyebrow="Screenshots"
          title="See it up close."
          intro="Shown with sample data. Your own sessions and folders never leave your Mac."
        />
      </div>
      <div data-reveal className="mt-8 sm:mt-12 md:mt-16 short:mt-8">
        <GalleryScroller label="Headroom screenshots">
          {screenshots.map((shot) => (
            <figure key={shot.src} className="m-0">
              <div
                className="shot"
                data-fit={shot.fit ?? "contain"}
                data-portrait={shot.height > shot.width ? "true" : undefined}
                data-phone-crop={shot.phone ? "true" : undefined}
              >
                <ShotImage shot={shot} />
              </div>
              <figcaption className="mt-3 max-w-[46ch] text-[15px] leading-relaxed text-muted sm:mt-4">{shot.caption}</figcaption>
            </figure>
          ))}
        </GalleryScroller>
      </div>
    </section>
  );
}

function ShotImage({ shot }: { shot: Screenshot }) {
  const className =
    shot.fit === "cover"
      ? "absolute inset-0 size-full object-cover"
      : "absolute inset-[5%] m-auto h-[90%] w-[90%] object-contain drop-shadow-[0_24px_40px_rgb(0_0_0/0.45)] sm:inset-[7%] sm:h-[86%] sm:w-[86%]";

  if (!shot.phone) {
    return <Image src={shot.src} width={shot.width} height={shot.height} alt={shot.alt} quality={90} sizes={SIZES} className={className} />;
  }

  // Below 640 px a crop of the panel and the pill replaces the whole desktop, so it can be read.
  // From 640 px up the <img> is exactly what <Image> renders.
  const { props: full } = getImageProps({ src: shot.src, width: shot.width, height: shot.height, alt: shot.alt, quality: 90, sizes: SIZES });
  const { props: crop } = getImageProps({ src: shot.phone.src, width: shot.phone.width, height: shot.phone.height, alt: "", quality: 90, sizes: "84vw" });
  return (
    <picture>
      <source media="(max-width: 639px)" srcSet={crop.srcSet} sizes={crop.sizes} width={crop.width} height={crop.height} />
      <img {...full} alt={shot.alt} className={className} />
    </picture>
  );
}
