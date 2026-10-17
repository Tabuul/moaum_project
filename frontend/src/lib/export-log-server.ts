/**
 * V529: a report the portal's own server builds (a PDF, a CSV or a workbook made in a route handler) is recorded on the export
 * log as the browser's are, for the person and office of the session that asked for it. It never holds up or stops the document:
 * the record is awaited briefly and a failure is ignored.
 */
import { api } from "@/lib/api";
import { exportBody, type ExportRecord } from "@/lib/export-log";

export async function logServerExport(r: ExportRecord, request: Request): Promise<void> {
  try {
    const url = new URL(request.url);
    await api("/api/v1/exports", { method: "POST", body: JSON.parse(exportBody(r, url.pathname, url.search)) });
  } catch {
    /* the document goes out */
  }
}
