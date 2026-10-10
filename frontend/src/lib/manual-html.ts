/** V387: the manual as a printed sheet — the body the central document system prints under the official header. Pure, node-tested. */
import { byCategory, pieces, type Procedure } from "./manual.ts";

const esc = (x: unknown) => String(x ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c] ?? c));

function stepHtml(step: string, menus: string[]): string {
  return pieces(step, menus).map((p) => (p.kind === "menu" ? `<b>${esc(p.label)}</b>` : p.kind === "control" ? `<code>${esc(p.text)}</code>` : esc(p.text))).join("");
}

/** the procedures by category: a heading, then title, purpose, numbered steps and the expected result for each */
export function manualHtml(rows: Procedure[], menus: string[], opts: { contents?: boolean } = {}): string {
  const groups = byCategory(rows);
  let out = "";
  if (opts.contents !== false && rows.length > 6) {
    out += `<h2 style="font-size:12.5px;margin:0 0 6px">Contents</h2><ol style="margin:0 0 14px 18px;padding:0;font-size:10.5px;columns:2">`;
    for (const g of groups) for (const p of g.rows) out += `<li>${esc(p.title)} <span style="color:#667">— ${esc(g.word)}</span></li>`;
    out += `</ol>`;
  }
  for (const g of groups) {
    out += `<h2 style="font-size:12.5px;margin:14px 0 6px;padding-bottom:3px;border-bottom:1px solid #cbd3dc;break-after:avoid">${esc(g.word)}</h2>`;
    for (const p of g.rows) {
      out += `<section style="break-inside:avoid;margin:0 0 10px"><h3 style="font-size:11.5px;margin:0 0 2px">${esc(p.title)}</h3>`;
      out += `<p style="margin:0 0 4px;font-size:10.5px"><b>Purpose:</b> ${esc(p.purpose)}</p><ol style="margin:0 0 4px 18px;padding:0;font-size:10.5px">`;
      for (const s of p.steps) out += `<li>${stepHtml(s, menus)}</li>`;
      out += `</ol><p style="margin:0;font-size:10.5px"><b>Expected result:</b> ${esc(p.expected)}</p></section>`;
    }
  }
  return out || `<p>No procedure is published for this office yet.</p>`;
}
