import { NextRequest, NextResponse } from "next/server";
import { API_URL } from "@/lib/api";
import { OFFICE_COOKIE } from "@/lib/offices";
import { reasonHeader } from "@/lib/reason";
import { SESSION_COOKIE, cookieOptions } from "@/lib/session";
import { SUPPORT_RETURN_COOKIE, SUPPORT_RETURN_OFFICE_COOKIE, SUPPORT_VIEW_COOKIE, readSupportView, safeBack } from "@/lib/support-view";

/**
 * V521: leaving a student view — the view (and its portal session) ended on the API by the agent's own session, which comes back
 * in the browser; the agent returns to the support record the view was opened from. Shared by the exit and sign-out routes.
 */
export async function leaveSupportView(request: NextRequest): Promise<NextResponse> {
  const agentToken = request.cookies.get(SUPPORT_RETURN_COOKIE)?.value ?? null;
  const office = request.cookies.get(SUPPORT_RETURN_OFFICE_COOKIE)?.value ?? "";
  const view = readSupportView(request.cookies.get(SUPPORT_VIEW_COOKIE)?.value);
  if (agentToken && view) {
    await fetch(`${API_URL}/api/v1/helpdesk/support/portal-views/${encodeURIComponent(view.viewId)}/end`, {
      method: "POST",
      headers: { authorization: `Bearer ${agentToken}`, "x-active-office": office, "x-reason": reasonHeader(`Left the portal of ${view.matricNo ?? view.name}`) },
      cache: "no-store",
    }).catch(() => null);
  }
  const response = NextResponse.json({ left: true, redirect: agentToken ? safeBack(view?.back, "/helpdesk") : "/login" });
  if (agentToken) {
    response.cookies.set(SESSION_COOKIE, agentToken, cookieOptions(12 * 3600));
    if (office) response.cookies.set(OFFICE_COOKIE, office, { ...cookieOptions(12 * 3600), httpOnly: false });
  } else {
    response.cookies.set(SESSION_COOKIE, "", { path: "/", maxAge: 0 });
    response.cookies.set(OFFICE_COOKIE, "", { path: "/", maxAge: 0 });
  }
  response.cookies.set(SUPPORT_RETURN_COOKIE, "", { path: "/", maxAge: 0 });
  response.cookies.set(SUPPORT_RETURN_OFFICE_COOKIE, "", { path: "/", maxAge: 0 });
  response.cookies.set(SUPPORT_VIEW_COOKIE, "", { path: "/", maxAge: 0 });
  return response;
}
