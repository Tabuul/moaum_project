import "server-only";
import { cookies } from "next/headers";

/** the signed-in session: a token the browser never reads, in an httpOnly cookie */
export const SESSION_COOKIE = "moaum_session";

/** the token this request carries: the session's, or in development the minted one */
export async function sessionToken(): Promise<string | null> {
  try {
    const c = (await cookies()).get(SESSION_COOKIE)?.value;
    if (c) return c;
  } catch {
    /* outside a request */
  }
  if (process.env.NODE_ENV !== "production" && process.env.PORTAL_API_TOKEN) return process.env.PORTAL_API_TOKEN;
  return null;
}

export function cookieOptions(maxAgeSeconds: number) {
  return {
    httpOnly: true,
    sameSite: "lax" as const,
    secure: process.env.NODE_ENV === "production",
    path: "/",
    maxAge: maxAgeSeconds,
  };
}
