import { NextRequest, NextResponse } from "next/server";
import { API_URL } from "@/lib/api";
import { OFFICE_COOKIE } from "@/lib/offices";
import { reasonHeader } from "@/lib/reason";
import { SESSION_COOKIE, cookieOptions, sessionToken } from "@/lib/session";
import { SUPPORT_RETURN_COOKIE, SUPPORT_RETURN_OFFICE_COOKIE, SUPPORT_VIEW_COOKIE, safeBack, type SupportViewState } from "@/lib/support-view";

/** V521: ICT Support opens a student's portal as the student, read-only — the agent's session set aside, the student's view in its place */
export async function POST(request: NextRequest) {
  const body = (await request.json().catch(() => null)) as { studentId?: string; reason?: string; ticket?: string | null; back?: string } | null;
  const studentId = body?.studentId ?? "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(studentId)) {
    return NextResponse.json({ status: 400, title: "No student named" }, { status: 400 });
  }
  if (request.cookies.get(SUPPORT_RETURN_COOKIE)?.value) {
    return NextResponse.json({ status: 409, code: "SUPPORT_VIEW_OPEN", title: "A student's portal is already open", detail: "Leave the student view you are in first." }, { status: 409 });
  }
  const agentToken = await sessionToken();
  if (!agentToken) return NextResponse.json({ status: 401, title: "Sign in first" }, { status: 401 });
  const office = request.cookies.get(OFFICE_COOKIE)?.value ?? (process.env.NODE_ENV !== "production" ? process.env.PORTAL_ACTIVE_OFFICE : undefined) ?? "";
  const reason = (body?.reason ?? "").trim();
  const upstream = await fetch(`${API_URL}/api/v1/helpdesk/support/students/${studentId}/portal-view`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${agentToken}`, "content-type": "application/json", "x-active-office": office,
      "x-reason": reasonHeader(`Student portal opened by ICT Support: ${reason}`), "x-forwarded-for": request.headers.get("x-forwarded-for") ?? "",
    },
    body: JSON.stringify({ reason, ticket: body?.ticket || null }),
    cache: "no-store",
  }).catch(() => null);
  if (!upstream) return NextResponse.json({ status: 503, title: "The portal API is not reachable" }, { status: 503 });
  const text = await upstream.text();
  if (!upstream.ok) {
    return new NextResponse(text, { status: upstream.status, headers: { "content-type": upstream.headers.get("content-type") ?? "application/problem+json" } });
  }
  const v = JSON.parse(text) as { token: string; viewId: string; endsAt: string; matricNo: string | null; name: string; studentId: string };
  const seconds = Math.max(60, Math.floor((new Date(v.endsAt).getTime() - Date.now()) / 1000));
  const state: SupportViewState = {
    viewId: v.viewId, studentId: v.studentId, name: v.name, matricNo: v.matricNo, endsAt: v.endsAt,
    back: safeBack(body?.back, `/helpdesk/students/${studentId}`),
  };
  const response = NextResponse.json({ redirect: "/student", view: state });
  // the agent's own session waits here, httpOnly, until the agent leaves the student view
  response.cookies.set(SUPPORT_RETURN_COOKIE, agentToken, cookieOptions(12 * 3600));
  response.cookies.set(SUPPORT_RETURN_OFFICE_COOKIE, office, cookieOptions(12 * 3600));
  response.cookies.set(SESSION_COOKIE, v.token, cookieOptions(seconds));
  response.cookies.set(OFFICE_COOKIE, "student", { ...cookieOptions(seconds), httpOnly: false });
  response.cookies.set(SUPPORT_VIEW_COOKIE, encodeURIComponent(JSON.stringify(state)), { ...cookieOptions(12 * 3600), httpOnly: false });
  return response;
}
