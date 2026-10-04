/**
 * One place that brands everything the portal hands a user to download (V320): the official
 * identity from the institution profile — the logo, the University's name, the motto and contacts —
 * the document title, the date it was generated, and a serial the office can quote. A PDF, a print
 * and an Excel of the same thing look like one institution's document. Reuse brandedXlsx /
 * brandedPrint for any new export rather than calling buildXlsx or window.print directly.
 */
import { buildXlsx, loadCrest } from "@/lib/xlsx";
import { DEFAULT_INSTITUTION, formatDocDate } from "@/lib/document/institution";
import { currentInstitution } from "@/lib/document/institution-cache";
import { getInstitution, institutionLogoUrl } from "@/lib/document/institution-client";
import { printDocument, withSerial, type Cell as DocCell } from "@/lib/document/html";
import type { DocumentProfileId } from "@/lib/document/profiles";

/** the University's name as the code carried it; prefer currentInstitution().name, which follows the profile */
export const SCHOOL = DEFAULT_INSTITUTION.name;

type Cell = string | number | null;

/** A per-document serial the office can quote: <SHORT NAME>/<PREFIX>/YYYYMMDD/HHMMSS-RR. */
export function docSerial(prefix: string): string {
  const d = new Date();
  const p = (n: number, w = 2) => String(n).padStart(w, "0");
  const stamp = `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}/${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
  const rand = p(Math.floor(Math.random() * 100));
  return `${currentInstitution().shortName.toUpperCase()}/${prefix.toUpperCase()}/${stamp}-${rand}`;
}

/** whether the rows already lead with a serial column (a screen that numbered them itself) */
function leadsWithSerial(headers: string[]): boolean {
  const h = (headers[0] ?? "").trim().toUpperCase().replace(/\./g, "");
  return h === "S/N" || h === "SN" || h === "#" || h === "NO" || h === "S/NO";
}

/**
 * A branded .xlsx: the logo, the University name, the title and the generation date/serial sit above
 * the table; S/N leads every row (display only, numeric), the header row is frozen and filterable.
 * Returns the blob (async — it reads the profile and the logo).
 */
export async function brandedXlsx(
  title: string,
  headers: string[],
  rows: Cell[][],
  opts: { sheetName?: string; serial?: string; sub?: string; meta?: [string, string][]; noSerialColumn?: boolean } = {},
): Promise<Blob> {
  const inst = typeof window === "undefined" ? currentInstitution() : await getInstitution();
  const serial = opts.serial ?? docSerial("DOC");
  const logo = await loadCrest(institutionLogoUrl(inst)).catch(() => null) ?? await loadCrest().catch(() => null);
  const sheet = (opts.sheetName ?? title).replace(/[\\/?*[\]:]/g, "-").slice(0, 31) || "Sheet1";
  const numbered = !opts.noSerialColumn && !leadsWithSerial(headers);
  const h = numbered ? ["S/N", ...headers] : headers;
  const r = numbered ? (withSerial(rows as DocCell[][]) as Cell[][]) : rows;
  return buildXlsx(h, r, sheet, {
    school: inst.name.toUpperCase(),
    title: opts.sub ? `${title} — ${opts.sub}` : title,
    date: `Generated ${formatDocDate(new Date(), inst)} · Serial ${serial}`,
    logo: logo ?? undefined,
    meta: opts.meta,
  });
}

/** Trigger a browser download of a blob under a filename. */
export function downloadBlob(blob: Blob, filename: string): void {
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}

/**
 * Open a clean, branded document and print it — the browser's "Save as PDF" does the rest. The
 * official header, the title, the subtitle, the date and the serial head the page; the rows fill a
 * table with a serial column, its header repeated on every printed page; the footer runs on every page.
 */
export function brandedPrint(
  title: string,
  subtitle: string,
  headers: string[],
  rows: Cell[][],
  serial: string = docSerial("DOC"),
  opts: { profile?: DocumentProfileId; meta?: [string, string][]; generatedBy?: string | null; footnote?: string | null; orientation?: "portrait" | "landscape" } = {},
): void {
  const numbered = !leadsWithSerial(headers);
  void printDocument(opts.profile ?? "STANDARD_REPORT", {
    title,
    subtitle: subtitle || null,
    headers,
    rows,
    reference: serial,
    meta: opts.meta,
    generatedBy: opts.generatedBy ?? null,
    footnote: opts.footnote ?? null,
    serial: numbered,
    orientation: opts.orientation ?? "landscape",
  });
}
