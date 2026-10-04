/**
 * The institution profile the current process last loaded (V320), for the synchronous builders — the
 * PDF header, the letters, the certificate — that draw a document in one pass. The server loader primes
 * it before a route draws; the client loader primes it after its first fetch. Until primed, the
 * defaults stand, so a document is never left without its University.
 */
import { DEFAULT_INSTITUTION, type Institution } from "./institution.ts";
import type { Image } from "../pdf-write.ts";

let current: Institution = DEFAULT_INSTITUTION;
let logo: Image | null = null;
let logoVersion = -1;

export function currentInstitution(): Institution {
  return current;
}

export function primeInstitution(i: Institution): void {
  current = i;
}

/** the logo the PDF engine embeds (a JPEG), once the server loader has fetched it; null means the built-in crest */
export function currentLogo(): Image | null {
  return logo;
}

export function primeLogo(img: Image | null, version: number): void {
  logo = img;
  logoVersion = version;
}

export function primedLogoVersion(): number {
  return logoVersion;
}
