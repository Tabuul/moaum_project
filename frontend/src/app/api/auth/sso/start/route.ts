import { NextRequest, NextResponse } from "next/server";
import { API_URL } from "@/lib/api";

/** the browser is sent to the University's identity provider; the API builds the address with a signed state */
export async function GET(request: NextRequest) {
  const redirectUri = new URL("/api/auth/sso/callback", request.nextUrl.origin).toString();
  const r = await fetch(`${API_URL}/api/v1/auth/sso/start?redirectUri=${encodeURIComponent(redirectUri)}`, { cache: "no-store" }).catch(() => null);
  const j = r ? await r.json().catch(() => null) : null;
  if (!r || !r.ok || !j?.url) {
    const why = j?.detail ?? j?.title ?? "Single sign-on is not connected to this portal.";
    return NextResponse.redirect(new URL(`/login?sso=${encodeURIComponent(why)}`, request.nextUrl.origin));
  }
  return NextResponse.redirect(j.url as string);
}
