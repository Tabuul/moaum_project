import { NextRequest, NextResponse } from "next/server";
import { API_URL } from "@/lib/api";
import { OFFICE_COOKIE } from "@/lib/offices";
import { SESSION_COOKIE, cookieOptions } from "@/lib/session";

/** the provider sends the browser back here with a code; the API exchanges and verifies it, and the portal's own session follows */
export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  const state = request.nextUrl.searchParams.get("state");
  const error = request.nextUrl.searchParams.get("error_description") ?? request.nextUrl.searchParams.get("error");
  const back = (why: string) => NextResponse.redirect(new URL(`/login?sso=${encodeURIComponent(why)}`, request.nextUrl.origin));
  if (error) return back(error);
  if (!code || !state) return back("The identity provider returned no code.");
  const redirectUri = new URL("/api/auth/sso/callback", request.nextUrl.origin).toString();
  const upstream = await fetch(`${API_URL}/api/v1/auth/sso/callback`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-forwarded-for": request.headers.get("x-forwarded-for") ?? "" },
    body: JSON.stringify({ code, state, redirectUri }),
    cache: "no-store",
  }).catch(() => null);
  if (!upstream) return back("The portal API is not reachable.");
  const j = await upstream.json().catch(() => null);
  if (!upstream.ok) return back(j?.detail ?? j?.title ?? "The sign-in was refused.");
  const signed = j as { token: string; expiresAt: string; offices: { code: string }[] };
  const seconds = Math.max(60, Math.floor((new Date(signed.expiresAt).getTime() - Date.now()) / 1000));
  const response = NextResponse.redirect(new URL("/", request.nextUrl.origin));
  response.cookies.set(SESSION_COOKIE, signed.token, cookieOptions(seconds));
  const office = signed.offices[0]?.code;
  if (office) response.cookies.set(OFFICE_COOKIE, office, { ...cookieOptions(seconds), httpOnly: false });
  return response;
}
