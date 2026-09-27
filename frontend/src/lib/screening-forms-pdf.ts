/**
 * The screening forms, printable once the applicant has filled them (V273
 * pages, printed): the five paper pages as the University binds them — Form A,
 * the Screening of Fresh Undergraduate Students (Sections A and B), Section C
 * with the declaration and the official-use section, the Supplementary Biodata
 * Form and the Student Data Capture Form — each with the headings and the
 * information of the paper original, filled from the applicant's answers. Only
 * the University's name differs from the paper: the forms were the former
 * University's. Drawn with pdf-write; no library.
 *
 * Imports are relative with extensions so the builder also runs under node's
 * type stripping for its test; the crest and the passport come in as images.
 */
import { A4, type Image, Page, pdf } from "./pdf-write.ts";

export const UNIVERSITY = "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI";
export const UNIVERSITY_TITLE = "Rev. Fr. Moses Orshio Adasu University, Makurdi";

export interface FormsInstitution { name: string; from_year: number | null; to_year: number | null; certificate: string | null; award_year: number | null }
export interface FormsOlevel { exam_body: string; exam_number: string | null; exam_year: number | null; subject: string; grade: string }
export interface FormsPrefill {
  surname: string; other_names: string; jamb_reg_no: string; programme: string; entry_mode: string; session: string; application_no: string; sex: string | null;
  state_of_origin: string | null; lga: string | null; faculty: string | null; department: string | null; date_of_birth: string | null; email: string; phone: string; next_of_kin: string | null;
}
export interface FormsForm {
  screening_no: string; state: string; submitted_at: string | null; declaration_at: string | null; membership: string | null;
  decided_at: string | null; decided_office: string | null; decision_reason: string | null;
}
export interface FormsInput {
  prefill: FormsPrefill;
  answers: Record<string, string>;
  institutions: FormsInstitution[];
  olevel: FormsOlevel[];
  form: FormsForm;
  /** when the acceptance fee was confirmed — the "Date Paid" the paper forms carry */
  acceptancePaidOn: string | null;
  passport: Image | null;
  crest: Image | null;
  /** the day the print is made, for the footer */
  printedOn?: Date;
  /** the issued document (V280): its number, version and verification code, and the QR that opens the public verifier */
  document?: { number: string; version: number; code: string; issuedOn: string; verifyUrl: string; verifyPage: string; qr: { size: number; dark: Uint8Array | boolean[] | number[] } };
}

const L = 46;
const R = A4.w - 46;
const W = R - L;
const CX = A4.w / 2;
const GREY: [number, number, number] = [0.35, 0.35, 0.35];

const longDate = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "");
const dmy = (iso: string | null | undefined) => {
  if (!iso) return "";
  const d = new Date(iso);
  if (isNaN(d.getTime())) return iso;
  return `${String(d.getDate()).padStart(2, "0")}-${String(d.getMonth() + 1).padStart(2, "0")}-${d.getFullYear()}`;
};
const ageOn = (iso: string | null | undefined): number | null => {
  if (!iso) return null;
  const d = new Date(iso);
  if (isNaN(d.getTime())) return null;
  const now = new Date();
  let a = now.getFullYear() - d.getFullYear();
  if (now.getMonth() < d.getMonth() || (now.getMonth() === d.getMonth() && now.getDate() < d.getDate())) a -= 1;
  return a;
};
const words = (s: string) => s.replace(/_/g, " ");
/** the same wrapping rule pdf-write's paragraph uses, so a table row's height is known before it is drawn */
function wrap(s: string, width: number, size: number): string[] {
  const maxChars = Math.max(10, Math.floor(width / (size * 0.5)));
  const out: string[] = [];
  let line = "";
  for (const w of (s || "").split(/\s+/)) {
    if ((line + " " + w).trim().length > maxChars && line) { out.push(line.trim()); line = w; } else line = (line + " " + w).trim();
  }
  if (line) out.push(line);
  return out.length ? out : [""];
}
function lines(p: Page, x: number, y: number, ls: string[], size: number, lead = 1.3, bold = false): number {
  let yy = y;
  for (const l of ls) { p.text(x, yy, l, size, bold); yy -= size * lead; }
  return yy;
}
/** an approximate Helvetica width: capitals and bold are wider than lower case, punctuation narrower */
function textWidth(s: string, size: number, bold = false): number {
  let w = 0;
  for (const ch of s) {
    if (/[A-Z]/.test(ch)) w += bold ? 0.72 : 0.68;
    else if (/[a-z0-9]/.test(ch)) w += bold ? 0.58 : 0.54;
    else if (/[ :.,;'()\/-]/.test(ch)) w += 0.3;
    else w += 0.6;
  }
  return w * size;
}
/** a bold label followed by its value on one line; the value wraps under itself when long */
function kv(p: Page, x: number, y: number, label: string, value: string, width: number, size = 10): number {
  p.text(x, y, label, size, true);
  const lx = x + textWidth(label, size, true) + 5;
  if (!(value || "").trim()) {
    // not held by the University: a dotted line for the student's hand
    p.rule(lx, y - 2, x + width, y - 2, 0.5, 0.6);
    return y - size * 1.3;
  }
  const ls = wrap(value || "", Math.max(60, x + width - lx), size);
  p.text(lx, y, ls[0], size);
  let yy = y - size * 1.3;
  for (const l of ls.slice(1)) { p.text(lx, yy, l, size); yy -= size * 1.3; }
  return yy;
}
/** a dotted signature line: the label, a rule, and what stands on it */
function dotted(p: Page, x: number, y: number, label: string, width: number, on = "", size = 10) {
  p.text(x, y, label, size, true);
  const lx = x + textWidth(label, size, true) + 5;
  p.rule(lx, y - 2, x + width, y - 2, 0.5, 0.5);
  if (on) p.text(lx + 4, y + 1, on, size - 1, false, GREY);
}
/** a tick in a box: the box, and two strokes when ticked */
function tickBox(p: Page, x: number, y: number, ticked: boolean) {
  p.box(x, y, 11, 11, 0.2);
  if (ticked) { p.rule(x + 2, y + 5, x + 4.5, y + 2, 1.2, 0); p.rule(x + 4.5, y + 2, x + 9.5, y + 9.5, 1.2, 0); }
}
function passportBox(p: Page, x: number, y: number, w: number, h: number, img: Image | null, caption = "Passport Photograph") {
  p.box(x, y, w, h, 0.3);
  if (img) p.jpeg(x + 1, y + 1, w - 2, h - 2, img);
  else { p.text(x + 6, y + h / 2 + 2, caption.split(" ")[0], 8, false, GREY); p.text(x + 6, y + h / 2 - 8, caption.split(" ").slice(1).join(" "), 8, false, GREY); }
}
/** a ruled table: column widths, a header (one or two rows), rows whose cells wrap; returns the y under it */
function table(p: Page, x: number, y: number, cols: number[], header: string[][], rows: string[][], size = 9): number {
  const pad = 4;
  const lead = size * 1.3;
  const rowH = (cells: string[]) => Math.max(...cells.map((c, i) => (c === "<" ? 1 : wrap(c, cols[i] - 2 * pad, size).length))) * lead + 2 * pad;
  const drawRow = (cells: string[], top: number, bold: boolean): number => {
    const h = rowH(cells);
    let cx = x;
    cells.forEach((c, i) => {
      if (c === "<") return;
      let w = cols[i];
      for (let k = i + 1; k < cells.length && cells[k] === "<"; k++) w += cols[k];
      p.box(cx, top - h, w, h, 0.2);
      lines(p, cx + pad, top - pad - size, wrap(c, w - 2 * pad, size), size, 1.3, bold);
      cx += w;
    });
    return top - h;
  };
  let yy = y;
  for (const h of header) yy = drawRow(h, yy, true);
  for (const r of rows) yy = drawRow(r, yy, false);
  return yy;
}
function crestAt(p: Page, x: number, y: number, side: number, img: Image | null) {
  if (img) p.jpeg(x, y, side, side, img);
}
function headerName(p: Page, y: number, size = 14): number {
  p.textCenter(CX, y, UNIVERSITY, size, true);
  p.textCenter(CX, y - 15, "(Office of the Registrar)", 10);
  return y - 15;
}
function underlined(p: Page, x: number, y: number, s: string, size: number, bold = true) {
  p.text(x, y, s, size, bold);
  p.rule(x, y - 2, x + textWidth(s, size, bold), y - 2, 0.6, 0);
}
function footer(p: Page, input: FormsInput, page: number) {
  const on = input.printedOn ?? new Date();
  const d = input.document;
  p.text(L, 28, `${d ? `Document ${d.number} v${d.version} · code ${d.code} · ` : `${input.form.screening_no} · `}${input.prefill.application_no} · generated from the University's record ${longDate(on.toISOString())} · page ${page} of 5`, 7.5, false, GREY);
}
/** the verification block on the first page: the QR opens the public verifier; the code is typed where it cannot be scanned */
function verification(p: Page, input: FormsInput) {
  const d = input.document;
  if (!d) return;
  const side = 70;
  const cell = side / d.qr.size;
  const x0 = R - side, y0 = 40;
  for (let r = 0; r < d.qr.size; r++) for (let c = 0; c < d.qr.size; c++) if (d.qr.dark[r * d.qr.size + c]) p.fill(x0 + c * cell, y0 + (d.qr.size - 1 - r) * cell, cell, cell, 0);
  p.text(L, 62, `Screening forms ${d.number} · version ${d.version} · issued ${longDate(d.issuedOn)} · verification code ${d.code}`, 8, true);
  p.text(L, 50, `Verify at ${d.verifyPage} by the code or the document number; only what the University discloses is shown. A field left blank is not held by the University and is filled by hand.`, 7.5, false, GREY);
}

/** the faculty group ticked on the screening form: A Arts, Law · B Soc. Sc, Mgt. Sc · C Edu., Scs., CHS */
export function facultyTick(faculty: string | null): string | null {
  const f = (faculty ?? "").toLowerCase();
  if (/law/.test(f)) return "Law";
  if (/art/.test(f)) return "Arts";
  if (/social/.test(f)) return "Soc. Sc";
  if (/management|admin|business/.test(f)) return "Mgt. Sc";
  if (/educ/.test(f)) return "Edu.";
  if (/health|medic|clinical|nursing|pharm|dent|allied/.test(f)) return "CHS";
  if (/scien|engineer|agric|environ|comput/.test(f)) return "Scs.";
  return null;
}

/** the five pages as one PDF */
export function screeningFormsPdf(input: FormsInput): Uint8Array {
  const { prefill: pf, form: f } = input;
  const a = (k: string) => (input.answers[k] ?? "").trim();
  const sexWord = pf.sex === "M" ? "Male" : pf.sex === "F" ? "Female" : pf.sex ?? "";
  const dob = a("date_of_birth") || pf.date_of_birth || "";
  const age = ageOn(dob);
  const state = a("state_of_origin") || pf.state_of_origin || "";
  const lga = a("lga") || pf.lga || "";
  const nationality = a("nationality") || "";
  const name = `${pf.other_names} ${pf.surname}`.trim();
  const signedOn = f.declaration_at ?? f.submitted_at;
  const signature = signedOn ? `Signed on the portal, ${longDate(signedOn)}` : "";
  const datePaid = input.acceptancePaidOn ? dmy(input.acceptancePaidOn).split("-").reverse().join("-") : "";
  const level = pf.entry_mode === "DIRECT_ENTRY" ? "200" : "100";
  const mode = pf.entry_mode === "DIRECT_ENTRY" ? "Direct Entry" : words(pf.entry_mode);
  const other = pf.other_names.trim().split(/\s+/);
  const firstName = other[0] ?? "";
  const middleName = other.slice(1).join(" ");

  /* ── page 1 · Form A ── */
  const p1 = new Page();
  let y = A4.h - 52;
  crestAt(p1, L, y - 62, 66, input.crest);
  p1.textCenter(CX + 30, y - 14, UNIVERSITY, 13, true);
  p1.textCenter(CX + 30, y - 29, "(Office of the Registrar)", 10);
  p1.textCenter(CX + 30, y - 50, "FORM: A", 9, true);
  y -= 96;
  p1.text(L, y, "Pin No :", 10.5, true); p1.text(L + 46, y, pf.application_no, 10.5);
  p1.text(R - 130, y, "Date Paid:", 10.5, true); p1.text(R - 72, y, datePaid, 10.5);
  y -= 36;
  p1.textCenter(CX, y, "THIS FORM IS TO BE COMPLETED BY EACH NEW STUDENT", 11, true);
  p1.textCenter(CX, y - 15, "BEFORE FULL REGISTRATION", 11, true);
  y -= 44;
  p1.textCenter(CX, y, `JAMB NO: ${pf.jamb_reg_no}`, 10);
  y -= 34;
  p1.text(L, y, "SESSION:", 10, true); p1.text(L + 52, y, pf.session, 10);
  y -= 22;
  const formA: [string, string][] = [
    ["1. Surname:", pf.surname], ["2. Other names:", pf.other_names], ["3. Sex:", sexWord], ["4. Nationality:", nationality], ["5. State:", state], ["6. LGA:", lga],
    ["7. Marital Status:", a("marital_status")], ["8. Course Admitted into:", pf.programme], ["9. Faculty:", pf.faculty ?? ""],
    ["Address of Sponsor(Home):", a("sponsor_address")], ["Postal Address:", a("postal_address")],
  ];
  for (const [k, v] of formA) { const ny = kv(p1, L, y, k, v, W, 10); y = Math.min(y - 21, ny - 7); }
  y -= 8;
  dotted(p1, L, y, "Student's Signature:", 310, signature); dotted(p1, L + 330, y, "Date:", W - 330, signedOn ? longDate(signedOn) : "");
  y -= 40;
  dotted(p1, L, y, "Name of Reg. Officer:", 230); dotted(p1, L + 240, y, "Sign:", 130); dotted(p1, L + 380, y, "Date:", W - 380);
  verification(p1, input);
  footer(p1, input, 1);

  /* ── page 2 · Screening of Fresh Undergraduate Students · Sections A and B ── */
  const p2 = new Page();
  y = A4.h - 40;
  crestAt(p2, CX - 31, y - 62, 62, input.crest);
  y -= 78;
  headerName(p2, y, 14);
  y -= 31;
  underlined(p2, L + 40, y, "SCREENING OF FRESH UNDERGRADUATE STUDENTS.", 11);
  y -= 20;
  p2.text(L, y, "Pin No", 10, true); p2.text(L, y - 12, `: ${pf.application_no}`, 10);
  p2.text(L + 150, y, "JAMB NO", 10, true); p2.text(L + 150, y - 12, `: ${pf.jamb_reg_no}`, 10);
  p2.text(L + 300, y, "Date Paid:", 10, true); p2.text(L + 358, y, datePaid, 10);
  y -= 34;
  const tick = facultyTick(pf.faculty);
  const groups: [string, string[]][] = [["A", ["Arts", "Law"]], ["B", ["Soc. Sc", "Mgt. Sc"]], ["C", ["Edu.", "Scs.", "CHS"]]];
  let gx = L + 10;
  for (const [g, items] of groups) {
    p2.text(gx + (items.length * 44) / 2 - 3, y, g, 9.5, true);
    items.forEach((it, i) => { const x = gx + i * 44; p2.text(x, y - 13, it, 8.5); p2.rule(x, y - 15, x + it.length * 4.6, y - 15, 0.4, 0); tickBox(p2, x + 2, y - 30, tick === it); });
    gx += items.length * 44 + 14;
  }
  passportBox(p2, R - 74, y - 64, 74, 90, input.passport);
  y -= 46;
  const notes = ["(Ticked as appropriate)", "(To be completed in Triplicate.)", "One copy to the Registrar (Academic Office)", "One copy to the Dean of Faculty", "One copy to the Head of Department"];
  for (const n of notes) { p2.text(L, y, n, 8.5); y -= 11; }
  y = p2.paragraph(L, y, "Every Fresh Undergraduate, Remedial Science and Pre-French candidate must undergo screening by the Screening Committee before Registration as a student. Please complete the form below, present it to and appear before the screening committee personally. You must bring to the screening, originals of your academic qualifications, original of UME result slip, certificate of state of origin, Birth certificate/Declaration of Age, Marriage certificate/Declaration, change of name(s) where applicable.", W - 84, 8.5, 1.3);
  y -= 8;
  underlined(p2, L, y, "SECTION A: PERSONAL DATA", 10.5);
  y -= 20;
  const colW = 240;
  const left: [string, string][] = [
    ["SURNAME:", pf.surname], ["OTHER NAMES (in full):", pf.other_names], ["MAIDEN NAME:", a("maiden_name")], ["DATE OF BIRTH:", dmy(dob)], ["AGE LAST BIRTHDAY:", age == null ? "" : String(age)],
    ["SEX:", sexWord], ["ADDRESS:", a("home_address")], ["MODE OF ADMISSION:", mode],
  ];
  const right: [string, string][] = [
    ["LGA:", lga], ["STATE OF ORIGIN:", state], ["NATIONALITY:", nationality], ["RELIGION:", a("religion")], ["MARITAL STATUS:", a("marital_status")],
    ["WORKING EXPERIENCE IF ANY:", a("working_experience") || "NONE"], ["SPONSOR NAME:", a("sponsor_name")], ["SPONSOR ADDRESS:", a("sponsor_address")],
  ];
  let yl = y;
  for (const [k, v] of left) { const ny = kv(p2, L, yl, k, v, colW, 9.5); yl = Math.min(yl - 19, ny - 6); }
  let yr = y;
  for (const [k, v] of right) { const ny = kv(p2, L + colW + 14, yr, k, v, W - colW - 14, 9.5); yr = Math.min(yr - 19, ny - 6); }
  y = Math.min(yl, yr) - 4;
  p2.box(L, y - 30, W, 30, 0.2);
  underlined(p2, L + 4, y - 12, "SECTION B: ACADEMIC RECORD", 10);
  p2.text(L + 4, y - 25, "INSTITUTIONS ATTENDED WITH DATES AND QUALIFICATIONS OBTAINED", 9.5, true);
  y -= 30;
  const instRows = input.institutions.filter((i) => i.name.trim()).map((i) => [i.name, i.from_year == null ? "" : String(i.from_year), i.to_year == null ? "" : String(i.to_year), i.certificate ?? "", i.award_year == null ? "" : String(i.award_year)]);
  while (instRows.length < 2) instRows.push(["", "", "", "", ""]);
  y = table(p2, L, y, [190, 52, 52, 120, W - 414], [["Name of Inst.", "Year of Study", "<", "Certificates awarded", "Year of Award"], ["", "From", "To", "", ""]], instRows, 9);
  footer(p2, input, 2);

  /* ── page 3 · Section C, membership, declaration, Section D ── */
  const p3 = new Page();
  y = A4.h - 52;
  p3.box(L, y - 30, W, 30, 0.2);
  underlined(p3, L + 4, y - 12, "SECTION C: ACADEMIC RECORD", 10);
  p3.text(L + 4, y - 25, "O-LEVEL RESULTS WITH DATES", 9.5, true);
  y -= 30;
  const olRows = input.olevel.map((r) => [r.exam_body, r.subject, r.exam_number ?? "", r.grade, r.exam_year == null ? "" : String(r.exam_year)]);
  while (olRows.length < 9) olRows.push(["", "", "", "", ""]);
  y = table(p3, L, y, [95, 160, 100, 64, W - 419], [["EXAM TYPE/BODY .", "SUBJECTS", "EXAM. NUMBER", "GRADES", "YEAR OF AWARD"]], olRows, 9);
  y -= 26;
  dotted(p3, L, y, "Membership of any Association, Club, Union, Society etc.", W, f.membership ?? "", 9.5);
  y -= 34;
  p3.text(L, y, "DECLARATION:", 10.5, true);
  y -= 14;
  y = p3.paragraph(L, y, `I ${name} hereby declare that the information given on this form is to the best of my knowledge correct, and that, I am bound by the Ordinances, Statutes and Regulations of the University, and that if at any time it is discovered that any of the information provided is false or incorrect, I will be required to withdraw from the institution or be liable to prosecution or both.`, W, 10, 1.35);
  y -= 14;
  dotted(p3, L, y, "Signature:", 300, signature); dotted(p3, L + 320, y, "Date:", W - 320, signedOn ? longDate(signedOn) : "");
  y -= 40;
  underlined(p3, L, y, "SECTION D: FOR OFFICIAL USE ONLY", 10.5);
  y -= 18;
  p3.text(L, y, "1.  SCREENING RESULT", 10, true);
  y -= 15;
  const result = f.state === "SUCCESSFUL" ? "YOU HAVE BEEN SUCCESSFULLY SCREENED. YOU CAN GO AHEAD AND PAY SCHOOL FEES AND COMMENCE REGISTRATION USING YOUR REGISTRATION NUMBER."
    : f.state === "UNSUCCESSFUL" ? `SCREENING UNSUCCESSFUL. ${(f.decision_reason ?? "").toUpperCase()}` : "";
  y = result ? p3.paragraph(L + 12, y, result, W - 90, 10, 1.35) : (p3.rule(L + 12, y - 2, R, y - 2, 0.5, 0.5), p3.rule(L + 12, y - 16, R, y - 16, 0.5, 0.5), y - 30);
  y -= 8;
  p3.text(L, y, "2.  NAME AND SIGNATURE OF CHAIRMAN", 10, true);
  y -= 26;
  dotted(p3, L, y, "DATE:", 230, f.decided_at ? longDate(f.decided_at) : "", 10); dotted(p3, L + 260, y, "STAMP", W - 260, f.decided_office ? `Decided on the portal · ${f.decided_office}` : "", 10);
  footer(p3, input, 3);

  /* ── page 4 · Supplementary Biodata Form ── */
  const p4 = new Page();
  y = A4.h - 52;
  headerName(p4, y, 14);
  y -= 22;
  crestAt(p4, CX - 24, y - 48, 48, input.crest);
  y -= 68;
  underlined(p4, CX - 92, y, "SUPPLEMENTARY BIODATA FORM", 11);
  y -= 14;
  p4.textCenter(CX, y, "(To be completed and returned to Faculty, Department, Academic Office, Students Affairs Division and Security Unit)", 8.5);
  y -= 26;
  const vx = L + 232;
  const num = (n: string, label: string, value: string, lead = 21) => {
    p4.text(L + 10, y, n, 10); p4.text(L + 34, y, label, 10);
    const below = L + 34 + textWidth(label, 10) + 8 > vx;
    let yy = below ? y - 14 : y;
    if (!(value || "").trim()) { p4.rule(vx, yy - 2, R, yy - 2, 0.5, 0.6); y = Math.min(y - lead, yy - 21); return; }
    const ls = wrap(value, R - vx, 10);
    for (const l of ls) { p4.text(vx, yy, l, 10); yy -= 13; }
    y = Math.min(y - lead, yy - 8);
  };
  num("1.", "Surname:", pf.surname);
  num("2.", "Other Names:", pf.other_names);
  num("3.", "State of Origin:", state);
  num("4.", "Local Government Area:", lga);
  num("5.", "Nationality:", nationality);
  num("6.", "Date and Place of Birth:", [dmy(dob), a("place_of_birth")].filter(Boolean).join(" / "));
  num("7.", "Gender:", sexWord);
  num("8.", "Department:", pf.department ?? "");
  num("9.", "Faculty:", pf.faculty ?? "");
  num("10.", "Matriculation:", pf.jamb_reg_no);
  num("11.", "Name of Primary School Attended:", a("primary_school"));
  num("", "Fees Paid Per Term:", a("primary_fees_per_term"));
  num("12.", "Name of Secondary School Attended:", a("secondary_school"));
  num("", "Fees Paid Per Term:", a("secondary_fees_per_term"));
  num("13.", "Profession of Parent/Guardian:", a("parent_profession"));
  num("14.", "Estimated annual income of Parent/Guardian:", a("parent_income"));
  p4.text(L + 10, y, "15.", 10); p4.text(L + 34, y, "Name and Address of Parent/Guardian:", 10);
  y -= 19;
  for (const [k, v] of [["Name:", a("guardian_name")], ["Address:", a("guardian_address")], ["Phone No:", a("guardian_mobile")], ["Email:", a("guardian_email") || "NIL"]] as [string, string][]) {
    const ny = kv(p4, L + 60, y, k, v, W - 60, 10); y = Math.min(y - 18, ny - 5);
  }
  y -= 6;
  p4.text(L + 34, y, "Next of Kin:", 10, true); p4.text(L + 100, y, [a("kin_name"), a("kin_relationship"), a("kin_mobile")].filter(Boolean).join(" · ") || pf.next_of_kin || "", 10);
  y -= 30;
  p4.text(L + 34, y, "Declaration:", 10, true);
  y -= 22;
  y = p4.paragraph(L + 34, y, `I, ${name} hereby declare that the information given above is to the best of my knowledge correct, and that I am bound by the Regulations of the University, and that if at any time it is discovered that any of the information provided is false or incorrect, I shall be summarily expelled from the University.`, W - 34, 10, 1.35);
  y -= 14;
  dotted(p4, L + 34, y, "Student's Signature:", 300, signature); dotted(p4, L + 350, y, "Date:", W - 350, signedOn ? longDate(signedOn) : "");
  footer(p4, input, 4);

  /* ── page 5 · Student Data Capture Form (block letters) ── */
  const p5 = new Page();
  const up = (s: string) => (s || "").toUpperCase();
  y = A4.h - 40;
  p5.box(L, y - 46, 150, 46, 0.3);
  p5.text(L + 8, y - 14, "JAMB REG. NO:", 9, true);
  p5.text(L + 8, y - 34, pf.jamb_reg_no.toUpperCase(), 11);
  crestAt(p5, CX - 26, y - 54, 52, input.crest);
  passportBox(p5, R - 78, y - 96, 78, 96, input.passport, "PASSPORT");
  y -= 72;
  p5.textCenter(CX, y, UNIVERSITY, 12.5, true);
  y -= 14;
  p5.textCenter(CX, y, `DEPARTMENT OF ${up(pf.department ?? "")}`, 10, true);
  y -= 22;
  underlined(p5, CX - 78, y, "STUDENT DATA CAPTURE FORM", 11);
  y -= 16;
  p5.text(L, y, "Instructions: Please, study carefully before you fill this form", 8, false, GREY);
  y -= 13;
  p5.text(L, y, "Fill this Form using ONLY BLOCK LETTERS (Capital Letters)", 8, false, GREY);
  p5.text(L + 250, y, "MATRIC NO:", 10, true); p5.rule(L + 312, y - 2, R, y - 2, 0.5, 0.5); p5.text(L + 316, y + 1, "ISSUED AFTER REGISTRATION", 7.5, false, GREY);
  y -= 26;
  /** a row of dotted fields: label, value, share of the width */
  const row = (items: [string, string, number][], size = 8.5) => {
    const total = items.reduce((s, i) => s + i[2], 0);
    let x = L;
    const tallest = Math.max(...items.map(([label, value, share]) => wrap(up(value), (W * share) / total - textWidth(label, size, true) - 8, 9).length));
    for (const [label, value, share] of items) {
      const w = (W * share) / total;
      p5.text(x, y, label, size, true);
      const vx2 = x + textWidth(label, size, true) + 5;
      const ls = wrap(up(value), w - (vx2 - x) - 6, 9);
      let yy = y;
      for (const l of ls) { p5.text(vx2 + 2, yy + 1, l, 9); p5.rule(vx2, yy - 2, x + w - 6, yy - 2, 0.4, 0.55); yy -= 13; }
      for (let k = ls.length; k < tallest; k++) { p5.rule(vx2, yy - 2, x + w - 6, yy - 2, 0.4, 0.55); yy -= 13; }
      x += w;
    }
    y -= 13 * tallest + 8;
  };
  row([["FIRSTNAME:", firstName, 1], ["MIDDLENAME:", middleName, 1], ["SURNAME:", pf.surname, 1]]);
  row([["(NICK/PET/ALIAS) NAMES:", a("preferred_name"), 1], ["COURSE OF STUDY:", pf.programme, 1]]);
  row([["SEX:", sexWord.slice(0, 1), 0.5], ["LEVEL:", `${level}L`, 0.6], ["DATE OF BIRTH:", dmy(dob).replace(/-/g, "/"), 1.1], ["PRESENT AGE:", age == null ? "" : String(age), 0.8]]);
  row([["L.G.A.:", lga, 1], ["STATE:", state, 1], ["NATIONALITY:", nationality, 1]]);
  row([["MODE OF ENTRY:", mode, 1], ["MARITAL STATUS:", a("marital_status"), 1], ["BLOOD GROUP:", a("blood_group"), 0.8]]);
  row([["NO OF CHILDREN:", a("children") || "NIL", 0.9], ["RELIGION:", a("religion"), 1.1], ["TRIBE:", a("ethnic_group"), 1]]);
  row([["PHONE NUMBER:", a("mobile") || pf.phone, 1], ["BACK-UP PHONE NO:", a("alt_mobile"), 1]]);
  row([["E-MAIL:", a("personal_email") || pf.email, 1.2], ["BANKERS:", a("bank_name"), 1]]);
  row([["BANK SORT CODE:", a("bank_sort_code"), 1], ["BANK ACCOUNT NO:", a("bank_account_no"), 1]]);
  row([["BANK LOCATION:", a("bank_location"), 1]]);
  row([["WORKING EXPERIENCE : (Rank, Place & Duration)", a("working_experience"), 1]]);
  row([["POSTAL ADDRESS:", a("postal_address"), 1]]);
  row([["PERMANENT HOME ADDRESS (Village):", a("home_address"), 1]]);
  row([["SPONSOR NAME:", a("sponsor_name"), 1]]);
  row([["SPONSORS ADDRESS:", a("sponsor_address"), 1]]);
  row([["SPORTS:", a("extracurricular"), 1]]);
  row([["HOBBIES/SKILLS/HANDWORK:", a("hobbies"), 1]]);
  row([["YEAR OF GRADUATION FROM SECONDARY SCHOOL:", a("secondary_graduation_year"), 1]]);
  row([["NAME OF SECONDARY SCHOOL ATTENDED:", a("secondary_school"), 1]]);
  row([["(For D.E. Students Only) NAME OF C.O.E./POLYTECHNIC/INSTITUTION OF A' LEVEL/SCHOOL ATTENDED:", a("alevel_institution"), 1]], 7.5);
  row([["YEAR OF GRADUATION FROM 'A' LEVEL:", a("alevel_graduation_year"), 1]]);
  footer(p5, input, 5);

  return pdf([p1, p2, p3, p4, p5], `Screening forms ${pf.application_no}`);
}

/** a data URL's bytes as an image for pdf-write, when it is a JPEG; otherwise null (PNG is not embedded) */
export function imageFromDataUrl(dataUrl: string | null | undefined, jpegSize: (d: Uint8Array) => { width: number; height: number } | null): Image | null {
  if (!dataUrl || !/^data:image\/jpe?g;base64,/i.test(dataUrl)) return null;
  try {
    const b64 = dataUrl.slice(dataUrl.indexOf(",") + 1);
    const data = new Uint8Array(Buffer.from(b64, "base64"));
    const size = jpegSize(data);
    return size ? { data, width: size.width, height: size.height } : null;
  } catch {
    return null;
  }
}
