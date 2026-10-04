/**
 * The central browser print (V320): one HTML document for every "Print" that is not a server PDF —
 * the official header, the title and subtitle, the filters a report was made with, a table with a
 * serial column whose header repeats on every printed page, and a running footer with the University,
 * the title, the generation line and the reference. The same identity and profile dress the server's
 * PDFs, so the two look like one institution's paper.
 *
 * Page numbers: browsers print "Page X of Y" only from the @page margin boxes, which Firefox honours and
 * Chrome does not; the rule is emitted for the browsers that can, and the server PDF numbers every page.
 */
import { DEFAULT_INSTITUTION, addressLine, contactLine, formatDocDateTime, nameUpper, type Institution } from "./institution.ts";
import { currentInstitution } from "./institution-cache.ts";
import { getInstitution, institutionLogoAbsoluteUrl } from "./institution-client.ts";
import { documentTitle, profileOf, type DocumentProfileId } from "./profiles.ts";

export type Cell = string | number | null | undefined;

export interface PrintSpec {
  title: string;
  subtitle?: string | null;
  /** the filters and facts the paper must carry on its own */
  meta?: [string, string][];
  headers?: string[];
  rows?: Cell[][];
  /** HTML already built by the screen (a designed sheet), printed under the official header instead of rows */
  bodyHtml?: string;
  footnote?: string | null;
  reference?: string | null;
  generatedBy?: string | null;
  copy?: string | null;
  confidentiality?: string | null;
  watermark?: string | null;
  unit?: string | null;
  /** a serial column leads the table (the profile's default) */
  serial?: boolean;
  orientation?: "portrait" | "landscape";
}

export const esc = (x: unknown) => String(x ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c] ?? c));

/** rows with a serial column in front, 1 upwards — display only, never an identifier */
export function withSerial(rows: Cell[][], from = 1): Cell[][] {
  return rows.map((r, i) => [from + i, ...r]);
}

const CSS = `
  *{box-sizing:border-box}
  html,body{margin:0;padding:0;background:#fff}
  body{font:11.5px/1.45 "Segoe UI",system-ui,-apple-system,Arial,sans-serif;color:#13242d;padding:0 0 16mm}
  .doc{padding:0}
  .hd{display:flex;gap:14px;align-items:center;border-bottom:2px solid #0d3f54;padding-bottom:10px;margin-bottom:12px}
  .hd img{width:58px;height:58px;object-fit:contain;flex-shrink:0}
  .hd .name{font-size:15px;font-weight:800;color:#0d3f54;letter-spacing:.02em}
  .hd .motto{font-size:11px;font-style:italic;color:#5a6b74;margin-top:1px}
  .hd .addr,.hd .contact{font-size:10px;color:#5a6b74;margin-top:1px}
  .hd .unit{font-size:10.5px;font-weight:700;color:#13242d;margin-top:3px;text-transform:uppercase}
  .ttl{display:flex;align-items:baseline;gap:12px;margin:2px 0 2px}
  .ttl h1{font-size:14px;margin:0;letter-spacing:.04em;text-transform:uppercase;color:#13242d}
  .ttl .copy{margin-left:auto;font-size:9.5px;font-weight:700;color:#5a6b74;letter-spacing:.08em}
  .sub{font-size:11px;color:#5a6b74;margin:0 0 2px}
  .ref{font-size:10px;color:#5a6b74;margin:0 0 4px}
  .meta{display:grid;grid-template-columns:repeat(3,1fr);gap:2px 18px;margin:8px 0 12px;font-size:10.5px}
  .meta div span{display:block;font-size:8.5px;text-transform:uppercase;letter-spacing:.06em;color:#7a8a94}
  .meta div b{font-weight:600}
  table{border-collapse:collapse;width:100%;page-break-inside:auto}
  thead{display:table-header-group}
  tr{page-break-inside:avoid;break-inside:avoid}
  th{background:#0d3f54;color:#fff;text-align:left;padding:5px 7px;font-size:9.5px;text-transform:uppercase;letter-spacing:.04em;-webkit-print-color-adjust:exact;print-color-adjust:exact}
  td{padding:4px 7px;border-bottom:1px solid #e3e9ec;font-size:10.5px;vertical-align:top}
  tbody tr:nth-child(even) td{background:#f5f8f9;-webkit-print-color-adjust:exact;print-color-adjust:exact}
  td.n,th.n{text-align:right;font-variant-numeric:tabular-nums}
  td.sn,th.sn{width:38px;text-align:right;color:#5a6b74;font-variant-numeric:tabular-nums}
  .body button,.body .btn,.body input,.body .tsrch,.body .tfoot__x,.body .no-print{display:none!important}
  .body table{width:100%}
  .foot{position:fixed;left:0;right:0;bottom:0;border-top:1px solid #c9d3d9;padding:4px 0 0;font-size:9px;color:#6b7b85;background:#fff;display:flex;justify-content:space-between;gap:12px}
  .foot .r{text-align:right;white-space:nowrap}
  .note{margin-top:10px;font-size:10px;color:#5a6b74}
  .wm{position:fixed;top:40%;left:0;right:0;text-align:center;font-size:72px;font-weight:800;color:rgba(120,130,140,.13);transform:rotate(-24deg);pointer-events:none;letter-spacing:.1em}
  @page{margin:14mm 12mm 18mm;@bottom-right{content:"Page " counter(page) " of " counter(pages);font-size:9px;color:#6b7b85}}
  @media print{.foot{position:fixed}}
`;

/** the document as HTML — a pure function, so it can be tested and so a preview and the print are the same page */
export function documentHtml(inst: Institution, profileId: DocumentProfileId | string, spec: PrintSpec, logoUrl: string): string {
  const profile = profileOf(profileId);
  const title = documentTitle(profile, spec.title);
  const serial = spec.serial ?? profile.serialColumn;
  const headers = spec.headers ?? [];
  const rows = spec.rows ?? [];
  const hdr = serial ? ["S/N", ...headers] : headers;
  const body = serial ? withSerial(rows) : rows;
  const numeric = hdr.map((_, i) => body.length > 0 && body.every((r) => r[i] == null || r[i] === "" || typeof r[i] === "number" || /^-?[\d,]+(\.\d+)?%?$/.test(String(r[i]).trim())) && body.some((r) => r[i] != null && r[i] !== ""));
  const th = hdr.map((h, i) => `<th class="${i === 0 && serial ? "sn" : numeric[i] ? "n" : ""}">${esc(h)}</th>`).join("");
  const tr = body.map((r) => `<tr>${hdr.map((_, i) => `<td class="${i === 0 && serial ? "sn" : numeric[i] ? "n" : ""}">${esc(typeof r[i] === "number" ? (r[i] as number).toLocaleString("en-NG") : r[i])}</td>`).join("")}</tr>`).join("");
  const copy = spec.copy === undefined ? profile.copy : spec.copy;
  const conf = spec.confidentiality === undefined ? profile.confidentiality : spec.confidentiality;
  const orientation = spec.orientation ?? profile.orientation;
  const generated = `Generated ${formatDocDateTime(new Date(), inst)}${spec.generatedBy && inst.showGeneratedBy ? ` by ${esc(spec.generatedBy)}` : ""}`;
  const meta = spec.meta && spec.meta.length ? `<div class="meta">${spec.meta.map(([k, v]) => `<div><span>${esc(k)}</span><b>${esc(v)}</b></div>`).join("")}</div>` : "";
  const addr = addressLine(inst), contact = contactLine(inst);
  return `<!doctype html><html><head><meta charset="utf-8"><title>${esc(title)}${spec.reference ? ` · ${esc(spec.reference)}` : ""}</title>
<style>${CSS}@page{size:A4 ${orientation}}</style></head><body>
${spec.watermark ? `<div class="wm">${esc(spec.watermark)}</div>` : ""}
<div class="doc">
  <div class="hd">
    <img src="${esc(logoUrl)}" alt="" onerror="this.style.display='none'">
    <div>
      <div class="name">${esc(nameUpper(inst))}</div>
      ${inst.motto ? `<div class="motto">&ldquo;${esc(inst.motto)}&rdquo;</div>` : ""}
      ${addr ? `<div class="addr">${esc(addr)}</div>` : ""}
      ${contact ? `<div class="contact">${esc(contact)}</div>` : ""}
      ${spec.unit ? `<div class="unit">${esc(spec.unit)}</div>` : ""}
    </div>
  </div>
  <div class="ttl"><h1>${esc(title)}</h1>${copy ? `<span class="copy">${esc(copy)}</span>` : ""}</div>
  ${spec.subtitle ? `<div class="sub">${esc(spec.subtitle)}</div>` : ""}
  ${spec.reference ? `<div class="ref">Reference ${esc(spec.reference)}</div>` : ""}
  ${meta}
  ${spec.bodyHtml ? `<div class="body">${spec.bodyHtml}</div>` : `<table><thead><tr>${th}</tr></thead><tbody>${tr}</tbody></table>`}
  ${spec.footnote ? `<div class="note">${esc(spec.footnote)}</div>` : ""}
</div>
<div class="foot"><div>${esc(inst.name)} &nbsp;|&nbsp; ${esc(title)}${conf ? ` &nbsp;|&nbsp; ${esc(conf)}` : ""}${inst.footerNote ? `<br>${esc(inst.footerNote)}` : ""}</div><div class="r">${generated}${spec.reference ? `<br>Ref ${esc(spec.reference)}` : ""}</div></div>
</body></html>`;
}

/** open the document in a window of its own and print it (the browser's Save as PDF does the rest) */
function openAndPrint(html: string): void {
  const w = window.open("", "_blank");
  if (!w) return;
  w.document.write(html + `<script>window.onload=function(){setTimeout(function(){window.print();},300);}</script>`);
  w.document.close();
}

/** print a table document under the official header */
export async function printDocument(profileId: DocumentProfileId | string, spec: PrintSpec): Promise<void> {
  const inst = typeof window === "undefined" ? DEFAULT_INSTITUTION : await getInstitution();
  openAndPrint(documentHtml(inst, profileId, spec, institutionLogoAbsoluteUrl(inst)));
}

/** the document as a page to look at before printing: the same HTML, without the print call */
export async function previewDocument(profileId: DocumentProfileId | string, spec: PrintSpec): Promise<void> {
  const inst = await getInstitution();
  const w = window.open("", "_blank");
  if (!w) return;
  w.document.write(documentHtml(inst, profileId, spec, institutionLogoAbsoluteUrl(inst)));
  w.document.close();
}

/** the HTML of a part of the screen — a designed sheet, a table — cleaned of its controls, with the app's stylesheets */
export function elementHtml(el: HTMLElement): { body: string; heads: string } {
  const clone = el.cloneNode(true) as HTMLElement;
  clone.querySelectorAll(".no-print, button, .tfoot__x, .tsrch, input, select, .btn").forEach((n) => n.remove());
  clone.querySelectorAll("tr[hidden]").forEach((tr) => tr.removeAttribute("hidden"));
  if (clone instanceof HTMLTableElement) { clone.classList.remove("tbl--stack"); clone.removeAttribute("style"); }
  const heads: string[] = [];
  document.querySelectorAll('link[rel="stylesheet"], style').forEach((n) => { heads.push(n.outerHTML); });
  return { body: clone.outerHTML, heads: heads.join("") };
}

/** print a part of the screen under the official header — what the table's Print button and printNode do */
export async function printElement(el: HTMLElement | null, spec: Omit<PrintSpec, "rows" | "headers" | "bodyHtml">, profileId: DocumentProfileId | string = "STANDARD_REPORT"): Promise<void> {
  if (!el) { window.print(); return; }
  const inst = await getInstitution();
  const { body, heads } = elementHtml(el);
  const html = documentHtml(inst, profileId, { ...spec, bodyHtml: body }, institutionLogoAbsoluteUrl(inst))
    .replace("</head>", `${heads}<style>body{padding:0 0 16mm}.shell,.topbar,.nav,.scrim{display:none!important}</style></head>`);
  // a hidden same-origin iframe prints without a pop-up; the window is the fallback when it cannot
  const f = document.createElement("iframe");
  f.style.position = "fixed"; f.style.right = "0"; f.style.bottom = "0"; f.style.width = "0"; f.style.height = "0"; f.style.border = "0";
  document.body.appendChild(f);
  const doc = f.contentWindow?.document;
  if (!doc) { document.body.removeChild(f); openAndPrint(html); return; }
  doc.open(); doc.write(html); doc.close();
  window.setTimeout(() => {
    try { f.contentWindow?.focus(); f.contentWindow?.print(); } catch { openAndPrint(html); }
    window.setTimeout(() => { try { document.body.removeChild(f); } catch { /* already gone */ } }, 60000);
  }, 350);
}

export { currentInstitution };
