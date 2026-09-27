import { NextRequest, NextResponse } from "next/server";
import { API_URL } from "@/lib/api";
import { OFFICE_COOKIE } from "@/lib/offices";
import { SESSION_COOKIE, cookieOptions, sessionToken } from "@/lib/session";

export const dynamic = "force-dynamic";

/**
 * From the applicant portal into the student portal, as the student the
 * applicant has become: the API issues the student session on the strength of
 * the applicant's own, the cookies switch sides, and the browser lands where
 * it was going (school fees, registration). While the applicant is not yet on
 * the register, they are sent back to Admission Progress, which says so.
 */
export async function GET(request: NextRequest) {
  const nextParam = request.nextUrl.searchParams.get("next") ?? "/student/fees";
  const next = /^\/student(\/|$)/.test(nextParam) ? nextParam : "/student/fees";
  const token = await sessionToken();
  if (!token) return NextResponse.redirect(new URL(`/login?next=${encodeURIComponent(next)}`, request.url));
  const upstream = await fetch(`${API_URL}/api/v1/student-auth/continue`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json", "x-forwarded-for": request.headers.get("x-forwarded-for") ?? "" },
    body: "{}",
    cache: "no-store",
  }).catch(() => null);
  if (!upstream || !upstream.ok) {
    let code = "unavailable";
    if (upstream) {
      const problem = (await upstream.json().catch(() => null)) as { code?: string } | null;
      code = problem?.code ?? String(upstream.status);
    }
    return NextResponse.redirect(new URL(`/applicant/admission?portal=${encodeURIComponent(code)}`, request.url));
  }
  const signed = (await upstream.json()) as { token: string; expiresAt: string; mustChange: boolean };
  const seconds = Math.max(60, Math.floor((new Date(signed.expiresAt).getTime() - Date.now()) / 1000));
  const response = NextResponse.redirect(new URL(next, request.url));
  response.cookies.set(SESSION_COOKIE, signed.token, cookieOptions(seconds));
  response.cookies.set(OFFICE_COOKIE, "student", { ...cookieOptions(seconds), httpOnly: false });
  return response;
}
