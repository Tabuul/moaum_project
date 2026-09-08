import { NextRequest, NextResponse } from "next/server";
import { API_URL } from "@/lib/api";
import { OFFICE_COOKIE } from "@/lib/offices";
import { SESSION_COOKIE, cookieOptions } from "@/lib/session";

/** the browser posts the form here; the token goes into a cookie it cannot read */
export async function POST(request: NextRequest) {
  const body = await request.json().catch(() => null);
  const upstream = await fetch(`${API_URL}/api/v1/auth/sign-in`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-forwarded-for": request.headers.get("x-forwarded-for") ?? "" },
    body: JSON.stringify(body ?? {}),
    cache: "no-store",
  }).catch(() => null);
  if (!upstream) {
    return NextResponse.json({ status: 503, title: "The portal API is not reachable" }, { status: 503 });
  }
  const text = await upstream.text();
  if (!upstream.ok) {
    return new NextResponse(text, { status: upstream.status, headers: { "content-type": upstream.headers.get("content-type") ?? "application/problem+json" } });
  }
  const signed = JSON.parse(text) as { token: string; expiresAt: string; offices: { code: string }[]; mustChange: boolean; surname: string; givenNames: string };
  const seconds = Math.max(60, Math.floor((new Date(signed.expiresAt).getTime() - Date.now()) / 1000));
  const response = NextResponse.json({ mustChange: signed.mustChange, name: `${signed.surname}, ${signed.givenNames}`, offices: signed.offices });
  response.cookies.set(SESSION_COOKIE, signed.token, cookieOptions(seconds));
  const office = typeof body?.office === "string" && signed.offices.some((o) => o.code === body.office) ? body.office : signed.offices[0]?.code;
  if (office) response.cookies.set(OFFICE_COOKIE, office, { ...cookieOptions(seconds), httpOnly: false });
  return response;
}
