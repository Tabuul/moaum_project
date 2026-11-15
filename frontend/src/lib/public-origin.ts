/**
 * The portal's public address — scheme, host and port, no path — for everything the Next server prints or hands out that a
 * person or a phone opens later: the QR and the "verify at" line on a letter, a card, a receipt, a certificate, a redirect.
 *
 * One rule, for every route:
 *   1. the public address the server is configured with: MOAUM_PORTAL_URL in the Next server's environment, read when the
 *      document is printed (the name and the value the API already uses for the portal's links), taken only when it is an
 *      absolute http or https origin — a scheme, a host and an optional port, a trailing "/" at most, no path, user, query or
 *      fragment — and otherwise ignored as if unset;
 *   2. else the host the request came to: the first value of X-Forwarded-Host, else the first of Host — a host name, an IPv4
 *      address or a bracketed IPv6 address with an optional port, and nothing else (a value carrying a path, a query, a user,
 *      whitespace or any other character is passed over, as if it were absent); the scheme the first value of
 *      X-Forwarded-Proto when it is http or https, else https;
 *   3. neither usable: the request's own URL's origin (the fallback a caller gives; "" for none).
 *
 * Never the request's own URL first: Next builds it from the name and port the server itself runs on, so on AWS an admission
 * letter printed "verify at https://ip-10-20-41-127.us-east-2.compute.internal:3000/verify/document" and a QR nobody outside
 * could open. The headers are right only as far as the edge forwards them: in production CloudFront stands in front of the ALB,
 * and unless its origin request policy forwards the viewer's Host, Next sees the origin's name instead. So the frontend container
 * should carry MOAUM_PORTAL_URL on AWS (the portal_url variable, e.g. https://portal.moaum.edu.ng — docs/aws-deployment.md §3),
 * and then nothing a request says changes the address. Without it (a development server, Railway's own domain) the headers are
 * the rule: Next fills X-Forwarded-Host from Host and X-Forwarded-Proto from the connection when no proxy set them, so a
 * development server on http://localhost:3000 prints its own address.
 */

/** a host name (labels of letters, digits and hyphens), an IPv4 address or a bracketed IPv6 address, and an optional port */
const HOST = /^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*|\[[0-9a-f:.]+\])(?::(\d{1,5}))?$/;

/** the first value of a header that a chain of proxies may have made a comma-separated list, trimmed; null when empty */
function first(v: string | null): string | null {
  const x = (v ?? "").split(",")[0].trim();
  return x || null;
}

/** the header's first value as a host, lower-cased, or null when it is not one */
function hostOf(v: string | null): string | null {
  const h = first(v)?.toLowerCase() ?? null;
  if (!h || h.length > 260) return null;
  const m = HOST.exec(h);
  if (!m) return null;
  if (m[1] !== undefined && (Number(m[1]) < 1 || Number(m[1]) > 65535)) return null;
  return h;
}

/** an absolute http or https origin as written: a scheme, "://", a host and port with no "/", "?", "#", "\", "@" or whitespace in
 *  them, and at most a trailing "/" */
const ORIGIN = /^https?:\/\/[^/?#\\@\s]+\/?$/i;

/** the public address configured for the server (MOAUM_PORTAL_URL, read now, not when the server was built), as an origin; null when
 *  it is unset, blank or anything but an absolute http(s) origin with no path */
export function configuredOrigin(v: string | undefined = process.env.MOAUM_PORTAL_URL): string | null {
  const s = (v ?? "").trim();
  if (!ORIGIN.test(s)) return null;
  try {
    const u = new URL(s);
    // the host by the same rule as a header's (a port of 1 to 65535); the URL parser's own origin, a default port dropped
    return hostOf(u.host) ? u.origin : null;
  } catch {
    return null;
  }
}

/** the public origin: the configured one, else from the request's headers, else the fallback when no header names a host */
export function publicOriginOf(headers: Headers, fallback = ""): string {
  const configured = configuredOrigin();
  if (configured) return configured;
  const host = hostOf(headers.get("x-forwarded-host")) ?? hostOf(headers.get("host"));
  if (!host) return fallback;
  const p = first(headers.get("x-forwarded-proto"))?.toLowerCase();
  const proto = p === "http" || p === "https" ? p : "https";
  try {
    // the URL parser's own origin: a default port (https on 443, http on 80) dropped, an IPv6 address in its one form
    const u = new URL(`${proto}://${host}`);
    return u.pathname === "/" && !u.username && !u.password && !u.search && !u.hash ? u.origin : fallback;
  } catch {
    return fallback;
  }
}

/** the public origin of a route's request: the configured one, else the headers' rule, else the request's own URL's origin */
export function publicOrigin(req: Request): string {
  let own = "";
  try { own = new URL(req.url).origin; } catch { /* no URL of its own: "" */ }
  return publicOriginOf(req.headers, own === "null" ? "" : own);
}
