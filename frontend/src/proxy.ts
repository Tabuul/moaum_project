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
const OPEN = ["/login", "/apply", "/pg/apply", "/api/auth/", "/api/bff/api/v1/applicant/lookup", "/verify", "/healthz", "/crest.png", "/favicon.ico",
  /* an external examiner's activation link (V254): the invitation read, the account activated, before any sign-in */
  "/api/bff/api/v1/examiners/invitation/", "/api/bff/api/v1/examiners/activate",
  /* a referee's form (V225): opened from the email link by someone who has no account here */
  "/pg/referee/", "/api/bff/api/v1/pg/referee/",
  /* a recipient's secure document link (V262): opened from the email by someone who has no account here */
  "/documents/d/",
  /* the University's public figures for its website (V282): counts only, no session, any origin */
  "/api/v1/public/",
  /* the public JUPEB application and the forgotten-password page (V339) */
  "/jupeb/apply", "/jupeb/reset",
  /* the CCE application (V379): only those on JAMB's CCE list register, with the JAMB number and the date of birth */
  "/cce/apply"];
/* the public postgraduate endpoints, matched exactly so the prefix does not also open the
   authenticated PG desks that share the /api/v1/pg base (e.g. /pg/applications) */
const OPEN_EXACT = new Set([
  "/api/bff/api/v1/pg/programmes",
  "/api/bff/api/v1/pg/apply",
  "/api/bff/api/v1/pg/status",
  "/api/bff/api/v1/pg/sign-in",
  /* the public JUPEB endpoints (V339), exactly, so the prefix does not open the candidate's portal or the JUPEB Office */
  "/api/bff/api/v1/jupeb/options",
  "/api/bff/api/v1/jupeb/apply",
  "/api/bff/api/v1/jupeb/forgot",
  /* V379: the CCE list look-up (the API limits each connection; a number with the wrong date of birth reads as not listed) */
  "/api/bff/api/v1/applicant/cce/lookup",
  /* the public ticket tracking (V251): the sign-in page sends someone who cannot sign in here, so it cannot ask them to; the
     ticket number and the email it was raised with open the ticket, and the API limits the lookups */
  "/track",
  "/api/bff/api/v1/helpdesk/track",
  /* help asked of the desk from the sign-in page (V363; the page itself is under /login); the API limits each connection */
  "/api/bff/api/v1/helpdesk/sign-in-help",
  /* Interswitch PayDirect's doors (V299; the one address for both messages, Oct 2026) when the API has no public address of its
     own and the portal forwards to it: Interswitch has no session. The API answers them as it answers them directly — a
     notification believed only with its credentials. Exactly these three, not the Bursary's /paydirect desk. */
  "/api/bff/api/v1/payments/paydirect/interswitch",
  "/api/bff/api/v1/payments/paydirect/validate",
  "/api/bff/api/v1/payments/paydirect/notify",
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
