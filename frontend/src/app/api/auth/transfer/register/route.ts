import { NextRequest, NextResponse } from "next/server";
import { API_URL } from "@/lib/api";
import { OFFICE_COOKIE } from "@/lib/offices";
import { SESSION_COOKIE, cookieOptions } from "@/lib/session";
import { recordRegistrationAcceptance } from "@/lib/acceptance-server";
import { IUT_COOKIE } from "@/lib/transfer-application";

/** V766: the inter-university transfer application registered and the applicant signed in, in one step (the Post-UTME registration's
 *  pattern): the account and the application are made by the API's public door, the session cookie set, and the transfer cookie that
 *  sends the applicant's home to /transfer/portal. The Privacy Policy box is the applicant's own act, recorded with the new token; it is
 *  never sent to the API's door. */
export async function POST(request: NextRequest) {
  const body = (await request.json().catch(() => null)) as Record<string, unknown> | null;
  const { acceptPolicy, ...application } = body ?? {};
  const upstream = await fetch(`${API_URL}/api/v1/transfer-applications/apply`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-forwarded-for": request.headers.get("x-forwarded-for") ?? "" },
    body: JSON.stringify(application),
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
  response.cookies.set(IUT_COOKIE, "1", { ...cookieOptions(seconds), httpOnly: false });
  response.cookies.delete("moaum_jupeb");
  if (acceptPolicy === true) {
    await recordRegistrationAcceptance(signed.token, request.headers.get("x-forwarded-for"), request.headers.get("user-agent"));
  }
  return response;
}
