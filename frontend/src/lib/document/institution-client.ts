/**
 * The institution profile in the browser (V320): fetched once through the BFF, kept for the session,
 * and primed into the shared cache so a branded print or workbook built on the client carries the
 * same identity the server's PDFs carry. The defaults stand until the fetch answers, and after a failure.
 */
import { DEFAULT_INSTITUTION, normaliseInstitution, type Institution } from "./institution.ts";
import { currentInstitution, primeInstitution } from "./institution-cache.ts";

let pending: Promise<Institution> | null = null;
let loaded = false;

export function getInstitution(): Promise<Institution> {
  if (loaded) return Promise.resolve(currentInstitution());
  if (pending) return pending;
  pending = (async () => {
    try {
      const res = await fetch("/api/bff/api/v1/public/institution", { cache: "no-store" });
      if (res.ok) {
        const i = normaliseInstitution((await res.json()) as Record<string, unknown>);
        primeInstitution(i);
        loaded = true;
        return i;
      }
    } catch {
      /* the defaults stand */
    }
    return currentInstitution();
  })();
  try {
    return pending;
  } finally {
    void pending.then(() => { pending = null; }, () => { pending = null; });
  }
}

/** where the browser finds the logo: the uploaded one through the BFF, else the built-in crest */
export function institutionLogoUrl(i: Institution = currentInstitution()): string {
  if (!i.logoUrl) return "/crest.png";
  return `/api/bff${i.logoUrl}`;
}

/** an absolute logo URL, for a document opened in a window of its own */
export function institutionLogoAbsoluteUrl(i: Institution = currentInstitution()): string {
  const origin = typeof window === "undefined" ? "" : window.location.origin;
  return origin + institutionLogoUrl(i);
}

export { DEFAULT_INSTITUTION };
