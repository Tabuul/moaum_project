import { NextResponse } from "next/server";

/** what a load balancer or Railway asks: is the portal up. No session needed, nothing personal answered. */
export function GET() {
  return NextResponse.json({ status: "up", service: "moaum-portal" }, { headers: { "cache-control": "no-store" } });
}
