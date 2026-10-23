/**
 * The school fees setup as a report: every fee line of the session grouped by faculty — and, where a faculty's fees differ by
 * programme (the College of Health Sciences under Basic Medical Sciences), by programme within it — and within each, the whole
 * session's lines, then the first semester's, then the second's, before the next faculty; levels in order, spillover last,
 * then the entry mode and indigeneship. The serial number runs down the whole report. Pure functions: the screen prints and
 * exports with them under the official header (logo, name, session).
 */

export interface FeeLine {
  item: string; amount: number; level: number | null; entry_mode: string | null; faculty_code: string | null; faculty_name: string | null;
  programme_code: string | null; programme_name: string | null; fee_group_name?: string | null; semester: number | null; indigene: string | null;
  spillover: boolean; kind?: string; ord?: number;
  /** V648: ACTIVE, ARCHIVED (deactivated), REPLACED (a corrected line stated beside it) or REMOVED — a report of more than the lines
   *  in force says which each is */
  status?: string;
}

export interface FeeGroup { key: string; faculty: string; programme: string | null; lines: FeeLine[] }

const MODES = ["UTME", "TRANSFER", "DIRECT_ENTRY", "JUPEB", "SANDWICH", "POSTGRADUATE", "CCE"];
const MODE_LABEL: Record<string, string> = {
  UTME: "UTME", TRANSFER: "Transfer", DIRECT_ENTRY: "Direct entry", JUPEB: "JUPEB", SANDWICH: "Sandwich", POSTGRADUATE: "Postgraduate", CCE: "CCE (part-time)",
};
const SEMESTER = ["Whole session", "First semester", "Second semester", "Third semester"];

/** "BASIC MEDICAL SCIENCES" → "Basic Medical Sciences" (and, of, for, in, the kept small) */
export function titled(s: string | null | undefined): string {
  return (s ?? "").toLowerCase().replace(/(^|\s|\()\S/g, (c) => c.toUpperCase()).replace(/ (And|Of|For|In|The) /g, (m) => m.toLowerCase()).trim();
}

export const facultyOf = (l: FeeLine) => (l.faculty_name ? titled(l.faculty_name) : l.faculty_code ?? "All faculties");
export const semesterOf = (l: FeeLine) => SEMESTER[l.semester ?? 0] ?? `Semester ${l.semester}`;
export const levelOf = (l: FeeLine) => (l.spillover ? "Spillover" : l.level ? `${l.level} Level` : "All levels");
export const modeOf = (l: FeeLine) => (l.entry_mode ? MODE_LABEL[l.entry_mode] ?? l.entry_mode : "All");
/** the item as the student's fees page words it: "School fees (First Semester)", not "(semester 1)" */
export const itemOf = (l: FeeLine) => l.item.replace(/\(semester ([123])\)/i, (_m, n: string) => `(${["First", "Second", "Third"][Number(n) - 1]} Semester)`);
export const statusOf = (l: FeeLine) => ({ ACTIVE: "Active", ARCHIVED: "Archived", REPLACED: "Replaced", REMOVED: "Removed" } as Record<string, string>)[l.status ?? "ACTIVE"] ?? l.status ?? "Active";
export const indigeneOf = (l: FeeLine) => (l.indigene === "INDIGENE" ? "Indigene" : l.indigene === "NON_INDIGENE" ? "Non-indigene" : "All");

const rank = (v: string | null, order: string[]) => (v == null ? order.length + 1 : order.indexOf(v) < 0 ? order.length : order.indexOf(v));
const KIND = ["FEE", "LATE_PAYMENT", "LATE_REGISTRATION"];

/** faculty (the University-wide lines first), programme (the faculty's own lines first), semester (the whole session's, then
 *  first, second, third), level (spillover after the highest), entry mode, indigene before non-indigene, the kind, the item */
export function compareFeeLines(a: FeeLine, b: FeeLine): number {
  const fa = a.faculty_code ? facultyOf(a) : "", fb = b.faculty_code ? facultyOf(b) : "";
  if (fa !== fb) return fa < fb ? -1 : 1;
  const pa = a.programme_name ?? "", pb = b.programme_name ?? "";
  if (pa !== pb) return pa < pb ? -1 : 1;
  const sa = a.semester ?? 0, sb = b.semester ?? 0;
  if (sa !== sb) return sa - sb;
  const la = a.spillover ? 10_000 : a.level ?? 0, lb = b.spillover ? 10_000 : b.level ?? 0;
  if (la !== lb) return la - lb;
  const ma = rank(a.entry_mode, MODES), mb = rank(b.entry_mode, MODES);
  if (ma !== mb) return ma - mb;
  const ia = rank(a.indigene, ["INDIGENE", "NON_INDIGENE"]), ib = rank(b.indigene, ["INDIGENE", "NON_INDIGENE"]);
  if (ia !== ib) return ia - ib;
  const ka = rank(a.kind ?? "FEE", KIND), kb = rank(b.kind ?? "FEE", KIND);
  if (ka !== kb) return ka - kb;
  return (a.ord ?? 0) - (b.ord ?? 0) || a.item.localeCompare(b.item);
}

export function sortFeeLines(lines: FeeLine[]): FeeLine[] {
  return [...lines].sort(compareFeeLines);
}

/** the report's sections: a faculty, or a programme of a faculty whose fees differ by programme, in the report's order */
export function feeGroups(lines: FeeLine[]): FeeGroup[] {
  const out: FeeGroup[] = [];
  for (const l of sortFeeLines(lines)) {
    const faculty = l.faculty_code ? facultyOf(l) : "All faculties";
    const programme = l.programme_name ?? null;   // as the register spells it: MBBS, B.Sc. HUMAN ANATOMY
    const key = `${faculty}|${programme ?? ""}`;
    const last = out[out.length - 1];
    if (last && last.key === key) last.lines.push(l);
    else out.push({ key, faculty, programme, lines: [l] });
  }
  return out;
}

/** the Excel rows: S/N first, then faculty, programme, semester, level, entry mode, indigeneship, item and amount */
export const FEE_SHEET_HEADERS = ["S/N", "Faculty", "Programme", "Semester", "Level", "Entry mode", "Indigeneship", "Item", "Amount (₦)"];
/** V648: with the status column when the report holds archived, replaced or removed lines beside the ones in force */
export const FEE_SHEET_HEADERS_WITH_STATUS = [...FEE_SHEET_HEADERS, "Status"];
export function feeSheetRows(lines: FeeLine[], withStatus = false): (string | number)[][] {
  return sortFeeLines(lines).map((l, i) => [
    i + 1, l.faculty_code ? facultyOf(l) : "All faculties", l.programme_name ?? "All programmes", semesterOf(l), levelOf(l),
    modeOf(l), indigeneOf(l), itemOf(l), Number(l.amount), ...(withStatus ? [statusOf(l)] : []),
  ]);
}

const esc = (x: unknown) => String(x ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c] ?? c));
const naira = (n: number) => Number(n).toLocaleString("en-NG", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

/** the printed report's body: a section for each faculty (or programme), the semesters one after another inside it, and one
 *  serial number down the whole report */
export function feeSetupBodyHtml(lines: FeeLine[]): string {
  const css = `<style>
    .fs-grp{margin:14px 0 4px;font-size:12px;font-weight:800;color:#0d3f54;text-transform:uppercase;letter-spacing:.03em;break-after:avoid;page-break-after:avoid}
    .fs-grp small{font-weight:600;color:#5a6b74;text-transform:none;letter-spacing:0}
    .fs tr.sem td{background:#e8eff2!important;font-weight:700;color:#13242d;font-size:10px;text-transform:uppercase;letter-spacing:.04em;-webkit-print-color-adjust:exact;print-color-adjust:exact}
    .fs{margin-bottom:6px}
  </style>`;
  let n = 0;
  const withGroup = lines.some((l) => l.fee_group_name);
  const cols = withGroup ? 7 : 6;
  const sections = feeGroups(lines).map((g) => {
    const bySem = new Map<string, FeeLine[]>();
    for (const l of g.lines) bySem.set(semesterOf(l), [...(bySem.get(semesterOf(l)) ?? []), l]);
    const body = [...bySem.entries()].map(([sem, ls]) =>
      `<tr class="sem"><td colspan="${cols}">${esc(sem)}</td></tr>` +
      ls.map((l) => `<tr><td class="sn">${++n}</td><td>${esc(levelOf(l))}</td><td>${esc(modeOf(l))}</td><td>${esc(indigeneOf(l))}</td><td>${esc(itemOf(l))}${l.status && l.status !== "ACTIVE" ? ` <small>(${esc(statusOf(l))})</small>` : ""}</td>` +
        `${withGroup ? `<td>${esc(l.fee_group_name ?? "")}</td>` : ""}<td class="n">${naira(l.amount)}</td></tr>`).join("")).join("");
    const title = g.programme ? `${esc(g.faculty)} <small>· ${esc(g.programme)}</small>` : esc(g.faculty);
    return `<div class="fs-grp">${title} <small>· ${g.lines.length} line${g.lines.length === 1 ? "" : "s"}</small></div>` +
      `<table class="fs"><thead><tr><th class="sn">S/N</th><th>Level</th><th>Entry mode</th><th>Indigeneship</th><th>Item</th>${withGroup ? "<th>Fee group</th>" : ""}<th class="n">Amount (₦)</th></tr></thead>` +
      `<tbody>${body}</tbody></table>`;
  });
  return css + (sections.length ? sections.join("") : `<p>No fee line matches these filters.</p>`);
}
