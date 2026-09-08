import { NextRequest, NextResponse } from "next/server";
import { API_URL } from "@/lib/api";
import { OFFICE_COOKIE } from "@/lib/offices";
import { SESSION_COOKIE, cookieOptions } from "@/lib/session";

/** the first account, once; the secret travels in a header and is never stored here */
export async function POST(request: NextRequest) {
  const body = (await request.json().catch(() => null)) as Record<string, string> | null;
  const { secret, ...rest } = body ?? {};
  const upstream = await fetch(`${API_URL}/api/v1/auth/bootstrap`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-bootstrap-secret": secret ?? "" },
    body: JSON.stringify(rest),
    cache: "no-store",
  }).catch(() => null);
  if (!upstream) {
    return NextResponse.json({ status: 503, title: "The portal API is not reachable" }, { status: 503 });
  }
  const text = await upstream.text();
  if (!upstream.ok) {
    return new NextResponse(text, { status: upstream.status, headers: { "content-type": upstream.headers.get("content-type") ?? "application/problem+json" } });
  }
  const signed = JSON.parse(text) as { token: string; expiresAt: string; offices: { code: string }[]; surname: string; givenNames: string };
  const seconds = Math.max(60, Math.floor((new Date(signed.expiresAt).getTime() - Date.now()) / 1000));
  const response = NextResponse.json({ name: `${signed.surname}, ${signed.givenNames}`, offices: signed.offices });
  response.cookies.set(SESSION_COOKIE, signed.token, cookieOptions(seconds));
  response.cookies.set(OFFICE_COOKIE, "registrar", { ...cookieOptions(seconds), httpOnly: false });
  return response;
}
