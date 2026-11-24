/**
 * The BFF's reply to the browser (app/api/bff/[...path]): which of the API's response headers are passed on. The body's type, the
 * correlation id and a created thing's location, as always. V749: nosniff always, so a photograph is never read as anything but the
 * image it says it is; and the API's caching word only when it forbids keeping the reply (no-store) — a private photograph (the staff
 * identity photographs) then never sits in the browser's cache. Any other caching word (a passport's or an HR photograph's
 * "private, max-age=600") is dropped as it always was, so a photograph replaced at the desk or at My identity is never shown stale
 * from the browser's cache on a screen whose address does not change. V779: the file name the API gives a download (Content-Disposition)
 * only to a page's own script reading the reply (fetch: Sec-Fetch-Mode cors or same-origin), which saves the file under it — the Summer
 * desk's CSVs; a link the browser opens itself (a document in a new tab, an image, an <a download>) never receives it, so each opens or
 * saves exactly as it always has.
 */
export const BFF_RESPONSE_HEADERS = ["content-type", "x-correlation-id", "location", "x-content-type-options", "cache-control"] as const;

/** a request a page's script made (fetch, XHR) rather than one the browser made to open, show or save a link: by its Fetch Metadata */
export function scriptRead(request: { get(name: string): string | null } | null | undefined): boolean {
  const mode = (request?.get("sec-fetch-mode") ?? "").trim().toLowerCase();
  return mode === "cors" || mode === "same-origin";
}

/** a Cache-Control value that forbids keeping the reply: one of its directives is no-store (any case, any spacing) */
export function forbidsStore(cacheControl: string | null | undefined): boolean {
  return (cacheControl ?? "").split(",").some((d) => d.split("=")[0].trim().toLowerCase() === "no-store");
}

/** the headers passed to the browser, each as the API set it: cache-control only when it says no-store; content-disposition only to a
 *  script's own read (the request's headers say whose it is) */
export function bffResponseHeaders(upstream: { get(name: string): string | null }, request?: { get(name: string): string | null } | null): [string, string][] {
  const out: [string, string][] = [];
  for (const name of BFF_RESPONSE_HEADERS) {
    const value = upstream.get(name);
    if (!value) continue;
    if (name === "cache-control" && !forbidsStore(value)) continue;
    out.push([name, value]);
  }
  const disposition = upstream.get("content-disposition");
  if (disposition && scriptRead(request)) out.push(["content-disposition", disposition]);
  return out;
}
