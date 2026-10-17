import { NextRequest, NextResponse } from "next/server";
import { API_URL } from "@/lib/api";
import { OFFICE_COOKIE } from "@/lib/offices";
import { SESSION_COOKIE } from "@/lib/session";
import { SUPPORT_RETURN_COOKIE } from "@/lib/support-view";
import { leaveSupportView } from "../support-view/leave";

/** ends the server-side session, then the cookie */
export async function POST(request: NextRequest) {
  // V521: signing out of a student view leaves the view — the agent's own session comes back, it is not ended
  if (request.cookies.get(SUPPORT_RETURN_COOKIE)?.value) return leaveSupportView(request);
  const token = request.cookies.get(SESSION_COOKIE)?.value;
  if (token) {
    await fetch(`${API_URL}/api/v1/auth/sign-out`, { method: "POST", headers: { authorization: `Bearer ${token}` }, cache: "no-store" }).catch(() => null);
  }
  const response = NextResponse.json({ signedOut: true });
  response.cookies.set(SESSION_COOKIE, "", { path: "/", maxAge: 0 });
  response.cookies.set(OFFICE_COOKIE, "", { path: "/", maxAge: 0 });
  response.cookies.set("moaum_jupeb", "", { path: "/", maxAge: 0 });
  return response;
}
