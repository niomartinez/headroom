import Image from "next/image";
import { site } from "@/content/site";

/** Apple's official badge, displayed without modification or pointer animation. */
export function StoreButton() {
  return (
    <a href={site.appStoreUrl} className="inline-flex shrink-0 rounded-lg">
      <Image
        src="https://tools.applemediaservices.com/api/badges/download-on-the-mac-app-store/black/en-us"
        alt="Download on the Mac App Store"
        width={234}
        height={60}
        unoptimized
        className="h-[54px] w-auto sm:h-[60px]"
      />
    </a>
  );
}
