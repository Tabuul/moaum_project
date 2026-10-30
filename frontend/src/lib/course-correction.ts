/** A course's code and title corrected (V713): the reasons the University lists, what the database says the change would be,
 *  what hangs on the course, and the trail of every change of code and title. */

/** the reasons a code or title is corrected for, in the University's order */
export const REASONS: [string, string][] = [
  ["OFFICIAL_CORRECTION", "Official course correction"],
  ["TYPOGRAPHICAL_ERROR", "Typographical error"],
  ["ACADEMIC_OFFICE_INSTRUCTION", "Academic Office instruction"],
  ["CURRICULUM_CORRECTION", "Curriculum correction"],
  ["MIGRATION_CORRECTION", "Migration correction"],
  ["DUPLICATE_DATA_CORRECTION", "Duplicate data correction"],
  ["COURSE_APPROVAL_UPDATE", "Course approval update"],
  ["LEGACY_DATA_CORRECTION", "Legacy data correction"],
  ["ICT_SUPPORT_CORRECTION", "ICT Support correction"],
  ["OTHER", "Other"],
];
export const REASON_WORDS: Record<string, string> = Object.fromEntries(REASONS);

/** how a change of code or title came about */
export const CHANGE_SOURCE: Record<string, string> = {
  CORRECTION: "Correction",
  EDIT: "Department desk or upload",
  MIGRATION: "Migration",
  AUDIT: "Before V713",
};

export interface CourseImpact {
  registrations: number; currentRegistrations: number; currentSession: string | null; students: number; carryOvers: number;
  results: number; publishedResults: number; scoreSheets: number; classes: number; lecturerAllocations: number;
  programmeBindings: number; programmes: number; cbtExams: number; questions: number; deferred: number; oldPortalResults: number;
  broadsheetOmissions: number; pastClasses: number; pastClassesOtherTitle: number; generalOffice: string | null; changes: number;
}

export interface SimilarCourse {
  id: string; code: string; shown: string; title: string; state: string; dept_code: string | null; dept_name: string | null;
  level: number; units: number; programmes?: number; sameTitle?: boolean; possibleDuplicate?: boolean;
}

export interface CorrectionCheck {
  id: string; code: string; shown: string; title: string; version: string;
  newCode: string | null; newTitle: string; key: string; codeChanged: boolean; titleChanged: boolean; separate: boolean;
  generalOffice: string | null; refusal: { code: string; message: string } | null;
  sameCode: SimilarCourse[]; sameTitle: SimilarCourse[];
  impact: CourseImpact; may: { code: boolean; title: boolean };
}

export interface CorrectionDone {
  id: string; code: string; shown: string; title: string; was: string; wasTitle: string; separate: boolean;
  classesRetitled: number; version: string; reason: string; remarks: string | null;
}

export interface CourseChangeRow {
  id: string; course_id: string; current_code: string | null; current_shown: string | null; current_title: string | null;
  dept_code: string | null; dept_name: string | null; field: "CODE" | "TITLE"; old_value: string; new_value: string;
  reason_kind: string | null; reason_words: string | null; remarks: string | null; reason: string | null; source: string;
  past_classes: boolean | null; ticket: string | null; changed_at: string; changed_by: string | null; changed_office: string | null;
}
export interface CourseChangeList { total: number; page: number; size: number; rows: CourseChangeRow[] }

const plural = (n: number, one: string, many = `${one}s`) => `${n.toLocaleString()} ${n === 1 ? one : many}`;

/** what hangs on the course, each count that is not nought, in the order a person reads them */
export function impactLines(i: CourseImpact | null | undefined): string[] {
  if (!i) return [];
  const n = (v: unknown) => Number(v ?? 0);
  const out: string[] = [];
  if (n(i.registrations)) out.push(`${plural(n(i.registrations), "registration")} (${plural(n(i.students), "student")})${n(i.currentRegistrations) ? `, ${n(i.currentRegistrations).toLocaleString()} in ${i.currentSession ?? "this session"}` : ""}`);
  if (n(i.carryOvers)) out.push(plural(n(i.carryOvers), "carry-over registration"));
  if (n(i.results)) out.push(`${plural(n(i.results), "result")}${n(i.publishedResults) ? `, ${n(i.publishedResults).toLocaleString()} published` : ""} on ${plural(n(i.scoreSheets), "score sheet")}`);
  if (n(i.classes)) out.push(plural(n(i.classes), "class", "classes") + " (session offerings)");
  if (n(i.lecturerAllocations)) out.push(plural(n(i.lecturerAllocations), "lecturer allocation"));
  if (n(i.programmeBindings)) out.push(`${n(i.programmes) === 1 ? "1 programme binds" : `${n(i.programmes).toLocaleString()} programmes bind`} it (${plural(n(i.programmeBindings), "binding")})`);
  if (n(i.cbtExams)) out.push(plural(n(i.cbtExams), "CBT examination"));
  if (n(i.questions)) out.push(plural(n(i.questions), "question") + " in the question bank");
  if (n(i.deferred)) out.push(plural(n(i.deferred), "deferred course"));
  if (n(i.oldPortalResults)) out.push(plural(n(i.oldPortalResults), "old-portal result"));
  if (n(i.broadsheetOmissions)) out.push(plural(n(i.broadsheetOmissions), "broadsheet omission"));
  if (i.generalOffice) out.push(`a ${i.generalOffice.toUpperCase()} course: its classification stays`);
  return out;
}

/** the one sentence the warning opens with */
export function impactSentence(i: CourseImpact | null | undefined): string {
  if (!i) return "";
  const regs = Number(i.registrations ?? 0), res = Number(i.results ?? 0);
  if (!regs && !res && !Number(i.classes ?? 0) && !Number(i.programmeBindings ?? 0)) return "Nothing hangs on this course yet.";
  return `This course has ${plural(regs, "registration")} and ${plural(res, "result record")}. The change shows on every one of them: they stay on the same course.`;
}

/** may the form be sent: something changes, a reason is chosen, Other is explained, and the database refuses nothing */
export function readyToReview(form: { code: string; title: string; reason: string; remarks: string }, check: CorrectionCheck | null): string | null {
  if (!form.title.trim()) return "Give the course its title.";
  if (!form.code.trim()) return "Give the course its code.";
  if (!check) return "Checking…";
  if (check.refusal) return check.refusal.code === "COURSE_UNCHANGED" ? "Change the code or the title." : check.refusal.message;
  if (check.codeChanged && !check.may.code) return "You may not change this course's code.";
  if (check.titleChanged && !check.may.title) return "You may not change this course's title.";
  if (!form.reason) return "Choose the reason for the change.";
  if (form.reason === "OTHER" && form.remarks.trim().length < 5) return "Explain \"Other\" in the remarks.";
  return null;
}

/** the reason as it is written to the request's audit (X-Reason) */
export function reasonText(reason: string, remarks: string): string {
  const words = REASON_WORDS[reason] ?? reason;
  const r = remarks.trim().replace(/\s+/g, " ");
  return r ? `${words}: ${r}` : words;
}
