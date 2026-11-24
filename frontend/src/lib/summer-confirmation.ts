import { PdfDocument, CHROME, MUTED, fit } from "./document/pdf.ts";
import { formatDocDate, formatDocDateTime, type Institution } from "./document/institution.ts";
import { styledLines, textWidth } from "./pdf-write.ts";
import {
  VERIFICATION_WORD, categoryWord, confirmationRowWord, confirmationState, confirmationStatusWord, confirmationTitle, feeFormula, failedInWord, naira, num,
  printVerificationWord, type SummerConfirmation,
} from "./summer.ts";

/** V779: the Summer Semester registration confirmation (and, until the registration stands, the selection summary: payment outstanding,
 *  or a course paid and the registration pending) on the University's document writer. It prints what the server gave
 *  (registration.summer_confirmation) and works no sum of its own beyond writing the server's total out as a formula. A course the
 *  Academic Office found not outstanding or rejected is struck out with its reason; a pending course reads "Pending verification" and
 *  is never called a carry-over. The QR is printed only once the registration stands (status REGISTERED): the public check answers
 *  genuine only for an approved registration, so a summary, paid or not, carries none. */

/** text as the document writer sets it: the naira and the dashes written in the characters its fonts have */
export function ascii(s: unknown): string {
  return String(s ?? "")
    .replace(/₦/g, "NGN ").replace(/[–—]/g, "-").replace(/×/g, "x").replace(/[’‘]/g, "'").replace(/[“”]/g, '"').replace(/\s*·\s*/g, " - ")
    .replace(/[^\x20-\x7E]/g, " ").replace(/\s+/g, " ").trim();
}
const money = (m: unknown): string => ascii(naira(m as number | string | null | undefined));

const COLS: { h: string; w: number; right?: boolean }[] = [
  { h: "S/N", w: 22 }, { h: "CODE", w: 50 }, { h: "COURSE TITLE", w: 131 }, { h: "UNITS", w: 28, right: true }, { h: "OWED IN", w: 62 },
  { h: "CATEGORY", w: 62 }, { h: "REGISTRATION", w: 66 }, { h: "VERIFICATION", w: 86 },
];

export function summerConfirmationPdf(c: SummerConfirmation, inst: Institution, qr: { matrix: { size: number; dark: boolean[] }; caption: string } | null): PdfDocument {
  const state = confirmationState(c);
  const title = confirmationTitle(state);
  const doc = new PdfDocument("FORM", {
    title, subtitle: `${c.session} academic session - Summer Semester`, unit: "Academic Office",
    meta: [["Session", c.session], ["Generated", formatDocDateTime(c.generatedAt, inst)]],
  }, inst);
  doc.space(6);
  doc.heading("Student");
  doc.keyValues([
    ["Name", ascii(c.student.name)], ["Matriculation number", ascii(c.student.number ?? "")], ["Programme", ascii(c.student.programme ?? "")],
    ["Department", ascii(c.student.department ?? "")], ["Faculty", ascii(c.student.faculty ?? "")],
    ["Level and category", `${c.student.level ? `${c.student.level} Level` : "-"} - ${ascii(categoryWord(c.student.category))}`],
  ]);
  doc.space(4);
  doc.heading("Summer Semester");
  const p = c.period;
  doc.keyValues([
    ["Registration", p.registration_opens ? `${formatDocDate(p.registration_opens, inst)} to ${formatDocDate(p.registration_closes, inst)}` : "Not dated"],
    ["Examinations", p.exams_from ? `${formatDocDate(p.exams_from, inst)} to ${formatDocDate(p.exams_to, inst)}` : "Not yet dated"],
    ["Results expected", p.results_due ? formatDocDate(p.results_due, inst) : "-"],
    ["Status", confirmationStatusWord(c)],
  ]);

  doc.space(4);
  doc.heading("Courses");
  const xs: number[] = [];
  let at = doc.L;
  for (const col of COLS) { xs.push(at); at += col.w; }
  const header = () => {
    doc.ensure(40);
    const y = doc.y;
    doc.page.fillRgb(doc.L, y - 12, doc.width, 16, CHROME);
    COLS.forEach((col, i) => doc.page.text(col.right ? xs[i] + col.w - 4 - col.h.length * 3.6 : xs[i] + 3, y - 8, col.h, 6.8, true, [1, 1, 1]));
    doc.y = y - 18;
  };
  header();
  c.rows.forEach((r, i) => {
    const decided = r.verification === "NOT_OUTSTANDING" || r.verification === "REJECTED";
    const notes: string[] = [];
    if (decided && r.decision_reason) notes.push(`Reason: ${ascii(r.decision_reason)}`);
    if (!decided && r.clarification_note) notes.push(`Question from the Academic Office: ${ascii(r.clarification_note)}`);
    const noteLines = notes.flatMap((n) => styledLines(n, COLS[2].w + COLS[3].w + COLS[4].w + COLS[5].w - 8, 6.8));
    // the words wrap inside their column (three lines at most); none is cut
    const wrap = (col: number, text: string) => styledLines(text, COLS[col].w - 6, 7.2).slice(0, 3);
    const owed = failedInWord({ original_session: r.original_session, original_semester: r.original_semester, basis: "STUDENT_SELECTED" });
    const cells: { col: number; lines: string[]; bold?: boolean }[] = [
      { col: 0, lines: [String(i + 1)] }, { col: 1, lines: [ascii(r.course_code)], bold: true }, { col: 2, lines: wrap(2, ascii(r.title ?? "")) },
      { col: 3, lines: [r.units == null ? "-" : String(r.units)] }, { col: 4, lines: wrap(4, ascii(owed)) }, { col: 5, lines: wrap(5, ascii(r.category_label ?? "")) },
      { col: 6, lines: wrap(6, ascii(confirmationRowWord(state, r.registration_status))) }, { col: 7, lines: wrap(7, ascii(printVerificationWord(r.verification))), bold: true },
    ];
    const rows = Math.max(1, ...cells.map((x) => x.lines.length));
    const h = 5 + rows * 8.5 + noteLines.length * 8;
    if (doc.y - h < doc.bottom) { doc.newPage(); header(); }
    const y = doc.y;
    const ink: [number, number, number] = decided ? [0.45, 0.45, 0.45] : [0.08, 0.14, 0.2];
    if (i % 2 === 1) doc.page.fill(doc.L, y - h + 3, doc.width, h, 0.965);
    const base = y - 8;
    for (const x of cells) {
      x.lines.forEach((line, k) => {
        const t = x.col === 1 || x.col === 0 || x.col === 3 ? fit(line, COLS[x.col].w - 6, 7.2) : line;
        doc.page.text(COLS[x.col].right ? xs[x.col] + COLS[x.col].w - 4 - t.length * 3.6 : xs[x.col] + 3, base - k * 8.5, t, 7.2, !!x.bold, ink);
      });
    }
    // a decided course is struck out across its code, title, units and where it was owed
    if (decided) doc.page.rule(xs[1] + 2, base + 2.6, xs[5] - 4, base + 2.6, 0.7, 0.35);
    noteLines.forEach((line, k) => doc.page.text(xs[2] + 3, base - rows * 8.5 - k * 8, line, 6.8, false, [0.3, 0.3, 0.3]));
    doc.page.rule(doc.L, y - h + 3, doc.R, y - h + 3, 0.3, 0.85);
    doc.y = y - h;
  });
  if (c.rows.length === 0) { doc.page.text(doc.L + 3, doc.y - 8, "No course is selected.", 8, false, MUTED); doc.y -= 16; }
  doc.y -= 12;
  // the four states, each said once in full beside the short word the table uses
  doc.ensure(44);
  const legend = (Object.keys(VERIFICATION_WORD) as (keyof typeof VERIFICATION_WORD)[]).map((k) => `${ascii(printVerificationWord(k))}: ${ascii(VERIFICATION_WORD[k])}`);
  legend.forEach((line, k) => doc.page.text(doc.L, doc.y - k * 8, line, 6.8, false, MUTED));
  doc.y -= legend.length * 8 + 6;

  doc.space(4);
  doc.heading("Fees");
  const t = c.totals;
  const live = c.rows.filter((r) => r.registration_status !== "TAKEN_OFF").length;
  const courses = num(t.courses ?? live);
  doc.keyValues([
    ["Courses", String(courses)], ["Units", String(t.units)], ["Units registered", String(t.unitsRegistered)], ["Programme fee", money(t.programmeFee)],
    ["Course fees", money(t.courseFees)], ["Total charged", money(t.total)], ["Paid", money(t.paid)], ["Owed", money(t.due)],
  ], 4);
  if (courses > 0) {
    doc.paragraph(`Worked out as ${ascii(feeFormula({ programme: t.programmeFee, perCourse: num(t.courseFees) / courses, courses, total: t.total }))}.`, 8.5);
  }
  if (c.payments.length) {
    doc.heading("Payments");
    doc.table(["Reference", "Amount", "Receipt", "Confirmed"], c.payments.map((x) => [ascii(x.reference), money(x.amount), ascii(x.receipt_no ?? ""), x.confirmed_at ? formatDocDateTime(x.confirmed_at, inst) : "Awaiting payment"]), { serial: true });
  }
  doc.space(2);
  const notice = ascii(c.notice);
  if (c.status === "REGISTERED" && qr) {
    // the QR sits to the right of the notice, so a short list still fits one page; it opens the public check of the semester-3 registration
    const side = 62;
    doc.ensure(side + 24);
    const top = doc.y;
    const qx = doc.R - side;
    const cell = side / qr.matrix.size;
    for (let r = 0; r < qr.matrix.size; r++) for (let k = 0; k < qr.matrix.size; k++) if (qr.matrix.dark[r * qr.matrix.size + k]) doc.page.fill(qx + k * cell, top - (r + 1) * cell, cell, cell, 0);
    doc.page.text(qx, top - side - 10, "SCAN TO VERIFY", 7, true, MUTED);
    const caption = ascii(qr.caption);
    doc.page.text(Math.max(doc.L, doc.R - textWidth(caption, 6.5)), top - side - 20, caption, 6.5, false, MUTED);
    const after = doc.page.paragraph(doc.L, top - 8, notice, doc.width - side - 24, 8.5);
    doc.y = Math.min(after, top - side - 24);
  } else {
    doc.paragraph(notice, 8.5);
  }
  return doc;
}
