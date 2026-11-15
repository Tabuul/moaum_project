/** The letter of admission as the Registry issues it (V283): the crest and the University over the Office of the Registrar, the
 *  date, the applicant's name and number, CONFIRMATION OF OFFER OF ADMISSION for the session, the course, programme, faculty,
 *  level and duration, the Registry's six notes, the signatory the document template names, and the QR that verifies it. Drawn
 *  the same from the applicant's dashboard and from the student's library (V282). */
import type { ScreeningResult } from "./applicant.ts";
import { currentInstitution } from "./document/institution-cache.ts";
import { A4, Page, pdf, styledLines, textWidth, type Image } from "./pdf-write.ts";
import { SIGNATURE_BOX, fitBottomLeft, type LetterSignature } from "./letter-signature.ts";

export interface LetterApplication {
  applicationNo: string; session: string; name: string; jambKey: string; entryLevel: number; programme: string | null; faculty: string | null;
  decision: string | null; decisionReleasedAt: string | null; decisionBasis: string | null; acceptedAt: string | null; result?: ScreeningResult | null;
  /** V283: what the letter states beyond the offer */
  department?: string | null; degreeType?: string | null; durationSemesters?: number | null; registrationOpens?: string | null; surname?: string | null; otherNames?: string | null;
}
export interface LetterTemplate { title?: string | null; subtitle?: string | null; signatory_name?: string | null; signatory_title?: string | null; second_name?: string | null; second_title?: string | null; footer?: string | null; remarks?: string | null }
export interface LetterDoc {
  number: string; version: number; verification_code: string; statement: string; issued_on: string; verifyPath: string; application?: LetterApplication; template?: LetterTemplate | null;
  /** V759: the signature uploaded for the signatory the template in force names (the letter is drawn with it whenever it is
   *  opened), when one is held; absent otherwise */
  signature?: LetterSignature | null;
}

/** what the route supplies from the server: the crest, the signature (V759: the one uploaded for the template's signatory, from the
 *  letter's JSON — lib/letter-signature), the QR of the verifying address, and (V379, a CCE admission) the applicant's passport
 *  photograph as a JPEG */
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

/**
 * Lines of Helvetica at a size, none wider than the width: the parts joined by the separator while a line holds them, each part
 * kept whole on a line when it fits one. A part wider than a line starts its own and is broken between its words, and a word wider
 * than a line — a long address — after a "/", "." or "-" (a host name's labels are 63 characters at most, so it always has one);
 * only a stretch without one that is itself wider than a line is cut where the width ends. Nothing is dropped: the lines read back
 * as the parts, the separator or space at each break left out.
 */
export function linesWithin(parts: string[], width: number, size: number, sep = " · "): string[] {
  const fits = (s: string) => textWidth(s, size) <= width;
  const lines: string[] = [];
  let line = "";
  const add = (piece: string, glue: string) => {
    if (line && fits(line + glue + piece)) { line += glue + piece; return; }
    if (line) lines.push(line);
    line = piece;
  };
  /** a piece wider than a line, cut where the width ends (a character at least each time) */
  const hard = (piece: string): string[] => {
    const out: string[] = [];
    let rest = piece;
    while (!fits(rest)) {
      let n = 1;
      while (n < rest.length && fits(rest.slice(0, n + 1))) n++;
      out.push(rest.slice(0, n));
      rest = rest.slice(n);
    }
    return rest ? [...out, rest] : out;
  };
  for (const part of parts) {
    if (!part) continue;
    if (fits(part)) { add(part, sep); continue; }
    if (line) { lines.push(line); line = ""; }
    for (const word of part.split(" ").filter(Boolean)) {
      if (fits(word)) { add(word, " "); continue; }
      (word.match(/[^/.-]*[/.-]+|[^/.-]+$/g) ?? [word]).flatMap(hard).forEach((bit, j) => add(bit, j > 0 ? "" : " "));
    }
  }
  if (line) lines.push(line);
  return lines;
}

/** the footer's size and leading; where its last line stands, the template's footer under it, as the letter has always had them;
 *  the lowest any line may stand; and how far its top line's baseline keeps under the signatory's last baseline (16 pt: about 8 pt
 *  between the one's descenders and the other's capitals) and under the QR's foot (20 pt) */
const FOOT = { size: 7.5, lead: 9, verify: 44, template: 33, floor: 18, underSignatory: 16, underQr: 20, grey: [0.4, 0.4, 0.4] as [number, number, number] };

/** the signatory's block, measured from the top of the space a signature takes — 176 pt up the page when the body leaves room, as
 *  the letter has always had it: the name 58 pt under that top and each line after it 15 pt lower, the signature standing 12 pt
 *  over the name's baseline; the QR on the right, 84 pt square, its foot 80 pt under the top (96 pt, where it has always stood) */
const SIGN = { top: 176, name: 58, step: 15, over: 12, qr: 84, qrFoot: 80 };

/** how closely the body under the confirmation sentence is set, the Registry's own spacing first: the space under that sentence,
 *  the step between the statement's lines from COURSE on, the change of programme's leading, the space over the notes, the notes'
 *  leading, and the space between the notes and the top of the signature's space. A body that leaves the signatory, the QR and the
 *  footer no room on the page at one is set at the next. (Nothing above the sentence moves: a CCE passport stands beside it.) */
const SPACING = [
  { after: 22, kv: 20, change: 1.4, notes: 6, lead: 1.35, sign: 20 },
  { after: 18, kv: 17, change: 1.3, notes: 5, lead: 1.25, sign: 16 },
  { after: 15, kv: 15, change: 1.2, notes: 4, lead: 1.15, sign: 12 },
  { after: 14, kv: 14, change: 1.15, notes: 4, lead: 1.1, sign: 12 },
] as const;
type Spacing = (typeof SPACING)[number];

/** the name as the letter writes it: surname first as the record holds it, in title case */
function titleCase(s: string): string {
  return s.toLowerCase().replace(/(^|[\s'-])([a-z])/g, (m, a: string, b: string) => a + b.toUpperCase());
}

/**
 * The letter, laid out from the foot of the page up so that nothing meets: the footer (the number, the version, the code and the
 * verifying address, the template's footer under them) where it has always stood unless the signatory's block above it needs it
 * lower, down to the page's foot (18 pt) at most; the signatory's block (the signature, the name, the title, the second title, the
 * QR beside them) at 176 pt, lower when the notes come further down, higher when a footer of many lines needs it, its last line
 * and the QR's foot always over the footer's top line; the notes over the block. A body that leaves the block no room is set
 * closer (SPACING); one too long even then goes on to a second page at the Registry's own spacing, the block after its notes and
 * the footer on every page.
 */
export function admissionLetterPdf(a: LetterApplication, letter: LetterDoc, origin: string, art: LetterArt): Uint8Array {
  const st = JSON.parse(letter.statement) as { changedFrom?: string | null; changedTo?: string | null; changedOn?: string | null } & CceStatement;
  const cce = st.admissionRoute === "CCE";
  const t = letter.template ?? {};
  const L = 56, W = A4.w - 2 * L, cx = A4.w / 2;
  const name = a.surname && a.otherNames ? `${titleCase(a.otherNames)} ${titleCase(a.surname)}` : titleCase(a.name.includes(",") ? a.name.split(",").reverse().join(" ").trim() : a.name);
  const programme = st.changedTo ?? a.programme ?? "";
  const degree = (a.degreeType ?? "").replace(/\s+/g, "").toUpperCase() || "UNDERGRADUATE";
  const from = a.registrationOpens ? ` from ${longDate(a.registrationOpens)}` : "";
  const notes = (t.remarks ? t.remarks.split(/\r?\n/).map((x) => x.trim()).filter(Boolean) : DEFAULT_NOTES).map((n) => n.replace("{session}", a.session).replace("{from}", from).replace("{date}", longDate(a.registrationOpens)));

  // the footer: the number and the code beneath the page, within the margins whatever the address's length — a line that would run
  // past the right margin goes on to a second line above the first's place (44 pt) — and the template's footer under them, keeping
  // its own place (33 pt, its own lines going up the page too)
  const verify = linesWithin([`Document no ${letter.number}`, `version ${letter.version}`, `verification code ${letter.verification_code}`, `verify at ${origin}/verify/document`], W, FOOT.size);
  const footer = t.footer ? linesWithin([t.footer], W, FOOT.size) : [];
  const base = FOOT.verify + Math.max(0, footer.length - 1) * FOOT.lead;
  const foot = [
    ...verify.map((s, i) => ({ s, y: base + (verify.length - 1 - i) * FOOT.lead })),
    ...footer.map((s, i) => ({ s, y: FOOT.template + (footer.length - 1 - i) * FOOT.lead })),
  ];
  const footTop = foot[0].y, footHeight = footTop - foot[foot.length - 1].y;

  // the signatory the template names, under it the title, and For: Registrar unless the template names a signatory and no second title
  const signatory: { s: string; font: typeof B | typeof R }[] = [
    { s: t.signatory_name || "The Registrar", font: B },
    { s: t.signatory_title || "Registrar", font: R },
  ];
  if (t.second_title || !t.signatory_name) signatory.push({ s: t.second_title || "For: Registrar", font: R });
  /** the highest the footer's top line may stand under the block whose top is at `top`: under its last line and under the QR */
  const ceiling = (top: number) => Math.min(top - SIGN.name - (signatory.length - 1) * SIGN.step - FOOT.underSignatory, art.qr ? top - SIGN.qrFoot - FOOT.underQr : Infinity);
  /** the lowest the block's top may stand: where the footer, brought down to the page's foot, is still under it */
  const lowest = FOOT.floor + footHeight - ceiling(0);

  /** the letter at a spacing; null when the body leaves the block no room on the page and the notes may not go on to another */
  const draw = (sp: Spacing, overflow: boolean): Page[] | null => {
    const pages = [new Page()];
    let p = pages[0];
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
    const kv = (k: string, v: string, step = 20) => { p.textStyled(L, y, k, 10.5, { font: B }); p.textStyled(L + k.length * 10.5 * 0.69 + 5, y, v, 10.5, { font: R }); y -= step; };
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
    p.textStyled(L + 344, y, "as approved by JAMB as follows:", 10.5, { font: R }); y -= sp.after;
    kv("COURSE:", programme, sp.kv);
    kv("PROGRAMME:", degree, sp.kv);
    kv("FACULTY:", (a.faculty ?? "").toUpperCase(), sp.kv);
    if (cce) {
      // V379: the Centre for Continuing Education's admission: the route, part-time, the Centre, and the duration in years
      kv("CENTRE:", (st.centre ?? "Centre for Continuing Education").toUpperCase(), sp.kv);
      kv("STUDY MODE:", (st.studyMode ?? "PART-TIME").toUpperCase(), sp.kv);
      kv("ADMISSION ROUTE:", "CCE", sp.kv);
    }
    kv("LEVEL:", `${a.entryLevel} LEVEL`, sp.kv);
    kv("DURATION:", cce && st.durationYears ? `${st.durationYears} YEARS (PART-TIME)` : `${a.durationSemesters ?? 8} SEMESTERS`, sp.kv);
    if (st.changedTo) {
      y -= 2;
      y = p.paragraphStyled(L, y, `Your change of programme from ${st.changedFrom ?? "the programme first offered"} to ${st.changedTo} was approved${st.changedOn ? ` on ${longDate(st.changedOn)}` : ""}; this letter, version ${letter.version} under the same number, states the admission as it now stands.`, W, 9.5, { font: R }, sp.change);
    }
    y -= sp.notes;
    // the Registry's notes, numbered, a line at a time: going on to another page, only when they may, before a line would come
    // within 20 pt of the footer's top line
    notes.forEach((n, i) => styledLines(n, W - 30, 10.5, R).forEach((line, j) => {
      if (overflow && y < footTop + 20) { p = new Page(); pages.push(p); y = A4.h - 56; }
      if (j === 0) p.textStyled(L + 14, y, `${i + 1}.`, 10.5, { font: R });
      p.textStyled(L + 30, y, line, 10.5, { font: R });
      y -= 10.5 * sp.lead;
    }));
    // the signatory's block: its top at 176 pt, lower when the notes come further down (`sp.sign` under them), higher when the
    // footer needs it; never below `lowest` — at the closest spacing, on a page of its own after the notes
    let top = Math.min(y - sp.sign, Math.max(SIGN.top, lowest));
    if (top < lowest) {
      if (!overflow) return null;
      p = new Page(); pages.push(p); top = Math.max(SIGN.top, lowest);
    }
    // V759: above the name, the signature uploaded for the signatory, in its own proportions within the space a hand signature takes
    // (140 x 48 pt), standing 12 pt over the name's baseline (clear of its capitals). Without a signature the space is left for a
    // hand signature
    const sy = top - SIGN.name;
    const sig = art.signature;
    const at = sig ? fitBottomLeft(sig, { x: L, y: sy + SIGN.over, w: SIGNATURE_BOX.w, h: SIGNATURE_BOX.h }) : null;
    if (sig && at) p.jpeg(at.x, at.y, at.w, at.h, sig);
    signatory.forEach((l, i) => p.textStyled(L, sy - i * SIGN.step, l.s, 10.5, { font: l.font }));
    // the QR that opens the public verifier, on the right beside the block
    if (art.qr) qr(p, A4.w - L - SIGN.qr, top - SIGN.qrFoot, SIGN.qr, art.qr);
    // the footer on every page, on the block's page brought down as far as the block needs
    const down = Math.max(0, footTop - ceiling(top));
    for (const pg of pages) for (const f of foot) pg.text(L, f.y - (pg === p ? down : 0), f.s, FOOT.size, false, FOOT.grey);
    return pages;
  };

  const title = `Admission letter ${a.applicationNo}`;
  for (const sp of SPACING) {
    const pages = draw(sp, false);
    if (pages) return pdf(pages, title);
  }
  // too long for one page even at the closest spacing: the Registry's own spacing, the notes going on to a second page (never null)
  return pdf(draw(SPACING[0], true) as Page[], title);
}
