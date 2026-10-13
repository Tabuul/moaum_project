import { NextRequest, NextResponse } from "next/server";
import { API_URL } from "@/lib/api";
import { OFFICE_COOKIE } from "@/lib/offices";
import { SESSION_COOKIE, cookieOptions } from "@/lib/session";
import { recordRegistrationAcceptance } from "@/lib/acceptance-server";

/** Post-UTME registration: the account is made and the applicant is signed in, in one step */
export async function POST(request: NextRequest) {
  const body = await request.json().catch(() => null);
  const upstream = await fetch(`${API_URL}/api/v1/applicant/register`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-forwarded-for": request.headers.get("x-forwarded-for") ?? "" },
    body: JSON.stringify(body ?? {}),
    cache: "no-store",
  }).catch(() => null);
  if (!upstream) return NextResponse.json({ status: 503, title: "The portal API is not reachable" }, { status: 503 });
  const text = await upstream.text();
  if (!upstream.ok) {
    return new NextResponse(text, { status: upstream.status, headers: { "content-type": upstream.headers.get("content-type") ?? "application/problem+json" } });
  }
  const signed = JSON.parse(text) as { token: string; expiresAt: string; applicationNo: string; surname: string; otherNames: string };
  const seconds = Math.max(60, Math.floor((new Date(signed.expiresAt).getTime() - Date.now()) / 1000));
  const response = NextResponse.json({ applicationNo: signed.applicationNo, name: `${signed.surname}, ${signed.otherNames}` });
  response.cookies.set(SESSION_COOKIE, signed.token, cookieOptions(seconds));
  response.cookies.set(OFFICE_COOKIE, "applicant", { ...cookieOptions(seconds), httpOnly: false });
  /* V441: the Privacy Policy box ticked on the form — recorded as the applicant's own act, against the version published now */
  if (body && typeof body === "object" && (body as { acceptPolicy?: unknown }).acceptPolicy === true) {
    await recordRegistrationAcceptance(signed.token, request.headers.get("x-forwarded-for"), request.headers.get("user-agent"));
  }
  return response;
}
