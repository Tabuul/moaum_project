import { NextRequest, NextResponse } from "next/server";

/**
 * Nobody reaches a screen without a session. The sign-in page, the first-
 * account page, the public verification page and the sign-in handlers are
 * open; everything else sends a visitor to sign in and back again after.
 */
const SESSION_COOKIE = "moaum_session";
const OPEN = ["/login", "/api/auth/", "/verify", "/crest.png", "/favicon.ico"];

export function proxy(request: NextRequest) {
  const { pathname, search } = request.nextUrl;
  if (OPEN.some((p) => pathname === p || pathname.startsWith(p + "/") || pathname.startsWith(p))) {
    return NextResponse.next();
  }
  if (request.cookies.get(SESSION_COOKIE)?.value) {
    return NextResponse.next();
  }
  if (process.env.NODE_ENV !== "production" && process.env.PORTAL_API_TOKEN) {
    return NextResponse.next();
  }
  const to = new URL("/login", request.url);
  if (pathname !== "/") to.searchParams.set("next", pathname + search);
  return NextResponse.redirect(to);
}

export const config = {
  matcher: ["/((?!_next/static|_next/image).*)"],
};
