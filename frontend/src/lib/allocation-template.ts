/**
 * A department's course allocation template (V478): the workbook built from what the server issued — the department's classes
 * with whoever teaches each now, its lecturers, programmes and courses as lists to choose from — and read back on upload.
 * The register's values are written in and locked; a person chooses only the lecturer, the role, whether the teaching crosses
 * departments, and a remark. The template's own context (reference, department, programme type, session, semester) is on
 * the letterhead and on a hidden sheet; the server checks an upload against the template it issued, never against the file.
 */
import type { Cell, SheetSpec } from "./xlsx-write.ts";
import type { RowIn } from "./allocation-import.ts";

export type ProgrammeType = "UNDERGRADUATE" | "POSTGRADUATE";

export interface TemplateContext {
  facultyCode: string | null; facultyName: string | null; deptCode: string; deptName: string; programmeType: ProgrammeType;
  session: string; semester: number; stream?: string; version: number;
  reference?: string; issuedAt?: string; issuedBy?: string | null; issuedOffice?: string;
}
export interface TemplateLecturer { id: string; staff_number: string; name: string; email: string | null; load: number }
export interface TemplateProgramme { code: string; name: string; category: string; pg_award?: string | null; dept_name: string; faculty_name: string | null }
export interface TemplateClass {
  course_id: string; code: string; title: string; units: number; kind: string; level: number; course_semester?: number; both_semesters?: boolean;
  offering_id: string | null; lecturer_id: string | null; lecturer_staff_number: string | null; lecturer: string | null;
  second_examiner_id: string | null; second_staff_number: string | null; second_examiner: string | null;
  co_lecturers: string; programme_codes: string; programme_names: string;
}
export interface TemplateSummary { programmes: number; classes: number; open: number; lecturers: number; allocations: number; unallocated: number; /** courses its programmes take from other departments */ borrowed?: number }
/** a course the department's programmes take from another department: its owner allocates it (shown, never uploaded) */
export interface TemplateBorrowed { code: string; title: string; units: number; level: number; owner_dept: string | null; owner_code: string | null; programme_codes: string; lecturer: string | null }
export interface IssuedTemplate {
  context: TemplateContext; summary: TemplateSummary; programmes: TemplateProgramme[]; lecturers: TemplateLecturer[]; classes: TemplateClass[];
  borrowed?: TemplateBorrowed[];
}

/** the sheets, by name */
export const SHEET = { allocation: "Course Allocation", lecturers: "Lecturers", courses: "Courses", programmes: "Programmes", borrowed: "Borrowed Courses", instructions: "Instructions", template: "Template" } as const;
/** the allocation sheet's columns, in order */
export const COLUMNS = ["S/N", "Faculty", "Department", "Course code", "Course title", "Units", "Course type", "Level", "Programmes", "Session", "Semester",
  "Lecturer now", "Lecturer", "Role", "Cross-department", "Remarks", "Course ID"] as const;
const COL = Object.fromEntries(COLUMNS.map((c, i) => [c, i])) as Record<(typeof COLUMNS)[number], number>;
/** blank rows at the end for a further co-lecturer or second examiner, the course chosen from the list */
export const EXTRA_ROWS = 25;
const DASH = " — ";

export const semesterWord = (n: number) => (n === 1 ? "First semester" : n === 2 ? "Second semester" : n === 3 ? "Third semester" : `Semester ${n}`);
export const typeWord = (t: string) => (t === "POSTGRADUATE" ? "Postgraduate" : "Undergraduate");

/** the choice a lecturer is picked by: the name and the staff number, which the upload reads the number back from */
export function lecturerChoice(name: string | null | undefined, staff: string | null | undefined): string {
  return `${(name ?? "").trim()}${DASH}${(staff ?? "").trim()}`;
}

/** the staff number of a choice ("SURNAME, Given — STF/0012"), or the cell itself when it holds a number alone */
export function staffOf(choice: string): string {
  const v = (choice ?? "").trim();
  const i = v.lastIndexOf(DASH.trim());
  return i < 0 ? v : v.slice(i + 1).trim();
}

/** the name of a choice, or "" when the cell holds a number alone */
export function nameOf(choice: string): string {
  const v = (choice ?? "").trim();
  const i = v.lastIndexOf(DASH.trim());
  return i < 0 ? "" : v.slice(0, i).trim();
}

/** the course a choice names ("CSC 301 — Data Structures"), or the cell itself */
export function courseOf(choice: string): string {
  const v = (choice ?? "").trim();
  const i = v.indexOf(DASH.trim());
  return i < 0 ? v : v.slice(0, i).trim();
}

function parseCo(json: string): { staff_number: string; name: string }[] {
  try {
    const v = JSON.parse(json || "[]");
    return Array.isArray(v) ? v : [];
  } catch {
    return [];
  }
}

/** the workbook's sheets, from a template the server issued */
export function templateSheets(t: IssuedTemplate, institution: string, generatedOn: string): SheetSpec[] {
  const c = t.context;
  const fac = c.facultyName ?? c.facultyCode ?? "";
  const sem = semesterWord(c.semester);
  const letterhead: Cell[][] = [
    [institution.toUpperCase()],
    ["COURSE ALLOCATION TEMPLATE"],
    ["Faculty", `${fac}${c.facultyCode ? ` (${c.facultyCode})` : ""}`],
    ["Department", `${c.deptName} (${c.deptCode})`],
    ["Programme type", typeWord(c.programmeType)],
    ["Academic session", c.session],
    ["Semester", sem],
    ["Generated by", `${c.issuedBy ?? ""}${c.issuedOffice ? ` (${c.issuedOffice})` : ""}`],
    ["Generated", generatedOn],
    ["Template reference", `${c.reference ?? ""} · version ${c.version}`],
    [],
  ];
  const header = letterhead.length;
  const rows: Cell[][] = [...letterhead, [...COLUMNS]];
  let n = 0;
  const base = (k: TemplateClass): Cell[] => ["", fac, c.deptName, k.code, k.title, k.units, k.kind, k.level, k.programme_codes ? `${k.programme_codes}${k.programme_names ? ` (${k.programme_names})` : ""}` : "", c.session, sem];
  for (const k of t.classes) {
    const now = [k.lecturer ? `Lead: ${lecturerChoice(k.lecturer, k.lecturer_staff_number)}` : "Not allocated",
      ...(k.second_examiner ? [`Second examiner: ${k.second_examiner}`] : []), ...parseCo(k.co_lecturers).map((x) => `Co-lecturer: ${x.name}`)].join("; ")
      + (k.offering_id ? "" : classNote(c.programmeType));
    const lead = k.lecturer ? lecturerChoice(k.lecturer, k.lecturer_staff_number) : "";
    rows.push([++n, ...base(k).slice(1), now, lead, "Lecturer", "", "", k.course_id]);
    if (k.second_examiner) rows.push([++n, ...base(k).slice(1), "", lecturerChoice(k.second_examiner, k.second_staff_number), "Second examiner", "", "", k.course_id]);
    for (const co of parseCo(k.co_lecturers)) rows.push([++n, ...base(k).slice(1), "", lecturerChoice(co.name, co.staff_number), "Co-lecturer", "", "", k.course_id]);
  }
  const firstExtra = rows.length;
  for (let i = 0; i < EXTRA_ROWS; i++) rows.push([++n, fac, c.deptName, "", "", "", "", "", "", c.session, sem, "", "", "", "", "", ""]);
  const last = rows.length - 1;
  for (let i = header + 1; i < rows.length; i++) rows[i][0] = i - header;   // S/N first, display only

  const lect: Cell[][] = [["Staff ID", "Lecturer name", "Choice", "Department", "Faculty", "Email", "Status", "Teaching load (units)", "Person ID"],
    ...t.lecturers.map((l) => [l.staff_number, l.name, lecturerChoice(l.name, l.staff_number), c.deptName, fac, l.email ?? "", "Active", Number(l.load) || 0, l.id])];
  const crs: Cell[][] = [["Course code", "Course title", "Choice", "Units", "Course type", "Department", "Programmes", "Level", "Semester", "Class this semester", "Course ID"],
    ...t.classes.map((k) => [k.code, k.title, `${k.code}${DASH}${k.title}`, k.units, k.kind, c.deptName, k.programme_codes, k.level,
      k.both_semesters ? "First and second" : semesterWord(k.course_semester ?? c.semester), k.offering_id ? "Open" : "Not yet open", k.course_id])];
  const progs: Cell[][] = [["Programme code", "Programme name", "Department", "Faculty", "Programme type", "Status"],
    ...t.programmes.map((p) => [p.code, p.name, p.dept_name, p.faculty_name ?? fac, typeWord(c.programmeType), "Active"])];
  const instructions: Cell[][] = [
    ["How to complete this template"],
    [""],
    ["1", `Choose the Lecturer for each class from the list (lecturers of ${c.deptName}). Leave it blank to leave the class as it is.`],
    ["2", "Role: Lecturer (the lead, who owns the score sheet), Co-lecturer or Second examiner."],
    ["3", "Cross-department: YES only when a lecturer of another department teaches the class."],
    ["4", "For a further co-lecturer or second examiner, use a row at the end: choose the course, the lecturer and the role."],
    ["5", `Upload the file on the Course Allocation page with ${c.deptName}, ${c.session} and ${sem.toLowerCase()} chosen. Nothing is written until you confirm the preview.`],
    ["6", "Borrowed Courses lists the courses this department's programmes take from other departments: their own departments allocate them."],
    [""],
    ["The grey cells come from the register and cannot be changed here. The upload is checked against the register and against this template's reference, whatever the file says."],
  ];
  const lectRange = t.lecturers.length ? `'${SHEET.lecturers}'!$C$2:$C$${t.lecturers.length + 1}` : undefined;
  const courseRange = t.classes.length ? `'${SHEET.courses}'!$C$2:$C$${t.classes.length + 1}` : undefined;
  const col = (name: (typeof COLUMNS)[number]) => String.fromCharCode(65 + COL[name]);
  const dataFrom = header + 2;     // 1-based first data row
  const allocOpts = {
    headerRows: [header],
    freezeBelow: header + 1,
    hiddenCols: [COL["Course ID"]],
    protect: { unlocked: [
      { cols: [COL.Lecturer, COL.Role, COL["Cross-department"], COL.Remarks], fromRow: header + 1, toRow: last },
      { cols: [COL["Course code"]], fromRow: firstExtra, toRow: last },
    ] },
    validations: [
      ...(lectRange ? [{ sqref: `${col("Lecturer")}${dataFrom}:${col("Lecturer")}${last + 1}`, range: lectRange, prompt: `A lecturer of ${c.deptName}` }] : []),
      { sqref: `${col("Role")}${dataFrom}:${col("Role")}${last + 1}`, list: ["Lecturer", "Co-lecturer", "Second examiner"] },
      { sqref: `${col("Cross-department")}${dataFrom}:${col("Cross-department")}${last + 1}`, list: ["YES", "NO"] },
      ...(courseRange ? [{ sqref: `${col("Course code")}${firstExtra + 1}:${col("Course code")}${last + 1}`, range: courseRange, prompt: `A course of ${c.deptName}` }] : []),
    ],
  };
  const borrowed: Cell[][] = [["Course code", "Course title", "Units", "Level", "Owning department", "Taken by programmes", "Lecturer now"],
    ...(t.borrowed ?? []).map((b) => [b.code, b.title, b.units, b.level, b.owner_dept ?? b.owner_code ?? "", b.programme_codes, b.lecturer ?? "Not allocated"])];
  const context: Cell[][] = [["Key", "Value"], ["reference", c.reference ?? ""], ["version", c.version], ["faculty", c.facultyCode ?? ""], ["department", c.deptCode],
    ["programme_type", c.programmeType], ["session", c.session], ["semester", c.semester], ["generated", c.issuedAt ?? ""]];
  return [
    [SHEET.allocation, rows, allocOpts],
    [SHEET.lecturers, lect, { headerRows: [0], freezeBelow: 1, hiddenCols: [8], protect: { unlocked: [] } }],
    [SHEET.courses, crs, { headerRows: [0], freezeBelow: 1, hiddenCols: [10], protect: { unlocked: [] } }],
    [SHEET.programmes, progs, { headerRows: [0], freezeBelow: 1, protect: { unlocked: [] } }],
    [SHEET.borrowed, borrowed, { headerRows: [0], freezeBelow: 1, protect: { unlocked: [] } }],
    [SHEET.instructions, instructions],
    [SHEET.template, context, { headerRows: [0], hidden: true, protect: { unlocked: [] } }],
  ];
}

function classNote(type: ProgrammeType): string {
  return type === "POSTGRADUATE" ? " (no class open yet: the School opens it)" : " (no class yet: the import opens it)";
}

/** what an uploaded template says of itself, and its rows as the server reads them */
export interface ReadTemplate {
  context: { reference: string; version: number; faculty: string; dept: string; programmeType: string; session: string; semester: number };
  rows: RowIn[];
  /** classes whose Lecturer cell is blank: left as they are */
  blank: number;
}

/** a workbook's sheets read back: null when it is not a department template (no hidden context sheet, no allocation sheet) */
export function readTemplate(sheets: { name: string; rows: string[][] }[]): ReadTemplate | null {
  const ctxSheet = sheets.find((s) => s.name.trim().toLowerCase() === SHEET.template.toLowerCase());
  const alloc = sheets.find((s) => s.name.trim().toLowerCase() === SHEET.allocation.toLowerCase());
  if (!ctxSheet || !alloc) return null;
  const kv: Record<string, string> = {};
  for (const r of ctxSheet.rows) if (r[0]) kv[String(r[0]).trim().toLowerCase()] = String(r[1] ?? "").trim();
  if (!kv.reference) return null;
  const hi = alloc.rows.findIndex((r) => String(r[0] ?? "").trim().toUpperCase() === "S/N" && r.some((x) => String(x ?? "").trim() === "Lecturer"));
  if (hi < 0) return null;
  const head = alloc.rows[hi].map((x) => String(x ?? "").trim().toLowerCase());
  const at = (name: string) => head.indexOf(name.toLowerCase());
  const ix = { course: at("Course code"), title: at("Course title"), level: at("Level"), session: at("Session"), semester: at("Semester"),
    lecturer: at("Lecturer"), role: at("Role"), cross: at("Cross-department") };
  const g = (r: string[], i: number) => (i < 0 ? "" : String(r[i] ?? "").trim());
  const semester = Number(kv.semester) || 0;
  const rows: RowIn[] = [];
  let blank = 0;
  alloc.rows.slice(hi + 1).forEach((r, i) => {
    const course = courseOf(g(r, ix.course));
    if (!course) return;
    const lecturer = g(r, ix.lecturer);
    if (!lecturer) { blank++; return; }
    const semCell = g(r, ix.semester);
    const semNo = /^first/i.test(semCell) ? 1 : /^second/i.test(semCell) ? 2 : /^third/i.test(semCell) ? 3 : Number(semCell) || semester;
    const cross = g(r, ix.cross).toUpperCase();
    rows.push({
      row: hi + i + 2, staffId: staffOf(lecturer), lecturerName: nameOf(lecturer), lecturerDept: "", courseCode: course,
      courseTitle: g(r, ix.title), courseDept: "", programme: "", level: g(r, ix.level),
      session: g(r, ix.session) || kv.session, semester: String(semNo), role: g(r, ix.role) || "Lecturer", crossDepartment: cross === "YES" ? "YES" : "",
    });
  });
  return {
    context: { reference: kv.reference, version: Number(kv.version) || 1, faculty: kv.faculty ?? "", dept: kv.department ?? "", programmeType: kv.programme_type ?? "",
      session: kv.session ?? "", semester },
    rows, blank,
  };
}
