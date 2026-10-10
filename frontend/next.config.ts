import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // A self-contained server for the Docker image (frontend/Dockerfile).
  output: "standalone",
  // A page kept in a cache (only the sign-in page is, rebuilt each minute) may be served stale for five minutes at most,
  // not Next's default year: a cache in front never hands out a sign-in naming scripts an older deploy had.
  expireTime: 300,
};

export default nextConfig;
