import { NextRequest, NextResponse } from "next/server";
import { API_URL } from "@/lib/api";
import { OFFICE_COOKIE } from "@/lib/offices";
import { SESSION_COOKIE } from "@/lib/session";

/** ends the server-side session, then the cookie */
export async function POST(request: NextRequest) {
  const token = request.cookies.get(SESSION_COOKIE)?.value;
  if (token) {
    await fetch(`${API_URL}/api/v1/auth/sign-out`, { method: "POST", headers: { authorization: `Bearer ${token}` }, cache: "no-store" }).catch(() => null);
  }
  const response = NextResponse.json({ signedOut: true });
  response.cookies.set(SESSION_COOKIE, "", { path: "/", maxAge: 0 });
  response.cookies.set(OFFICE_COOKIE, "", { path: "/", maxAge: 0 });
  return response;
}
