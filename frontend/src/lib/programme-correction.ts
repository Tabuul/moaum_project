/** A programme's code corrected (V716): the reasons the University lists, what the database says the change would be, what hangs on
 *  the programme, and the trail of every correction. Every figure, refusal and permission is the server's; these only say them. */

/** the reasons a programme's code is corrected for, in the University's order */
export const REASONS: [string, string][] = [
  ["WRONG_CODE_ENTERED", "Wrong code entered"],
  ["JAMB_CODE_CHANGED", "JAMB code changed"],
  ["SENATE_RENUMBERING", "Senate renumbering"],
  ["MIGRATION_CORRECTION", "Migration correction"],
  ["LEGACY_DATA_CORRECTION", "Legacy data correction"],
  ["DUPLICATE_DATA_CORRECTION", "Duplicate data correction"],
  ["ICT_SUPPORT_CORRECTION", "ICT Support correction"],
  ["OTHER", "Other"],
];
export const REASON_WORDS: Record<string, string> = Object.fromEntries(REASONS);

export interface ProgrammeImpact {
  students: number; activeStudents: number; pgApplications: number; cceCandidates: number; jupebApplications: number; feeLines: number;
  courseBindings: number; specialisations: number; ownedCourses: number; transfersIn: number; aliases: string[]; jambNames: number;
  rows: Record<string, number>; history: Record<string, number>;
}

export interface ProgrammeCodeCheck {
  code: string; name: string; category: string | null; deptCode: string | null; facultyCode: string | null; archived: boolean; version: string;
  newCode: string | null; reused: boolean; refusal: { code: string; message: string } | null; impact: ProgrammeImpact; may: boolean;
}

export interface ProgrammeCodeDone {
  id: string; code: string; was: string; name: string; category: string | null; students: number; reused: boolean;
  moved: Record<string, number> | null; kept: Record<string, number> | null; mergeId: string; version: string; reason: string; remarks: string | null;
}

export interface ProgrammeChangeRow {
  id: string; old_code: string; new_code: string; name: string; category: string | null; reason_kind: string; reason_words: string | null;
  remarks: string | null; ticket: string | null; students: number; moved: Record<string, number> | null; changed_at: string; changed_office: string;
  changed_by: string; undone_at: string | null; undone_office: string | null; undone_by: string | null; undo_reason: string | null;
  new_code_kept: boolean | null; dept_name: string | null; new_archived: boolean | null; students_now: number;
}
export interface ProgrammeChangeList { total: number; page: number; size: number; rows: ProgrammeChangeRow[]; may: boolean }

/** the code as the register holds it: C and five digits, spaces and case forgiven */
export function normalCode(code: string): string {
  return code.replace(/\s+/g, "").toUpperCase();
}

/** why a new code cannot be checked yet, or null */
export function codeProblem(code: string, current: string): string | null {
  const c = normalCode(code);
  if (!c) return "Give the programme's new code.";
  if (!/^C\d{5}$/.test(c)) return `A programme code is C and five digits (C00023), as JAMB writes it; ${c} is not.`;
  if (c === normalCode(current)) return "The code is as it stands; nothing would change.";
  return null;
}

/** the remarks a reason needs: "Other" is explained */
export function reasonProblem(reason: string, remarks: string): string | null {
  if (!reason) return "Choose the reason for the correction.";
  if (reason === "OTHER" && remarks.trim().length < 5) return "“Other” is explained in the remarks.";
  if (remarks.trim().length > 2000) return "The remarks are at most 2,000 characters.";
  return null;
}

const plural = (n: number, one: string, many = `${one}s`) => `${n.toLocaleString()} ${n === 1 ? one : many}`;

/** the words for a classed column the impact names */
export const ROW_WORDS: Record<string, string> = {
  "people.student.programme_code": "students",
  "admissions.pg_application.programme_code": "postgraduate applications",
  "admissions.cce_candidate.programme_code": "CCE candidates",
  "jupeb.application.programme_code": "JUPEB applications",
  "finance.fee_schedule.programme_code": "fee lines",
  "catalogue.course_offer.programme_code": "course bindings",
  "catalogue.course_offer_specialisation.programme_code": "specialisation bindings",
  "catalogue.programme_specialisation.programme_code": "specialisations",
  "catalogue.offer_proposal.programme_code": "proposed bindings",
  "catalogue.offering_teacher.programme_code": "class teachers",
  "catalogue.course.owner_programme": "courses it owns",
  "admissions.pg_course.programme_code": "postgraduate courses",
  "people.transfer_application.to_programme_code": "transfers into it",
  "admissions.programme_change_request.to_programme_code": "changes of programme into it",
  "admissions.prelim_review.target_programme": "preliminary students aiming for it",
  "admissions.prelim_target.programme_code": "preliminary targets",
  "extexam.appointment.programme_code": "external examiner appointments",
  "people.pg_cycle.programme_code": "postgraduate cycles",
  "admissions.pg_legacy_programme.programme_code": "old-portal programme mappings",
  "admissions.programme_rule.programme_code": "admission rules",
  "admissions.rule_subject_group.programme_code": "admission subject groups",
  "admissions.programme_olevel_allowance.programme_code": "O'Level allowances",
  "admissions.programme_closed.programme_code": "closures to admission",
  "admissions.screening_exam_programme.programme_code": "screening examinations",
  "college.programme_rule.programme_code": "College rules",
  "finance.gst_fee.programme_code": "GST fee lines",
  "jupeb.combination_relevance.programme_code": "JUPEB combinations",
  "ref.programme_route.programme_code": "admission routes",
  "ref.jamb_alias_name.code": "JAMB names",
  "ref.jamb_alias.code": "JAMB primary name",
};

/** what hangs on the programme, each count that is not nought, in the order a person reads them */
export function impactLines(i: ProgrammeImpact | null | undefined): string[] {
  if (!i) return [];
  const n = (v: unknown) => Number(v ?? 0);
  const out: string[] = [];
  if (n(i.students)) out.push(`${plural(n(i.students), "student")}${n(i.activeStudents) !== n(i.students) ? `, ${n(i.activeStudents).toLocaleString()} in study` : ""}`);
  if (n(i.pgApplications)) out.push(plural(n(i.pgApplications), "postgraduate application"));
  if (n(i.cceCandidates)) out.push(plural(n(i.cceCandidates), "CCE candidate"));
  if (n(i.jupebApplications)) out.push(plural(n(i.jupebApplications), "JUPEB application"));
  if (n(i.feeLines)) out.push(plural(n(i.feeLines), "fee line"));
  if (n(i.courseBindings)) out.push(plural(n(i.courseBindings), "course binding"));
  if (n(i.specialisations)) out.push(plural(n(i.specialisations), "specialisation"));
  if (n(i.ownedCourses)) out.push(`${plural(n(i.ownedCourses), "course")} it owns`);
  if (n(i.transfersIn)) out.push(plural(n(i.transfersIn), "transfer into it"));
  const named = new Set(["people.student.programme_code", "admissions.pg_application.programme_code", "admissions.cce_candidate.programme_code", "jupeb.application.programme_code",
    "finance.fee_schedule.programme_code", "catalogue.course_offer.programme_code", "catalogue.programme_specialisation.programme_code", "catalogue.course.owner_programme",
    "people.transfer_application.to_programme_code"]);
  for (const [k, v] of Object.entries(i.rows ?? {})) if (!named.has(k) && n(v)) out.push(`${n(v).toLocaleString()} ${ROW_WORDS[k] ?? k}`);
  if (i.aliases?.length) out.push(`${plural(i.aliases.length, "code")} already merged into it (${i.aliases.join(", ")}): they follow`);
  if (n(i.jambNames)) out.push(`${plural(n(i.jambNames), "JAMB name")}: they follow`);
  const hist = Object.values(i.history ?? {}).reduce((a, b) => a + n(b), 0);
  if (hist) out.push(`${plural(hist, "history row")} stay under the old code, which keeps its name`);
  return out;
}

/** one sentence on the impact */
export function impactSentence(i: ProgrammeImpact | null | undefined): string {
  if (!i) return "";
  const n = Number(i.students ?? 0);
  return n ? `${plural(n, "student")} and every record of the programme move to the new code; the old code stays as an alias, so anything written with it later lands on the programme.`
    : "No student is on the programme; its records move to the new code, and the old code stays as an alias.";
}
