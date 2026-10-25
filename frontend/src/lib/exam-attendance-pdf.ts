/** V652: the student examination attendance sheet as a PDF, for the examination hall — landscape, the University's letterhead and
 *  the sheet's reference at the top, the course and the paper's facts, every registered student listed with a large signature
 *  column, the table header repeated on every page, then the MANUAL / LATE REGISTRATION ATTENDANCE rows left blank for handwriting
 *  and the invigilator's and examinations officer's signature lines; Page X of Y counted for each sheet. Several sheets print as one
 *  document, each its own numbering. An earlier version prints as superseded. */
import { A4, Page, pdf, textWidth } from "./pdf-write.ts";
import { drawContinuationHeader, drawFooter, drawHeader, INK, MUTED, type DocumentMeta } from "./document/pdf.ts";
import { profileOf, type DocumentProfile } from "./document/profiles.ts";
import { currentInstitution } from "./document/institution-cache.ts";
import type { Institution } from "./document/institution.ts";
import { ELIGIBILITY_WORD, clock, examDay, scopeWords, type Sheet } from "./exam-attendance.ts";

const W = A4.h, H = A4.w;   // landscape
const L = 36, R = W - 36;
const BOTTOM = 60;          // the footer's rule sits at 46
const RED: [number, number, number] = [0.62, 0.1, 0.1];

export const ATTENDANCE_PROFILE: DocumentProfile = {
  ...profileOf("BROADSHEET"), title: "STUDENT EXAMINATION ATTENDANCE SHEET", confidentiality: "OFFICIAL USE ONLY",
};

/** the list's columns: header, width (points); together the page's width between the margins (770) */
export const LIST_COLUMNS: [string, number][] = [
  ["S/N", 30], ["MATRICULATION NUMBER", 112], ["STUDENT NAME", 176], ["PROGRAMME", 128], ["LEVEL", 42], ["CARD / PERMIT", 58],
  ["SIGNATURE", 112], ["ATTENDANCE STATUS", 58], ["INVIGILATOR REMARKS", 54],
];
export const MANUAL_COLUMNS: [string, number][] = [
  ["S/N", 30], ["NAME WRITTEN BY STUDENT", 186], ["MATRIC / JAMB NO.", 110], ["PROGRAMME", 110], ["LEVEL", 40], ["SIGNATURE", 106],
  ["REASON / REMARK", 108], ["VERIFIED", 80],
];
const LIST_ROW = 19, MANUAL_ROW = 26, HEAD_ROW = 20;

const clean = (s: unknown) => String(s ?? "").replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim();

/** text cut to what fits a width at a size, with an ellipsis */
function clip(s: string, width: number, size: number, bold = false): string {
  let t = clean(s);
  if (textWidth(t, size, bold) <= width) return t;
  while (t.length > 1 && textWidth(t + "…", size, bold) > width) t = t.slice(0, -1);
  return t + "…";
}

/** a column heading on one line, or two when the column is narrow — never cut */
function headLines(h: string, width: number): string[] {
  if (textWidth(h, 7, true) <= width) return [h];
  const words = h.split(" ");
  let a = words[0];
  let i = 1;
  while (i < words.length && textWidth(`${a} ${words[i]}`, 7, true) <= width) a = `${a} ${words[i++]}`;
  const b = words.slice(i).join(" ");
  return b ? [a, clip(b, width, 7, true)] : [clip(a, width, 7, true)];
}

const semester = (n: number) => (n === 2 ? "Second" : n === 3 ? "Third" : "First");

function grid(p: Page, y: number, cols: [string, number][], h: number, grey = 0.55): void {
  let x = L;
  p.box(L, y - h, R - L, h, grey);
  for (let i = 0; i < cols.length - 1; i++) {
    x += cols[i][1];
    p.rule(x, y, x, y - h, 0.5, grey);
  }
}

function tableHead(p: Page, y: number, cols: [string, number][]): number {
  p.fill(L, y - HEAD_ROW, R - L, HEAD_ROW, 0.9);
  grid(p, y, cols, HEAD_ROW, 0.4);
  let x = L;
  for (const [h, w] of cols) {
    const lines = headLines(h, w - 8);
    if (lines.length === 1) p.text(x + 4, y - 13, lines[0], 7, true, INK);
    else lines.slice(0, 2).forEach((t, i) => p.text(x + 4, y - 8.5 - i * 8, t, 7, true, INK));
    x += w;
  }
  return y - HEAD_ROW;
}

/** the reference band at the top of every page: the reference, the version, superseded when a later version stands */
function referenceBand(p: Page, y: number, s: Sheet): number {
  p.fill(L, y - 22, R - L, 22, 0.95);
  p.box(L, y - 22, R - L, 22, 0.5);
  p.text(L + 8, y - 14.5, "ATTENDANCE SHEET REFERENCE", 7, true, MUTED);
  p.text(L + 132, y - 15, clean(s.reference), 11.5, true, INK);
  const superseded = s.latest_reference && s.latest_reference !== s.reference;
  const right = superseded ? `SUPERSEDED BY ${clean(s.latest_reference)}` : `Version ${s.version}${s.version > 1 ? " (latest)" : ""} · issued ${new Date(s.generated_at).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" })}`;
  p.text(R - 8 - textWidth(right, 8, true), y - 14.5, right, 8, true, superseded ? RED : MUTED);
  return y - 30;
}

/** the course and the paper, three facts a line */
function facts(p: Page, y: number, s: Sheet): number {
  const o = s.offering;
  const time = s.starts_at ? `${clock(s.starts_at)}${s.ends_at ? ` – ${clock(s.ends_at)}` : ""}` : "";
  const items: [string, string][] = [
    ["Faculty", s.faculty ?? (s.scope_fac ? s.scope_fac : "All faculties")],
    ["Department", s.department ?? (s.scope_dept ? s.scope_dept : "All departments")],
    ["Programme", s.programme ?? (s.scope_prog ? s.scope_prog : "All programmes")],
    ["Course code", o.shown_code],
    ["Course title", o.course_title],
    ["Course unit", `${o.units} unit${o.units === 1 ? "" : "s"}`],
    ["Level", o.level ? `${o.level} Level` : ""],
    ["Session", o.session],
    ["Semester", `${semester(o.semester)} Semester`],
    ["Examination date", examDay(s.exam_on)],
    ["Examination time", time],
    ["Examination venue", s.venue ?? ""],
    ["Examiner / invigilator", ""],
    ["Students listed", `${s.students}`],
    ["Course department", o.course_department ?? o.course_dept ?? ""],
  ];
  const colW = (R - L) / 3;
  for (let i = 0; i < items.length; i++) {
    const [k, v] = items[i];
    const col = i % 3, x = L + col * colW;
    p.text(x, y, k.toUpperCase(), 6.5, false, MUTED);
    if (v) p.text(x + 92, y, clip(v, colW - 100, 9, true), 9, true, INK);
    else p.rule(x + 92, y - 2, x + colW - 12, y - 2, 0.5, 0.45);   // to be written in at the hall
    if (col === 2) y -= 15;
  }
  return y - 6;
}

/** one sheet's pages: the list, the manual rows, the signatures — Page X of Y for this sheet alone */
export function attendanceSheetPages(s: Sheet, opts: { inst?: Institution; generatedBy?: string | null } = {}): Page[] {
  const inst = opts.inst ?? currentInstitution();
  const meta: DocumentMeta = {
    title: ATTENDANCE_PROFILE.title,
    // plain separators: the letterhead draws ASCII only
    subtitle: `${clean(s.offering.shown_code)} - ${clean(s.offering.course_title)} | ${s.offering.session} | ${semester(s.offering.semester)} Semester | ${scopeWords(s)}`,
    reference: s.reference,
    generatedBy: opts.generatedBy ?? s.generated_by_name ?? null,
    watermark: s.latest_reference && s.latest_reference !== s.reference ? "SUPERSEDED" : null,
  };
  const pages: Page[] = [];
  let p = new Page();
  let y = 0;
  const open = (first: boolean) => {
    p = new Page();
    p.size = { w: W, h: H };
    pages.push(p);
    // an earlier version's mark goes under the content, so every name on it stays legible
    if (meta.watermark) p.bigDiagonalWatermark(meta.watermark, 54, 0.9);
    y = first ? drawHeader(p, inst, ATTENDANCE_PROFILE, { ...meta, reference: null }) : drawContinuationHeader(p, inst, ATTENDANCE_PROFILE, meta, pages.length);
    y = referenceBand(p, y + (first ? 4 : 6), s);
  };
  open(true);
  y = facts(p, y - 4, s);

  // ── the list ──
  y = tableHead(p, y, LIST_COLUMNS);
  if (!s.list.length) {
    grid(p, y, [["", R - L]], LIST_ROW);
    p.text(L + 8, y - 13, "No student is registered for this course in this scope. Students permitted to sit write their names in the section below.", 8.5, false, MUTED);
    y -= LIST_ROW;
  }
  s.list.forEach((st, i) => {
    if (y - LIST_ROW < BOTTOM) {
      open(false);
      y = tableHead(p, y, LIST_COLUMNS);
    }
    grid(p, y, LIST_COLUMNS, LIST_ROW);
    const cells = [
      String(i + 1), st.matric ?? st.jamb ?? "", st.name, st.programme, `${st.level ?? ""}${st.carryOver ? " C/O" : ""}`,
      ELIGIBILITY_WORD[st.eligibility] ?? "", "", "", "",
    ];
    let x = L;
    cells.forEach((c, k) => {
      const w = LIST_COLUMNS[k][1];
      const missing = k === 5 && !st.eligible;
      if (c) p.text(x + 4, y - 13, clip(c, w - 8, k === 2 ? 8.5 : 8, k === 2 || missing), k === 2 ? 8.5 : 8, k === 2 || missing, missing ? RED : INK);
      x += w;
    });
    y -= LIST_ROW;
  });

  // ── the manual / late registration rows, left blank for handwriting ──
  if (s.manual_lines > 0) {
    const heading = (cont: boolean) => {
      p.text(L, y - 14, `MANUAL / LATE REGISTRATION ATTENDANCE${cont ? " (continued)" : ""}`, 11, true, INK);
      y -= 18;
      if (!cont) {
        p.text(L, y - 9, "Students whose names are not on the main attendance list but are permitted to sit for the examination may complete this section.", 8, false, INK);
        p.text(L, y - 20, "The invigilator must verify the student's identity and eligibility before allowing attendance to be recorded.", 8, true, INK);
        y -= 26;
      }
      y = tableHead(p, y, MANUAL_COLUMNS);
    };
    y -= 10;
    // the section starts where its heading and its first rows fit together, never a lone row at the foot of a page
    if (y - (18 + 26 + HEAD_ROW + Math.min(3, s.manual_lines) * MANUAL_ROW) < BOTTOM) open(false);
    heading(false);
    for (let i = 0; i < s.manual_lines; i++) {
      if (y - MANUAL_ROW < BOTTOM) {
        open(false);
        heading(true);
      }
      grid(p, y, MANUAL_COLUMNS, MANUAL_ROW);
      p.text(L + 4, y - 16, String(i + 1), 8, false, MUTED);
      y -= MANUAL_ROW;
    }
  }

  // ── the totals and the signatures ──
  const closing = 74;
  if (y - closing < BOTTOM) open(false);
  y -= 14;
  p.text(L, y, `Students listed: ${s.students}   ·   Manual lines: ${s.manual_lines}   ·   Present: ________   ·   Absent: ________   ·   Manual attendance: ________`, 8.5, false, INK);
  if (s.reason) p.text(L, y - 12, clip(`Version ${s.version}: ${s.reason}`, R - L, 7.5), 7.5, false, MUTED);
  y -= 34;
  const half = (R - L) / 2;
  p.text(L, y, "INVIGILATOR SIGNATURE:", 8.5, true, INK); p.rule(L + 118, y - 2, L + half - 20, y - 2, 0.6, 0.3);
  p.text(L + half, y, "DATE:", 8.5, true, INK); p.rule(L + half + 34, y - 2, R, y - 2, 0.6, 0.3);
  y -= 24;
  p.text(L, y, "EXAM OFFICER:", 8.5, true, INK); p.rule(L + 76, y - 2, L + half - 20, y - 2, 0.6, 0.3);
  p.text(L + half, y, "SIGNATURE:", 8.5, true, INK); p.rule(L + half + 58, y - 2, R, y - 2, 0.6, 0.3);

  pages.forEach((pg, i) => drawFooter(pg, inst, ATTENDANCE_PROFILE, meta, i + 1, pages.length));
  return pages;
}

/** several sheets as one document, each with its own Page X of Y */
export function attendanceSheetsPdf(sheets: Sheet[], opts: { inst?: Institution; generatedBy?: string | null } = {}): Uint8Array {
  const pages = sheets.flatMap((s) => attendanceSheetPages(s, opts));
  const title = sheets.length === 1 ? `Attendance sheet ${sheets[0].reference}` : `Attendance sheets (${sheets.length})`;
  return pdf(pages, title);
}
