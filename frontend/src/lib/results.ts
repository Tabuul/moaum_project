import { buildXlsx, loadCrest } from "@/lib/xlsx";

const SCHOOL = "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI";

/** a filename base as a readable title: "ledger-2026-2027" → "Ledger 2026 2027" */
function humanize(base: string): string {
  const s = base.replace(/[-_]+/g, " ").replace(/\s+/g, " ").trim();
  return s ? s.charAt(0).toUpperCase() + s.slice(1) : "Download";
}

/** the shapes the results and registration modules answer with */
export interface SheetListed {
  id: string;
  courseCode: string;
  courseTitle: string;
  units: number;
  deptName: string;
  facultyName: string;
  session: string;
  semester: number;
  stage: string;
  spineStage: number;
  sitting: string;
  dueOn: string | null;
  daysLate: number | null;
  returnedTimes: number;
  lecturer: string | null;
  candidates: number;
  failRate: number | null;
  mayAct: boolean;
  blockedForYou: boolean;
}

export interface SheetListing {
  tiles: { expected: number; senateApproved: number; inWorkflow: number; notSubmitted: number };
  sheets: SheetListed[];
  desk: string;
}

export interface Decision {
  id: string;
  fromStage: string;
  toStage: string;
  kind: "SUBMIT" | "ADVANCE" | "RETURN";
  actorId: string;
  actor: string | null;
  actorOffice: string;
  comment: string | null;
  decidedAt: string;
}

export interface Mark {
  studentId: string;
  number: string;
  surname: string;
  otherNames: string;
  ca: number | null;
  exam: number | null;
  total: number | null;
  grade: string | null;
  points: number | null;
  outcome: string;
  version: number;
  amended: boolean;
}

export interface SheetDetail {
  sheet: SheetListed;
  secondExaminer: string | null;
  senateMinute: string | null;
  publishedAt: string | null;
  engineVersion: string | null;
  chain: Decision[];
  marks: Mark[];
}

export interface ExamSession {
  id: string;
  session: string;
  semester: number;
  kind: string;
  examsFrom: string;
  examsTo: string;
  sheetsDue: string;
  state: string;
  openedAt: string | null;
  sheets: number;
  candidates: number;
  outstanding: number;
}

export interface Monitor {
  examSession: ExamSession;
  faculties: { facultyCode: string; facultyName: string; expected: number; submitted: number; verified: number; pastTheBoard: number; outstanding: number; progress: number }[];
  outstanding: { id: string; courseCode: string; deptName: string; facultyCode: string; lecturer: string | null; candidates: number; daysLate: number | null; escalatedTo: string }[];
}

export interface ClassList {
  offeringId: string;
  courseCode: string;
  courseTitle: string;
  units: number;
  session: string;
  semester: number;
  deptCode: string;
  deptName: string;
  lecturer: string | null;
  all: number;
  own: number;
  borrowed: number;
  fromProgrammes: string[];
  rows: { studentId: string; number: string; surname: string; otherNames: string; programmeCode: string; programmeName: string; deptCode: string; level: number; basis: string; cleared: boolean }[];
}

/** the desks, as the prototype names them (proto/part28 CHAIN) */
export const STAGE_LABEL: Record<string, [string, string]> = {
  ENTRY: ["Not submitted", "Course lecturer"],
  VERIFICATION: ["Submitted for verification", "Second examiner"],
  DEPT_BOARD: ["Verified", "Head of Department"],
  FACULTY_SCRUTINY: ["Departmental approved", "Faculty Examinations Officer"],
  FACULTY_COMPILATION: ["Faculty scrutiny done", "Faculty Officer"],
  FACULTY_BOARD: ["Compiled for the Board", "Dean, in the Board"],
  RECORDS: ["Faculty Board approved", "Exams & Records"],
  SENATE: ["Validated", "Senate, on the Registrar’s minute"],
  PUBLISHED: ["Senate approved — published", ""],
};

/** the six-stage spine a student sees (proto/part15 RS_STAGES) */
export const RS_STAGES: [string, string, string][] = [
  ["Draft", "Scores are being entered on the sheet", "Submit for verification"],
  ["Submitted for verification", "With the departmental examinations officer", "Verify the sheet"],
  ["Verified", "Arithmetic and completeness checked by a second academic", "Approve at Departmental Board"],
  ["Departmental Board approved", "With the Faculty Board", "Approve at Faculty Board"],
  ["Faculty Board approved", "With Senate", "Approve for Senate"],
  ["Senate approved — published", "Visible to students; the result is now final", ""],
];

/** a table for download: the first row is the header. csv() tags the rows so
 *  download() writes a formatted .xlsx (auto column widths, bordered cells). */
export interface SheetData { __sheet: (string | number | null | undefined)[][]; __meta?: [string, string][] }

/** rows (the first is the header); meta is the labelled block written above the table — Department, Programme… */
export function csv(rows: (string | number | null | undefined)[][], meta?: [string, string][]): SheetData {
  return meta && meta.length ? { __sheet: rows, __meta: meta } : { __sheet: rows };
}

function saveBlob(name: string, blob: Blob) {
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}

/** download a table as a formatted .xlsx (branded header: crest, University name, title, date),
 *  or a raw string as text. Stays synchronous — the crest is fetched then the file saved. */
export function download(name: string, data: string | SheetData) {
  if (typeof data === "object" && data !== null && "__sheet" in data) {
    const rows = data.__sheet;
    const headers = (rows[0] ?? []).map((h) => String(h ?? ""));
    const base = name.replace(/\.(csv|xlsx|txt)$/i, "");
    const sheet = base.replace(/[\\/?*[\]:]/g, "-").slice(0, 31) || "Sheet1";
    const date = "Generated " + new Date().toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" });
    void loadCrest().then((logo) =>
      saveBlob(base + ".xlsx", buildXlsx(headers, rows.slice(1), sheet, { school: SCHOOL, title: humanize(base), date, logo: logo ?? undefined, meta: data.__meta })),
    );
    return;
  }
  saveBlob(name, new Blob([data], { type: "text/csv;charset=utf-8" }));
}

/* ── the lecturer's own sheets, the roll, the broadsheet and Senate (V013 results module, second cut) ── */
export interface MySheet {
  id: string; courseCode: string; courseTitle: string; units: number; session: string; semester: number; stage: string;
  spineStage: number; dueOn: string | null; daysLate: number | null; daysToDue: number | null; returnedTimes: number; candidates: number; entered: number;
  graded: number; secondExaminer: string | null; mine: boolean;
  openQueries: number; bankQuestions: number; caEntered: number;
}
export interface RollRow {
  studentId: string; number: string; surname: string; otherNames: string; programmeCode: string; programmeName: string; level: number;
  ca: number | null; exam: number | null; total: number | null; grade: string | null; points: number | null; outcome: string | null; version: number | null;
}
export interface GradeBand { grade: string; low: number; high: number; points: number }
export interface ClassBand { clazz: string; low: number; high: number; ord: number }
export interface BroadsheetMark { courseCode: string; stage: string; total: number | null; grade: string | null; points: number | null; outcome: string | null; counted: boolean }
export interface BroadsheetRow { studentId: string; number: string; name: string; marks: BroadsheetMark[]; units: number; cur: number; cue: number; points: number; gpa: number | null; pending: number; standing: string; tcr: number; tce: number; twgp: number; cgpa: number | null; lcgpa: number | null; carryovers: string[]; remarks: string }
export interface Broadsheet {
  programme: string; level: number; session: string; semester: number; courses: { courseCode: string; title: string; units: number; kind: string }[]; rows: BroadsheetRow[];
  meanGpa: number | null; passed: number; carrying: number; pendingSets: number; bands: GradeBand[]; classes: ClassBand[]; gradingInstrument: string | null;
}
export interface SenateFaculty { facultyCode: string; facultyName: string; sets: number; atSenate: number; published: number; outstanding: number; candidates: number }
export interface SenateMinute { minute: string; firstPublishedAt: string; lastPublishedAt: string; sets: number; candidates: number }
export interface Senate { session: string; semester: number; faculties: SenateFaculty[]; minutes: SenateMinute[]; sets: number; atSenate: number; published: number; outstanding: number; candidatesPublished: number }

/** the outcomes a mark can carry besides a grade (assessment.score) */
export const OUTCOMES = ["GRADED", "ABSENT", "WITHHELD", "INCOMPLETE", "MALPRACTICE", "EXEMPTED"] as const;

/** The stage of a lecturer's sheet as a pill, its label and the action it offers.
 *  Pure — lives here (not in the "use client" SheetsList) so a server component
 *  (the lecturer dashboard) can call it without the RSC "called on the server" error. */
export function stageOf(s: MySheet): { pill: "ok" | "info" | "bad" | "grey"; text: string; act: string; kind: "primary" | "urgent" | "ghost" } {
  if (s.stage === "ENTRY") {
    if (s.entered === 0) return { pill: "bad", text: "Not started", act: "Type them in", kind: "urgent" };
    if (s.entered < s.candidates) return { pill: "bad", text: `Draft — ${s.candidates - s.entered} to enter`, act: "Continue", kind: "primary" };
    return { pill: "info", text: "Complete — not yet submitted", act: "Submit and attest", kind: "primary" };
  }
  if (s.stage === "PUBLISHED") return { pill: "ok", text: "Senate approved — published", act: "View", kind: "ghost" };
  return { pill: "info", text: STAGE_LABEL[s.stage]?.[0] ?? s.stage, act: "View", kind: "ghost" };
}
