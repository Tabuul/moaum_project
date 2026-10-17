/**
 * V523: every report the portal hands a person to download or print is recorded on the export log Internal Audit reads — the
 * report, the format, the rows, the filters it was drawn with, the screen and the serial printed on the document. The server
 * records it for the person and office of the request; this only says what was exported. It never holds up or stops an export:
 * the record goes in the background (a keepalive request, so leaving the page does not drop it) and a failure is ignored.
 */

/** XLSX and PRINT from the browser; PDF and CSV from the documents the server builds (V529) */
export type ExportFormat = "XLSX" | "PRINT" | "PDF" | "CSV";

export interface ExportRecord {
  report: string;
  format: ExportFormat;
  rows: number;
  /** the labelled block written above the table — Session, Faculty… */
  meta?: [string, string][];
  /** the subtitle, which often names the filters */
  sub?: string | null;
  serial?: string | null;
}

/** the filters an export was drawn with: the labelled block above the table, the subtitle, and the screen's own query */
export function exportFilters(r: Pick<ExportRecord, "meta" | "sub">, search: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of r.meta ?? []) {
    const key = String(k ?? "").trim().slice(0, 80);
    const val = String(v ?? "").trim().slice(0, 300);
    if (key && val) out[key] = val;
  }
  if (r.sub && r.sub.trim()) out["Subtitle"] = r.sub.trim().slice(0, 300);
  new URLSearchParams(search).forEach((v, k) => {
    const key = k.trim().slice(0, 80);
    if (key && v.trim() && !(key in out)) out[key] = v.trim().slice(0, 300);
  });
  return out;
}

/** the body the export log is sent, from what was exported and where */
export function exportBody(r: ExportRecord, pathname: string, search: string): string {
  return JSON.stringify({
    report: (r.report || "Untitled report").trim().slice(0, 300),
    format: r.format,
    rows: Math.max(0, Math.floor(Number(r.rows) || 0)),
    filters: exportFilters(r, search),
    screen: (pathname + search).slice(0, 2000),
    serial: r.serial ?? null,
  });
}

/** record an export, in the background; nothing on the server side holds the download */
export function logExport(r: ExportRecord): void {
  if (typeof window === "undefined" || typeof fetch !== "function") return;
  try {
    const body = exportBody(r, window.location.pathname, window.location.search);
    void fetch("/api/bff/api/v1/exports", { method: "POST", headers: { "Content-Type": "application/json" }, body, keepalive: true })
      .catch(() => undefined);
  } catch {
    /* the export goes on */
  }
}
