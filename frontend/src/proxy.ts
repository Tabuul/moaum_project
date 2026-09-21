import { NextRequest, NextResponse } from "next/server";

/**
 * Nobody reaches a screen without a session. The sign-in page, the first-
 * account page, the public verification page and the sign-in handlers are
 * open; everything else sends a visitor to sign in and back again after.
 *
 * A session must also still stand with the API. A deploy ends every session
 * issued before it (SessionGuard's floor), so on the next navigation the API
 * answers 401, the stale cookies are cleared here, and the visitor lands on a
 * fresh sign-in rather than a dead session. A momentary failure to reach the
 * API does not lock anyone out: the request is allowed through and the page's
 * own call decides.
 */
const SESSION_COOKIE = "moaum_session";
const OFFICE_COOKIE = "moaum_office";
const OPEN = ["/login", "/apply", "/pg/apply", "/api/auth/", "/api/bff/api/v1/applicant/lookup", "/verify", "/healthz", "/crest.png", "/favicon.ico"];
/* the public postgraduate endpoints, matched exactly so the prefix does not also open the
   authenticated PG desks that share the /api/v1/pg base (e.g. /pg/applications) */
const OPEN_EXACT = new Set([
  "/api/bff/api/v1/pg/programmes",
  "/api/bff/api/v1/pg/apply",
  "/api/bff/api/v1/pg/status",
  "/api/bff/api/v1/pg/accept",
]);
const API_URL = (process.env.PORTAL_API_URL ?? "http://localhost:8081").replace(/\/$/, "");

function toLogin(request: NextRequest, clear: boolean): NextResponse {
  const { pathname, search } = request.nextUrl;
  const to = new URL("/login", request.url);
  if (pathname !== "/") to.searchParams.set("next", pathname + search);
  const response = NextResponse.redirect(to);
  if (clear) {
    response.cookies.set(SESSION_COOKIE, "", { path: "/", maxAge: 0 });
    response.cookies.set(OFFICE_COOKIE, "", { path: "/", maxAge: 0 });
  }
  return response;
}

export async function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;
  /* the platform asking whether the portal is up is not a visitor to send to sign in */
  const agent = request.headers.get("user-agent") ?? "";
  if (agent.includes("RailwayHealthCheck") || request.headers.get("host") === "healthcheck.railway.app") {
    return NextResponse.next();
  }
  if (OPEN_EXACT.has(pathname) || OPEN.some((p) => pathname === p || pathname.startsWith(p + "/") || pathname.startsWith(p))) {
    return NextResponse.next();
  }
  const token = request.cookies.get(SESSION_COOKIE)?.value;
  if (token) {
    /* validate the session on a real page navigation — not on BFF/API calls (the API
       validates those itself) and not on prefetches (a redirect there is wasted work) */
    const isApi = pathname.startsWith("/api/");
    const isPrefetch = request.headers.get("next-router-prefetch") === "1" || request.headers.get("purpose") === "prefetch";
    if (!isApi && !isPrefetch) {
      try {
        const r = await fetch(`${API_URL}/api/v1/iam/me`, { headers: { authorization: `Bearer ${token}` }, cache: "no-store" });
        if (r.status === 401) return toLogin(request, true);
      } catch {
        /* the API is unreachable for a moment; do not lock the user out */
      }
    }
    return NextResponse.next();
  }
  if (process.env.NODE_ENV !== "production" && process.env.PORTAL_API_TOKEN) {
    return NextResponse.next();
  }
  return toLogin(request, false);
}

export const config = {
  matcher: ["/((?!_next/static|_next/image).*)"],
};
