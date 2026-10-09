/** The letter of admission as the Registry issues it (V283): the crest and the University over the Office of the Registrar, the
 *  date, the applicant's name and number, CONFIRMATION OF OFFER OF ADMISSION for the session, the course, programme, faculty,
 *  level and duration, the Registry's six notes, the signatory the document template names, and the QR that verifies it. Drawn
 *  the same from the applicant's dashboard and from the student's library (V282). */
import type { ScreeningResult } from "./applicant.ts";
import { currentInstitution } from "./document/institution-cache.ts";
import { A4, Page, pdf, type Image } from "./pdf-write.ts";

export interface LetterApplication {
  applicationNo: string; session: string; name: string; jambKey: string; entryLevel: number; programme: string | null; faculty: string | null;
  decision: string | null; decisionReleasedAt: string | null; decisionBasis: string | null; acceptedAt: string | null; result?: ScreeningResult | null;
  /** V283: what the letter states beyond the offer */
  department?: string | null; degreeType?: string | null; durationSemesters?: number | null; registrationOpens?: string | null; surname?: string | null; otherNames?: string | null;
}
export interface LetterTemplate { title?: string | null; subtitle?: string | null; signatory_name?: string | null; signatory_title?: string | null; second_name?: string | null; second_title?: string | null; footer?: string | null; remarks?: string | null }
export interface LetterDoc { number: string; version: number; verification_code: string; statement: string; issued_on: string; verifyPath: string; application?: LetterApplication; template?: LetterTemplate | null }

/** what the route supplies from the server: the crest, the lodged signature, the QR of the verifying address, and (V379, a CCE
 *  admission) the applicant's passport photograph as a JPEG */
export interface LetterArt { crest: Image | null; signature: Image | null; qr: { size: number; dark: Uint8Array | boolean[] | number[] } | null; passport?: Image | null }

/** V379: what a CCE admission's statement adds — the route, the study mode, the Centre and the programme's duration on the route */
export interface CceStatement { admissionRoute?: string | null; studyMode?: string | null; centre?: string | null; durationYears?: number | null }

function qr(p: Page, x: number, y: number, side: number, m: NonNullable<LetterArt["qr"]>) {
  const { size, dark } = m;
  const cell = side / size;
  for (let r = 0; r < size; r++) for (let c = 0; c < size; c++) if (dark[r * size + c]) p.fill(x + c * cell, y + (size - 1 - r) * cell, cell, cell, 0);
}

const ordinal = (d: number) => `${d}${d % 10 === 1 && d !== 11 ? "st" : d % 10 === 2 && d !== 12 ? "nd" : d % 10 === 3 && d !== 13 ? "rd" : "th"}`;
/** "5th January, 2026" */
export function longDate(iso: string | null | undefined): string {
  if (!iso) return "";
  const d = new Date(iso);
  if (isNaN(d.getTime())) return "";
  return `${ordinal(d.getDate())} ${d.toLocaleDateString("en-GB", { month: "long" })}, ${d.getFullYear()}`;
}
const isoDay = (iso: string | null | undefined) => (iso ? String(iso).slice(0, 10) : "");

/** the Registry's notes when the template states none */
export const DEFAULT_NOTES = [
  "The University shall commence registration of Fresh Students for the First Semester of {session} Academic Session{from}.",
  "This admission is only provisional as only candidates who are successful at the screening exercise would be registered.",
  "Successfully screened candidates are to proceed and pay appropriate user charges immediately in order to validate their admission.",
  "There shall be physical screening of certificates at the faculties.",
  "Please, note that should any problem be discovered with your credentials in the course of your study, you will be required to withdraw from the University.",
  "Congratulations on your admission.",
];

const R = "F4", B = "F3", BI = "F5";

/** the name as the letter writes it: surname first as the record holds it, in title case */
function titleCase(s: string): string {
  return s.toLowerCase().replace(/(^|[\s'-])([a-z])/g, (m, a: string, b: string) => a + b.toUpperCase());
}

export function admissionLetterPdf(a: LetterApplication, letter: LetterDoc, origin: string, art: LetterArt): Uint8Array {
  const st = JSON.parse(letter.statement) as { changedFrom?: string | null; changedTo?: string | null; changedOn?: string | null } & CceStatement;
  const cce = st.admissionRoute === "CCE";
  const t = letter.template ?? {};
  const p = new Page();
  const L = 56, W = A4.w - 2 * L, cx = A4.w / 2;
  let y = A4.h - 40;
  // the crest and the University, centred
  const crest = art.crest;
  if (crest) { p.jpeg(cx - 34, y - 68, 68, 68, crest); y -= 82; } else y -= 10;
  p.textCenterStyled(cx, y, currentInstitution().name.toUpperCase(), 12.5, { font: B }); y -= 17;
  p.textCenterStyled(cx, y, "P. M. B 102119, Makurdi, Nigeria", 10.5, { font: B }); y -= 15;
  p.textCenterStyled(cx, y, "(Office of the Registrar)", 10.5, { font: BI }); y -= 22;
  // the date, right; the applicant's name and number
  const dateText = `DATE: ${isoDay(letter.issued_on) || isoDay(a.decisionReleasedAt)}`;
  p.textStyled(A4.w - L - dateText.length * 5.6, y, "DATE: ", 10.5, { font: B });
  p.textStyled(A4.w - L - dateText.length * 5.6 + 36, y, dateText.slice(6), 10.5, { font: R }); y -= 22;
  const name = a.surname && a.otherNames ? `${titleCase(a.otherNames)} ${titleCase(a.surname)}` : titleCase(a.name.includes(",") ? a.name.split(",").reverse().join(" ").trim() : a.name);
  const kv = (k: string, v: string, size = 10.5) => { p.textStyled(L, y, k, size, { font: B }); p.textStyled(L + k.length * size * 0.69 + 5, y, v, size, { font: R }); y -= 20; };
  // V379: a CCE letter carries the applicant's passport photograph, top right beside the name
  if (cce && art.passport) p.jpeg(A4.w - L - 74, y - 76, 66, 82, art.passport);
  kv("APPLICANT'S NAME:", name);
  kv("APPLICATION NUMBER:", a.jambKey || a.applicationNo);
  y -= 22;
  p.textCenterStyled(cx, y, (t.title || "CONFIRMATION OF OFFER OF ADMISSION").toUpperCase() + ":", 11.5, { font: B }); y -= 16;
  p.textCenterStyled(cx, y, (t.subtitle ? t.subtitle.replace("{session}", a.session) : `${a.session} ACADEMIC SESSION`).toUpperCase(), 11.5, { font: B }); y -= 26;
  // the confirmation sentence, the University's name in bold within it
  p.textStyled(L, y, "I am pleased to confirm your offer of provisional admission into the", 10.5, { font: R }); y -= 15;
  p.textStyled(L, y, currentInstitution().name.toUpperCase(), 10.5, { font: B });
  p.textStyled(L + 344, y, "as approved by JAMB as follows:", 10.5, { font: R }); y -= 22;
  const programme = st.changedTo ?? a.programme ?? "";
  const degree = (a.degreeType ?? "").replace(/\s+/g, "").toUpperCase() || "UNDERGRADUATE";
  kv("COURSE:", programme);
  kv("PROGRAMME:", degree);
  kv("FACULTY:", (a.faculty ?? "").toUpperCase());
  if (cce) {
    // V379: the Centre for Continuing Education's admission: the route, part-time, the Centre, and the duration in years
    kv("CENTRE:", (st.centre ?? "Centre for Continuing Education").toUpperCase());
    kv("STUDY MODE:", (st.studyMode ?? "PART-TIME").toUpperCase());
    kv("ADMISSION ROUTE:", "CCE");
  }
  kv("LEVEL:", `${a.entryLevel} LEVEL`);
  kv("DURATION:", cce && st.durationYears ? `${st.durationYears} YEARS (PART-TIME)` : `${a.durationSemesters ?? 8} SEMESTERS`);
  if (st.changedTo) {
    y -= 2;
    y = p.paragraphStyled(L, y, `Your change of programme from ${st.changedFrom ?? "the programme first offered"} to ${st.changedTo} was approved${st.changedOn ? ` on ${longDate(st.changedOn)}` : ""}; this letter, version ${letter.version} under the same number, states the admission as it now stands.`, W, 9.5, { font: R });
  }
  y -= 6;
  // the Registry's notes, numbered
  const from = a.registrationOpens ? ` from ${longDate(a.registrationOpens)}` : "";
  const notes = (t.remarks ? t.remarks.split(/\r?\n/).map((x) => x.trim()).filter(Boolean) : DEFAULT_NOTES).map((n) => n.replace("{session}", a.session).replace("{from}", from).replace("{date}", longDate(a.registrationOpens)));
  notes.forEach((n, i) => {
    p.textStyled(L + 14, y, `${i + 1}.`, 10.5, { font: R });
    y = p.paragraphStyled(L + 30, y, n, W - 30, 10.5, { font: R }, 1.35);
  });
  // the signatory the template names, the signature above it when the University has lodged one
  const sigTop = Math.min(y - 20, 176);
  const sig = art.signature;
  if (sig) p.jpeg(L, sigTop - 44, 120, 44, sig);
  const sName = t.signatory_name || "The Registrar";
  const sTitle = t.signatory_title || "Registrar";
  let sy = sigTop - 58;
  p.textStyled(L, sy, sName, 10.5, { font: B }); sy -= 15;
  p.textStyled(L, sy, sTitle, 10.5, { font: R }); sy -= 15;
  if (t.second_title || !t.signatory_name) p.textStyled(L, sy, t.second_title || "For: Registrar", 10.5, { font: R });
  // the QR that opens the public verifier, the number and the code beneath the page
  if (art.qr) qr(p, A4.w - L - 84, 96, 84, art.qr);
  p.text(L, 44, `Document no ${letter.number} · version ${letter.version} · verification code ${letter.verification_code} · verify at ${origin}/verify/document`, 7.5, false, [0.4, 0.4, 0.4]);
  if (t.footer) p.text(L, 33, t.footer, 7.5, false, [0.4, 0.4, 0.4]);
  return pdf([p], `Admission letter ${a.applicationNo}`);
}
