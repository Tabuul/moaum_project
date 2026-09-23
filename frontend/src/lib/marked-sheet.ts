/** The marked score sheet as the lecturer may take it away: every candidate with the two marks, the
 *  total the register computed (the grace mark included), the grade and the point, and at the end a
 *  summary of performance — how many took each grade, how many passed and failed, the mean. Built on
 *  the server from the roll as the register holds it, for reference; the record stays the register. */
import { A4, Page, pdf } from "@/lib/pdf-write";
import { crestImage } from "@/lib/pdf-crest";
import type { RollRow, SheetListed } from "@/lib/results";

export interface MarkedSheet {
  sheet: SheetListed;
  /** the programme most of the roll belongs to */
  programme: string;
  roll: RollRow[];
}

export const MARKED_HEADERS = ["S/N", "Matriculation number", "Name", "Programme", "Level", "CA", "Exam", "Total", "Grade", "Points", "Outcome"];

const outcomeWord = (o: string | null) => (o == null ? "Not entered" : o === "GRADED" ? "Graded" : o.charAt(0) + o.slice(1).toLowerCase());

/** the roll as rows for a table, in the order the register gives it (matriculation number) */
export function markedRows(roll: RollRow[]): (string | number | null)[][] {
  return roll.map((r, i) => [
    i + 1, r.number, `${r.surname}, ${r.otherNames}`, r.programmeName, r.level,
    r.ca ?? null, r.exam ?? null,
    r.outcome === "GRADED" ? r.total ?? null : null,
    r.outcome === "GRADED" ? r.grade ?? null : null,
    r.outcome === "GRADED" && r.points != null ? Number(r.points) : null,
    outcomeWord(r.outcome),
  ]);
}

export interface Performance {
  candidates: number;
  graded: number;
  passed: number;
  failed: number;
  notEntered: number;
  /** each grade the scheme gave, in order, with its count and share of the graded */
  grades: { grade: string; count: number; share: number }[];
  /** outcomes other than a grade — absent, withheld, incomplete, malpractice, exempted — with counts */
  outcomes: { outcome: string; count: number }[];
  mean: number | null;
  highest: number | null;
  lowest: number | null;
}

/** the summary of performance: grades in the scheme's order, pass and fail by the point (a point of
 *  zero is a fail), the other outcomes by name, and the spread of totals */
export function performance(roll: RollRow[]): Performance {
  const graded = roll.filter((r) => r.outcome === "GRADED" && r.total != null);
  const byGrade = new Map<string, number>();
  for (const r of graded) byGrade.set(r.grade ?? "?", (byGrade.get(r.grade ?? "?") ?? 0) + 1);
  const order = ["A", "B", "C", "D", "E", "F"];
  const seen = [...byGrade.keys()];
  const gradesInOrder = [...order.filter((g) => seen.includes(g)), ...seen.filter((g) => !order.includes(g)).sort()];
  const grades = gradesInOrder.map((g) => ({ grade: g, count: byGrade.get(g) ?? 0, share: graded.length ? Math.round((1000 * (byGrade.get(g) ?? 0)) / graded.length) / 10 : 0 }));
  const passed = graded.filter((r) => Number(r.points ?? 0) > 0).length;
  const byOutcome = new Map<string, number>();
  for (const r of roll) if (r.outcome && r.outcome !== "GRADED") byOutcome.set(r.outcome, (byOutcome.get(r.outcome) ?? 0) + 1);
  const outcomes = [...byOutcome.entries()].sort().map(([o, count]) => ({ outcome: outcomeWord(o), count }));
  const totals = graded.map((r) => r.total as number);
  return {
    candidates: roll.length,
    graded: graded.length,
    passed,
    failed: graded.length - passed,
    notEntered: roll.filter((r) => r.outcome == null).length,
    grades,
    outcomes,
    mean: totals.length ? Math.round((10 * totals.reduce((a, b) => a + b, 0)) / totals.length) / 10 : null,
    highest: totals.length ? Math.max(...totals) : null,
    lowest: totals.length ? Math.min(...totals) : null,
  };
}

/** the summary as table rows to sit under the roll in a workbook */
export function performanceRows(p: Performance): (string | number | null)[][] {
  const rows: (string | number | null)[][] = [
    [],
    ["Performance summary"],
    ["Grade", "Candidates", "Share of graded"],
    ...p.grades.map((g) => [g.grade, g.count, `${g.share}%`]),
    [],
    ["Candidates on the roll", p.candidates],
    ["Graded", p.graded],
    ["Passed (a point above zero)", p.passed, p.graded ? `${Math.round((1000 * p.passed) / p.graded) / 10}%` : ""],
    ["Failed (no point)", p.failed, p.graded ? `${Math.round((1000 * p.failed) / p.graded) / 10}%` : ""],
    ...p.outcomes.map((o) => [o.outcome, o.count]),
  ];
  if (p.notEntered) rows.push(["Not yet entered", p.notEntered]);
  if (p.mean != null) rows.push([], ["Mean total", p.mean], ["Highest total", p.highest], ["Lowest total", p.lowest]);
  return rows;
}

/* ── the PDF ── */
const W = A4.h, H = A4.w;           // landscape
const L = 36, R = 36, TOP = 36, BOTTOM = 40;
const INK: [number, number, number] = [0.09, 0.15, 0.23];
const MUTED: [number, number, number] = [0.42, 0.47, 0.53];
const isNum = (v: unknown) => typeof v === "number" || (typeof v === "string" && /^-?[\d,]+(\.\d+)?%?$/.test(v.trim()) && v.trim() !== "");
const fmt = (v: string | number | null) => (v == null ? "—" : typeof v === "number" ? v.toLocaleString("en-NG") : String(v));
const day = (d: Date) => d.toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" });

function widths(headers: string[], rows: (string | number | null)[][], avail: number, size: number): number[] {
  const cw = size * 0.52;
  const want = headers.map((h, i) => {
    let m = h.length;
    for (const r of rows.slice(0, 400)) m = Math.max(m, Math.min(48, fmt(r[i] ?? null).length));
    return Math.max(6, m) * cw + 10;
  });
  const sum = want.reduce((a, b) => a + b, 0);
  const k = sum > avail ? avail / sum : 1;
  return want.map((w) => w * k);
}
function clip(s: string, width: number, size: number): string {
  const max = Math.max(3, Math.floor((width - 6) / (size * 0.52)));
  return s.length <= max ? s : s.slice(0, max - 1) + "…";
}

export function markedSheetPdf(m: MarkedSheet, semester: string): Uint8Array {
  const s = m.sheet;
  const headers = MARKED_HEADERS;
  const rows = markedRows(m.roll);
  const perf = performance(m.roll);
  const size = 8;
  const rowH = size * 1.9;
  const cols = widths(headers, rows, W - L - R, size);
  const numeric = headers.map((_, i) => rows.length > 0 && rows.every((r) => r[i] == null || r[i] === "" || isNum(r[i])) && rows.some((r) => r[i] != null && r[i] !== ""));
  const crest = crestImage();
  const pages: Page[] = [];
  const generated = day(new Date());
  const caMax = typeof s.caMax === "number" ? s.caMax : 40;
  const sub = `${s.deptName} · ${m.programme || "Programme"} · ${s.units} unit${s.units === 1 ? "" : "s"} · ${s.session} ${semester} semester · CA out of ${caMax}, examination out of ${100 - caMax}`;
  const lecturer = `Lecturer: ${s.lecturer ?? "not allocated"}`;

  // the summary block's height, to know whether it fits under the last rows or wants its own page
  const summaryLines = 3 + perf.grades.length + 1 + 4 + perf.outcomes.length + (perf.notEntered ? 1 : 0) + (perf.mean != null ? 1 : 0);
  const summaryH = 22 + summaryLines * (rowH - 1);

  let idx = 0;
  let pageNo = 0;
  let summaryDrawn = false;
  const startPage = (): { p: Page; y: number } => {
    pageNo++;
    const p = new Page();
    p.size = { w: W, h: H };
    let y = H - TOP;
    if (crest) p.jpeg(L, y - 40, 40, 40, crest);
    const tx = crest ? L + 50 : L;
    p.text(tx, y - 14, "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI", 11, true, INK);
    p.text(tx, y - 27, "Makurdi, Benue State · Unified University Portal", 8, false, MUTED);
    p.text(W - R - 200, y - 14, `Marked score sheet · ${s.courseCode}`, 8, true, INK);
    p.text(W - R - 200, y - 27, `Page ${pageNo}`, 8, false, MUTED);
    y -= 48;
    p.rule(L, y, W - R, y, 1, 0.2);
    y -= 18;
    p.text(L, y, `${s.courseCode} — ${s.courseTitle}`, 14, true, INK);
    y -= 14;
    p.text(L, y, sub, 8.5, false, MUTED);
    y -= 11;
    p.text(L, y, `${lecturer} · sheet at ${s.stage.toLowerCase().replace(/_/g, " ")} · ${perf.graded} of ${perf.candidates} graded`, 8.5, false, MUTED);
    y -= 14;
    // the footer, the same on every page
    const fy = BOTTOM - 6;
    p.rule(L, fy + 14, W - R, fy + 14, 0.6, 0.6);
    p.text(L, fy, `Generated ${generated} from the register. For reference: the total carries the University's grace mark where it applies; the grade and the point follow from the scheme in force. The record is the register, not this print.`, 6.8, false, MUTED);
    return { p, y };
  };
  const tableHeader = (p: Page, y: number): number => {
    p.fill(L, y - rowH + 4, W - L - R, rowH, 0.93);
    let x = L;
    headers.forEach((h, i) => {
      const t = clip(h, cols[i], size);
      if (numeric[i]) p.text(x + cols[i] - 3 - t.length * size * 0.52, y - rowH + 4 + size * 0.55, t, size, true, INK);
      else p.text(x + 3, y - rowH + 4 + size * 0.55, t, size, true, INK);
      x += cols[i];
    });
    return y - rowH;
  };
  const drawSummary = (p: Page, y0: number) => {
    let y = y0 - 8;
    p.text(L, y, "Performance summary", 11, true, INK);
    y -= 14;
    const c1 = 90, c2 = 80, c3 = 90;
    const row = (a: string, b: string, c: string, bold = false, shade?: number) => {
      if (shade != null) p.fill(L, y - rowH + 4, c1 + c2 + c3, rowH, shade);
      p.text(L + 3, y - rowH + 4 + size * 0.55, a, size, bold, INK);
      p.text(L + c1 + c2 - 3 - b.length * size * 0.52, y - rowH + 4 + size * 0.55, b, size, bold, INK);
      p.text(L + c1 + c2 + c3 - 3 - c.length * size * 0.52, y - rowH + 4 + size * 0.55, c, size, bold, INK);
      p.rule(L, y - rowH + 4, L + c1 + c2 + c3, y - rowH + 4, 0.3, 0.85);
      y -= rowH - 1;
    };
    row("Grade", "Candidates", "Share", true, 0.93);
    for (const g of perf.grades) row(g.grade, String(g.count), `${g.share}%`);
    y -= 6;
    row("Candidates on the roll", String(perf.candidates), "", true, 0.93);
    row("Graded", String(perf.graded), "");
    row("Passed (a point above zero)", String(perf.passed), perf.graded ? `${Math.round((1000 * perf.passed) / perf.graded) / 10}%` : "");
    row("Failed (no point)", String(perf.failed), perf.graded ? `${Math.round((1000 * perf.failed) / perf.graded) / 10}%` : "");
    for (const o of perf.outcomes) row(o.outcome, String(o.count), "");
    if (perf.notEntered) row("Not yet entered", String(perf.notEntered), "");
    if (perf.mean != null) row("Mean · highest · lowest total", `${perf.mean}`, `${perf.highest} · ${perf.lowest}`);
  };

  do {
    const { p, y: y0 } = startPage();
    let y = tableHeader(p, y0);
    while (idx < rows.length && y - rowH > BOTTOM + 14) {
      const r = rows[idx];
      if (idx % 2 === 1) p.fill(L, y - rowH + 4, W - L - R, rowH, 0.975);
      let x = L;
      headers.forEach((_, i) => {
        const t = clip(fmt(r[i] ?? null), cols[i], size);
        if (numeric[i]) p.text(x + cols[i] - 3 - t.length * size * 0.52, y - rowH + 4 + size * 0.55, t, size, false, INK);
        else p.text(x + 3, y - rowH + 4 + size * 0.55, t, size, false, INK);
        x += cols[i];
      });
      p.rule(L, y - rowH + 4, W - R, y - rowH + 4, 0.3, 0.85);
      y -= rowH;
      idx++;
    }
    if (rows.length === 0) { p.text(L + 3, y - 12, "Nobody is registered and approved for this course, so the sheet has no rows.", size, false, MUTED); y -= 16; }
    if (idx >= rows.length && y - summaryH > BOTTOM + 14) { drawSummary(p, y); summaryDrawn = true; }
    pages.push(p);
  } while (idx < rows.length);
  if (!summaryDrawn) {
    const { p, y } = startPage();
    drawSummary(p, y);
    pages.push(p);
  }
  return pdf(pages, `${s.courseCode} marked score sheet · ${s.session}`);
}
