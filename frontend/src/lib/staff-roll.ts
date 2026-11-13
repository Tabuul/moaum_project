/**
 * V750: the nominal roll — the University's authentic list of staff (November 2026), as both staff uploads now read it.
 *
 * The roll is three Word tables: the teaching staff (17 columns, PNO), the senior non-teaching staff and the junior staff (16 columns
 * each, CURRENT POSTING in place of DEPARTMENT and FAC-COLL-DIR). The junior roll numbers its staff under JP-NO — its title line
 * says SENIOR NON-TEACHING, so the heading is what tells. An upload takes the Excel template (the same columns) or the Word roll as
 * issued, and still the sheet the uploads read before (Full Names, PNO, …, CONUASS / CONTISS).
 *
 * This file holds the columns, how a heading row is recognised (case, spaces, _ and - aside), a row turned into what the API reads
 * (iam.import_lecturers / iam.import_staff read the cells themselves: day-first dates, NA, notes), the words for what an upload did,
 * the result as a sheet, and a reader for the tables of a .docx. The screens share it.
 */
import { inflate, unescapeXml, zipEntries } from "./xlsx.ts";
import type { Cell, SheetSpec } from "./xlsx-write.ts";

/** the two uploads: the teaching staff, and the non-teaching staff (senior and junior) */
export type RollKind = "ACADEMIC" | "NON_ACADEMIC";
/** the three templates, one per roll */
export type RollTemplate = "ACADEMIC" | "SENIOR" | "JUNIOR";

export type RollField =
  | "sno" | "first_name" | "middle_name" | "last_name" | "pno" | "jp_no" | "sex" | "date_of_birth" | "email" | "phone" | "lga"
  | "state" | "date_first_appointment" | "date_of_confirmation" | "date_of_last_promotion" | "present_rank" | "department"
  | "faculty" | "posting" | "unit" | "full_names" | "conuass" | "contiss";

/** one column of a template: its heading as the roll prints it, the key the API reads, and what to write in it */
export interface RollColumn { head: string; field: RollField; note: string }

const col = (head: string, field: RollField, note: string): RollColumn => ({ head, field, note });
const DAY_FIRST = "Day first, as the roll writes it: 25/12/1970 is 25 December 1970.";
const DATE_OR_NOTE = "Day first (1/2/2010 is 1 February 2010), NA, or a note such as (Transfer of Service) Another University: a note is kept with the record.";

function columns(t: RollTemplate): RollColumn[] {
  const number = t === "JUNIOR"
    ? col("JP-NO", "jp_no", "The junior staff number: 858 or JP858. The staff id is JP and the digits, a series of its own, never merged with the P number of the same digits.")
    : col("PNO", "pno", "The staff number: 99029 or P99029. The staff id is P and the digits.");
  const head = [
    col("SNO", "sno", "The serial number. It may be blank; the upload does not read it."),
    col(t === "SENIOR" ? "FIRST_NAME" : "FIRST NAME", "first_name", "The first name."),
    col("MIDDLE NAME", "middle_name", "The middle name or names. It may be blank."),
    col("LAST-SURNAME", "last_name", "The surname."),
    number,
    col("SEX", "sex", "M or F."),
    col("DATE OF BIRTH", "date_of_birth", DAY_FIRST),
    col(t === "ACADEMIC" ? "E-MAIL-PERSONAL" : "E-MAIL", "email", "Written only where the portal has no e-mail for the person. A different one is reported on the result, never written over the one on record."),
    col("PHONE NO", "phone", "Written only where the portal has no phone for the person. A different one is reported, never written."),
    col("LGA", "lga", "The local government area of origin."),
    col("STATE", "state", "The state of origin."),
    col("DATE OF 1ST APPT-RANK", "date_first_appointment", `The date of first appointment. ${DAY_FIRST}`),
    col("DATE OF CONFIRMATION", "date_of_confirmation", DATE_OR_NOTE),
    col("DATE OF LAST PROMOTION", "date_of_last_promotion", DATE_OR_NOTE),
    col("PRESENT RANK", "present_rank", "The rank held now."),
  ];
  return t === "ACADEMIC"
    ? [...head,
       col("DEPARTMENT", "department", "The department, by its name or code as on the portal. A new lecturer is given the lecturer office in it; a lecturer on record whose department changes has the office moved to it."),
       col("FAC-COLL-DIR", "faculty", "The faculty, college or directorate.")]
    : [...head, col("CURRENT POSTING", "posting", "The unit, department or faculty the person works in, as the roll spells it. A new member of staff is placed in it.")];
}

/** the columns of a template, in the roll's order: 17 for the teaching staff, 16 for the senior and the junior staff */
export const ROLL_COLUMNS: Record<RollTemplate, RollColumn[]> = { ACADEMIC: columns("ACADEMIC"), SENIOR: columns("SENIOR"), JUNIOR: columns("JUNIOR") };

export const TEMPLATE_NAME: Record<RollTemplate, string> = {
  ACADEMIC: "Academic (Teaching) staff", SENIOR: "Senior non-teaching staff", JUNIOR: "Junior staff",
};

/** a template workbook: the roll's headings on the first sheet (nothing else — a filled template reads back as it is), and a
 *  second sheet saying what each column takes and what an upload does */
export function rollTemplate(t: RollTemplate): SheetSpec[] {
  const cols = ROLL_COLUMNS[t];
  const academic = t === "ACADEMIC";
  const rules: Cell[][] = [
    ["Dates", "Day first, as the roll writes them: 1/2/2010 is 1 February 2010, never 2 January. Type them as text, or format the date columns as Text before pasting, so Excel does not turn them round."],
    ["NA and blanks", "NA, NIL, N/A (written any way), a blank cell, a cell of dots or dashes, or a spreadsheet error such as #N/A is no value: it never erases what the portal holds. A name cell holding only a title (MR, DR., PROF DR) holds no name either, so it never erases a name on record — except a single bare title-word as the surname, which may be someone's surname."],
    ["Names written as a query", "A name cell the roll writes as a query (with a question mark, or two names joined by \"or\") is not written, and the result lists it. A query MIDDLE NAME, like a blank or query FIRST NAME, keeps all the given names on record as they are, the roll's first name too. For someone new, a surname or first name that is blank or a query stops the row (Not loaded): correct it and upload again."],
    ["Given names", "Someone on record: the given names follow the roll when FIRST NAME and MIDDLE NAME are both given. With MIDDLE NAME blank, a first name whose every word is already among the given names on record leaves them as they are; any other first name takes the place of the first of them, and the rest stay (none written twice). A title before the names on record (PROF., DR, …) goes. A blank surname or first name keeps the name on record and is listed; a blank middle name is not listed. Someone new needs a surname and a first name that can be read."],
    ["E-mail and phone", "Filled only where the portal has none. A different e-mail or phone on the roll is reported on the result and left as it is on the portal."],
    ["Staff on record", `Found by the staff number alone, never by name. Uploading the roll again updates them: the names, sex, date of birth, LGA, state, the dates, the present rank and ${academic ? "the department and faculty" : "the current posting"} follow the roll${academic ? ", and a lecturer whose department changes has the lecturer office moved to the new one" : ""}. The same file uploaded twice changes nothing the second time.`],
    ["The other kind of staff", academic
      ? "A staff number on record as non-teaching staff is not loaded here: load them on the non-academic staff desk."
      : "A staff number on record as teaching staff is not loaded here: load them on the teaching staff desk."],
    ["New staff", academic
      ? "Added with a sign-in (the username the staff id) and the lecturer office in their department. A department not on the portal: the row is not loaded. Ask ICT to add the department (Department upload), or correct the DEPARTMENT cell, and upload again."
      : "Added and placed in their posting, with no sign-in and no office. A posting not on the portal: the row is not loaded. Ask ICT to add it or its spelling (or correct the CURRENT POSTING cell), and upload again."],
    ...(academic ? [] : [["Senior and junior staff", "Senior staff are numbered under PNO (P and the digits), junior staff under JP-NO (JP and the digits). Use the template of the roll you are uploading: the heading of the number column is what tells them apart."]] as Cell[][]),
    ["Check, then upload", "The file is checked first and nothing is written: the check shows who is new, who will be updated and how, and what cannot be loaded. Then Upload writes it."],
    ["The Word roll", "The nominal roll as issued (.docx) may be uploaded as it is, in place of this template."],
  ];
  return [
    [TEMPLATE_NAME[t].replace(/[()]/g, ""), [cols.map((c) => c.head)], { headerRows: [0], freezeBelow: 1 }],
    ["Instructions", [
      [`Nominal roll: ${TEMPLATE_NAME[t]}. How to fill the first sheet`],
      [""],
      ["Column", "What to write"],
      ...cols.map((c): Cell[] => [c.head, c.note]),
      [""],
      ["Rule", "What the upload does"],
      ...rules,
    ], { headerRows: [2, 4 + cols.length] }],
  ];
}

// ── the heading row ───────────────────────────────────────────────────────────────────────────────────────────────────────

/** a heading as it is compared: letters and digits only, upper case (E-MAIL-PERSONAL, e_mail personal and EMAILPERSONAL are one) */
const headKey = (s: string) => s.toUpperCase().replace(/[^A-Z0-9]/g, "");

const HEADINGS: [RollField, string[]][] = [
  ["sno", ["SNO", "SN", "SERIALNO", "SNUMBER"]],
  ["first_name", ["FIRSTNAME", "FIRSTNAMES", "FORENAME", "FORENAMES"]],
  ["middle_name", ["MIDDLENAME", "MIDDLENAMES", "OTHERNAME", "OTHERNAMES"]],
  ["last_name", ["LASTSURNAME", "LASTNAME", "SURNAME", "LASTNAMESURNAME"]],
  ["pno", ["PNO", "PNUMBER", "STAFFNO", "STAFFNUMBER", "STAFFID"]],
  ["jp_no", ["JPNO", "JPNUMBER"]],
  ["sex", ["SEX", "GENDER"]],
  ["date_of_birth", ["DATEOFBIRTH", "DOB", "BIRTHDATE"]],
  ["email", ["EMAIL", "EMAILPERSONAL", "EMAILADDRESS", "PERSONALEMAIL"]],
  ["phone", ["PHONENO", "PHONE", "PHONENUMBER", "GSM", "GSMNO", "MOBILE", "MOBILENO"]],
  ["lga", ["LGA", "LGAOFORIGIN"]],
  ["state", ["STATE", "STATEOFORIGIN"]],
  ["date_first_appointment", ["DATEOF1STAPPTRANK", "DATEOF1STAPPT", "DATEOF1STAPPOINTMENT", "DATEOFFIRSTAPPOINTMENT", "DATEOFFIRSTAPPT", "FIRSTAPPOINTMENT"]],
  ["date_of_confirmation", ["DATEOFCONFIRMATION", "CONFIRMATION"]],
  ["date_of_last_promotion", ["DATEOFLASTPROMOTION", "LASTPROMOTION"]],
  ["present_rank", ["PRESENTRANK", "RANK"]],
  ["department", ["DEPARTMENT", "DEPT"]],
  ["faculty", ["FACCOLLDIR", "FACULTY", "FACCOLL", "FACULTYCOLLEGEDIRECTORATE", "FACULTYCOLLEGE"]],
  ["posting", ["CURRENTPOSTING", "POSTING"]],
  ["unit", ["UNIT"]],
  ["full_names", ["FULLNAMES", "FULLNAME", "NAMES", "NAME"]],
  ["conuass", ["CONUASS", "CONUAS", "CONNUAS", "CONNUASS"]],
  ["contiss", ["CONTISS", "CONTIS"]],
];
const FIELD_OF = new Map<string, RollField>(HEADINGS.flatMap(([f, keys]) => keys.map((k): [string, RollField] => [k, f])));

/** a recognised heading row: where each column is and its heading as the file writes it, whether it is the roll's (names in
 *  three cells) or the old sheet's (Full Names), whether it numbers junior staff (JP-NO), and which upload it is for (null when
 *  the headings do not say) */
export interface RollHeader {
  at: Partial<Record<RollField, number>>; heads: Partial<Record<RollField, string>>; roll: boolean; junior: boolean; kind: RollKind | null;
}

/** the row as headings, or null when it is not a heading row of a staff list (it needs a staff number and a name column) */
export function rollHeader(cells: readonly unknown[]): RollHeader | null {
  const at: Partial<Record<RollField, number>> = {};
  const heads: Partial<Record<RollField, string>> = {};
  cells.forEach((c, i) => {
    const f = FIELD_OF.get(headKey(String(c ?? "")));
    if (f && at[f] === undefined) { at[f] = i; heads[f] = String(c).replace(/[\s ]+/g, " ").trim(); }
  });
  const numbered = at.pno !== undefined || at.jp_no !== undefined;
  const roll = at.first_name !== undefined || at.last_name !== undefined || at.middle_name !== undefined;
  if (!numbered || !(roll || at.full_names !== undefined)) return null;
  const junior = at.jp_no !== undefined;
  const kind: RollKind | null = junior || at.posting !== undefined || at.unit !== undefined || at.contiss !== undefined ? "NON_ACADEMIC"
    : at.faculty !== undefined || at.conuass !== undefined || (roll && at.department !== undefined) ? "ACADEMIC"
    : null;
  return { at, heads, roll, junior, kind };
}

/** a recognised file named without its number column: "the junior staff roll", "the old teaching-staff sheet" */
function rollTitle(h: RollHeader): string {
  if (!h.roll) return h.kind === "ACADEMIC" ? "the old teaching-staff sheet" : h.kind === "NON_ACADEMIC" ? "the old non-teaching sheet" : "the old staff sheet";
  if (h.junior) return "the junior staff roll";
  return h.kind === "ACADEMIC" ? "the teaching staff roll" : h.kind === "NON_ACADEMIC" ? "the senior non-teaching staff roll" : "a nominal roll";
}

/** the words for a recognised file: "the junior staff roll (JP-NO)", "the old teaching-staff sheet" */
export function rollName(h: RollHeader): string {
  return h.roll && h.junior ? `${rollTitle(h)} (JP-NO)` : rollTitle(h);
}

/** "A", "A and B", "A, B and C" */
const andList = (xs: string[]) => (xs.length < 2 ? xs.join("") : `${xs.slice(0, -1).join(", ")} and ${xs[xs.length - 1]}`);

/**
 * A file for the other upload, in words for the screen; null when it is for this one. The bracket names the headings the file
 * itself carries that make it the other upload's, as it writes them (the reasons rollHeader gave it its kind): DEPARTMENT and
 * FAC-COLL-DIR on the teaching staff roll, CONUASS on the old teaching-staff sheet; JP-NO and CURRENT POSTING on the junior roll,
 * CURRENT POSTING on the senior roll, Unit or CONTISS on the old non-teaching sheet. JP-NO is named once.
 */
export function wrongRoll(h: RollHeader, kind: RollKind): string | null {
  if (!h.kind || h.kind === kind) return null;
  const tells: RollField[] = h.kind === "ACADEMIC"
    ? [...(h.roll ? ["department" as const] : []), "faculty", "conuass"]
    : ["jp_no", "posting", "unit", "contiss"];
  const named = tells.map((f) => (h.at[f] === undefined ? "" : h.heads[f] ?? "")).filter(Boolean);
  const what = named.length ? `${rollTitle(h)} (${andList(named)})` : rollName(h);
  return h.kind === "ACADEMIC"
    ? `This is ${what}. Upload it on the teaching staff desk.`
    : `This is ${what}. Upload it on the non-academic staff desk.`;
}

// ── the rows ──────────────────────────────────────────────────────────────────────────────────────────────────────────────

/** one row as the API reads it: the roll's keys (the old sheet's for an old file) and the row of the sheet or table it came from */
export type RollRow = { sheet_row: number } & Partial<Record<Exclude<RollField, "sno">, string>>;

const DATE_FIELDS = new Set<RollField>(["date_of_birth", "date_first_appointment", "date_of_confirmation", "date_of_last_promotion"]);

/** a date Excel holds as a serial (days since 30 December 1899) written day first; anything else as it is. A year alone (1990) is
 *  not taken for a serial: serials before 1910 are not read. */
export function excelDate(v: string): string {
  const t = v.trim();
  if (!/^\d{4,5}(\.\d+)?$/.test(t)) return t;
  const n = Math.floor(Number(t));
  if (n < 3654 || n > 73415) return t;
  const d = new Date(Date.UTC(1899, 11, 30) + n * 86400000);
  const p = (x: number) => String(x).padStart(2, "0");
  return `${p(d.getUTCDate())}/${p(d.getUTCMonth() + 1)}/${d.getUTCFullYear()}`;
}

/** the staff id a row names, as the database reads it: JP + digits under JP-NO (or a number written JP…), else P + digits */
export function staffNumberOf(r: Partial<Record<string, unknown>>): string | null {
  const jp = String(r.jp_no ?? "").toUpperCase();
  const fromJp = /[0-9]/.test(jp);
  const raw = fromJp ? jp : String(r.pno ?? "").toUpperCase();
  const junior = fromJp || /^JP/.test(raw.trim());
  const digits = raw.replace(/[^0-9]/g, "");
  return digits ? `${junior ? "JP" : "P"}${digits}` : null;
}

/** a file read: the heading, the rows to send, and the rows held back (a staff number the file already gave) */
export interface RollRead { header: RollHeader; headerRow: number; rows: RollRow[]; repeats: RollResult[] }

/** the first heading row in the first rows of a grid, its index and what it says */
export function findHeader(grid: readonly (readonly unknown[])[], within = 30): { index: number; header: RollHeader } | null {
  for (let i = 0; i < Math.min(grid.length, within); i++) {
    const header = rollHeader(grid[i] ?? []);
    if (header) return { index: i, header };
  }
  return null;
}

/**
 * A grid (a worksheet, or the tables of a Word roll) as the rows an upload sends. Each row carries its row of the sheet (rowNo:
 * by default the grid index + 1). Blank rows, a heading repeated down the file and a title row (no staff number and at most one
 * cell filled) are passed over; any other row is sent, the database reporting one with no staff number. A staff number the file
 * already gave is held back and reported, as the database would report it, named as its first row (then as the upload names it).
 */
export function readRoll(grid: readonly (readonly unknown[])[], rowNo: (i: number) => number = (i) => i + 1): RollRead | null {
  const found = findHeader(grid);
  if (!found) return null;
  const { header, index } = found;
  const fields = (Object.entries(header.at) as [RollField, number][]).filter(([f]) => f !== "sno");
  const rows: RollRow[] = [];
  const repeats: RollResult[] = [];
  const seen = new Map<string, RollRow>();
  for (let i = index + 1; i < grid.length; i++) {
    const cells = grid[i] ?? [];
    if (rollHeader(cells)) continue;                                  // the heading again (a table continued on a new page)
    const row: RollRow = { sheet_row: rowNo(i) };
    let filled = 0;
    for (const [f, c] of fields) {
      let v = String(cells[c] ?? "").replace(/[\s ]+/g, " ").trim();
      if (DATE_FIELDS.has(f)) v = excelDate(v);
      row[f as Exclude<RollField, "sno">] = v;
      if (v) filled++;
    }
    if (!filled) continue;
    const number = staffNumberOf(row);
    if (!number && filled < 2) continue;                             // a title row inside the table: one cell across it
    if (number) {
      const first = seen.get(number);
      if (first !== undefined) {
        repeats.push({ row: row.sheet_row, staffNumber: number, name: rowName(first), action: "ERROR", changes: [], kept: [], unresolved: [],
          error: `${number} is on this upload already, at row ${first.sheet_row}`, repeatOf: first.sheet_row });
        continue;
      }
      seen.set(number, row);
    }
    rows.push(row);
  }
  return { header, headerRow: rowNo(index), rows, repeats };
}

function rowName(r: RollRow): string {
  const given = [r.first_name, r.middle_name].filter(Boolean).join(" ");
  return r.last_name || given ? [r.last_name, given].filter(Boolean).join(", ") : (r.full_names ?? "");
}

/** the staff numbers of a file, for its "on the portal but not on this roll" */
export function rollNumbers(read: RollRead): string[] {
  const out = new Set<string>();
  for (const r of read.rows) { const n = staffNumberOf(r); if (n) out.add(n); }
  for (const r of read.repeats) if (r.staffNumber) out.add(r.staffNumber);
  return [...out];
}

// ── what an upload did ────────────────────────────────────────────────────────────────────────────────────────────────────

export type RollAction = "CREATED" | "UPDATED" | "UNCHANGED" | "SKIPPED" | "ERROR";
export interface RollChange { field: string; from: string | null; to: string | null }
export interface RollKept { field: string; onRecord: string | null; onRoll: string | null; reason?: string | null; givenTo?: string | null }
/** a cell the upload did not take: a place not on the portal, a value it could not read, or a name left blank or written as a
 *  query (reason BLANK or QUERY) — the record keeps what it held */
export interface RollUnresolved { field: string; onRoll?: string | null; reason?: string | null }
/** one row's result, as the upload functions return it */
export interface RollResult {
  row: number | null; staffNumber: string | null; name: string; action: RollAction; cadre?: string | null; personId?: string | null;
  changes: RollChange[]; kept: RollKept[]; unresolved: RollUnresolved[]; endedOn?: string | null; error: string | null;
  /** a staff number the file already gave: the row that gave it first (held back on this screen, never sent) */
  repeatOf?: number | null;
}
/** a member of staff on the portal whose number is not on the roll (hrm.roll_absent) */
export interface RollAbsent { person_id: string; staff_number: string; name: string; rank: string | null; posting: string | null }

/** an upload's counts and results, summed over its chunks */
export interface RollTally {
  dry: boolean; rows: number; created: number; updated: number; unchanged: number; skipped: number; errors: number;
  credentialed: number; granted: number; notPlaced: number; failedRows: number; missing: string[]; firstError: string | null; results: RollResult[];
}

export function emptyTally(dry: boolean, repeats: RollResult[] = []): RollTally {
  return { dry, rows: repeats.length, created: 0, updated: 0, unchanged: 0, skipped: 0, errors: repeats.length, credentialed: 0, granted: 0,
    notPlaced: 0, failedRows: 0, missing: [], firstError: firstProblem(repeats), results: [...repeats] };
}

/** the first row, in row order, that would not load or did not, in words: "Row 7 (P1): …" */
export function firstProblem(results: RollResult[]): string | null {
  const r = byRow(results).find((x) => x.action === "SKIPPED" || x.action === "ERROR");
  return r ? `Row ${r.row ?? "?"}${r.staffNumber ? ` (${r.staffNumber})` : ""}: ${r.error ?? ""}` : null;
}

/** the e-mail addresses the rows of an upload were given, {address: staff number} — sent with each later request of the upload */
export function claimedBy(results: RollResult[], claimed: Record<string, string> = {}): Record<string, string> {
  const out = { ...claimed };
  for (const r of results) {
    for (const c of r.changes ?? []) if (c.field === "email" && c.to && r.staffNumber) out[String(c.to).trim().toLowerCase()] = r.staffNumber;
  }
  return out;
}

const num = (v: unknown) => (Number.isFinite(Number(v)) ? Number(v) : 0);

/** one chunk's answer added to the tally (a new tally; the old one is left as it was) */
export function addChunk(t: RollTally, j: Record<string, unknown>): RollTally {
  const missing = [...t.missing];
  for (const m of String(j.missing_departments ?? j.unplaced_units ?? "").split(", ")) if (m && !missing.includes(m)) missing.push(m);
  const results = Array.isArray(j.results) ? (j.results as RollResult[]).map((r) => ({
    ...r, changes: r.changes ?? [], kept: r.kept ?? [], unresolved: r.unresolved ?? [], error: r.error ?? null,
  })) : [];
  return {
    ...t,
    rows: t.rows + num(j.rows), created: t.created + num(j.created), updated: t.updated + num(j.updated), unchanged: t.unchanged + num(j.unchanged),
    skipped: t.skipped + num(j.skipped), errors: t.errors + num(j.errors), credentialed: t.credentialed + num(j.credentialed),
    granted: t.granted + num(j.granted), notPlaced: t.notPlaced + num(j.no_department ?? j.unplaced),
    missing, firstError: firstProblem([...t.results, ...results]) ?? t.firstError ?? (j.first_error ? String(j.first_error) : null),
    results: [...named(t.results, results), ...results],
  };
}

/** the rows held back as repeats, named as the upload named the row that gave the number first */
function named(held: RollResult[], landed: RollResult[]): RollResult[] {
  const names = new Map(landed.filter((r) => r.staffNumber && r.row != null).map((r) => [`${r.staffNumber}@${r.row}`, r.name]));
  return held.map((r) => (r.repeatOf != null && names.has(`${r.staffNumber}@${r.repeatOf}`) ? { ...r, name: names.get(`${r.staffNumber}@${r.repeatOf}`) ?? r.name } : r));
}

/** a chunk that never landed: its rows counted, so the screen says to upload again */
export function chunkFailed(t: RollTally, rows: number, why: string | null): RollTally {
  return { ...t, failedRows: t.failedRows + rows, firstError: t.firstError ?? why };
}

/** the results in row order */
export function byRow(results: RollResult[]): RollResult[] {
  return [...results].sort((a, b) => (a.row ?? Number.MAX_SAFE_INTEGER) - (b.row ?? Number.MAX_SAFE_INTEGER));
}

const ACTION_WORDS: Record<RollAction, [string, string]> = {
  CREATED: ["Added", "New: to be added"],
  UPDATED: ["Updated", "To be updated"],
  UNCHANGED: ["Unchanged", "Unchanged"],
  SKIPPED: ["Not loaded", "Will not be loaded"],
  ERROR: ["Error", "Error"],
};
/** what happened to a row, or (dry) what the upload will do with it */
export function actionWord(a: RollAction, dry = false): string {
  return ACTION_WORDS[a]?.[dry ? 1 : 0] ?? a;
}
export const ACTION_PILL: Record<RollAction, "ok" | "info" | "grey" | "warn" | "bad"> = {
  CREATED: "ok", UPDATED: "info", UNCHANGED: "grey", SKIPPED: "warn", ERROR: "bad",
};

const FIELD_WORDS: Record<string, string> = {
  surname: "Surname", given_names: "Given names", first_name: "First name", middle_name: "Middle name", last_name: "Surname",
  lecturer_office: "Lecturer office", pno: "Number on the roll (digits)", sex: "Sex", date_of_birth: "Date of birth", lga: "LGA",
  state_of_origin: "State", date_first_appointment: "First appointment", date_of_confirmation: "Confirmation",
  confirmation_note: "Confirmation note", date_of_last_promotion: "Last promotion", promotion_note: "Last promotion note",
  present_rank: "Present rank", category: "Category", cadre: "Cadre", salary_scale: "Salary scale", contiss_step: "CONTISS step",
  conuass_step: "CONUASS step", home_department: "Department", home_faculty: "Faculty", home_unit: "Unit",
  unit_as_given: "Posting as the roll gives it", email: "E-mail", phone: "Phone", sign_in: "Sign-in", department: "Department",
  faculty: "Faculty", posting: "Current posting", full_names: "Full Names",
};
export function fieldWord(f: string): string {
  return FIELD_WORDS[f] ?? f.replace(/_/g, " ").replace(/^./, (c) => c.toUpperCase());
}

/** a value as the result shows it: a date day first, nothing as a dash */
export function shown(v: unknown): string {
  if (v === null || v === undefined || v === "") return "—";
  const s = String(v);
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  return m ? `${m[3]}/${m[2]}/${m[1]}` : s;
}

/** a change the upload makes: "Department: ACCOUNTING → ADVERTISING"; the lecturer office moved with a new department */
export function changeText(c: RollChange): string {
  if (c.field === "lecturer_office") return `Lecturer office moved: ${shown(c.from)} → ${shown(c.to)}`;
  return `${fieldWord(c.field)}: ${shown(c.from)} → ${shown(c.to)}`;
}

const KEPT_WHY: Record<string, string> = {
  DIFFERS: "differs from the one on the portal, which is kept",
  NOT_AN_EMAIL: "is not an e-mail address",
  NOT_A_PHONE: "could not be read as a phone number (0 and ten digits, or +234 and ten)",
  HELD_BY_ANOTHER: "is held by another person on the portal",
  GIVEN_TO_ANOTHER_ROW: "is given to another row of this file, so it is written for that row only",
  USERNAME_TOO_SHORT: "is shorter than a username may be (three characters), so no sign-in was made",
};
/** a contact (or the sign-in) the roll gives and the upload did not write; a reason these words do not know is shown as given */
export function keptText(k: RollKept): string {
  const why = k.reason === "GIVEN_TO_ANOTHER_ROW" && k.givenTo
    ? `is given to another row of this file (${k.givenTo}), so it is written for that row only`
    : KEPT_WHY[k.reason ?? "DIFFERS"] ?? `was not written (${k.reason})`;
  if (k.field === "sign_in") return `Sign-in: the staff id ${why}`;
  return `${fieldWord(k.field)}: the roll's ${shown(k.onRoll)} ${why}${k.reason === "DIFFERS" || !k.reason ? ` (${shown(k.onRecord)})` : ""}`;
}

/** the name cells: one the roll leaves blank keeps the name on record, one it writes as a query is not written */
const NAME_FIELDS = new Set(["first_name", "middle_name", "last_name", "surname", "given_names", "full_names"]);

/** a cell the upload did not take, in words; a field or a reason these words do not know is shown as given */
export function unresolvedText(u: RollUnresolved): string {
  const word = fieldWord(u.field);
  const value = u.onRoll ? shown(u.onRoll) : null;
  if (u.reason === "BLANK" && NAME_FIELDS.has(u.field)) {
    return value && value !== "—" ? `${word} on the roll (${value}) holds no name — kept as on record` : `${word} blank on the roll — kept as on record`;
  }
  if (u.reason === "QUERY" && NAME_FIELDS.has(u.field)) return `${word} on the roll is a query${value ? ` (${value})` : ""} — not written`;
  if (u.reason === "BLANK") return `${word}: blank on the roll — kept as on record`;
  if (u.reason === "QUERY") return `${word}: the roll's ${value ?? "cell"} is a query — not written`;
  if (u.reason) return `${word}: ${value ? `the roll's ${value} ` : ""}not written (${u.reason})`;
  if (u.field === "department" || u.field === "faculty" || u.field === "posting") {
    return value ? `${word}: ${value} is not on the portal` : `${word}: blank`;
  }
  return `${word}: ${value ?? "—"} could not be read`;
}

/**
 * The single "Add staff" forms send one row through the upload (the given names whole, as typed: given_names), checked first as a
 * dry run. What that check says: the row loads (as someone new, or as someone on record the form's list does not show), or why it
 * is refused — the upload's own ERROR or SKIPPED, given with its words: a number on record as the other kind of staff (the
 * database reads the kind, hrm.roll_kind, and names the desk that loads them), a place not on the portal, a name it cannot read.
 */
export function addCheck(j: Record<string, unknown> | null):
  { ok: true; existing: boolean; staffNumber: string | null; renames?: { from: string; to: string } } | { ok: false; title: string; detail?: string } {
  const r = Array.isArray(j?.results) ? (j.results as RollResult[])[0] : undefined;
  if (!r) return { ok: false, title: "That member of staff could not be read.", detail: "Fill in the staff number and both names." };
  if (r.action === "SKIPPED" || r.action === "ERROR") return { ok: false, title: "That member of staff could not be added.", detail: r.error ?? undefined };
  // someone on record whom the Add would rename: the name as it stands and as it would be (the form asks before it does)
  const sur = (r.changes ?? []).find((c) => c.field === "surname");
  const giv = (r.changes ?? []).find((c) => c.field === "given_names");
  if (r.action !== "CREATED" && (sur || giv)) {
    const [toSur, ...rest] = (r.name ?? "").split(", ");
    const toGiv = rest.join(", ");
    const from = [sur ? String(sur.from ?? "") : toSur, giv ? String(giv.from ?? "") : toGiv].filter(Boolean).join(", ");
    return { ok: true, existing: true, staffNumber: r.staffNumber, renames: { from, to: r.name } };
  }
  return { ok: true, existing: r.action !== "CREATED", staffNumber: r.staffNumber };
}

/**
 * What an Add form's upload did, in words: added; already on record and nothing changed; or already on record and updated — with
 * what it did not write said, worded for what was typed: a name read as a query or holding no name, an e-mail or phone that is not
 * one, is held by another person or differs from the one on record (which is kept), and a sign-in not made (a staff id too short).
 */
export function addOutcome(j: Record<string, unknown> | null, id: string): { existing: boolean; text: string; action: RollAction | null } {
  const r = Array.isArray(j?.results) ? (j.results as RollResult[])[0] : undefined;
  if (!r) return { existing: false, text: `${id} added.`, action: null };
  // what the form gave and the upload did not write, worded for what was typed (the form has no roll)
  const held = (r.unresolved ?? []).filter((u) => NAME_FIELDS.has(u.field)).map((u) => {
    const typed = u.onRoll ? ` (${shown(u.onRoll)})` : "";
    return u.reason === "QUERY" ? `${fieldWord(u.field)} typed${typed} read as a query — not written`
      : `${fieldWord(u.field)} typed${typed} holds no name — not written`;
  }).concat((r.kept ?? []).map((k) => {
    const typed = k.onRoll ? ` (${shown(k.onRoll)})` : "";
    switch (k.reason) {
      case "USERNAME_TOO_SHORT": return "no sign-in made: the staff id is shorter than three characters";
      case "NOT_AN_EMAIL": return `E-mail typed${typed} is not an e-mail address — not written`;
      case "NOT_A_PHONE": return `Phone typed${typed} could not be read as a phone number (0 and ten digits, or +234 and ten) — not written`;
      case "HELD_BY_ANOTHER": return `E-mail typed${typed} is held by another person — not written`;
      case "DIFFERS": return `${fieldWord(k.field)} typed${typed} differs from the one on record (${shown(k.onRecord)}), which is kept`;
      default: return `${fieldWord(k.field)} typed${typed} not written${k.reason ? ` (${k.reason})` : ""}`;
    }
  }));
  if (r.action === "CREATED") return { existing: false, text: held.length ? `${id} added (${held.join("; ")}).` : `${id} added.`, action: r.action };
  if (r.action === "UNCHANGED") {
    return { existing: true, action: r.action,
      text: held.length ? `${id} is already on record: nothing changed (${held.join("; ")}).` : `${id} is already on record as entered: nothing changed.` };
  }
  const changed = (r.changes ?? []).map(changeText);
  return { existing: true, action: r.action,
    text: `${id} was already on record, so the record was updated${changed.length ? `: ${changed.join("; ")}` : ""}${held.length ? ` (${held.join("; ")})` : ""}.` };
}

/** a cell of the result sheet, as brandedXlsx (lib/exportbrand) takes it */
type OutCell = string | number | null;

/** the result as a sheet: every row of the file and what happened to it, then the staff on the portal not on the roll */
export function resultSheet(t: RollTally, absent: RollAbsent[] | null): { headers: string[]; rows: OutCell[][] } {
  const headers = ["Row", "Staff id", "Name", t.dry ? "What the upload will do" : "What happened", "Changes", "Contacts and sign-in not written", "Not resolved", "Problem"];
  const rows: OutCell[][] = byRow(t.results).map((r) => [
    r.row ?? "", r.staffNumber ?? "", r.name, actionWord(r.action, t.dry),
    r.changes.map(changeText).join("; "), r.kept.map(keptText).join("; "), r.unresolved.map(unresolvedText).join("; "), r.error ?? "",
  ]);
  for (const a of absent ?? []) {
    rows.push(["", a.staff_number, a.name, "On the portal, not on this roll", [a.rank, a.posting].filter(Boolean).join(" · "), "", "", ""]);
  }
  return { headers, rows };
}

// ── the Word roll ─────────────────────────────────────────────────────────────────────────────────────────────────────────

/**
 * The tables of a .docx as grids of strings, in document order: every w:tbl a table, every w:tr a row, every w:tc a cell whose
 * text is its w:t runs joined (paragraphs and line breaks a space between, whitespace collapsed). A cell spanning columns
 * (gridSpan) is followed by empty cells and a row's leading gridBefore by empty cells, so the columns stay under their headings; a
 * table inside a cell gives its text to that cell. Deleted text (w:delText) is not read.
 */
export function wordTables(xml: string): string[][][] {
  type Open = { rows: string[][]; row: string[] | null; cell: string[] | null; para: string; span: number };
  const tables: string[][][] = [];
  const stack: Open[] = [];
  const collapse = (s: string) => s.replace(/[\s ]+/g, " ").trim();
  const re = /<(\/?)w:(tbl|tr|tc|p|t|tab|br|cr|noBreakHyphen|gridSpan|gridBefore)(?=[\s/>])([^>]*)>/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(xml))) {
    const [, close, tag, attrs] = m;
    const self = attrs.endsWith("/");
    if (tag === "tbl") {
      if (!close) { stack.push({ rows: [], row: null, cell: null, para: "", span: 1 }); continue; }
      const t = stack.pop();
      if (!t) continue;
      const outer = stack[stack.length - 1];
      if (!outer) tables.push(t.rows);
      else if (outer.cell) outer.cell.push(t.rows.map((r) => r.filter(Boolean).join(" ")).filter(Boolean).join(" "));
      continue;
    }
    const top = stack[stack.length - 1];
    if (!top) continue;                                               // outside every table: the title lines
    const val = () => Math.max(0, Math.min(64, Number(/w:val="(\d+)"/.exec(attrs)?.[1] ?? 0)));
    if (tag === "tr") {
      if (!close && !self) top.row = [];
      else if (close && top.row) { top.rows.push(top.row); top.row = null; }
    } else if (tag === "gridBefore") {
      if (top.row && !top.cell) for (let k = val(); k > 0; k--) top.row.push("");
    } else if (tag === "tc") {
      if (!close && !self) { top.cell = []; top.para = ""; top.span = 1; }
      else if (close && top.cell) {
        if (top.para) top.cell.push(top.para);
        top.row?.push(collapse(top.cell.join(" ")));
        for (let k = 1; k < top.span; k++) top.row?.push("");
        top.cell = null; top.para = "";
      }
    } else if (tag === "gridSpan") {
      if (top.cell) top.span = Math.max(1, val());
    } else if (tag === "p") {
      if (close && top.cell) { top.cell.push(top.para); top.para = ""; }
      else if (!close) top.para = "";
    } else if (tag === "t") {
      if (close || self) continue;
      const end = xml.indexOf("</w:t>", re.lastIndex);
      if (end < 0) break;
      if (top.cell) top.para += unescapeXml(xml.slice(re.lastIndex, end));
      re.lastIndex = end + 6;
    } else if (top.cell) {
      top.para += tag === "noBreakHyphen" ? "-" : " ";                // a tab or a line break: a space between words
    }
  }
  return tables;
}

/** the main part of a .docx: word/document.xml, or the part its relationships name */
async function documentXml(buf: ArrayBuffer): Promise<string> {
  let z: ReturnType<typeof zipEntries>;
  try { z = zipEntries(buf); } catch { throw new Error("not a Word document (.docx): there is no ZIP directory in it"); }
  let part = "word/document.xml";
  if (!z[part] && z["_rels/.rels"]) {
    const rels = await inflate(z["_rels/.rels"]);
    for (const r of rels.matchAll(/<Relationship\b[^>]*>/g)) {
      if (!/\/officeDocument"/.test(r[0])) continue;
      const target = /\bTarget="([^"]+)"/.exec(r[0])?.[1];
      if (target) part = target.replace(/^\//, "");
    }
  }
  if (!z[part]) throw new Error("not a Word document (.docx): it has no document part");
  return inflate(z[part]);
}

/** the tables of a .docx as grids of strings (wordTables over its document part) */
export async function docxTables(buf: ArrayBuffer): Promise<string[][][]> {
  return wordTables(await documentXml(buf));
}

/**
 * The Word roll as one grid: the first table whose heading row is a staff list's, then every later table that repeats that
 * heading or carries on with as many columns (a roll split over pages or sections). A row's number is its place in the grid,
 * the heading row 1 and a heading repeated by a later table counted as the row it is (readRoll passes over it).
 */
export function rollGridFromTables(tables: string[][][]): string[][] {
  const start = tables.findIndex((t) => findHeader(t, 5));
  if (start < 0) return [];
  const first = findHeader(tables[start], 5)!;
  const width = tables[start][first.index].length;
  const grid = tables[start].slice(first.index);
  for (const t of tables.slice(start + 1)) {
    const h = findHeader(t, 5);
    if (h) grid.push(...t.slice(h.index));
    else if (t.some((r) => r.length === width)) grid.push(...t);
  }
  return grid;
}
