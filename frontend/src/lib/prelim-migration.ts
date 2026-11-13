/**
 * Old-portal preliminary applicants migrated (V737): one template a programme — Preliminary Technology & Industrial Studies, or
 * Preliminary Sciences — built from what this portal reads (the columns, the programme's own targets, specialisations, O'Level
 * subjects and qualifications, the old portal's status words), with its instructions, an illustrative sample and a data
 * dictionary; the filled file read back into rows of the template's keys; the ranges the file is sent, checked and imported in;
 * the words for what a row is and does; the error report and the history. The programme of an upload is the section it is
 * uploaded in, never the file's own "Programme" cell; the rules are the server's, and this file only carries the rows.
 *
 * V745 (the review of V737): the template carries its programme's code, and a file of the other programme is refused; the dates,
 * numbers and references are Text columns; every sheet names an intended programme as the drop-down takes it; the Applicants
 * sheet is read first and the sheet read is named; O'Level results one a line, and O'Level headings without a sitting number, are
 * read; the import report lists every row; a resumed import counts only what is left; the desk's fee and old number read one way.
 *
 * Pure: only .ts-suffixed imports, so node:test loads it.
 */
import { colName, type Cell, type ListValidation, type SheetSpec } from "./xlsx-write.ts";
import { xlsxWorkbook, type Sheet } from "./xlsx.ts";

/** a cell of a report: text, a number or nothing */
export type ReportCell = string | number | null;
export type Tone = "ok" | "info" | "warn" | "bad" | "grey";

/** the two preliminary programmes an upload is for; a correction moves an application between them and nowhere else */
export const PRELIM_ROUTES = ["PRELIMINARY_TECHNOLOGY", "PRELIMINARY_SCIENCE"] as const;
export type PrelimRoute = (typeof PRELIM_ROUTES)[number];
export const isPrelimMigrationRoute = (r: string | null | undefined): r is PrelimRoute => PRELIM_ROUTES.includes(r as PrelimRoute);
/** the other preliminary programme: Technology ⇄ Science; anything else has none */
export const otherRoute = (r: string | null | undefined): PrelimRoute | null =>
  r === "PRELIMINARY_TECHNOLOGY" ? "PRELIMINARY_SCIENCE" : r === "PRELIMINARY_SCIENCE" ? "PRELIMINARY_TECHNOLOGY" : null;

/** where the desk is served */
export const MIGRATION_HOME = "/admissions/preliminary/migration";
/** where the API is */
export const MIGRATION_API = "/api/v1/admissions/preliminary/migration";

export interface Column { key: string; header: string; section: string; required: boolean; note: string | null; choices?: string[] | null }
export interface TemplateTarget {
  id: string; name: string; code: string | null; group: string | null; specialisations: { code: string; name: string }[];
  /** V745: the name as the programme was requested (the word Preliminary Science's drop-down takes), where the server gives it */
  requested?: string | null;
}
/** a preliminary programme by its route and its name */
export interface Programme { route: string; name: string }
export interface TemplateData {
  route: string; name: string; session: string; fileName?: string | null; maxSittings: number; columns: Column[];
  targets: TemplateTarget[]; qualifications: { code: string; label: string }[];
  /** the examination bodies, the subjects and the grades the O'Level form takes (words, or {code,label} pairs) */
  examBodies: unknown[]; subjects: unknown[]; grades: unknown[];
  statusWords: { application?: unknown[]; admission?: unknown[]; payment?: unknown[] } | null;
  fee: { application: number | null; portal: number | null; stated: boolean } | null;
}
export interface Problem { code: string; level: "duplicate" | "error" | "conflict" | "review" | "warning"; message: string; fix?: string | null }
export interface MigrationRow {
  id: string; row_no: number; legacy_no: string | null; applicant: string | null; email: string | null; fee_ref?: string | null;
  verdict: string | null; match: string | null; action: string | null; application_id: string | null; application_no?: string | null;
  problems: Problem[] | null; decided_new: boolean; decided_new_reason?: string | null; result: string | null; result_note: string | null;
  sheet_row?: string | number | null; data?: Record<string, string> | null;
  /** the matched application's own programme and session, where they differ from the upload's (another programme, another session) */
  appRoute?: string | null; appSession?: string | null;
}

/* ── reading the API's answers whatever their casing ───────────────────────────────────────────────────────────────── */

type Obj = Record<string, unknown>;
const isObj = (v: unknown): v is Obj => typeof v === "object" && v !== null && !Array.isArray(v);
/** the first of these keys the object carries (camelCase or snake_case, at the top or under counts/verdicts/results) */
export function pick(o: unknown, ...keys: string[]): unknown {
  if (!isObj(o)) return undefined;
  for (const k of keys) if (o[k] !== undefined && o[k] !== null) return o[k];
  for (const nest of ["counts", "verdicts", "results", "byVerdict", "byResult"]) {
    const n = o[nest];
    if (isObj(n)) for (const k of keys) if (n[k] !== undefined && n[k] !== null) return n[k];
  }
  return undefined;
}
/** a count or an amount, 0 when absent */
export function num(o: unknown, ...keys: string[]): number {
  const v = pick(o, ...keys);
  const n = typeof v === "number" ? v : typeof v === "string" ? Number(v) : NaN;
  return Number.isFinite(n) ? n : 0;
}
/** text, "" when absent */
export function str(o: unknown, ...keys: string[]): string {
  const v = pick(o, ...keys);
  return v == null ? "" : typeof v === "object" ? "" : String(v);
}
/** a list of words from words or {word|label|name|code|reference|value} objects */
export function words(v: unknown): string[] {
  if (!Array.isArray(v)) return [];
  return v.map((x) => (isObj(x) ? String(x.word ?? x.label ?? x.name ?? x.code ?? x.reference ?? x.value ?? "") : String(x ?? ""))).map((s) => s.trim()).filter(Boolean);
}
/** a page of rows: an array, or {rows|items, total} */
export function rowsOf<T = Obj>(v: unknown): { rows: T[]; total: number } {
  if (Array.isArray(v)) {
    const total = v.length ? num(v[0], "total_count", "totalCount", "total_rows", "total") : 0;
    return { rows: v as T[], total: Math.max(total, v.length) };
  }
  const rows = (isObj(v) ? (Array.isArray(v.rows) ? v.rows : Array.isArray(v.items) ? v.items : []) : []) as T[];
  return { rows, total: Math.max(num(v, "total", "totalCount", "total_count"), rows.length) };
}
const titleCase = (s: string) => s.replace(/\b([a-z])/g, (m) => m.toUpperCase());

/* ── the template ──────────────────────────────────────────────────────────────────────────────────────────────────── */

/** the sheets of the template, by name */
export const SHEET = {
  data: "Applicants", instructions: "Instructions", sample: "Sample Data", dictionary: "Data Dictionary", targets: "Targets",
  specialisations: "Specialisations", subjects: "Subjects", qualifications: "Qualifications", lists: "Lists",
} as const;
/** the rows a template leaves for data under its header, each with its drop-downs */
export const TEMPLATE_ROWS = 2000;
/** the most rows a file may hold */
export const MAX_ROWS = 20000;
/** the largest file accepted, in bytes */
export const MAX_BYTES = 15 * 1024 * 1024;
/** the letterhead's rows above the column header */
const HEAD_ROWS = 5;
/** the longest inline drop-down list Excel takes (the formula is at most 255 characters) */
const INLINE_MAX = 250;

const FILE_NAMES: Record<string, string> = {
  PRELIMINARY_TECHNOLOGY: "PRELIMINARY_TECHNOLOGY_INDUSTRIAL_STUDIES_APPLICANTS_TEMPLATE.xlsx",
  PRELIMINARY_SCIENCE: "PRELIMINARY_SCIENCES_APPLICANTS_TEMPLATE.xlsx",
};
/** the template's file name: the server's when it gives one */
export function fileNameOf(route: string, given?: string | null): string {
  return given?.trim() || FILE_NAMES[route] || `${route}_APPLICANTS_TEMPLATE.xlsx`;
}

/** a spreadsheet value that would run as a formula when the file is opened is written as text */
export function safeCell(v: Cell): ReportCell {
  if (v === undefined) return null;
  if (typeof v !== "string") return v;
  return /^[=+\-@\t\r]/.test(v) ? `'${v}` : v;
}

/** the drop-down words a column takes: its own choices, else the template's list for it */
function choicesOf(c: Column, t: TemplateData): string[] {
  const own = words(c.choices ?? []);
  if (own.length) return own;
  const sw = t.statusWords ?? {};
  if (c.key === "gender") return ["Male", "Female"];
  if (/^olevel\dBody$/.test(c.key)) return words(t.examBodies);
  if (/^olevel\dQualification$/.test(c.key)) return t.qualifications.map((q) => q.code);
  if (c.key === "paymentStatus") return words(sw.payment).map(titleCase);
  if (c.key === "applicationStatus") return words(sw.application).map(titleCase);
  if (c.key === "admissionStatus") return words(sw.admission).map(titleCase);
  return [];
}

/** V745: the word the Intended Programme drop-down takes for each target, in the targets' order — the name as requested where the
 *  server gives it, the area where the drop-down lists areas (Technology), the target's own name where the drop-down lists it, else
 *  the drop-down's word at the target's place (the server lists both in the targets' order); "" where none is known. With no list
 *  of its own, the drop-down is the Targets sheet's names. */
export function targetWords(t: Pick<TemplateData, "columns" | "targets">): string[] {
  const col = t.columns.find((c) => c.key === "target");
  const list = words(col?.choices ?? []);
  if (!list.length) return t.targets.map((x) => x.name);
  const byKey = new Map(list.map((w) => [w.trim().toLowerCase(), w]));
  const of = (s: string | null | undefined) => (s ? byKey.get(s.trim().toLowerCase()) : undefined);
  return t.targets.map((x, i) => of(x.requested) ?? of(x.name) ?? of(x.group) ?? (list.length === t.targets.length ? list[i] : ""));
}

/** V745: the words in the letterhead of the data sheet naming the programme the template was made for (the reader refuses the
 *  file in the other programme's section) */
const TEMPLATE_CODE = "Template code:";
/** V745: the columns whose cells stay as typed (Text): the dates, read day first by the server, and the numbers and references,
 *  which keep their leading zeros */
const TEXT_KEY = /^(?:dateOfBirth|applicationDate|paymentDate|phone|nextOfKinPhone|legacyApplicationNo|jambRegNo|examinationNumber|paymentReference|gatewayReference|olevel\dNumber)$/;

/** the template: the data sheet (letterhead with the programme's template code, the columns with required ones marked *,
 *  drop-downs on every row left for data, the dates, numbers and references as Text), the instructions, an illustrative sample,
 *  the data dictionary, and this portal's lists for the programme — never an id to type, only the names and codes the upload
 *  resolves, each as the drop-down takes it. The crest is the writer's (xlsx(sheets, {logo})). */
export function templateSheets(t: TemplateData, school: string): SheetSpec[] {
  const title = `${t.name.toUpperCase()} APPLICANTS TEMPLATE`;
  const headers = ["S/N", ...t.columns.map((c) => (c.required ? `${c.header} *` : c.header))];
  const head: Cell[][] = [[null, school], [null, title],
    [null, `Session ${t.session}. One row per applicant, from the row under the headings. Columns marked * are required; read the Instructions sheet first.`],
    [null, `${TEMPLATE_CODE} ${t.route} · for the ${t.name} section only`], []];
  const tw = targetWords(t);
  const wordOfTarget = (x: TemplateTarget) => tw[t.targets.indexOf(x)] ?? "";
  const first = HEAD_ROWS + 2;                 // the first data row, 1-based
  const last = first + TEMPLATE_ROWS - 1;
  const lists: Cell[][] = [];                  // the Lists sheet: a column per list too long to write inline
  const listCols: string[] = [];
  const range = (sheet: string, col: string, n: number) => `'${sheet}'!$${col}$2:$${col}$${Math.max(n + 1, 2)}`;
  const validations: ListValidation[] = [];
  const hasSpec = t.columns.some((c) => c.key === "specialisation");
  const specs = t.targets.flatMap((x) => x.specialisations.map((s) => ({ target: wordOfTarget(x) || x.name, code: s.code, name: s.name })));
  const textCols = t.columns.map((c, i) => (TEXT_KEY.test(c.key) ? i + 1 : -1)).filter((i) => i > 0);   // S/N is column 0
  t.columns.forEach((c, i) => {
    const col = colName(i + 1);               // S/N is column A
    const sqref = `${col}${first}:${col}${last}`;
    const prompt = c.note ?? undefined;
    if (c.key === "target" && !words(c.choices ?? []).length) {
      if (t.targets.length) validations.push({ sqref, range: range(SHEET.targets, "A", t.targets.length), prompt });
      return;
    }
    if (c.key === "specialisation" && !words(c.choices ?? []).length) {
      if (specs.length) validations.push({ sqref, range: range(SHEET.specialisations, "C", specs.length), prompt });
      return;
    }
    const ch = choicesOf(c, t);
    if (!ch.length) return;
    if (ch.join(",").length <= INLINE_MAX && !ch.some((w) => /[,"]/.test(w))) { validations.push({ sqref, list: ch, prompt }); return; }
    const lc = colName(listCols.length);
    listCols.push(c.header);
    ch.forEach((w, r) => { (lists[r + 1] ??= [])[listCols.length - 1] = w; });
    validations.push({ sqref, range: range(SHEET.lists, lc, ch.length), prompt });
  });
  if (listCols.length) lists[0] = listCols;
  for (let r = 0; r < lists.length; r++) lists[r] ??= [];

  const sheets: SheetSpec[] = [
    [SHEET.data, [...head, headers], { freezeBelow: HEAD_ROWS + 1, validations, textCols }],
    [SHEET.instructions, instructions(t, school, title), { freezeBelow: 4 }],
    [SHEET.sample, sample(t, school, headers, wordOfTarget), { freezeBelow: HEAD_ROWS + 1 }],
    [SHEET.dictionary, dictionary(t, school, title), { freezeBelow: 4 }],
    // column A as the Intended Programme drop-down takes it (the list it reads when the column has no list of its own), beside
    // the programme on this portal's register
    [SHEET.targets, [["Intended programme", "On this portal's register as", "Programme code", hasSpec ? "Area" : "Group"],
      ...t.targets.map((x) => [wordOfTarget(x), x.name, x.code ?? "", x.group ?? ""])]],
  ];
  if (hasSpec) sheets.push([SHEET.specialisations, [["Intended programme", "Code", "Specialisation"], ...specs.map((s) => [s.target, s.code, s.name])]]);
  sheets.push([SHEET.subjects, [["Subject"], ...words(t.subjects).map((s) => [s])]]);
  sheets.push([SHEET.qualifications, [["Code", "Qualification"], ...t.qualifications.map((q) => [q.code, q.label])]]);
  if (listCols.length) sheets.push([SHEET.lists, lists]);
  // every cell written from the portal's data made safe (a name that began "=" would run as a formula once the file is re-saved)
  return sheets.map(([name, rows, opts]): SheetSpec => (opts ? [name, rows.map((r) => r.map(safeCell)), opts] : [name, rows.map((r) => r.map(safeCell))]));
}

/** the instructions sheet: how the file is filled, read and checked */
function instructions(t: TemplateData, school: string, title: string): Cell[][] {
  const sittings = Math.max(1, t.maxSittings || 1);
  const grades = words(t.grades);
  const lines = [
    `This template is for ${t.name} only. The programme of every applicant uploaded with it is the programme of the upload section you use; the "Programme" column is checked against it, and a row naming the other preliminary programme is a conflict and is not imported.`,
    `Fill the "${SHEET.data}" sheet, one row per applicant from the row under the headings. Do not change, rename, reorder or delete the headings: the upload reads the columns by their headings.`,
    "Columns marked * are mandatory; the others are optional. The Data Dictionary sheet says what each column holds, the values it takes and where it goes.",
    "Dates (date of birth, application date, payment date) are DD/MM/YYYY (day first), YYYY-MM-DD, or an Excel date.",
    "The date, phone, number and reference columns are formatted as Text, so Excel keeps what you type (03/01/2025 stays 3 January 2025, 0803… keeps its 0). When you paste from an old export, paste the values only (Paste Special, Values) so they stay Text.",
    "The S/N column is for presentation only; it is not read.",
    `O'Level results: one group of columns a sitting, up to ${sittings} sitting${sittings === 1 ? "" : "s"}. Write the results as "Subject:Grade; Subject:Grade", for example "Mathematics:B3; English Language:C4", or one "Subject:Grade" a line in the cell. The subjects are those of the Subjects sheet${grades.length ? `; the grades are ${grades.join(", ")}` : ""}. An awaiting result is not accepted.`,
    `Choose the intended programme and the specialisation from the drop-downs: they are this portal's. The ${SHEET.targets} sheet lists each intended programme as the drop-down takes it, beside the programme on this portal's register.`,
    `The letterhead of the "${SHEET.data}" sheet carries the template's code (${t.route}): a file made for the other preliminary programme is refused in this section. Keep the applicants on the "${SHEET.data}" sheet.`,
    "An application fee marked \"Paid\" is not taken as proof: every old-portal fee is held until the Bursary verifies it, and the applicant is not asked to pay again meanwhile. Give the payment reference, the amount and the date where you have them.",
    "Each applicant gets this portal's application number; the old application number is kept beside it, and either finds the applicant.",
    "Nothing is written when you upload: every row is checked first, you read the preview and the error report, and you confirm the import.",
    `A file is an Excel workbook (.xlsx) of at most ${MAX_ROWS.toLocaleString("en-GB")} rows and 15 MB.`,
    `The "${SHEET.sample}" sheet is illustrative only: its values are made up and it is never read.`,
  ];
  return [[null, school], [null, `${title}: instructions`], [], ["S/N", "Instruction"], ...lines.map((l, i) => [i + 1, l])];
}

/** the destination of each column, in words */
const DESTINATION: Record<string, string> = {
  legacyApplicationNo: "Kept beside this portal's application number; finds the applicant and signs them in",
  jambRegNo: "Kept with the old-portal record; never used to merge",
  surname: "The applicant's record", firstName: "The applicant's record", otherNames: "The applicant's record", gender: "The applicant's record",
  dateOfBirth: "The application form (date of birth)", email: "The sign-in account and the application form", phone: "The sign-in account and the application form",
  stateOfOrigin: "The application form", lga: "The application form", nationality: "The application form", address: "The application form (residential address)",
  nextOfKinName: "The application form (next of kin)", nextOfKinRelationship: "The application form (next of kin)", nextOfKinPhone: "The application form (next of kin)",
  programme: "Checked against the upload section's programme; never stored as the programme",
  target: "The intended programme on the application", specialisation: "The specialisation on the application",
  examinationNumber: "Kept with the old-portal record", applicationDate: "The application's date",
  paymentReference: "Held for the Bursary to verify", gatewayReference: "Held for the Bursary to verify", amountPaid: "Held for the Bursary to verify",
  paymentDate: "Held for the Bursary to verify", paymentStatus: "Held for the Bursary to verify; never counted paid on upload",
  applicationStatus: "The application's state on this portal", admissionStatus: "The old portal's decision, published here as decided on the old portal",
};
/** the values a column takes, in words */
function acceptedOf(c: Column, t: TemplateData): string {
  const ch = choicesOf(c, t);
  if (/^olevel\dResults$/.test(c.key)) return `"Subject:Grade; Subject:Grade", or one Subject:Grade a line — subjects on the Subjects sheet${words(t.grades).length ? `, grades ${words(t.grades).join(", ")}` : ""}`;
  if (/^olevel\dYear$/.test(c.key)) return "A four-digit year";
  if (/^olevel\dNumber$/.test(c.key)) return "The examination number of the sitting";
  if (c.key === "target") return ch.length ? ch.join(", ") : "One of the Targets sheet";
  if (c.key === "specialisation") return ch.length ? ch.join(", ") : "One of the Specialisations sheet";
  if (ch.length) return ch.join(", ");
  if (["dateOfBirth", "applicationDate", "paymentDate"].includes(c.key)) return "DD/MM/YYYY, YYYY-MM-DD or an Excel date";
  if (["phone", "nextOfKinPhone"].includes(c.key)) return "A Nigerian mobile number, e.g. 0803 000 0000";
  if (c.key === "email") return "One email address";
  if (c.key === "amountPaid") return "An amount in naira (₦ and commas allowed)";
  if (c.key === "legacyApplicationNo") return "Letters, digits and / - . only; at most 40 characters; once in the file";
  if (c.key === "programme") return `${t.name}, as the old portal named it`;
  return "Text";
}
/** the data dictionary: every column, whether it is required, what it holds, what it takes and where it goes */
function dictionary(t: TemplateData, school: string, title: string): Cell[][] {
  return [[null, school], [null, `${title}: data dictionary`], [],
    ["S/N", "Column", "Required", "Section", "What it holds", "Accepted values", "Where it goes"],
    ...t.columns.map((c, i) => [i + 1, c.header, c.required ? "Yes" : "No", c.section, c.note ?? "", acceptedOf(c, t),
      DESTINATION[c.key] ?? (c.section.startsWith("O'Level") || c.section.startsWith("O’Level") ? "The O'Level results of the application" : "The application")])];
}

/** made-up values for the sample sheet (never a real person); the intended programme as the drop-down takes it (V745) */
function sample(t: TemplateData, school: string, headers: string[], wordOfTarget: (x: TemplateTarget) => string): Cell[][] {
  const choice = (c: Column | undefined, word: string) => choicesOf(c ?? { key: "", header: "", section: "", required: false, note: null }, t)
    .find((w) => w.toLowerCase() === word.toLowerCase()) ?? titleCase(word);
  const col = (k: string) => t.columns.find((c) => c.key === k);
  // the first row's intended programme and its specialisation from one target: one with specialisations where there is one
  const withSpec = t.targets.find((x) => x.specialisations.length);
  const target = withSpec ?? t.targets[0];
  const listed = words(col("target")?.choices ?? []);
  const targetWord = (x: TemplateTarget | undefined) => (x ? wordOfTarget(x) : "") || listed[0] || "";
  // the second row another target where there is one, by its drop-down word (Technology's areas may be one for two targets)
  const second = t.targets.find((x) => x !== target && targetWord(x) !== targetWord(target));
  const subjects = words(t.subjects);
  const grades = words(t.grades);
  const preferred = ["English Language", "Mathematics", "Biology", "Chemistry", "Physics", "Technical Drawing", "Economics"];
  const five = [...preferred.filter((s) => subjects.includes(s)), ...subjects.filter((s) => !preferred.includes(s))].slice(0, 5);
  const results = (g: number) => (grades.length ? five.map((s, i) => `${s}:${grades[(g + i) % Math.min(6, grades.length)]}`).join("; ") : "");
  const fee = t.fee?.stated && t.fee.application != null ? String(Number(t.fee.application) + Number(t.fee.portal ?? 0)) : "";
  const body = (n: number) => choicesOf(col(`olevel${n}Body`) ?? { key: `olevel${n}Body`, header: "", section: "", required: false, note: null }, t)[0] ?? "";
  const qual = (n: number) => choicesOf(col(`olevel${n}Qualification`) ?? { key: `olevel${n}Qualification`, header: "", section: "", required: false, note: null }, t)[0] ?? "";
  const rows: Record<string, string>[] = [
    {
      legacyApplicationNo: "OLD/PRE/2025/000101", surname: "Example", firstName: "Ada", otherNames: "Ngozi", gender: choice(col("gender"), "female"),
      dateOfBirth: "14/02/2007", email: "ada.example@example.com", phone: "08030000001", stateOfOrigin: "Benue", lga: "Makurdi", nationality: "Nigerian",
      address: "12 Example Street, Makurdi", nextOfKinName: "Example Okoh", nextOfKinRelationship: "Father", nextOfKinPhone: "08030000002", programme: t.name,
      target: targetWord(target), specialisation: target?.specialisations[0]?.name ?? "", examinationNumber: "EXM/0101",
      olevel1Body: body(1), olevel1Qualification: qual(1), olevel1Year: "2024", olevel1Number: "4250101001", olevel1Results: results(1),
      applicationDate: "03/01/2025", paymentReference: "OLDPAY-000101", gatewayReference: "GW-000000101", amountPaid: fee, paymentDate: "03/01/2025",
      paymentStatus: choice(col("paymentStatus"), "paid"), applicationStatus: choice(col("applicationStatus"), "submitted"), admissionStatus: choice(col("admissionStatus"), "pending"),
    },
    {
      legacyApplicationNo: "OLD/PRE/2025/000102", surname: "Sample", firstName: "Bola", gender: choice(col("gender"), "male"), dateOfBirth: "2006-09-30",
      phone: "08030000003", stateOfOrigin: "Benue", lga: "Gboko", nationality: "Nigerian", programme: t.name, target: targetWord(second ?? target),
      olevel1Body: body(1), olevel1Qualification: qual(1), olevel1Year: "2023", olevel1Number: "4250101002", olevel1Results: results(3),
      olevel2Body: body(2), olevel2Qualification: qual(2), olevel2Year: "2024", olevel2Number: "4250101003", olevel2Results: results(0),
      applicationDate: "10/01/2025", paymentStatus: choice(col("paymentStatus"), "not paid"), applicationStatus: choice(col("applicationStatus"), "not submitted"),
    },
  ];
  return [[null, school], [null, "SAMPLE DATA — ILLUSTRATIVE ONLY"],
    [null, "Every value on this sheet is made up to show the formats; it is never read. Fill the Applicants sheet."], [], [],
    headers, ...rows.map((r, i) => [i + 1, ...t.columns.map((c) => r[c.key] ?? "")])];
}

/* ── the filled file read back ─────────────────────────────────────────────────────────────────────────────────────── */

/** a heading as compared: no required mark, no apostrophes or full stops, single spaces, lower case */
const norm = (s: string) => s.replace(/\*/g, "").replace(/\((?:required|optional)\)/gi, "").replace(/[’‘'`.]/g, "").replace(/[_\s]+/g, " ").trim().toLowerCase();
/** headings an old export may use for a template column (compared as norm() leaves them) */
const ALIASES: Record<string, string> = {
  "application no": "legacyApplicationNo", "app no": "legacyApplicationNo", "appno": "legacyApplicationNo", "old application number": "legacyApplicationNo",
  "old application no": "legacyApplicationNo", "legacy application number": "legacyApplicationNo", "form no": "legacyApplicationNo", "form number": "legacyApplicationNo",
  "jamb no": "jambRegNo", "jamb reg no": "jambRegNo", "jamb number": "jambRegNo", "utme reg no": "jambRegNo", "jamb registration no": "jambRegNo",
  "last name": "surname", "lastname": "surname", "family name": "surname", "first name": "firstName", "firstname": "firstName", "given name": "firstName",
  "middle name": "otherNames", "other name": "otherNames", "othernames": "otherNames", "applicant name": "fullName", "full name": "fullName", "name": "fullName",
  "sex": "gender", "dob": "dateOfBirth", "birth date": "dateOfBirth", "date of birth dd/mm/yyyy": "dateOfBirth", "email": "email", "e-mail": "email",
  "email address": "email", "phone": "phone", "phone no": "phone", "phone number": "phone", "gsm": "phone", "gsm no": "phone", "mobile": "phone", "mobile number": "phone",
  "state": "stateOfOrigin", "local government": "lga", "local government area": "lga", "country": "nationality", "address": "address", "home address": "address",
  "contact address": "address", "next of kin": "nextOfKinName", "nok": "nextOfKinName", "nok name": "nextOfKinName", "next of kin relationship": "nextOfKinRelationship",
  "relationship": "nextOfKinRelationship", "nok phone": "nextOfKinPhone", "next of kin phone number": "nextOfKinPhone", "next of kin gsm": "nextOfKinPhone",
  "course": "programme", "programme name": "programme", "programme applied": "programme", "programme applied for": "programme",
  "intended programme": "target", "target programme": "target", "target": "target", "area": "target", "specialization": "specialisation",
  "exam number": "examinationNumber", "exam no": "examinationNumber", "examination no": "examinationNumber",
  "date applied": "applicationDate", "application date": "applicationDate", "payment reference": "paymentReference", "payment ref": "paymentReference",
  "rrr": "paymentReference", "transaction reference": "gatewayReference", "transaction ref": "gatewayReference", "gateway reference": "gatewayReference",
  "amount": "amountPaid", "amount paid": "amountPaid", "fee paid": "amountPaid", "date paid": "paymentDate", "payment date": "paymentDate",
  "payment status": "paymentStatus", "application status": "applicationStatus", "status": "applicationStatus", "admission status": "admissionStatus",
};
/** the sittings' headings an old export may use: "O'Level 1 Exam Type", "Sitting 1 Exam Body", "OLevel 2 Grades" …; V745: a heading
 *  without a sitting ("O'Level Examination Type", "O-Level Subjects and Grades", the brief's own names) is the first sitting's */
function sittingAlias(n: string): string | null {
  const m = /^(?:o[ -]?level|sitting|first sitting|second sitting)\s*([12])?\s*(.*)$/.exec(n);
  if (!m) return null;
  const k = m[1] ?? (n.startsWith("second") ? "2" : "1");
  const rest = m[2].trim();
  const part = /^(?:exam(?:ination)? (?:type|body)|body|type)$/.test(rest) ? "Body"
    : /^qualification|^certificate/.test(rest) ? "Qualification"
      : /^(?:exam(?:ination)? )?year$/.test(rest) ? "Year"
        : /^(?:exam(?:ination)? )?(?:number|no)$/.test(rest) ? "Number"
          : /^(?:results?|grades?|subjects(?: and grades)?)$/.test(rest) ? "Results" : null;
  return part ? `olevel${k}${part}` : null;
}

/** V745: an O'Level results cell as the server reads it: one result a line (Alt+Enter in Excel) as "; ", and "Subject:Grade
 *  Subject:Grade" with nothing between the pairs given a "; " after each grade — the server otherwise reads either as one subject
 *  with the last grade; spaces collapsed */
export function resultsText(v: string): string {
  return v.split(/\s*[\r\n]+\s*/).join("; ")
    .split(/([;,|])/)
    .map((part) => ((part.match(/:/g) ?? []).length >= 2 ? part.replace(/(:\s*(?:[A-F]\s?[1-9]|AR))\s+(?=\S)/gi, "$1; ") : part))
    .join("")
    .replace(/\s+/g, " ").replace(/\s*;(?:\s*;)+\s*/g, "; ").replace(/^[\s;]+|[\s;]+$/g, "");
}

/** a programme's words as the server compares them (admissions.pg_legacy_key): no full stops or quotes, brackets, slashes,
 *  ampersands and hyphens as spaces, single spaces, upper case */
const legacyKey = (s: string) => s.replace(/[.'"’]/g, "").replace(/[\],([)/&-]/g, " ").replace(/\s+/g, " ").trim().toUpperCase();
/** V745: the preliminary programme some words name, as admissions.prelim_mig_route_of reads a "Programme" cell: a programme's name
 *  or route code, else the common short forms ("pre-science", "PTIS", "preliminary technology" …); null when they name neither
 *  or both */
export function routeNamed(text: string | null | undefined, programmes: Programme[] = []): PrelimRoute | null {
  const k = legacyKey(text ?? "");
  if (!k) return null;
  const named = PRELIM_ROUTES.filter((r) => [r, r.replace(/_/g, " "), programmes.find((p) => p.route === r)?.name ?? ""].some((w) => w && legacyKey(w) === k));
  if (named.length === 1) return named[0];
  const sci = /\b(?:SCIENCES?|SCI|PRESCI|PRESCIENCES?)\b/.test(k);
  const tech = /\b(?:TECH|TECHNOLOGY|TECHNICAL|INDUSTRIAL|PTIS|PRETECH|VOCATIONAL)\b/.test(k);
  return sci && !tech ? "PRELIMINARY_SCIENCE" : tech && !sci ? "PRELIMINARY_TECHNOLOGY" : null;
}

export interface ReadFile {
  rows: Record<string, string>[]; unknown: string[]; missing: string[];
  /** the sheet read: the Applicants sheet when it holds applicants, else the one sheet that does */
  sheet: string | null;
  /** V745: the other sheets with the template's columns and applicant rows, not read */
  otherSheets: string[];
  /** V745: applicants on more than one sheet, none of them the Applicants sheet: nothing is read */
  ambiguous: boolean;
  /** V745: the file is the other preliminary programme's — by its template (the code in the letterhead, else the title), or
   *  because every row's "Programme" names the other programme */
  wrongProgramme: { route: string; name: string; by: "template" | "programme" } | null;
}
/** the template's own sheets that are never data */
const NOT_DATA = new Set<string>([SHEET.instructions, SHEET.sample, SHEET.dictionary, SHEET.targets, SHEET.specialisations, SHEET.subjects, SHEET.qualifications, SHEET.lists]
  .map((s) => s.toLowerCase()));

/** V745: whether a file read for one programme is the other's: the template it was made from — the code in the data sheet's
 *  letterhead, else its title ("PRELIMINARY SCIENCES APPLICANTS TEMPLATE", a template downloaded before the code) — and, whatever
 *  the template, every row naming the other programme in its "Programme" column */
function wrongProgrammeOf(above: string[][], rows: Record<string, string>[], route: string | undefined, programmes: Programme[]): ReadFile["wrongProgramme"] {
  if (!isPrelimMigrationRoute(route)) return null;
  const nameOf = (r: string, given?: string) => programmes.find((p) => p.route === r)?.name || given || r;
  let code: PrelimRoute | null = null;
  let titled: { route: PrelimRoute; words: string } | null = null;
  for (const v of above.flat()) {
    const c = new RegExp(`${TEMPLATE_CODE}\\s*([A-Z_]+)`, "i").exec(v ?? "")?.[1]?.toUpperCase();
    if (!code && isPrelimMigrationRoute(c)) code = c;
    const ti = /^(.+?)\s+APPLICANTS TEMPLATE$/i.exec((v ?? "").trim());
    const tr = ti ? routeNamed(ti[1], programmes) : null;
    if (!titled && ti && tr) titled = { route: tr, words: titleCase(ti[1].toLowerCase()) };
  }
  const made = code ?? titled?.route ?? null;
  if (made && made !== route) return { route: made, name: nameOf(made, made === titled?.route ? titled.words : undefined), by: "template" };
  const other = otherRoute(route);
  if (other && rows.length && rows.every((r) => routeNamed(r.programme, programmes) === other)) return { route: other, name: nameOf(other), by: "programme" };
  return null;
}

/** a filled template read back from its sheets: of the sheets (never the sample, the instructions or a list) whose heading row
 *  carries the old application number and another column of the template, the Applicants sheet when it holds applicants, else
 *  the one sheet that does (V745: several such sheets and none the Applicants sheet: nothing is read; the others are named); its
 *  headings matched to the template's keys by the template's headings or an old export's, the required marks, case and spacing
 *  aside; the S/N column dropped; blank rows left out; an O'Level results cell's line breaks read as "; "; each row's own sheet
 *  row kept for the error report. With the upload's route (and the programmes' names), a file of the other programme is named. */
export function readSheets(sheets: Sheet[], t: Pick<TemplateData, "columns"> & Partial<Pick<TemplateData, "route">>, programmes: Programme[] = []): ReadFile {
  const byHeader = new Map(t.columns.map((c) => [norm(c.header), c.key]));
  const keys = new Set(t.columns.map((c) => c.key));
  const keyOf = (v: string): string | null => {
    const n = norm(v);
    if (!n || n === "s/n" || n === "sn") return null;
    const k = byHeader.get(n) ?? ALIASES[n] ?? sittingAlias(n) ?? (keys.has(v.trim()) ? v.trim() : null);
    return k && (keys.has(k) || k === "fullName") ? k : null;
  };
  const found: { sheet: string; rows: Record<string, string>[]; unknown: string[]; missing: string[]; above: string[][] }[] = [];
  for (const sh of sheets) {
    if (NOT_DATA.has(sh.name.trim().toLowerCase())) continue;
    const h = sh.rows.findIndex((r) => {
      const ks = r.map((v) => keyOf(v ?? ""));
      return ks.includes("legacyApplicationNo") && ks.filter(Boolean).length >= 2;
    });
    if (h < 0) continue;
    const header = sh.rows[h];
    const map = header.map((v) => keyOf(v ?? ""));
    const seen = new Set<string>();
    map.forEach((k, i) => { if (k && seen.has(k)) map[i] = null; else if (k) seen.add(k); });   // a heading twice: the first is read
    const unknown = header.filter((v, i) => norm(v ?? "") && !map[i] && !["s/n", "sn"].includes(norm(v ?? ""))).map((v) => v.trim());
    const missing = t.columns.filter((c) => c.required && !seen.has(c.key) && !(["surname", "firstName"].includes(c.key) && seen.has("fullName"))).map((c) => c.header);
    const rows: Record<string, string>[] = [];
    for (let i = h + 1; i < sh.rows.length; i++) {
      const r = sh.rows[i];
      const o: Record<string, string> = {};
      map.forEach((k, j) => {
        const raw = r[j] ?? "";
        const v = (k && /^olevel\dResults$/.test(k) ? resultsText(raw) : raw.replace(/\s+/g, " ")).trim();
        if (k && v) o[k] = v;
      });
      if (Object.keys(o).length) { o.sheetRow = String(i + 1); rows.push(o); }
    }
    found.push({ sheet: sh.name, rows, unknown, missing, above: sh.rows.slice(0, h) });
  }
  if (!found.length) {
    const legacy = t.columns.find((c) => c.key === "legacyApplicationNo")?.header ?? "Application Number";
    return { rows: [], unknown: [], missing: [legacy], sheet: null, otherSheets: [], ambiguous: false, wrongProgramme: null };
  }
  const isData = (f: (typeof found)[number]) => f.sheet.trim().toLowerCase() === SHEET.data.toLowerCase();
  const withRows = found.filter((f) => f.rows.length);
  const chosen = found.find((f) => isData(f) && f.rows.length)
    ?? (withRows.length === 1 ? withRows[0] : withRows.length === 0 ? found.find(isData) ?? found[0] : null);
  if (!chosen) return { rows: [], unknown: [], missing: [], sheet: null, otherSheets: withRows.map((f) => f.sheet), ambiguous: true, wrongProgramme: null };
  return {
    rows: chosen.rows, unknown: chosen.unknown, missing: chosen.missing, sheet: chosen.sheet,
    otherSheets: withRows.filter((f) => f !== chosen).map((f) => f.sheet), ambiguous: false,
    wrongProgramme: wrongProgrammeOf(chosen.above, chosen.rows, t.route, programmes),
  };
}

/** a filled template read back from the file's bytes, each row at its own row of the sheet (the blank letterhead lines Excel
 *  does not write still counted), so the error report names the row the officer sees */
export async function readFile(buf: ArrayBuffer, t: Pick<TemplateData, "columns"> & Partial<Pick<TemplateData, "route">>, programmes: Programme[] = []): Promise<ReadFile> {
  return readSheets(await xlsxWorkbook(buf, { rowNumbers: true }), t, programmes);
}

/** the ranges [from, to] (1-based, inclusive) a file of n rows is sent, checked or imported in */
export function ranges(n: number, size: number): [number, number][] {
  const out: [number, number][] = [];
  for (let from = 1; from <= n; from += size) out.push([from, Math.min(n, from + size - 1)]);
  return out;
}

/** the SHA-256 of the file, in hex, as the server keeps it */
export async function sha256Hex(buf: ArrayBuffer): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", buf);
  return Array.from(new Uint8Array(d)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** the progress of a chunked step, in real rows */
export function progressWords(step: "upload" | "check" | "import", done: number, total: number): string {
  const verb = step === "upload" ? "Sending" : step === "check" ? "Checking" : "Importing";
  return `${verb} ${done.toLocaleString("en-GB")} / ${total.toLocaleString("en-GB")} rows`;
}

/* ── the words ─────────────────────────────────────────────────────────────────────────────────────────────────────── */

export const VERDICT: Record<string, [string, Tone]> = {
  READY: ["Ready", "ok"], WARNING: ["Ready, with a note", "info"], DUPLICATE_IN_FILE: ["Duplicate in the file", "warn"],
  CONFLICT: ["Conflict", "bad"], REQUIRES_REVIEW: ["Requires review", "warn"], ERROR: ["Error", "bad"],
};
export const RESULT: Record<string, [string, Tone]> = {
  CREATED: ["Created", "ok"], UPDATED: ["Updated", "ok"], RECONCILED: ["Reconciled", "ok"], UNCHANGED: ["Already on record", "grey"],
  SKIPPED: ["Not imported", "warn"], FAILED: ["Failed", "bad"],
};
export const MATCH: Record<string, string> = { NEW_APPLICANT: "New applicant", EXISTING_APPLICANT: "Already on the portal" };
export const ACTION: Record<string, string> = {
  CREATE: "Create the applicant", UPDATE: "Fill in missing details", RECONCILE: "Keep the old number with the application here", NONE: "Nothing to change",
};
export const BATCH_STATE: Record<string, [string, Tone]> = {
  STAGING: ["Uploading", "info"], CHECKED: ["Checked", "info"], IMPORTING: ["Importing", "warn"], COMPLETED: ["Completed", "ok"], ABANDONED: ["Set aside", "grey"],
};
export const FEE_STATE: Record<string, [string, Tone]> = {
  REQUIRES_REVIEW: ["Held for the Bursary", "warn"], VERIFIED: ["Verified", "ok"], REJECTED: ["Not verified", "bad"],
};
export const PAYMENT: Record<string, [string, Tone]> = {
  PAID: ["Paid", "ok"], HELD: ["Held for the Bursary", "warn"], UNPAID: ["Not paid", "grey"], NOT_REQUIRED: ["No fee", "grey"],
};
/** a verdict, a result or a state in words, with its tone */
export const wordOf = (m: Record<string, [string, Tone]>, k: string | null | undefined): [string, Tone] =>
  (k && m[k]) || [k ? k.charAt(0) + k.slice(1).toLowerCase().replace(/_/g, " ") : "—", "grey"];

/** the row's first problem that holds it back, else its first note */
export function firstProblem(r: Pick<MigrationRow, "problems">): Problem | null {
  const ps = r.problems ?? [];
  return ps.find((p) => p.level !== "warning") ?? ps[0] ?? null;
}

/** can an officer confirm a new applicant on this row (a possible same person, and nothing else holding it)? On a row not yet
 *  imported while the upload is open (CHECKED or IMPORTING); V745 (admissions.prelim_migration_row_new): also on one the import left
 *  out for that review alone, while the upload is importing or after it is finished (never set aside) — confirmed, it is imported
 *  there and then. Without the upload's state, a row not yet imported only. */
export function mayConfirmNew(r: Pick<MigrationRow, "problems" | "verdict" | "result" | "decided_new">, batchState?: string): boolean {
  const pending = !r.result && (batchState == null || batchState === "CHECKED" || batchState === "IMPORTING");
  const skipped = r.result === "SKIPPED" && (batchState === "IMPORTING" || batchState === "COMPLETED");
  if (!(pending || skipped) || r.decided_new || r.verdict !== "REQUIRES_REVIEW") return false;
  const held = (r.problems ?? []).filter((p) => p.level !== "warning");
  return held.length > 0 && held.every((p) => p.code === "POSSIBLE_SAME_APPLICANT");
}

/** what the reader may open from a row: the preliminary desk, the change of programme, the programme corrections; and the programmes
 *  the reader reads */
export interface RowLinkAccess { desk: boolean; change: boolean; corrections: boolean; routes: string[] }
/** where a row's "Open" goes: a row whose email found an application on the other programme (PROGRAMME_CONFLICT) to that
 *  application under Programme corrections, for a reader who may change its programme; else the preliminary desk at the
 *  application's own programme and session, for a reader of the desk who reads that programme; else the application under
 *  Programme corrections, for a reader of them; else nowhere */
export function rowLink(r: Pick<MigrationRow, "application_id" | "application_no" | "problems" | "appRoute" | "appSession">, batchRoute: string,
                        may: RowLinkAccess): string | null {
  if (!r.application_id || !r.application_no) return null;
  const corrections = `${MIGRATION_HOME}?view=corrections&app=${encodeURIComponent(r.application_id)}`;
  if (may.change && (r.problems ?? []).some((p) => p.code === "PROGRAMME_CONFLICT")) return corrections;
  const route = str(r, "appRoute", "app_route") || batchRoute;
  if (may.desk && may.routes.includes(route)) {
    const qs = new URLSearchParams({ route });
    const session = str(r, "appSession", "app_session");
    if (session) qs.set("session", session);
    qs.set("q", r.application_no);
    return `/preliminary?${qs.toString()}`;
  }
  return may.corrections && may.routes.includes(route) ? corrections : null;   // a programme office reads its own programme's records only
}

/* ── the preview's figures ─────────────────────────────────────────────────────────────────────────────────────────── */

export interface Figures {
  rows: number; staged: number; checked: number; valid: number; invalid: number; existing: number; duplicates: number; newApplicants: number;
  toUpdate: number; skipped: number; paymentsToVerify: number; programmeConflicts: number; conflicts: number; review: number;
  created: number; updated: number; reconciled: number; unchanged: number; notImported: number; failed: number; feesHeld: number; imported: number;
  /** V745: the ready rows not yet imported; the old-portal fees this upload brought in that the Bursary has since verified or not */
  readyToImport: number; feesVerified: number; feesRejected: number;
  /** V745: of the rows not yet imported, the new applicants and the applicants already here, as the server counts them (null from a
   *  server that does not); the applications made here an upload without "fill in missing details" only keeps the old number with */
  newApplicantsToImport: number | null; toUpdateToImport: number | null; oldNumberOnly: number;
}
/** a batch's summary read into the preview's figures (the server's counts; valid = ready + ready with a note; paymentsToVerify the
 *  old-portal fees the import holds for the Bursary: rows claiming "Paid" that import, with no fee paid here or held already) */
export function figuresOf(s: unknown): Figures {
  const rows = num(s, "rowsExpected", "rows_expected", "rows");      // the file's rows (the summary's "rows" counts those staged so far)
  const created = num(s, "created", "CREATED");
  const updated = num(s, "updated", "UPDATED");
  const reconciled = num(s, "reconciled", "RECONCILED");
  const unchanged = num(s, "unchanged", "UNCHANGED");
  const notImported = num(s, "importSkipped", "SKIPPED");             // the result; the summary's "skipped" is the rows that will not import
  const failed = num(s, "failed", "FAILED");
  return {
    rows, staged: num(s, "staged", "rowsStaged", "rows_staged"), checked: num(s, "checked"),
    valid: num(s, "ready", "READY") + num(s, "warning", "WARNING"), invalid: num(s, "invalid", "error", "ERROR"),
    existing: num(s, "existing", "existingApplicants"), duplicates: num(s, "duplicates"), newApplicants: num(s, "newApplicants", "creates"),
    toUpdate: num(s, "toUpdate"), skipped: num(s, "skipped"), paymentsToVerify: num(s, "paymentsToVerify"),
    programmeConflicts: num(s, "programmeConflicts"), conflicts: num(s, "conflicts", "conflict", "CONFLICT"), review: num(s, "review", "requiresReview", "REQUIRES_REVIEW"),
    created, updated, reconciled, unchanged, notImported, failed, feesHeld: num(s, "feesHeld"),
    imported: num(s, "imported") || created + updated + reconciled + unchanged + notImported + failed,
    readyToImport: num(s, "readyToImport", "ready_to_import"), feesVerified: num(s, "feesVerified"), feesRejected: num(s, "feesRejected"),
    newApplicantsToImport: pick(s, "newApplicantsToImport") == null ? null : num(s, "newApplicantsToImport"),
    toUpdateToImport: pick(s, "toUpdateToImport") == null ? null : num(s, "toUpdateToImport"), oldNumberOnly: num(s, "oldNumberOnly"),
  };
}

/** V745: what an import already begun has still to do — the rows not yet imported only: the ready ones; of them the new applicants
 *  and the applicants already here, as the server counts them; and the rows still to go that will not import. From a server that
 *  does not count them, the new applicants are the file's less those created and those whose import failed (a failed row keeps the
 *  check's action and is not imported again), unknown (null) while the failed rows are not read, and the applicants already here
 *  the ready rows left. Null before anything is imported. */
export interface StillToDo { ready: number; create: number | null; existing: number | null; notReady: number }
export function stillToDo(f: Figures, failed: Pick<MigrationRow, "verdict" | "action">[] | null): StillToDo | null {
  if (!f.imported) return null;
  const ready = f.readyToImport;
  const notReady = Math.max(0, (f.staged || f.rows) - f.imported - ready);
  if (f.newApplicantsToImport != null) return { ready, create: f.newApplicantsToImport, existing: f.toUpdateToImport ?? ready - f.newApplicantsToImport, notReady };
  const known = f.failed === 0 || (failed != null && failed.length >= f.failed);
  const failedNew = known ? (failed ?? []).filter((r) => r.action === "CREATE" && ["READY", "WARNING"].includes(r.verdict ?? "")).length : 0;
  const create = known ? Math.min(ready, Math.max(0, f.newApplicants - f.created - failedNew)) : null;
  return { ready, create, existing: create == null ? null : ready - create, notReady };
}

/* ── the error report and the history ──────────────────────────────────────────────────────────────────────────────── */

export const REPORT_HEAD = ["Row", "Sheet row", "Applicant", "Old application number", "Status", "Error type", "Error message", "Suggested correction"];
/** the error report: a line for each problem of each row not plainly ready (or each flat line the server gives), in the
 *  file's row order; every cell made safe */
export function reportLines(rows: unknown[]): ReportCell[][] {
  const out: Cell[][] = [];
  for (const r of rows) {
    if (!isObj(r)) continue;
    const result = str(r, "result");
    const verdict = str(r, "verdict", "status");
    const status = result === "FAILED" ? "Failed" : result && result !== "SKIPPED" ? wordOf(RESULT, result)[0] : wordOf(VERDICT, verdict)[0];
    const sheetRow = num(r, "sheet_row", "sheetRow");
    const at: Cell[] = [num(r, "row_no", "rowNo", "row") || null, sheetRow || null, str(r, "applicant", "name"), str(r, "legacy_no", "legacyNo", "oldNumber", "old_number"), status];
    const ps = Array.isArray(r.problems) ? (r.problems as unknown[]) : null;
    if (result === "FAILED" && str(r, "result_note", "resultNote")) out.push([...at, "IMPORT_FAILED", str(r, "result_note", "resultNote"), "Correct the row and upload it again."]);
    if (ps) for (const p of ps) out.push([...at, str(p, "code"), str(p, "message"), str(p, "fix")]);
    else if (str(r, "code")) out.push([...at, str(r, "code"), str(r, "message"), str(r, "fix")]);
  }
  return out.map((l) => l.map(safeCell));
}

/** V745: the import report, every row of an upload (GET …/batches/{id}/report?scope=all): which old number became which application
 *  number on this portal, what the import did with the row, and why a row was not imported */
export const IMPORT_REPORT_HEAD = ["Row", "Sheet row", "Old application number", "Applicant", "Application number on this portal", "Result", "Old-portal fee", "Note", "Problems"];
export function importReportLines(rows: unknown[]): ReportCell[][] {
  return rows.filter(isObj).map((r) => {
    const result = str(r, "result");
    const status = result ? wordOf(RESULT, result)[0] : `${wordOf(VERDICT, str(r, "verdict", "status"))[0]}, not yet imported`;
    const ps = (Array.isArray(r.problems) ? (r.problems as unknown[]) : []).filter(isObj).map((p) => [str(p, "code"), str(p, "message")].filter(Boolean).join(": "));
    const cells: Cell[] = [num(r, "row_no", "rowNo", "row") || null, num(r, "sheet_row", "sheetRow") || null, str(r, "legacy_no", "legacyNo", "oldNumber", "old_number"),
      str(r, "applicant", "name"), str(r, "application_no", "applicationNo"), status,
      // V745: the old-portal fee the row brought — held for the Bursary, verified, not verified — blank when it held none
      str(r, "fee_state", "feeState") ? wordOf(FEE_STATE, str(r, "fee_state", "feeState"))[0] : "", str(r, "result_note", "resultNote"), ps.join(" | ")];
    return cells.map(safeCell);
  });
}

/** V745: how an application's fee stands on the preliminary desk's rows — PAID, HELD (paid on the old portal, held for the Bursary)
 *  or UNPAID — whatever the endpoint calls it (feeStatus, V737's payment, else the paid flag); and the old portal's number */
export function feeStatusOf(r: unknown): string {
  return str(r, "feeStatus", "fee_status", "payment") || (pick(r, "paid") === true ? "PAID" : "UNPAID");
}
export const legacyNoOf = (r: unknown): string => str(r, "legacyApplicationNo", "legacy_application_no", "legacy_no", "legacyNo");

export const HISTORY_HEAD = ["Batch reference", "Programme", "File", "Uploaded", "Administrator", "Total rows", "Successful", "Created", "Updated",
  "Already on record", "Not imported", "Failed", "Fees held", "Status"];
const stamp = (v: string) => (v ? new Date(v).toLocaleString("en-GB", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" }) : "");
/** an upload of the history in words: the totals, what was written (created, updated or reconciled), what was not */
export function historyLine(b: unknown): { reference: string; route: string; routeName: string; file: string; startedAt: string; by: string; office: string; state: string;
  rows: number; successful: number; created: number; updated: number; unchanged: number; skipped: number; failed: number; feesHeld: number; id: string } {
  const created = num(b, "created");
  const updated = num(b, "updated") + num(b, "reconciled");
  const successful = pick(b, "successful");     // the server's count when it gives one (imported without a failure)
  return {
    id: str(b, "id"), reference: str(b, "reference"), route: str(b, "route"), routeName: str(b, "route_name", "routeName", "programme") || str(b, "route"),
    file: str(b, "file_name", "fileName", "file"), startedAt: str(b, "started_at", "startedAt"), by: str(b, "started_by_name", "startedByName", "started_by", "startedBy"),
    office: str(b, "started_office", "startedOffice"), state: str(b, "state"), rows: num(b, "rows_expected", "rowsExpected", "rows"),
    successful: successful != null ? num(b, "successful") : created + updated + num(b, "unchanged"), created, updated, unchanged: num(b, "unchanged"),
    skipped: num(b, "skipped"), failed: num(b, "failed"),
    feesHeld: num(b, "fees_held", "feesHeld"),
  };
}
export function historyLines(rows: unknown[]): ReportCell[][] {
  return rows.map(historyLine).map((h) => [h.reference, h.routeName, h.file, stamp(h.startedAt), h.office ? `${h.by} (${h.office})` : h.by, h.rows, h.successful,
    h.created, h.updated, h.unchanged, h.skipped, h.failed, h.feesHeld, wordOf(BATCH_STATE, h.state)[0]].map(safeCell));
}

/** a reason the correction takes: at least 15 characters and three words */
export function reasonOk(reason: string): boolean {
  const r = reason.trim();
  return r.length >= 15 && r.split(/\s+/).filter(Boolean).length >= 3;
}

/* ── the server's answers, read the one way the screens use them ───────────────────────────────────────────────────── */

/** the template the server gives, every list there even when the server left one out */
export function templateOf(raw: unknown): TemplateData {
  const o = isObj(raw) ? raw : {};
  const arr = (k: string): unknown[] => (Array.isArray(o[k]) ? (o[k] as unknown[]) : []);
  const fee = pick(o, "fee");
  return {
    route: str(o, "route"), name: str(o, "name", "routeName") || str(o, "route"), session: str(o, "session"), fileName: str(o, "fileName", "file_name") || null,
    maxSittings: num(o, "maxSittings", "max_sittings") || 1,
    columns: arr("columns").filter(isObj).map((c) => ({
      key: str(c, "key"), header: str(c, "header"), section: str(c, "section"), required: pick(c, "required") === true, note: str(c, "note") || null,
      choices: words(pick(c, "choices")),
    })).filter((c) => c.key && c.header),
    targets: arr("targets").filter(isObj).map((x) => ({
      id: str(x, "id"), name: str(x, "name"), code: str(x, "code", "programmeCode", "programme_code") || null, group: str(x, "group", "group_name", "area") || null,
      specialisations: (Array.isArray(x.specialisations) ? x.specialisations : []).filter(isObj).map((s) => ({ code: str(s, "code"), name: str(s, "name") })),
      requested: str(x, "requestedName", "requested_name", "requested") || null,
    })).filter((x) => x.name),
    qualifications: arr("qualifications").map((q) => (isObj(q) ? { code: str(q, "code"), label: str(q, "label", "name") || str(q, "code") } : { code: String(q), label: String(q) }))
      .filter((q) => q.code),
    examBodies: arr("examBodies"), subjects: arr("subjects"), grades: arr("grades"),
    statusWords: isObj(o.statusWords) ? (o.statusWords as TemplateData["statusWords"]) : null,
    fee: isObj(fee) ? { application: pick(fee, "application", "applicationFee", "application_fee") == null ? null : num(fee, "application", "applicationFee", "application_fee"),
      portal: num(fee, "portal", "portalCharge", "portal_charge"), stated: pick(fee, "stated") !== false } : null,
  };
}

/** what a programme correction would do, as the check (prelim_change_route_check) says it */
export interface ChangeFacts {
  may: boolean; refusal: { code: string; message: string } | null; name: string; applicationNo: string; legacyNo: string;
  fromRoute: string; fromName: string; toRoute: string; toName: string; state: string; toState: string;
  feeStatus: string; feePaid: number; feeReferences: string[]; newFee: number | null; feeCovers: boolean | null; missing: string[];
}
/** a list of things in words: words, or objects with a message, a label or an item */
const things = (v: unknown): string[] => (Array.isArray(v)
  ? v.map((x) => (isObj(x) ? str(x, "message", "label", "item", "what", "name", "field") : String(x ?? ""))).map((s) => s.trim()).filter(Boolean) : []);
export function changeFactsOf(raw: unknown): ChangeFacts {
  const c = isObj(raw) ? raw : {};
  const fee = pick(c, "fee");
  const refusal = pick(c, "refusal");
  const nf = pick(c, "toRouteFee", "newFee", "newRouteFee", "toFee");
  const newFee = typeof nf === "number" || typeof nf === "string" ? Number(nf)
    : isObj(nf) ? (num(nf, "total", "amount", "stated_amount") || num(nf, "application", "applicationFee", "application_fee") + num(nf, "portal", "portalCharge", "portal_charge")) : null;
  const covers = pick(c, "feeCovers", "fee_covers");
  return {
    may: pick(c, "may") === true, refusal: isObj(refusal) ? { code: str(refusal, "code"), message: str(refusal, "message") } : null,
    name: str(c, "applicant", "name", "applicantName"), applicationNo: str(c, "applicationNo", "application_no"),
    legacyNo: str(c, "legacyNo", "legacyApplicationNo", "legacy_no", "legacy_application_no", "oldNumber"),
    fromRoute: str(c, "fromRoute", "currentRoute", "route"), fromName: str(c, "fromName", "fromRouteName", "currentRouteName", "routeName"),
    toRoute: str(c, "toRoute", "newRoute"), toName: str(c, "toName", "toRouteName", "newRouteName"),
    state: str(c, "state", "fromState"), toState: str(c, "toState", "stateAfter", "newState"),
    feeStatus: str(c, "feeStatus", "fee_status") || str(fee, "status"), feePaid: num(c, "feePaid", "feeAmount", "paidAmount", "fee_amount") || num(fee, "amount", "paid"),
    feeReferences: words(pick(c, "feeReferences", "fee_references", "references") ?? pick(fee, "references")),
    newFee: newFee != null && Number.isFinite(newFee) ? newFee : null, feeCovers: typeof covers === "boolean" ? covers : null,
    missing: things(pick(c, "missing")),
  };
}

/** a programme correction of the history, read one way */
export interface RouteChange {
  id: string; reference: string; at: string; applicationId: string; applicationNo: string; legacyNo: string; name: string; fromRoute: string; toRoute: string;
  fromName: string; toName: string; fromTarget: string; fromState: string; toState: string; reason: string; feeStatus: string; result: string; refusal: string; by: string; office: string;
}
export function routeChangeOf(raw: unknown): RouteChange {
  return {
    id: str(raw, "id"), reference: str(raw, "reference"), at: str(raw, "at", "created_at"), applicationId: str(raw, "application_id", "applicationId"),
    applicationNo: str(raw, "application_no", "applicationNo"), legacyNo: str(raw, "legacy_application_no", "legacyApplicationNo", "legacy_no", "legacyNo"),
    name: str(raw, "name", "applicant"), fromRoute: str(raw, "from_route", "fromRoute"), toRoute: str(raw, "to_route", "toRoute"),
    fromName: str(raw, "from_route_name", "fromRouteName", "from_name", "fromName") || str(raw, "from_route", "fromRoute"),
    toName: str(raw, "to_route_name", "toRouteName", "to_name", "toName") || str(raw, "to_route", "toRoute"),
    fromTarget: str(raw, "from_target_name", "fromTargetName", "fromTarget"), fromState: str(raw, "from_state", "fromState"), toState: str(raw, "to_state", "toState"),
    reason: str(raw, "reason"), feeStatus: str(raw, "fee_status", "feeStatus"), result: str(raw, "result"),
    refusal: str(raw, "refusal_message", "refusalMessage") || str(raw, "refusal_code", "refusalCode"),
    by: str(raw, "actor_name", "actorName", "by", "actor"), office: str(raw, "actor_office", "actorOffice", "office"),
  };
}

/** an old-portal fee, read one way */
export interface LegacyFee {
  id: string; applicationId: string; applicationNo: string; legacyNo: string; name: string; route: string; routeName: string; reference: string; gatewayReference: string;
  amount: number; paidOn: string; statedStatus: string; state: string; batchReference: string; uploadedBy: string; uploadedById: string; uploadedByMe: boolean;
  decidedBy: string; decidedAt: string; note: string; postedReference: string;
  /** the server's word on whether the reader may decide this fee (a Bursary officer who did not upload it), when it gives one */
  mayDecide: boolean | null;
  /** V745: whether the file gave the amount; a fee "Paid" with none is held all the same, its amount for the Bursary to confirm */
  amountGiven: boolean;
}
/** V745: an old-portal fee's amount in words — the amount, or that the Bursary confirms it */
export const feeAmountWords = (f: Pick<LegacyFee, "amount" | "amountGiven">, naira: (n: number) => string): string =>
  (f.amountGiven ? naira(f.amount) : "amount to confirm");
export function legacyFeeOf(raw: unknown): LegacyFee {
  return {
    id: str(raw, "id"), applicationId: str(raw, "application_id", "applicationId"), applicationNo: str(raw, "application_no", "applicationNo"),
    legacyNo: str(raw, "legacy_application_no", "legacyApplicationNo", "legacy_no", "legacyNo"), name: str(raw, "name", "applicant"),
    route: str(raw, "route"), routeName: str(raw, "route_name", "routeName") || str(raw, "route"),
    reference: str(raw, "legacy_reference", "legacyReference", "reference"), gatewayReference: str(raw, "gateway_reference", "gatewayReference"),
    amount: num(raw, "amount"), paidOn: str(raw, "paid_on", "paidOn"), statedStatus: str(raw, "stated_status", "statedStatus"), state: str(raw, "state"),
    batchReference: str(raw, "batch_reference", "batchReference"), uploadedBy: str(raw, "uploaded_by_name", "uploadedByName", "uploaded_by", "uploadedBy"),
    uploadedById: str(raw, "uploaded_by_id", "uploadedById", "started_by_id", "startedById"), uploadedByMe: pick(raw, "uploadedByYou", "uploaded_by_me", "uploadedByMe") === true,
    decidedBy: str(raw, "decided_by_name", "decidedByName", "decided_by", "decidedBy"), decidedAt: str(raw, "decided_at", "decidedAt"),
    note: str(raw, "decision_note", "decisionNote"), postedReference: str(raw, "posted_reference", "postedReference"),
    mayDecide: typeof pick(raw, "mayDecide") === "boolean" ? (pick(raw, "mayDecide") as boolean) : null,
    amountGiven: pick(raw, "amount") != null && str(raw, "amount").trim() !== "",
  };
}
