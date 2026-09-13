/**
 * One place that brands everything the portal hands a user to download, so a PDF
 * and an Excel of the same thing look like the same institution's document: the
 * crest, the University's name, the document title, the date it was generated,
 * and a serial the office can quote. Reuse brandedXlsx / brandedPrint for any
 * new export rather than calling buildXlsx or window.print directly.
 */
import { buildXlsx, loadCrest } from "@/lib/xlsx";

export const SCHOOL = "Rev. Fr. Moses Orshio Adasu University, Makurdi";

type Cell = string | number | null;

/** A per-document serial the office can quote: MOAUM/<PREFIX>/YYYYMMDD/HHMMSS-RR. */
export function docSerial(prefix: string): string {
  const d = new Date();
  const p = (n: number, w = 2) => String(n).padStart(w, "0");
  const stamp = `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}/${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
  const rand = p(Math.floor(Math.random() * 100));
  return `MOAUM/${prefix.toUpperCase()}/${stamp}-${rand}`;
}

function today(): string {
  return new Date().toLocaleDateString("en-GB", { day: "2-digit", month: "long", year: "numeric" });
}

/**
 * A branded .xlsx: the crest, the University name, the title and the generation
 * date/serial sit above the table. Returns the blob (async — it fetches the crest).
 */
export async function brandedXlsx(
  title: string,
  headers: string[],
  rows: Cell[][],
  opts: { sheetName?: string; serial?: string; sub?: string } = {},
): Promise<Blob> {
  const serial = opts.serial ?? docSerial("DOC");
  const logo = await loadCrest().catch(() => null);
  const sheet = (opts.sheetName ?? title).replace(/[\\/?*[\]:]/g, "-").slice(0, 31) || "Sheet1";
  return buildXlsx(headers, rows, sheet, {
    school: SCHOOL,
    title: opts.sub ? `${title} — ${opts.sub}` : title,
    date: `Generated ${today()} · Serial ${serial}`,
    logo: logo ?? undefined,
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
 * Open a clean, branded window and print it — the browser's "Save as PDF" does
 * the rest. The crest, University name, title, subtitle, date and serial head
 * the page; the rows fill a table.
 */
export function brandedPrint(
  title: string,
  subtitle: string,
  headers: string[],
  rows: Cell[][],
  serial: string = docSerial("DOC"),
): void {
  const esc = (x: unknown) => String(x ?? "").replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c] ?? c));
  const th = headers.map((h) => `<th>${esc(h)}</th>`).join("");
  const tr = rows.map((r) => `<tr>${r.map((c) => `<td>${esc(c)}</td>`).join("")}</tr>`).join("");
  const crest = `${window.location.origin}/crest.png`;
  const html = `<!doctype html><html><head><meta charset="utf-8"><title>${esc(title)} · ${esc(serial)}</title>
    <style>
      body{font:12px/1.4 "Segoe UI",system-ui,sans-serif;color:#13242d;margin:24px;}
      .head{display:flex;gap:14px;align-items:center;border-bottom:2px solid #0e3f55;padding-bottom:12px;margin-bottom:14px;}
      .head img{width:56px;height:56px;object-fit:contain;}
      .school{font-size:15px;font-weight:700;color:#0e3f55;}
      .title{font-size:13px;margin-top:2px;}
      .meta{margin-left:auto;text-align:right;color:#5a6b74;font-size:11px;line-height:1.5;}
      table{border-collapse:collapse;width:100%;} th{background:#0e3f55;color:#fff;text-align:left;padding:6px 8px;font-size:10px;text-transform:uppercase;letter-spacing:.3px;}
      td{padding:5px 8px;border-bottom:1px solid #e8eef1;font-size:11px;} tbody tr:nth-child(even){background:#f6f9fa;}
      .foot{margin-top:14px;color:#8a99a1;font-size:10px;}
      @media print{@page{size:landscape;margin:12mm;}}
    </style></head><body>
    <div class="head">
      <img src="${crest}" alt="">
      <div><div class="school">${esc(SCHOOL)}</div><div class="title">${esc(title)}${subtitle ? ` — ${esc(subtitle)}` : ""}</div></div>
      <div class="meta">Generated ${esc(today())}<br>Serial ${esc(serial)}</div>
    </div>
    <table><thead><tr>${th}</tr></thead><tbody>${tr}</tbody></table>
    <div class="foot">${esc(SCHOOL)} · ${esc(serial)} · generated from the portal on ${esc(today())}</div>
    <script>window.onload=function(){setTimeout(function(){window.print();},250);}</script></body></html>`;
  const w = window.open("", "_blank");
  if (!w) return;
  w.document.write(html);
  w.document.close();
}
