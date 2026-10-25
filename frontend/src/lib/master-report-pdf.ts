/**
 * V650: the Master University Report as a printed document — the browser's "Save as PDF" writes it, as every report of the
 * portal (lib/document/html). A cover page (the crest, the University, the scope, the title, the session and semester, when it
 * was generated, the period, who generated it, the reference), then on every page the official heading and a footer with the
 * reference, who generated it, when, and the page of pages; the sections in the University's order, each numbered, each table
 * with S/N first and running on across its pages, the charts beside the figures they draw, the definitions, the filters and the
 * report's record last. Pure: the same package always draws the same document.
 */
import { esc } from "@/lib/document/html";
import { addressLine, contactLine, formatDocDateTime, nameUpper, type Institution } from "@/lib/document/institution";
import { getInstitution, institutionLogoAbsoluteUrl } from "@/lib/document/institution-client";
import { cellText, type Section } from "@/lib/master-report";

export interface ReportPart { section?: Section; chart?: string; charts?: string[]; heading?: string; html?: string }

export interface ReportPackage {
  reference: string;
  title: string;
  generatedBy: string | null;
  generatedAt: string;
  session: string;
  semester: string;
  scope: string;
  period: string;
  meta: [string, string][];
  kpis: { label: string; value: string }[];
  parts: ReportPart[];
}

/** a table's rows in the PDF: at most this many, the whole list in the Excel */
export const PDF_ROWS = 2500;

const CSS = `
*{box-sizing:border-box}
html,body{margin:0;padding:0;background:#fff}
body{font:10.5px/1.4 "Segoe UI",system-ui,-apple-system,Arial,sans-serif;color:#13242d}
@page{size:A4 landscape;margin:10mm 10mm 16mm;@bottom-right{content:"Page " counter(page) " of " counter(pages);font-size:8.5px;color:#5d6c76}}
.cover{position:relative;z-index:3;background:#fff;height:182mm;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;break-after:page;page-break-after:always}
.cover img{width:110px;height:110px;object-fit:contain;margin-bottom:12px}
.cover .name{font-size:22px;font-weight:800;color:#0d3f54;letter-spacing:.03em}
.cover .motto{font-style:italic;color:#5a6b74;margin-top:2px}
.cover .addr{font-size:10px;color:#5a6b74;margin-top:2px}
.cover .unit{font-size:13px;font-weight:700;margin-top:14px;text-transform:uppercase}
.cover h1{font-size:20px;margin:22px 0 6px;letter-spacing:.06em;color:#13242d}
.cover .period{font-size:13px;color:#13242d;margin-bottom:22px}
.cover table{border-collapse:collapse;margin:0 auto;font-size:11.5px}
.cover td{padding:4px 14px;text-align:left;border:none}
.cover td.k{color:#5a6b74;text-transform:uppercase;font-size:9.5px;letter-spacing:.06em;text-align:right}
.phead{position:fixed;top:0;left:0;right:0;height:17mm;display:flex;align-items:center;gap:10px;border-bottom:1.5px solid #0d3f54;background:#fff;z-index:2}
.phead img{width:34px;height:34px;object-fit:contain}
.phead .n{font-size:11.5px;font-weight:800;color:#0d3f54}
.phead .t{font-size:9.5px;color:#13242d;text-transform:uppercase;letter-spacing:.04em}
.phead .s{margin-left:auto;font-size:9.5px;color:#5a6b74;text-align:right}
.pfoot{position:fixed;bottom:0;left:0;right:0;height:9mm;border-top:1px solid #c9d3d9;font-size:8.5px;color:#5d6c76;display:flex;justify-content:space-between;align-items:flex-start;padding-top:3px;background:#fff;z-index:2}
table.page{width:100%;border-collapse:collapse}
table.page>thead>tr>td{height:20mm;padding:0}
table.page>tfoot>tr>td{height:11mm;padding:0}
table.page>tbody>tr>td{padding:0}
h2{font-size:13px;color:#0d3f54;margin:14px 0 6px;text-transform:uppercase;letter-spacing:.04em;break-after:avoid;page-break-after:avoid}
h2 .no{color:#5a6b74;margin-right:6px}
.kpis{display:grid;grid-template-columns:repeat(5,1fr);gap:6px;margin:4px 0 10px}
.kpi{border:1px solid #d6dee3;border-radius:4px;padding:6px 8px;break-inside:avoid}
.kpi .l{font-size:8.5px;color:#5a6b74;text-transform:uppercase;letter-spacing:.05em}
.kpi .v{font-size:15px;font-weight:700;color:#13242d;font-variant-numeric:tabular-nums}
table.t{border-collapse:collapse;width:100%;margin-bottom:6px}
table.t thead{display:table-header-group}
table.t tr{break-inside:avoid;page-break-inside:avoid}
table.t th{background:#0d3f54;color:#fff;text-align:left;padding:4px 5px;font-size:8.5px;text-transform:uppercase;letter-spacing:.03em;-webkit-print-color-adjust:exact;print-color-adjust:exact}
table.t td{padding:3px 5px;border-bottom:1px solid #e3e9ec;font-size:9.5px;vertical-align:top}
table.t tbody tr:nth-child(even) td{background:#f5f8f9;-webkit-print-color-adjust:exact;print-color-adjust:exact}
table.t td.n,table.t th.n{text-align:right;font-variant-numeric:tabular-nums}
table.t td.sn{color:#5a6b74;text-align:right;width:34px}
.note{font-size:9px;color:#5a6b74;margin:2px 0 8px}
.charts{display:flex;flex-wrap:wrap;gap:10px;margin:6px 0 12px;break-inside:avoid}
.charts>div{flex:1 1 320px;break-inside:avoid;border:1px solid #e3e9ec;border-radius:4px;padding:4px}
.charts svg{width:100%;height:auto}
.wide{flex-basis:100%!important}
`;

/** a section's table, S/N first and continuous across its pages, the figures to the right as the section's kinds say */
export function sectionTable(s: Section, cap = PDF_ROWS): string {
  const rows = s.rows.slice(0, cap);
  const numeric = s.kinds.map((k) => k === "INT" || k === "MONEY");
  const head = `<tr><th class="n">S/N</th>${s.headers.map((h, i) => `<th class="${numeric[i] ? "n" : ""}">${esc(h)}</th>`).join("")}</tr>`;
  const body = rows.map((r, i) => `<tr><td class="sn">${i + 1}</td>${s.headers.map((_, c) => `<td class="${numeric[c] ? "n" : ""}">${esc(cellText(r[c] ?? null, s.kinds[c] ?? "TEXT"))}</td>`).join("")}</tr>`).join("");
  return rows.length ? `<table class="t"><thead>${head}</thead><tbody>${body}</tbody></table>` : `<div class="note">Nothing to list for this selection.</div>`;
}

export function masterReportHtml(inst: Institution, logoUrl: string, p: ReportPackage): string {
  const addr = addressLine(inst), contact = contactLine(inst);
  const when = formatDocDateTime(p.generatedAt, inst);
  const footLeft = `${esc(inst.name)} · ${esc(p.title)} · Reference ${esc(p.reference)}`;
  const footRight = `Generated ${esc(when)}${p.generatedBy ? ` by ${esc(p.generatedBy)}` : ""}`;
  let no = 0;
  const body = p.parts.map((part) => {
    const out: string[] = [];
    if (part.heading) {
      no += 1;
      out.push(`<h2><span class="no">${no}.</span>${esc(part.heading)}</h2>`);
    } else if (part.section) {
      no += 1;
      out.push(`<h2><span class="no">${no}.</span>${esc(part.section.title)}</h2>`);
    }
    if (part.html) out.push(part.html);
    if (part.section) {
      out.push(sectionTable(part.section));
      if (part.section.note) out.push(`<div class="note">${esc(part.section.note)}</div>`);
    }
    const charts = [...(part.charts ?? []), ...(part.chart ? [part.chart] : [])];
    if (charts.length) out.push(`<div class="charts">${charts.map((c) => `<div class="${c.includes('viewBox="0 0 720') ? "wide" : ""}">${c}</div>`).join("")}</div>`);
    return out.join("");
  }).join("");
  const kpis = `<div class="kpis">${p.kpis.map((k) => `<div class="kpi"><div class="l">${esc(k.label)}</div><div class="v">${esc(k.value)}</div></div>`).join("")}</div>`;
  const meta = `<h2><span class="no">${no + 1}.</span>Report filters and metadata</h2>${sectionTable({ key: "meta", title: "Filters", headers: ["Item", "Value"], kinds: ["TEXT", "TEXT"], rows: p.meta, note: null }, 200)}`;
  return `<!doctype html><html><head><meta charset="utf-8"><title>${esc(p.title)} · ${esc(p.reference)}</title><style>${CSS}</style></head><body>
<div class="cover">
  <img src="${esc(logoUrl)}" alt="" onerror="this.style.display='none'">
  <div class="name">${esc(nameUpper(inst))}</div>
  ${inst.motto ? `<div class="motto">&ldquo;${esc(inst.motto)}&rdquo;</div>` : ""}
  ${addr ? `<div class="addr">${esc(addr)}</div>` : ""}${contact ? `<div class="addr">${esc(contact)}</div>` : ""}
  <div class="unit">${esc(p.scope)}</div>
  <h1>${esc(p.title.toUpperCase())}</h1>
  <div class="period">Academic Session: ${esc(p.session)} · ${esc(p.semester)}</div>
  <table>
    <tr><td class="k">Report generated</td><td>${esc(when)}</td></tr>
    <tr><td class="k">Report period</td><td>${esc(p.period)}</td></tr>
    <tr><td class="k">Generated by</td><td>${esc(p.generatedBy ?? "—")}</td></tr>
    <tr><td class="k">Report reference</td><td><b>${esc(p.reference)}</b></td></tr>
  </table>
</div>
<div class="phead"><img src="${esc(logoUrl)}" alt="" onerror="this.style.display='none'"><div><div class="n">${esc(nameUpper(inst))}</div><div class="t">${esc(p.title)}</div></div>
  <div class="s">${esc(p.session)} · ${esc(p.semester)}<br>${esc(p.scope)}</div></div>
<div class="pfoot"><div>${footLeft}</div><div>${footRight}</div></div>
<table class="page"><thead><tr><td></td></tr></thead><tfoot><tr><td></td></tr></tfoot><tbody><tr><td>
<h2><span class="no">1.</span>Executive summary</h2>${kpis}
${body.replace(/<span class="no">(\d+)\.<\/span>/g, (_, n) => `<span class="no">${Number(n) + 1}.</span>`)}
${meta.replace(/<span class="no">(\d+)\.<\/span>/, (_, n) => `<span class="no">${Number(n) + 1}.</span>`)}
</td></tr></tbody></table>
</body></html>`;
}

/** write the report into a window opened at the click, and print it (the browser's Save as PDF does the rest) */
export async function printMasterReport(p: ReportPackage, opened: Window | null): Promise<boolean> {
  const inst = await getInstitution();
  const w = opened ?? window.open("", "_blank");
  if (!w) return false;
  w.document.open();
  w.document.write(masterReportHtml(inst, institutionLogoAbsoluteUrl(inst), p) + `<script>window.onload=function(){setTimeout(function(){window.print();},400);}</script>`);
  w.document.close();
  return true;
}
