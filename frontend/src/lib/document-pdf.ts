import "server-only";
import { A4, Page, pdf } from "@/lib/pdf-write";
import { brandHeader, crestImage } from "@/lib/pdf-crest";
import { qrMatrix } from "@/lib/qr";
import type { Statement, Template } from "@/lib/documents";

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
  p.textCenter(cx, A4.h - 168, "REV. FR. MOSES ORSHIO ADASU UNIVERSITY", 17, true, INK);
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
  p.text(284, 157, clean(verifyUrl.replace(/^https?:\/\//, "")).slice(0, 48), 7, false, MUTED);
  p.text(284, 146, `Verification code`, 7.5, false, MUTED);
  p.text(284, 135, clean((s as unknown as { verificationCode?: string }).verificationCode ?? ""), 8.5, true, INK);
  p.text(284, 122, `Certificate ${clean(s.number)}`, 7.5, false, MUTED);
  p.textCenter(cx, 48, clean(t?.footer ?? "This certificate is verified by the QR code and the verification reference it carries."), 7.5, false, MUTED);
  statusStamp(p, status);
  return pdf([p], `Certificate ${s.number}`);
}

/** a transcript, sessional transcript, mini-transcript or statement: the record tabulated, as many pages as it takes */
export function transcriptPdf(s: Statement, t: Template | null, verifyUrl: string, verificationCode: string, status = "ACTIVE"): Uint8Array {
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
  last.text(L + 200, 73, clean(verifyUrl.replace(/^https?:\/\//, "")).slice(0, 60), 7, false, MUTED);
  last.text(L, 48, clean(t?.footer ?? "Not valid without the verification reference."), 7.5, false, MUTED);
  for (const pg of pages) pg.text(L, 36, `${clean(s.holder)} · ${clean(s.matricNo)} · ${clean(s.number)}`, 6.5, false, MUTED);
  return pdf(pages, `${title} ${s.number}`);
}

export function documentPdf(s: Statement, t: Template | null, verifyUrl: string, verificationCode: string, status = "ACTIVE"): Uint8Array {
  return s.kind === "DEGREE_CERTIFICATE" ? certificatePdf({ ...s, ...({ verificationCode } as object) }, t, verifyUrl, status) : transcriptPdf(s, t, verifyUrl, verificationCode, status);
}

export function originOf(req: Request): string {
  const h = req.headers;
  const host = h.get("x-forwarded-host") ?? h.get("host");
  const proto = h.get("x-forwarded-proto") ?? "https";
  try { return host ? `${proto}://${host}` : new URL(req.url).origin; } catch { return new URL(req.url).origin; }
}
