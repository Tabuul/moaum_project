import "server-only";
import { API_URL } from "@/lib/api";
import { jpegSize } from "@/lib/pdf-write";
import { DEFAULT_INSTITUTION, normaliseInstitution, type Institution } from "./institution.ts";
import { currentLogo, primeInstitution, primeLogo, primedLogoVersion } from "./institution-cache.ts";

/**
 * The institution profile on the server (V320): read from the public endpoint, cached for a minute,
 * and primed into the process-wide cache the synchronous PDF builders read. The logo's JPEG derivative
 * is fetched once per version; without one the built-in crest stands. A route that draws a document
 * awaits this once, first.
 */
let cached: { at: number; value: Institution } | null = null;
let inflight: Promise<Institution> | null = null;

export async function loadInstitution(): Promise<Institution> {
  const now = Date.now();
  if (cached && now - cached.at < 60_000) return cached.value;
  if (inflight) return inflight;
  inflight = (async () => {
    let value = DEFAULT_INSTITUTION;
    try {
      const res = await fetch(`${API_URL}/api/v1/public/institution`, { cache: "no-store" });
      if (res.ok) value = normaliseInstitution((await res.json()) as Record<string, unknown>);
    } catch {
      value = cached?.value ?? DEFAULT_INSTITUTION;
    }
    cached = { at: Date.now(), value };
    primeInstitution(value);
    await primeLogoFor(value);
    return value;
  })();
  try {
    return await inflight;
  } finally {
    inflight = null;
  }
}

/** the JPEG derivative of the logo, fetched once per version and kept for the PDF builders */
async function primeLogoFor(i: Institution): Promise<void> {
  if (!i.logoJpegUrl) {
    if (primedLogoVersion() !== i.logoVersion) primeLogo(null, i.logoVersion);
    return;
  }
  if (primedLogoVersion() === i.logoVersion && currentLogo()) return;
  try {
    const res = await fetch(`${API_URL}${i.logoJpegUrl}`, { cache: "no-store" });
    if (!res.ok) { primeLogo(null, i.logoVersion); return; }
    const data = new Uint8Array(await res.arrayBuffer());
    const size = jpegSize(data);
    primeLogo(size ? { data, width: size.width, height: size.height } : null, i.logoVersion);
  } catch {
    primeLogo(null, i.logoVersion);
  }
}

/** the logo as uploaded (PNG preferred), for a workbook built on the server; undefined for the built-in crest */
export async function institutionLogoPng(): Promise<{ png: Uint8Array; w: number; h: number } | undefined> {
  const i = await loadInstitution();
  if (!i.logoUrl) return undefined;
  try {
    const res = await fetch(`${API_URL}${i.logoUrl}`, { cache: "no-store" });
    if (!res.ok) return undefined;
    const buf = new Uint8Array(await res.arrayBuffer());
    const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
    if (dv.getUint32(0) !== 0x89504e47) return undefined;   // a JPEG upload: the workbook keeps the crest
    return { png: buf, w: dv.getUint32(16), h: dv.getUint32(20) };
  } catch {
    return undefined;
  }
}
