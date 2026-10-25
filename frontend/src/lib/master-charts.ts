/**
 * V650: the Master University Report's charts, drawn as SVG text so the dashboard and the printed report show the very same
 * drawing from the same figures. The categorical colours are the validated reference palette in its fixed order (never cycled,
 * the colour following the entity); thin marks with rounded data-ends and a 2px gap; every mark carries a native tooltip; values
 * and labels stay in text inks; each chart sits beside the table of its figures, which is its accessible view.
 */

import type { MasterSummary, SummaryRow } from "@/lib/master-report";

export const SERIES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6", "#e34948"];
const INK = "#0b0b0b";
const INK_2 = "#52514e";
const MUTED = "#8a8985";
const GRID = "#e4e3df";
const SURFACE = "#fcfcfb";

export interface Datum { label: string; value: number }

const esc = (s: unknown) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c] ?? c));

/** a figure as people read it: grouped thousands, naira with the sign where asked, millions shortened on an axis */
export function figure(v: number, money = false, short = false): string {
  const n = Number(v) || 0;
  if (short && Math.abs(n) >= 1_000_000) return `${money ? "₦" : ""}${(n / 1_000_000).toLocaleString("en-GB", { maximumFractionDigits: 1 })}m`;
  if (short && Math.abs(n) >= 10_000) return `${money ? "₦" : ""}${(n / 1_000).toLocaleString("en-GB", { maximumFractionDigits: 0 })}k`;
  return `${money ? "₦" : ""}${n.toLocaleString("en-GB", { maximumFractionDigits: money ? 2 : 0 })}`;
}

function frame(w: number, h: number, title: string, body: string): string {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}" width="100%" role="img" aria-label="${esc(title)}" style="font-family:'Segoe UI',system-ui,Arial,sans-serif;background:${SURFACE};max-width:${w}px">`
    + `<text x="12" y="20" font-size="13" font-weight="600" fill="${INK}">${esc(title)}</text>${body}</svg>`;
}

function clip(label: string, max: number): string {
  return label.length > max ? `${label.slice(0, max - 1)}…` : label;
}

/** a horizontal bar chart: one series, the bars in the order given, each labelled with its value */
export function barChart(title: string, data: Datum[], opts: { money?: boolean; color?: string; width?: number } = {}): string {
  const w = opts.width ?? 720;
  const rows = data.slice(0, 40);
  const labelW = 210;
  const bar = 16, gap = 8, top = 34;
  const h = top + rows.length * (bar + gap) + 18;
  const max = Math.max(1, ...rows.map((d) => d.value));
  const plot = w - labelW - 90;
  const color = opts.color ?? SERIES[0];
  const ticks = [0, 0.25, 0.5, 0.75, 1].map((t) => `<line x1="${labelW + t * plot}" y1="${top - 4}" x2="${labelW + t * plot}" y2="${h - 14}" stroke="${GRID}" stroke-width="1"/>`
    + `<text x="${labelW + t * plot}" y="${h - 3}" font-size="9" fill="${MUTED}" text-anchor="middle">${esc(figure(max * t, opts.money, true))}</text>`).join("");
  const bars = rows.map((d, i) => {
    const y = top + i * (bar + gap);
    const len = Math.max(d.value > 0 ? 3 : 0, (d.value / max) * plot);
    return `<g><title>${esc(d.label)}: ${esc(figure(d.value, opts.money))}</title>`
      + `<text x="${labelW - 8}" y="${y + bar - 4}" font-size="10.5" fill="${INK_2}" text-anchor="end">${esc(clip(d.label, 34))}</text>`
      + `<path d="M${labelW},${y} h${Math.max(0, len - 4)} a4,4 0 0 1 4,4 v${bar - 8} a4,4 0 0 1 -4,4 h${-Math.max(0, len - 4)} z" fill="${color}"/>`
      + `<text x="${labelW + len + 6}" y="${y + bar - 4}" font-size="10.5" fill="${INK}">${esc(figure(d.value, opts.money))}</text></g>`;
  }).join("");
  return frame(w, h, title, ticks + bars);
}

/** a donut: the parts of one whole (two to four), each named with its value and share beside it */
export function pieChart(title: string, data: Datum[], opts: { money?: boolean; width?: number } = {}): string {
  const w = opts.width ?? 360;
  const parts = data.filter((d) => d.value > 0).slice(0, 8);
  const total = parts.reduce((s, d) => s + d.value, 0);
  const cx = 92, cy = 112, r = 66, inner = 40;
  const h = Math.max(200, 50 + data.length * 34);
  if (total <= 0) return frame(w, h, title, `<text x="12" y="60" font-size="11" fill="${MUTED}">Nothing to show for this selection.</text>`);
  let a = -Math.PI / 2;
  const arcs = parts.map((d, i) => {
    const sweep = (d.value / total) * Math.PI * 2;
    const a2 = a + sweep;
    const large = sweep > Math.PI ? 1 : 0;
    const p = (ang: number, rad: number) => `${cx + rad * Math.cos(ang)},${cy + rad * Math.sin(ang)}`;
    const color = SERIES[data.indexOf(d) % SERIES.length] ?? SERIES[i];
    const path = parts.length === 1
      ? `<circle cx="${cx}" cy="${cy}" r="${(r + inner) / 2}" fill="none" stroke="${color}" stroke-width="${r - inner}"/>`
      : `<path d="M${p(a, r)} A${r},${r} 0 ${large} 1 ${p(a2, r)} L${p(a2, inner)} A${inner},${inner} 0 ${large} 0 ${p(a, inner)} z" fill="${color}" stroke="${SURFACE}" stroke-width="2"/>`;
    a = a2;
    return `<g><title>${esc(d.label)}: ${esc(figure(d.value, opts.money))} (${((d.value / total) * 100).toFixed(1)}%)</title>${path}</g>`;
  }).join("");
  const legend = data.map((d, i) => {
    const y = 48 + i * 34;
    const share = total > 0 ? ((d.value / total) * 100).toFixed(1) : "0.0";
    return `<rect x="178" y="${y - 9}" width="10" height="10" rx="2" fill="${SERIES[i % SERIES.length]}"/>`
      + `<text x="194" y="${y}" font-size="10.5" fill="${INK_2}">${esc(clip(d.label, 24))}</text>`
      + `<text x="194" y="${y + 14}" font-size="11" font-weight="600" fill="${INK}">${esc(figure(d.value, opts.money))} · ${share}%</text>`;
  }).join("");
  const centre = `<text x="${cx}" y="${cy + 4}" font-size="12" font-weight="600" fill="${INK}" text-anchor="middle">${esc(figure(total, opts.money, true))}</text>`;
  return frame(w, h, title, arcs + centre + legend);
}

/** a line over days: one measure, its axis from zero, a marker on each day when there are few */
export function lineChart(title: string, data: Datum[], opts: { money?: boolean; width?: number; color?: string } = {}): string {
  const w = opts.width ?? 720, h = 230;
  const left = 64, right = 16, top = 34, bottom = 40;
  const pts = data.slice(-400);
  if (!pts.length) return frame(w, 80, title, `<text x="12" y="52" font-size="11" fill="${MUTED}">No transactions in the period.</text>`);
  const max = Math.max(1, ...pts.map((d) => d.value));
  const pw = w - left - right, ph = h - top - bottom;
  const x = (i: number) => left + (pts.length === 1 ? pw / 2 : (i / (pts.length - 1)) * pw);
  const y = (v: number) => top + ph - (v / max) * ph;
  const color = opts.color ?? SERIES[0];
  const grid = [0, 0.5, 1].map((t) => `<line x1="${left}" y1="${y(max * t)}" x2="${w - right}" y2="${y(max * t)}" stroke="${GRID}"/>`
    + `<text x="${left - 6}" y="${y(max * t) + 3}" font-size="9" fill="${MUTED}" text-anchor="end">${esc(figure(max * t, opts.money, true))}</text>`).join("");
  const line = `<polyline fill="none" stroke="${color}" stroke-width="2" stroke-linejoin="round" points="${pts.map((d, i) => `${x(i)},${y(d.value)}`).join(" ")}"/>`;
  const step = Math.max(1, Math.ceil(pts.length / 8));
  const labels = pts.map((d, i) => (i % step === 0 || i === pts.length - 1)
    ? `<text x="${x(i)}" y="${h - bottom + 16}" font-size="9" fill="${MUTED}" text-anchor="middle">${esc(d.label.slice(5))}</text>` : "").join("");
  const marks = pts.map((d, i) => `<g><title>${esc(d.label)}: ${esc(figure(d.value, opts.money))}</title>`
    + `<circle cx="${x(i)}" cy="${y(d.value)}" r="${pts.length <= 31 ? 4 : 6}" fill="${pts.length <= 31 ? color : "transparent"}" stroke="${pts.length <= 31 ? SURFACE : "none"}" stroke-width="2"/></g>`).join("");
  return frame(w, h, title, grid + line + marks + labels);
}

/** horizontal stacked bars: each category's parts side by side in the palette's order, a 2px gap between parts, a legend above */
export function stackedChart(title: string, categories: string[], series: { name: string; values: number[] }[], opts: { width?: number } = {}): string {
  const w = opts.width ?? 720;
  const labelW = 120, bar = 18, gap = 10, top = 58;
  const h = top + categories.length * (bar + gap) + 10;
  const totals = categories.map((_, i) => series.reduce((s, x) => s + (x.values[i] ?? 0), 0));
  const max = Math.max(1, ...totals);
  const plot = w - labelW - 80;
  const legend = series.map((s, i) => `<rect x="${12 + i * 160}" y="32" width="10" height="10" rx="2" fill="${SERIES[i % SERIES.length]}"/>`
    + `<text x="${28 + i * 160}" y="41" font-size="10.5" fill="${INK_2}">${esc(s.name)}</text>`).join("");
  const rows = categories.map((c, ci) => {
    const y = top + ci * (bar + gap);
    let x = labelW;
    const segs = series.map((s, si) => {
      const v = s.values[ci] ?? 0;
      const len = (v / max) * plot;
      const seg = len > 0 ? `<g><title>${esc(c)} — ${esc(s.name)}: ${esc(figure(v))}</title><rect x="${x}" y="${y}" width="${Math.max(0, len - 2)}" height="${bar}" rx="2" fill="${SERIES[si % SERIES.length]}"/></g>` : "";
      x += len;
      return seg;
    }).join("");
    return `<text x="${labelW - 8}" y="${y + bar - 5}" font-size="10.5" fill="${INK_2}" text-anchor="end">${esc(clip(c, 18))}</text>${segs}`
      + `<text x="${x + 6}" y="${y + bar - 5}" font-size="10.5" fill="${INK}">${esc(figure(totals[ci]))}</text>`;
  }).join("");
  return frame(w, h, title, legend + rows);
}

/* ── the report's charts, each placed after the section whose figures it draws ─────────────────────────────────────────── */

function rowsOf(s: MasterSummary, dim: string): SummaryRow[] {
  return s.summary.filter((r) => r.dim === dim);
}

export function reportCharts(s: MasterSummary): Record<string, string[]> {
  const a = s.summary.find((r) => r.dim === "ALL");
  if (!a) return {};
  const fac = rowsOf(s, "FACULTY").sort((x, y) => (x.faculty ?? "").localeCompare(y.faculty ?? ""));
  const sexOf = (v: string | null) => { const u = (v ?? "").toUpperCase(); return u === "M" || u === "MALE" ? "Male" : u === "F" || u === "FEMALE" ? "Female" : "Not stated"; };
  const out: Record<string, string[]> = {};
  out.faculty = [barChart("Students by faculty", fac.map((r) => ({ label: r.faculty ?? "(none)", value: r.total })))];
  const genders = rowsOf(s, "GENDER").sort((x, y) => sexOf(x.sex).localeCompare(sexOf(y.sex)));
  out.gender = [
    pieChart("Male and female students", genders.map((r) => ({ label: sexOf(r.sex), value: r.total }))),
    stackedChart("School fees by gender", genders.map((r) => sexOf(r.sex)), [
      { name: "Paid in full", values: genders.map((r) => r.fees_paid) },
      { name: "Part paid", values: genders.map((r) => r.fees_part) },
      { name: "Not paid", values: genders.map((r) => r.fees_not_paid) },
      { name: "No fee stated", values: genders.map((r) => r.no_fee) },
    ]),
  ];
  out.level = [barChart("Students by level", rowsOf(s, "LEVEL").sort((x, y) => (x.level ?? 9999) - (y.level ?? 9999))
    .map((r) => ({ label: r.level == null ? "Not stated" : `${r.level} Level`, value: r.total })))];
  out.fees = [pieChart("School fees: paid and not paid", [
    { label: "Paid in full", value: a.fees_paid }, { label: "Part paid", value: a.fees_part }, { label: "Not paid", value: a.fees_not_paid }, { label: "No fee stated", value: a.no_fee }])];
  out.fees_faculty = [barChart("Paid but not registered, by faculty", fac.map((r) => ({ label: r.faculty ?? "(none)", value: r.paid_not_registered })), { color: SERIES[1] })];
  if (s.money === "ALL" && a.paid_amount != null) {
    out.fees_faculty.push(barChart("School fees paid, by faculty (₦)", fac.map((r) => ({ label: r.faculty ?? "(none)", value: Number(r.paid_amount ?? 0) })), { money: true }));
  }
  if (s.transactions) {
    out.tx_purpose = [barChart("Revenue by payment purpose (₦)", s.transactions.byPurpose.filter((p) => p.revenue > 0).map((p) => ({ label: p.label, value: Number(p.revenue) })), { money: true })];
    out.tx_daily = [
      lineChart("Successful transactions by day", s.transactions.byDay.map((d) => ({ label: d.day, value: Number(d.transactions) }))),
      lineChart("Revenue by day (₦)", s.transactions.byDay.map((d) => ({ label: d.day, value: Number(d.amount) })), { money: true, color: SERIES[2] }),
    ];
  }
  out.gst = [pieChart("GST: paid and not paid", [{ label: "Paid", value: a.gst_paid }, { label: "Not paid", value: a.gst_not_paid }])];
  out.eps = [pieChart("EPS: paid and not paid", [{ label: "Paid", value: a.eps_paid }, { label: "Not paid", value: a.eps_not_paid }])];
  out.cards = [pieChart("Examination cards", [{ label: "Issued", value: a.card_issued }, { label: "Eligible, not drawn", value: a.card_not_issued }, { label: "Not eligible", value: a.card_not_eligible }])];
  out.permits = [pieChart("GST & EPS permits", [{ label: "Printed", value: a.permit_printed }, { label: "Eligible, not printed", value: a.permit_not_printed }])];
  return out;
}
