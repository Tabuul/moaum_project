import "server-only";
import { A4, Page, pdf, textWidth } from "@/lib/pdf-write";
import { brandHeader, crestImage } from "@/lib/pdf-crest";
import { currentInstitution } from "./document/institution-cache.ts";
import { qrMatrix } from "@/lib/qr";
import type { CoverLetter, Statement, Template } from "@/lib/documents";

/**
 * The official documents as PDFs (V262), rendered from the signed statement and the template version they were issued
 * under. The certificate follows the University's own certificate: the crest at the top with the number at the top right,
 * the University's name, "This is to certify that", the graduate's name, the Senate wording, the degree with its class,
 * the seal and the date at the bottom left, the signatories at the bottom right — with the QR and the verification
 * reference beside the seal. The transcripts tabulate the record session by session under the grading scale in force.
 */

const clean = (s: string | null | undefined) => (s ?? "").replace(/[^\x20-\x7E]/g, " ").replace(/\s+/g, " ").trim();
const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "");
const num = (n: number | null | undefined, d = 2) => (n === null || n === undefined ? "" : Number(n).toFixed(d));
const INK: [number, number, number] = [0.1, 0.1, 0.12];
const MUTED: [number, number, number] = [0.4, 0.4, 0.42];
const CHROME: [number, number, number] = [0.13, 0.27, 0.45];
const SEAL: [number, number, number] = [0.78, 0.16, 0.16];

function qr(p: Page, x: number, y: number, side: number, text: string) {
  const { size, dark } = qrMatrix(text);
  const cell = side / size;
  for (let r = 0; r < size; r++) for (let c = 0; c < size; c++) if (dark[r * size + c]) p.fill(x + c * cell, y + (size - 1 - r) * cell, cell, cell, 0);
}

function statusStamp(p: Page, status: string) {
  if (status === "REVOKED") p.bigDiagonalWatermark("REVOKED", 60, 0.82);
  else if (status === "REPLACED") p.bigDiagonalWatermark("REPLACED", 52, 0.85);
}

/** the degree certificate, one page, portrait */
export function certificatePdf(s: Statement, t: Template | null, verifyUrl: string, status = "ACTIVE"): Uint8Array {
  const p = new Page();
  const W = A4.w, cx = W / 2;
  const crest = crestImage();
  // a faint crest in the middle, as the paper carries one
  if (crest) p.imageFaint(cx - 110, 300, 220, 220, crest);
  p.box(28, 28, W - 56, A4.h - 56, 0.55);
  p.box(34, 34, W - 68, A4.h - 68, 0.8);
  if (crest) p.jpeg(cx - 42, A4.h - 130, 84, 84, crest);
  p.textStyled(W - 140, A4.h - 60, clean(s.number), 10.5, { font: "F2", colour: MUTED, spacing: 0.5 });
  p.textCenter(cx, A4.h - 168, currentInstitution().name.replace(/,.*$/, "").toUpperCase(), 17, true, INK);
  p.textCenter(cx, A4.h - 186, "MAKURDI, BENUE STATE, NIGERIA", 9.5, false, MUTED);
  p.textStyled(cx - 60, A4.h - 232, "This is to certify that", 15, { font: "F3", colour: INK });
  const name = clean(s.holder).toUpperCase();
  const nameSize = name.length > 34 ? 20 : 24;
  p.textCenter(cx, A4.h - 276, name, nameSize, true, CHROME);
  p.rule(cx - 200, A4.h - 286, cx + 200, A4.h - 286, 0.8, 0.5);
  p.textCenter(cx, A4.h - 304, `Matriculation number ${clean(s.matricNo)}`, 9.5, false, MUTED);
  const lines = ["Having completed an approved course of study", "and passed the prescribed examinations,", "has this day, under the authority of the Senate,", "been awarded the Degree of"];
  let y = A4.h - 344;
  for (const l of lines) { p.textCenter(cx, y, l, 13.5, false, INK); y -= 24; }
  const award = clean(s.award ?? s.programme);
  const cls = clean(s.classOfDegree);
  p.textCenter(cx, y - 16, award, award.length > 44 ? 17 : 20, true, INK);
  y -= 44;
  if (cls && cls !== "Awarded") { p.textCenter(cx, y, `with ${cls}`, 16, true, INK); y -= 26; }
  p.textCenter(cx, y - 6, `${clean(s.programme)} · ${clean(s.department ?? "")}${s.faculty ? ` · ${clean(s.faculty)}` : ""}`, 9.5, false, MUTED);
  y -= 26;
  if (s.graduationSession) p.textCenter(cx, y, `Graduation session ${clean(s.graduationSession)}${s.graduationMinute ? ` · Senate minute ${clean(s.graduationMinute)}` : ""}`, 9.5, false, MUTED);
  // the seal, bottom left, and the date beneath
  const sx = 118, sy = 150;
  for (let i = 0; i < 28; i++) {
    const a = (i / 28) * Math.PI * 2;
    p.fillRgb(sx + Math.cos(a) * 44 - 4, sy + Math.sin(a) * 44 - 4, 8, 8, SEAL);
  }
  p.roundRect(sx - 40, sy - 40, 80, 80, 40, SEAL);
  if (crest) p.jpeg(sx - 26, sy - 26, 52, 52, crest);
  p.text(70, 84, `Date: ${day(s.graduationDate ?? s.issuedOn)}`, 11, true, INK);
  p.text(70, 70, `Issued ${day(s.issuedOn)}${s.version > 1 ? ` · version ${s.version}` : ""}`, 8.5, false, MUTED);
  // the signatories, bottom right
  const sig1 = t?.second_name ?? "The Vice-Chancellor", sig1t = t?.second_title ?? "Vice-Chancellor", sig2 = t?.signatory_name ?? "The Registrar", sig2t = t?.signatory_title ?? "Registrar";
  p.rule(W - 230, 178, W - 70, 178, 0.6, 0.3);
  p.text(W - 230, 166, clean(sig1), 9.5, true, INK);
  p.text(W - 230, 155, clean(sig1t).toUpperCase(), 8, false, MUTED);
  p.rule(W - 230, 112, W - 70, 112, 0.6, 0.3);
  p.text(W - 230, 100, clean(sig2), 9.5, true, INK);
  p.text(W - 230, 89, clean(sig2t).toUpperCase(), 8, false, MUTED);
  // the QR and the reference beside the seal
  qr(p, 200, 108, 74, verifyUrl);
  p.text(284, 168, "Verify this certificate", 8, true, INK);
  p.text(284, 157, "Scan the code, or enter the verification code on the portal", 7, false, MUTED);
  p.text(284, 146, `Verification code`, 7.5, false, MUTED);
  p.text(284, 135, clean((s as unknown as { verificationCode?: string }).verificationCode ?? ""), 8.5, true, INK);
  p.text(284, 122, `Certificate ${clean(s.number)}`, 7.5, false, MUTED);
  p.textCenter(cx, 48, clean(t?.footer ?? "This certificate is verified by the QR code and the verification reference it carries."), 7.5, false, MUTED);
  statusStamp(p, status);
  return pdf([p], `Certificate ${s.number}`);
}

/** a transcript, sessional transcript, mini-transcript or statement: the record tabulated, as many pages as it takes */
export function transcriptPdf(s: Statement, t: Template | null, verifyUrl: string, verificationCode: string, status = "ACTIVE", letter: CoverLetter | null = null): Uint8Array {
  const pages: Page[] = [];
  const L = 48, R = A4.w - 48;
  const title = clean(t?.title ?? (s.kind === "TRANSCRIPT" ? "Official Academic Transcript" : s.kind === "SESSIONAL_TRANSCRIPT" ? "Sessional Transcript" : s.kind === "MINI_TRANSCRIPT" ? "Mini-Transcript" : "Statement of Academic Record"));
  let p = new Page();
  let y = 0;
  const head = (first: boolean) => {
    p = new Page();
    pages.push(p);
    y = brandHeader(p, L, `${title} · ${clean(s.number)}${pages.length > 1 ? ` · page ${pages.length}` : ""}`);
    if (first) {
      p.text(L, y, title.toUpperCase(), 14, true, INK);
      if (t?.subtitle) p.text(L, y - 14, clean(t.subtitle), 9, false, MUTED);
      p.text(R - 190, y, `No. ${clean(s.number)}${s.version > 1 ? ` (v${s.version})` : ""}`, 10, true, INK);
      p.text(R - 190, y - 14, `Issued ${day(s.issuedOn)}`, 8.5, false, MUTED);
      y -= 34;
      const rows: [string, string][] = [
        ["Name", clean(s.holder)], ["Matriculation number", clean(s.matricNo)], ["Programme", clean(s.programme)], ["Department", clean(s.department ?? "—")], ["Faculty", clean(s.faculty ?? "—")],
        ["Entry", `${clean(s.entrySession ?? "")}${s.entryMode ? ` · ${clean(s.entryMode).toLowerCase().replace("_", " ")}` : ""}${s.entryLevel ? ` · ${s.entryLevel} level` : ""}`],
        ["Standing", clean(s.standing ?? "")], ["Award", clean(s.award ?? "")],
      ];
      // V381: a part-time holder's record says so, and through which route — a full-time record is unchanged
      if (s.studyMode && s.studyMode !== "Full-time") rows.push(["Study mode", `${clean(s.studyMode)}${s.durationYears ? ` · ${s.durationYears} years` : ""}`]);
      if (s.route) rows.push(["Route", clean(s.route)]);
      if (s.specialisation) rows.push(["Specialisation", clean(s.specialisation)]);   // V488
      if (s.graduationSession) rows.push(["Graduation", `${clean(s.graduationSession)}${s.graduationMinute ? ` · Senate ${clean(s.graduationMinute)}` : ""}${s.graduationDate ? ` · ${day(s.graduationDate)}` : ""}`]);
      if (s.classOfDegree && s.classOfDegree !== "Awarded") rows.push(["Class of degree", clean(s.classOfDegree)]);
      if (s.scope && s.scope !== "CUMULATIVE") rows.push(["Scope", `${clean(s.session ?? "")}${s.semester ? ` · semester ${s.semester}` : ""}`]);
      const half = Math.ceil(rows.length / 2);
      for (let i = 0; i < rows.length; i++) {
        const col = i < half ? 0 : 1, yy = y - (i % half) * 15, x = L + col * ((R - L) / 2);
        p.text(x, yy, rows[i][0].toUpperCase(), 6.5, false, MUTED);
        p.text(x + 88, yy, rows[i][1].slice(0, 46), 8.5, i === 0);
      }
      y -= half * 15 + 8;
      p.rule(L, y, R, y, 0.8, 0.3);
      y -= 16;
    } else {
      y -= 4;
    }
    statusStamp(p, status);
  };
  head(true);
  const cols = [L, L + 62, R - 176, R - 138, R - 100, R - 62, R - 28];
  const tableHead = () => {
    p.fill(L, y - 4, R - L, 14, 0.92);
    const hs = ["CODE", "COURSE TITLE", "UNITS", "GRADE", "POINTS", "QUALITY", ""];
    for (let i = 0; i < 6; i++) p.text(cols[i] + 2, y, hs[i], 7, true, INK);
    y -= 16;
  };
  const need = (h: number) => { if (y - h < 70) { head(false); tableHead(); } };
  for (const ses of s.sessions ?? []) {
    need(40);
    p.text(L, y, `${clean(ses.session)} SESSION`, 9.5, true, CHROME);
    y -= 14;
    for (const sem of ses.semesters ?? []) {
      need(44);
      p.text(L, y, sem.semester === 1 ? "First semester" : sem.semester === 2 ? "Second semester" : `Semester ${sem.semester}`, 8.5, true, INK);
      y -= 12;
      tableHead();
      for (const c of sem.courses ?? []) {
        need(12);
        p.text(cols[0] + 2, y, clean(c.code), 8, true);
        p.text(cols[1] + 2, y, clean(c.title).slice(0, 62), 8);
        p.text(cols[2] + 14, y, String(c.units ?? ""), 8);
        p.text(cols[3] + 14, y, clean(c.grade ?? (c.outcome ?? "")), 8, true);
        p.text(cols[4] + 12, y, num(c.points, 2), 8);
        p.text(cols[5] + 10, y, num(c.quality, 2), 8);
        y -= 11.5;
      }
      need(16);
      p.rule(L, y + 4, R, y + 4, 0.4, 0.6);
      const summ = [`Units ${sem.units ?? "—"}`, sem.gpa !== null && sem.gpa !== undefined ? `GPA ${num(sem.gpa)}` : "", sem.cgpa !== null && sem.cgpa !== undefined ? `CGPA ${num(sem.cgpa)}` : "", sem.tcr !== undefined && sem.tcr !== null ? `TCR ${sem.tcr} · TCE ${sem.tce ?? ""} · TWGP ${num(sem.twgp)}` : ""].filter(Boolean).join("    ");
      p.text(R - 6 - summ.length * 3.9, y - 4, summ, 7.5, true, INK);
      y -= 20;
    }
  }
  if (!(s.sessions ?? []).length) { need(20); p.text(L, y, "No published result stands on the record within the scope of this document.", 9, false, MUTED); y -= 20; }
  need(80);
  p.rule(L, y, R, y, 0.8, 0.3);
  y -= 18;
  p.text(L, y, "SUMMARY", 8, true, MUTED);
  y -= 14;
  const summary = [`Cumulative grade point average ${num(s.cgpa)}`, s.classOfDegree && s.classOfDegree !== "Awarded" ? `Class of degree: ${clean(s.classOfDegree)}` : "", `Standing: ${clean(s.standing ?? "")}`].filter(Boolean);
  for (const l of summary) { p.text(L, y, l, 9.5, true, INK); y -= 13; }
  if (s.research) {
    y -= 4;
    p.text(L, y, "RESEARCH", 8, true, MUTED); y -= 13;
    p.text(L, y, clean(`${s.research.kind ?? ""}: ${s.research.topic ?? ""}`).slice(0, 110), 9, false, INK); y -= 12;
    if (s.research.vivaGrade || s.research.awardedAt) { p.text(L, y, clean(`${s.research.vivaGrade ? `Viva grade ${s.research.vivaGrade}` : ""}${s.research.awardedAt ? ` · awarded ${day(s.research.awardedAt)}` : ""}`), 8.5, false, MUTED); y -= 12; }
  }
  if (s.gradingScale?.length) {
    y -= 4;
    p.text(L, y, "GRADING SCALE", 8, true, MUTED); y -= 12;
    p.text(L, y, s.gradingScale.map((g) => `${g.grade} ${g.low}-${g.high} = ${g.points}`).join("   "), 8, false, INK); y -= 12;
  }
  if (s.classificationBands?.length && s.kind === "TRANSCRIPT") {
    p.text(L, y, s.classificationBands.map((b) => `${clean(b.class)} ${num(b.low)}-${num(b.high)}`).join("   ").slice(0, 150), 7.5, false, MUTED); y -= 12;
  }
  if (t?.remarks) { y -= 2; y = p.paragraph(L, y, clean(t.remarks), R - L - 120, 8); }
  // the signatory and the QR on the last page
  need(90);
  const last = pages[pages.length - 1];
  qr(last, R - 84, 58, 72, verifyUrl);
  last.text(R - 84, 50, "Verify", 6.5, false, MUTED);
  last.rule(L, 96, L + 170, 96, 0.6, 0.3);
  last.text(L, 84, clean(t?.signatory_name ?? "The Registrar"), 9, true, INK);
  last.text(L, 73, clean(t?.signatory_title ?? "Registrar").toUpperCase(), 7.5, false, MUTED);
  last.text(L + 200, 84, `Verification code ${clean(verificationCode)}`, 8, true, INK);
  last.text(L + 200, 73, "Scan the code, or enter the verification code on the portal", 7, false, MUTED);
  last.text(L, 48, clean(t?.footer ?? "Not valid without the verification reference."), 7.5, false, MUTED);
  for (const pg of pages) pg.text(L, 36, `${clean(s.holder)} · ${clean(s.matricNo)} · ${clean(s.number)}`, 6.5, false, MUTED);
  return pdf(letter ? [coverLetterPage(letter), ...pages] : pages, `${title} ${s.number}`);
}

/** a date as the University's transcript writes it: 06/06/1994 */
const dmy = (iso: string | null | undefined) => {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso ?? "");
  return m ? `${m[3]}/${m[2]}/${m[1]}` : "";
};
/** "SURNAME, Other Names" as the University writes a name in full, surname last */
const surnameLast = (holder: string) => {
  const i = holder.indexOf(",");
  return clean(i < 0 ? holder : `${holder.slice(i + 1)} ${holder.slice(0, i)}`).toUpperCase();
};
/** the Times faces measured by Helvetica's widths: a little wide, so a label never runs into its value */
const timesWidth = (s: string, size: number) => textWidth(s, size);
/** text cut to fit a width in Helvetica */
const fit = (s: string, size: number, width: number, bold = false) => {
  let t = s;
  while (t.length > 1 && textWidth(t, size, bold) > width) t = t.slice(0, -1);
  return t === s ? s : `${t.slice(0, -1)}.`;
};

/**
 * V668: the full transcript on the University's own template (TRanscript_Template.docx): the University's name, "(Office of the
 * Registrar)", the title and "(For External Use only)", the crest; the holder's particulars in the template's words; one ruled table of
 * COURSE CODE/NO, COURSE TITLE, CREDIT UNIT, LETTER GRADE, GRADE POINT and WEIGHTED GRADE POINT, a box for each semester, every attempt
 * shown; TCR, TCE, TWGP and CGPA under it; the grading system, the degree classification and the abbreviations; and the two signature
 * boxes the template names (the Dean's and the Academic Secretary's, each with its stamp and date). The verification reference and its
 * QR sit under the boxes, as on every document the portal issues.
 */
export function moaumTranscriptPdf(s: Statement, t: Template | null, verifyUrl: string, verificationCode: string, status = "ACTIVE", letter: CoverLetter | null = null): Uint8Array {
  const pages: Page[] = [];
  const W = A4.w, L = 40, R = W - 40, cx = W / 2, BOTTOM = 64;
  const title = clean(t?.title ?? "Academic Transcript").toUpperCase();
  // the table's columns, as the template's: code, title, credit unit, letter grade, grade point, weighted grade point
  const X = [L, L + 50, R - 212, R - 159, R - 106, R - 53, R];
  let p = new Page();
  let y = 0;
  const newPage = () => {
    p = new Page();
    pages.push(p);
    statusStamp(p, status);
    y = A4.h - 44;
    if (pages.length > 1) {
      p.text(L, y, `${surnameLast(s.holder)} · ${clean(s.matricNo)}`, 7.5, false, MUTED);
      p.text(R - textWidth(`${title} · page ${pages.length}`, 7.5), y, `${title} · page ${pages.length}`, 7.5, false, MUTED);
      y -= 16;
    }
  };
  newPage();
  // ── the head, as the template's ──
  const inst = currentInstitution().name.toUpperCase();
  p.textCenterStyled(cx, y, clean(inst), 13.5, { font: "F3" });
  y -= 16;
  p.textCenterStyled(cx, y, "(Office of the Registrar)", 12.5, { font: "F5" });
  y -= 13;
  p.textCenterStyled(cx, y, title, 9.5, { font: "F3" });
  y -= 11;
  if (t?.subtitle) { p.textCenterStyled(cx, y, clean(t.subtitle), 8.5, { font: "F5" }); y -= 6; }
  const crest = crestImage();
  if (crest) {
    const box = 56, ratio = crest.width && crest.height ? crest.width / crest.height : 1;
    const w = ratio >= 1 ? box : box * ratio, h = ratio >= 1 ? box / ratio : box;
    p.jpeg(cx - w / 2, y - h - 2, w, h, crest);
    y -= box + 10;
  } else y -= 8;
  const label = (x: number, yy: number, l: string, v: string, width: number) => {
    p.textStyled(x, yy, l, 8.5, { font: "F4" });
    const lw = timesWidth(l, 8.5) + 5;
    p.textStyled(x + lw, yy, fit(v, 8.5, width - lw, true), 8.5, { font: "F3" });
  };
  const leftAt = s.leftSession ?? "";
  label(L + 40, y, "NAME IN FULL (Surname Last):", surnameLast(s.holder), R - L - 40); y -= 11;
  label(L, y, "NUMBER:", clean(s.matricNo), 190);
  label(L + 200, y, "DATE OF BIRTH:", dmy(s.dateOfBirth), 150);
  label(L + 360, y, "SEX:", clean(s.sex ?? "").toUpperCase(), 120); y -= 11;
  label(L, y, "DATES IN THE UNIVERSITY (ENTER):", clean(s.entrySession ?? ""), 220);
  label(L + 220, y, "(LEFT):", clean(leftAt), 150); y -= 11;
  label(L, y, "FACULTY:", clean(s.faculty ?? "").toUpperCase(), 255);
  label(L + 260, y, "DEPARTMENT:", clean(s.department ?? "").toUpperCase(), R - L - 260); y -= 11;
  label(L, y, "COURSE/SPECIALIZATION:", clean(s.programme).toUpperCase() + (s.specialisation ? ` (${clean(s.specialisation).toUpperCase()})` : ""), R - L); y -= 11;
  const awarded = [clean(s.award ?? ""), s.classOfDegree && s.classOfDegree !== "Awarded" ? clean(s.classOfDegree) : ""].filter(Boolean).join(" - ").toUpperCase();
  label(L, y, "DEGREE/DIPLOMA/CERTIFICATE AWARDED & CLASS:", awarded || "NOT YET AWARDED", R - L); y -= 8;

  // ── the table ──
  const headH = 32;
  const tableHead = () => {
    p.box(L, y - headH, R - L, headH, 0);
    for (let i = 1; i < 6; i++) p.rule(X[i], y, X[i], y - headH, 0.6, 0);
    const heads = [["COURSE", "CODE/NO"], ["COURSE TITLE"], ["CREDIT", "UNIT"], ["LETTER", "GRADE"], ["GRADE", "POINT"], ["WEIGHTED", "GRADE", "POINT"]];
    heads.forEach((h, i) => h.forEach((w, j) => p.text(X[i] + 4, y - 9 - j * 8, w, 6.5, true)));
    y -= headH;
  };
  tableHead();
  const row = 10.5;
  let groupTop = y;
  const closeGroup = () => {
    if (groupTop - y < 1) return;
    p.box(L, y, R - L, groupTop - y, 0);
    for (let i = 1; i < 6; i++) p.rule(X[i], groupTop, X[i], y, 0.6, 0);
    groupTop = y;
  };
  const room = (h: number) => {
    if (y - h >= BOTTOM) return;
    closeGroup();
    newPage();
    tableHead();
    groupTop = y;
  };
  let tcr = 0, tce = 0, twgp = 0;
  const semesters = (s.sessions ?? []).flatMap((ses) => ses.semesters ?? []);
  for (const sem of semesters) {
    for (const c of sem.courses ?? []) {
      room(row);
      const u = Number(c.units ?? 0), pts = c.points === null || c.points === undefined ? null : Number(c.points);
      const q = c.quality === null || c.quality === undefined ? (pts === null ? null : pts * u) : Number(c.quality);
      tcr += u;
      if (pts !== null && pts > 0) tce += u;
      if (q !== null) twgp += q;
      const yy = y - 8;
      p.textStyled(X[0] + 6, yy, fit(clean(c.code), 8, X[1] - X[0] - 8), 8, { font: "F4" });
      p.textStyled(X[1] + 4, yy, fit(clean(c.title), 8, X[2] - X[1] - 8), 8, { font: "F4" });
      p.textCenterStyled((X[2] + X[3]) / 2, yy, String(u || ""), 8, { font: "F4" });
      p.textCenterStyled((X[3] + X[4]) / 2, yy, clean(c.grade ?? c.outcome ?? ""), 8, { font: "F4" });
      p.textCenterStyled((X[4] + X[5]) / 2, yy, pts === null ? "" : String(Math.round(pts * 100) / 100), 8, { font: "F4" });
      p.textCenterStyled((X[5] + X[6]) / 2, yy, q === null ? "" : String(Math.round(q * 100) / 100), 8, { font: "F4" });
      for (let i = 2; i < 6; i++) p.rule(X[i], y - row, X[i + 1], y - row, 0.3, 0.55);
      y -= row;
    }
    closeGroup();
  }
  if (!semesters.length) { room(row * 2); p.text(L + 6, y - 12, "No published result stands on the record.", 8.5, false, MUTED); y -= row * 2; closeGroup(); }
  const cgpa = s.cgpa !== undefined && s.cgpa !== null ? Number(s.cgpa) : tcr ? twgp / tcr : 0;
  room(16);
  p.box(L, y - 14, R - L, 14, 0);
  const totals: [string, string][] = [["TCR:", String(tcr)], ["TCE:", String(tce)], ["TWGP:", String(Math.round(twgp * 100) / 100)], ["CGPA:", cgpa.toFixed(2)]];
  totals.forEach(([k, v], i) => {
    const x = L + 20 + i * ((R - L) / 4);
    p.textStyled(x, y - 10, k, 8.5, { font: "F4" });
    p.textStyled(x + timesWidth(k, 8.5) + 4, y - 10, v, 8.5, { font: "F3" });
  });
  y -= 14;

  // ── the grading system, the degree classification, the abbreviations ──
  const scale = s.gradingScale ?? [];
  const bands = s.classificationBands ?? [];
  const keyRows = Math.max(scale.length, bands.length, 4);
  const keyH = 48 + keyRows * 10;
  const sigH = 108;
  if (y - keyH - sigH - 40 < BOTTOM - 20) { newPage(); }
  const C1 = L + 132, C2 = L + 278;
  p.box(L, y - keyH, R - L, keyH, 0);
  p.rule(C1, y, C1, y - keyH, 0.6, 0);
  p.rule(C2, y, C2, y - keyH, 0.6, 0);
  p.textCenterStyled((L + C1) / 2, y - 11, "GRADING SYSTEM", 8.5, { font: "F3" });
  p.textCenterStyled((C1 + C2) / 2, y - 11, "DEGREE CLASSIFICATION", 8.5, { font: "F3" });
  p.textCenterStyled((C2 + R) / 2, y - 11, "ABBREVIATIONS", 8.5, { font: "F3" });
  p.rule(L, y - 38, C2, y - 38, 0.6, 0);
  const g1 = L + 44, g2 = L + 88;
  p.rule(g1, y - 18, g1, y - keyH, 0.4, 0);
  p.rule(g2, y - 18, g2, y - keyH, 0.4, 0);
  p.rule(L, y - 18, C1, y - 18, 0.4, 0);
  p.textStyled(L + 3, y - 27, "SCORE", 6.5, { font: "F4" });
  p.textStyled(L + 3, y - 34, "(%)", 6.5, { font: "F4" });
  p.textStyled(g1 + 3, y - 27, "LETTER", 6.5, { font: "F4" });
  p.textStyled(g1 + 3, y - 34, "GRADE", 6.5, { font: "F4" });
  p.textStyled(g2 + 3, y - 27, "GRADE", 6.5, { font: "F4" });
  p.textStyled(g2 + 3, y - 34, "POINT", 6.5, { font: "F4" });
  const b1 = C1 + 64;
  p.rule(b1, y - 38, b1, y - keyH, 0.4, 0);
  scale.forEach((g, i) => {
    const yy = y - 48 - i * 10;
    p.textStyled(L + 4, yy, `${g.low}-${g.high}`, 7.5, { font: "F4" });
    p.textCenterStyled((g1 + g2) / 2, yy, clean(g.grade), 7.5, { font: "F4" });
    p.textCenterStyled((g2 + C1) / 2, yy, String(g.points), 7.5, { font: "F4" });
  });
  bands.forEach((b, i) => {
    const yy = y - 48 - i * 10;
    p.textStyled(C1 + 6, yy, `${num(b.low)} - ${num(b.high)}`, 7.5, { font: "F4" });
    p.textStyled(b1 + 4, yy, fit(clean(b.class), 7.5, C2 - b1 - 6), 7.5, { font: "F4" });
  });
  const abbr: [string, string][] = [["TCR", "Total Credits Registered"], ["TCE", "Total Credits Earned"], ["TWGP", "Total Weighted Grade Point"], ["CGPA", "Cumulative Grade Point Average"]];
  abbr.forEach(([k, v], i) => {
    const yy = y - 48 - i * 10;
    p.textStyled(C2 + 8, yy, k, 7.5, { font: "F4" });
    p.textStyled(C2 + 56, yy, v, 7.5, { font: "F4" });
  });
  y -= keyH;

  // ── the signature boxes the template names ──
  p.box(L, y - sigH, R - L, sigH, 0);
  p.rule(C2, y, C2, y - sigH, 0.6, 0);
  p.rule(L, y - sigH + 24, R, y - sigH + 24, 0.6, 0);
  p.textCenterStyled((L + C2) / 2, y - sigH + 14, clean(t?.signatory_name ?? "Signature of Dean"), 8, { font: "F5" });
  p.textCenterStyled((L + C2) / 2, y - sigH + 5, clean(t?.signatory_title ?? "Stamp and Date"), 8, { font: "F5" });
  p.textCenterStyled((C2 + R) / 2, y - sigH + 14, clean(t?.second_name ?? "Signature of Academic Secretary"), 8, { font: "F5" });
  p.textCenterStyled((C2 + R) / 2, y - sigH + 5, clean(t?.second_title ?? "Stamp and Date"), 8, { font: "F5" });
  y -= sigH;

  // ── the verification under the boxes ──
  const last = pages[pages.length - 1];
  const vy = Math.max(26, y - 62);
  qr(last, R - 52, vy, 50, verifyUrl);
  last.text(L, vy + 38, `No. ${clean(s.number)}${s.version > 1 ? ` (version ${s.version})` : ""} · issued ${day(s.issuedOn)}`, 7.5, true, INK);
  last.text(L, vy + 27, `Verification code ${clean(verificationCode)}: scan the code, or enter it on the University's portal.`, 7, false, MUTED);
  last.text(L, vy + 16, clean(t?.footer ?? "Not valid without the verification reference."), 7, false, MUTED);
  if (t?.remarks) last.text(L, vy + 5, clean(t.remarks).slice(0, 130), 6.5, false, MUTED);
  return pdf(letter ? [coverLetterPage(letter), ...pages] : pages, `${title} ${s.number}`);
}

/** day as the letter writes it: 5th January, 2026 */
const letterDay = (iso: string | null | undefined) => {
  const d = iso ? new Date(iso) : new Date();
  const n = d.getUTCDate();
  const th = n % 10 === 1 && n !== 11 ? "st" : n % 10 === 2 && n !== 12 ? "nd" : n % 10 === 3 && n !== 13 ? "rd" : "th";
  return `${n}${th} ${d.toLocaleDateString("en-GB", { month: "long", timeZone: "UTC" })}, ${d.getUTCFullYear()}`;
};

/** V668: the Transcript Desk's covering letter (Transcript_Letter.docx) as one page, on the University's letterhead */
export function coverLetterPage(c: CoverLetter): Page {
  const p = new Page();
  const L = 70, R = A4.w - 70;
  let y = brandHeader(p, L - 22, "Office of the Registrar") - 14;
  p.text(L + 8, y, clean(c.ref), 10.5, true, INK);
  y -= 20;
  const dt = letterDay(c.date);
  p.text(R - textWidth(dt, 10.5, true), y, dt, 10.5, true, INK);
  y -= 44;
  const to = [c.recipientName, c.department, c.organisation].map((x) => clean(x)).filter(Boolean);
  if (to.length) { p.text(L, y, to[0], 10.5, true, INK); y -= 14; for (const l of to.slice(1)) { p.text(L, y, l, 10.5, false, INK); y -= 14; } }
  for (const l of (c.address ?? "").split(/\r?\n/).map((x) => clean(x)).filter(Boolean).slice(0, 6)) { p.text(L, y, l, 10.5, false, INK); y -= 14; }
  if (c.recipientReference) { p.text(L, y, `Your ref: ${clean(c.recipientReference)}`, 9.5, false, MUTED); y -= 14; }
  y -= 30;
  p.text(L, y, "Dear Sir/Madam,", 10.5, false, INK);
  y -= 24;
  y = p.paragraph(L, y, `ACADEMIC TRANSCRIPT IN RESPECT OF ${clean(c.holderUpper)}`, R - L, 10.5, 1.3, true);
  y -= 10;
  y = p.paragraph(L, y, clean(c.body), R - L, 10.5, 1.45);
  for (const para of (c.closing ?? "").split(/\n\s*\n/)) { y -= 10; y = p.paragraph(L, y, clean(para), R - L, 10.5, 1.45); }
  y -= 44;
  if (c.signatoryName) { p.text(L, y, clean(c.signatoryName), 10.5, true, INK); y -= 13; }
  p.text(L, y, clean(c.signatoryTitle), 9, false, MUTED);
  y -= 12;
  if (c.onBehalfOf) p.text(L, y, clean(c.onBehalfOf), 9, false, MUTED);
  p.text(L, 48, `Request ${clean(c.requestRef)}`, 7, false, MUTED);
  return p;
}

export function coverLetterPdf(c: CoverLetter): Uint8Array {
  return pdf([coverLetterPage(c)], `Letter ${c.requestRef}`);
}

/** the document as a PDF; a recipient's copy (V668) opens with the Transcript Desk's covering letter */
export function documentPdf(s: Statement, t: Template | null, verifyUrl: string, verificationCode: string, status = "ACTIVE", letter: CoverLetter | null = null): Uint8Array {
  if (s.kind === "DEGREE_CERTIFICATE") return certificatePdf({ ...s, ...({ verificationCode } as object) }, t, verifyUrl, status);
  // V668: the full transcript on the University's own template; the other transcripts and statements as before
  return s.kind === "TRANSCRIPT" ? moaumTranscriptPdf(s, t, verifyUrl, verificationCode, status, letter) : transcriptPdf(s, t, verifyUrl, verificationCode, status, letter);
}

export function originOf(req: Request): string {
  const h = req.headers;
  const host = h.get("x-forwarded-host") ?? h.get("host");
  const proto = h.get("x-forwarded-proto") ?? "https";
  try { return host ? `${proto}://${host}` : new URL(req.url).origin; } catch { return new URL(req.url).origin; }
}
