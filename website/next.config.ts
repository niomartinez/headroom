import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  images: {
    // 90 keeps the small text in product renders and screenshots crisp.
    qualities: [75, 90],
  },
  poweredByHeader: false,
};

export default nextConfig;
