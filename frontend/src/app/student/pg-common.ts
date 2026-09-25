/** What the postgraduate student's screens share: the summary the coursework endpoint gives, the words for
 *  a research stage, the next step it asks of the candidate, and the graduation checks read from the record. */
import type { Fees } from "@/lib/student-portal";

export interface PgSemester { number: number; registration_opens: string | null; registration_closes: string | null; lectures_from: string | null; lectures_to: string | null; exams_from: string | null; exams_to: string | null; results_due: string | null; state: string }
export interface PgSupervisor { name: string; role: string; is_external: boolean; assigned_at: string; department: string | null; email: string | null }
export interface PgCoursework { courses: number; graded: number; passed: number; failed: number; units_registered: number; units_passed: number; registrations: number; endorsed: number }
export interface PgClearanceUnit { unit: string; label: string; state: string; decided_at: string | null }
export interface PgSummary {
  postgraduate: boolean;
  cgpa: number | null;
  standing: string;
  registration: { session: string; semester: number; mode: string; state: string; courses: number; units?: number } | null;
  research: { stage: string; topic: string | null; degree_kind: string; supervisor?: string | null } | null;
  session?: string;
  semester?: PgSemester | null;
  supervisors?: PgSupervisor[];
  researchDates?: { corrections_due: string | null; viva_held_at: string | null; draft_submitted_at: string | null; final_submitted_at: string | null; cleared_at: string | null; awarded_at: string | null; viva_outcome: string | null } | null;
  coursework?: PgCoursework;
  graduand?: { session: string; award: string; cgpa: number | null; senate_state: string; senate_minute: string | null } | null;
  clearance?: PgClearanceUnit[];
  status?: string;
}

export const RESEARCH_WORD: Record<string, string> = {
  REGISTERED: "Registered", SUPERVISED: "Supervised", PROPOSAL_SUBMITTED: "Proposal submitted", PROPOSAL_APPROVED: "Proposal approved",
  SEMINAR_HELD: "Seminar held", TITLE_REGISTERED: "Title registered", PANEL_CONSTITUTED: "Panel constituted", DRAFT_SUBMITTED: "Draft submitted",
  VIVA_HELD: "Viva held", CORRECTIONS: "Corrections", FINAL_SUBMITTED: "Final submitted", CLEARED: "Cleared", AWARD_RECOMMENDED: "Recommended to Senate",
  AWARDED: "Awarded", WITHDRAWN: "Withdrawn",
};
const DEGREE: Record<string, string> = { THESIS: "thesis", DISSERTATION: "dissertation", PROJECT: "project" };

export const awardWord = (level: number) => (level >= 900 ? "MPhil / Doctoral" : level >= 800 ? "Master's degree" : "Postgraduate Diploma");
export const fmtDay = (v: string | null | undefined) => {
  if (!v) return "—";
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? "—" : d.toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" });
};

/** what the research stage asks of the student next: a title, the words, and how urgent */
export function nextStep(stage: string, degreeKind: string, supervisor: string | null): [string, string, "info" | "ok" | "bad"] | null {
  const what = DEGREE[degreeKind] ?? "thesis";
  const who = supervisor ? `Your supervisor (${supervisor}) has been assigned. ` : "";
  switch (stage) {
    case "REGISTERED": return ["Await the assignment of a supervisor", "The department assigns a supervisor after registration (Policy 14). Your research desk shows the assignment once it is made.", "info"];
    case "SUPERVISED": return ["Submit your research proposal", `${who}Submit your proposal document and press Submit proposal under Research & Thesis; a Master's proposal is due within 6 months of first registration, a doctoral one within 12 (Policy 21).`, "info"];
    case "PROPOSAL_SUBMITTED": return ["Your proposal is with the department", `${who}The proposal is being considered; you will be told when it is approved or returned.`, "info"];
    case "PROPOSAL_APPROVED": return ["Present at the research seminar", "Your proposal is approved. The department schedules the research seminar; submit your seminar paper on your research desk (Policy 22).", "ok"];
    case "SEMINAR_HELD": return ["Register your title", "The seminar is held. Submit the plagiarism report and register the title of your research with the School (Policy 23).", "ok"];
    case "TITLE_REGISTERED": return [`Write the ${what}`, "Your title is registered. Submit the draft on your research desk when your supervisor is satisfied it is ready for examination (Policy 25).", "info"];
    case "PANEL_CONSTITUTED": return ["Submit your draft for examination", "A panel of examiners is constituted. Submit the draft through your research desk.", "info"];
    case "DRAFT_SUBMITTED": return ["Your draft is with the examiners", "The oral examination (viva) is scheduled once the examiners have reported (Policy 27).", "info"];
    case "VIVA_HELD": return ["Submit your final copy", "The viva has been held and the panel's decision is on your research desk. Submit the final copy when your supervisor certifies it.", "info"];
    case "CORRECTIONS": return ["Make the corrections", "The panel asked for corrections. Submit the corrected copy within the time given, and have your supervisor certify it (Policy 29).", "bad"];
    case "FINAL_SUBMITTED": return ["Await clearance", "Your final version is with the School for clearance (Policy 31–32).", "info"];
    case "CLEARED": return ["Cleared for binding", "Your final version is cleared. The School Board recommends the award to Senate.", "ok"];
    case "AWARD_RECOMMENDED": return ["Recommended to Senate", "The School Board has recommended your award; Senate's word completes it (Policy 33).", "ok"];
    case "AWARDED": return ["Degree awarded", "Congratulations — the award is recorded. Your certificate and transcript follow from the Registry.", "ok"];
    default: return null;
  }
}

export type CheckState = "MET" | "PENDING" | "NOT_MET";
export interface Check { label: string; state: CheckState; detail: string; href?: string }

/** the graduation requirements as the record answers them today. Nothing here invents a rule: coursework
 *  passed, standing, the research at or past clearance, fees settled, and each convocation clearance unit. */
export function eligibility(pg: PgSummary, fees: Fees): Check[] {
  const cw = pg.coursework;
  const r = pg.research;
  const out: Check[] = [];
  out.push({
    label: "Coursework completed",
    state: !cw || cw.courses === 0 ? "PENDING" : cw.failed > 0 ? "NOT_MET" : cw.graded === cw.courses ? "MET" : "PENDING",
    detail: !cw || cw.courses === 0 ? "No course registered yet" : cw.failed > 0 ? `${cw.failed} course${cw.failed === 1 ? "" : "s"} failed — to be repeated` : `${cw.passed} of ${cw.courses} course${cw.courses === 1 ? "" : "s"} passed · ${cw.units_passed} units earned`,
    href: "/student/pg-courses",
  });
  out.push({
    label: "Minimum CGPA of 2.50",
    state: pg.standing === "NEW" || pg.cgpa == null ? "PENDING" : Number(pg.cgpa) >= 2.5 ? "MET" : "NOT_MET",
    detail: pg.standing === "NEW" || pg.cgpa == null ? "No result published yet" : `CGPA ${Number(pg.cgpa).toFixed(2)} of 5.00`,
    href: "/student/pg-courses",
  });
  const past = ["CLEARED", "AWARD_RECOMMENDED", "AWARDED"];
  out.push({
    label: "Research completed and cleared",
    state: !r ? "PENDING" : r.stage === "WITHDRAWN" ? "NOT_MET" : past.includes(r.stage) ? "MET" : "PENDING",
    detail: !r ? "Research record not opened yet" : `${RESEARCH_WORD[r.stage] ?? r.stage}${pg.researchDates?.cleared_at ? ` · cleared ${fmtDay(pg.researchDates.cleared_at)}` : ""}`,
    href: "/student/research",
  });
  out.push({
    label: "Oral examination passed",
    state: !r ? "PENDING" : pg.researchDates?.viva_outcome ? (pg.researchDates.viva_outcome === "FAIL" ? "NOT_MET" : "MET") : "PENDING",
    detail: pg.researchDates?.viva_outcome ? `${pg.researchDates.viva_outcome.replace(/_/g, " ").toLowerCase()} · ${fmtDay(pg.researchDates.viva_held_at)}` : "Not yet held",
    href: "/student/research",
  });
  out.push({
    label: "School fees settled",
    state: fees.paidInFull ? "MET" : fees.balance > 0 ? "NOT_MET" : "PENDING",
    detail: fees.paidInFull ? `Paid in full · ${fees.session}` : fees.balance > 0 ? `Outstanding balance for ${fees.session}` : "No charge stated yet",
    href: "/student/fees",
  });
  for (const u of pg.clearance ?? []) {
    out.push({ label: `${u.label} clearance`, state: u.state === "CLEARED" ? "MET" : "PENDING", detail: u.state === "CLEARED" ? `Cleared ${fmtDay(u.decided_at)}` : "Not yet cleared for convocation", href: "/student/graduation" });
  }
  return out;
}
