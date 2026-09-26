/** The admission lifecycle and the online screening (V269): the shapes the endpoints answer with, and the words for them. */

export type ScreeningState = "DRAFT" | "SUBMITTED" | "UNDER_REVIEW" | "RETURNED" | "SUCCESSFUL" | "UNSUCCESSFUL";
export type TrackerState = "done" | "now" | "todo" | "failed";
export interface TrackerStep { key: string; label: string; state: TrackerState }
export interface AdmissionStatus { status: string; label: string; next_action: string | null; next_href: string | null; detail: string | null }
export interface Entitlement { paid: boolean; reference: string | null; confirmed_at: string | null; amount: number | null; checking_paid?: boolean; checking_reference?: string | null; checking_confirmed_at?: string | null; checking_amount?: number | null }
export interface Offer {
  application_no: string; session: string; decision: string | null; decision_released_at: string | null; decision_basis: string | null; accepted_at: string | null; undertaking_at: string | null; acceptance_confirmed_at: string | null; cleared_at: string | null;
  surname: string; other_names: string; jamb_reg_no: string; programme: string; entry_mode: string; entry_level: number; programme_code: string | null; degree_type: string | null; faculty: string | null; department: string | null;
  student_id: string | null; admission_no: string | null; matric_no: string | null; matriculated_at: string | null; student_status: string | null; current_level: number | null; changed_to: string | null; changed_from: string | null;
}
export interface Admission extends AdmissionStatus { tracker: string; entitlement: Entitlement; screeningRequired: boolean; offer: Offer; checkingDue?: boolean; checkingFee?: number | null; checkingReference?: string | null }

export interface ScreeningForm {
  application_id: string; screening_no: string; state: ScreeningState; version: number; opened_at: string; submitted_at: string | null; declaration_at: string | null;
  review_started_at: string | null; decided_at: string | null; decided_office: string | null; decision_reason: string | null; remarks: string | null; returned_note: string | null; membership: string | null;
}
export interface ScreeningPolicy { session: string; enabled: boolean; enabled_from: string; required_documents: string[]; required_fields: string[]; instructions: string | null }
export interface FieldDef { field: string; section: string; label: string; tier: string; hint: string | null; wide: boolean; ord: number }
export interface Institution { ord?: number; name: string; from_year: number | null; to_year: number | null; certificate: string | null; award_year: number | null }
export interface OlevelRow { ord?: number; exam_body: string; exam_number: string | null; exam_year: number | null; subject: string; grade: string }
export interface JambOlevel { exam_body: string; exam_year: string | null; exam_number: string | null; subject: string; grade: string }
export interface ScreeningDocument { id: string; kind: string; filename: string; content_type: string; bytes: number; uploaded_at: string; status: "PENDING" | "ACCEPTED" | "REJECTED"; review_note: string | null; reviewed_at: string | null }
export interface Missing { kind: "FIELD" | "DOCUMENT" | "OLEVEL"; item: string; label: string }
export interface ScreeningEvent { action: string; detail: string | null; actor_office: string | null; at: string; officer?: string | null }
export interface ChangeRow { id: string; from_programme: string; to_programme: string; state: string; requested_at: string; decided_at: string | null; decision_note: string | null; note?: string | null }
export interface Prefill {
  surname: string; other_names: string; jamb_reg_no: string; programme: string; entry_mode: string; session: string; application_no: string; sex: string | null; state_of_origin: string | null; lga: string | null;
  faculty: string | null; department: string | null; date_of_birth: string | null; email: string; phone: string; next_of_kin: string | null;
  /** the photograph as JAMB sent it (a data URL), the one every screen shows; the form takes no other (V274) */
  jamb_passport?: string | null;
}
export interface ScreeningView {
  required: boolean; form: ScreeningForm | null; policy: ScreeningPolicy | null; fields: FieldDef[]; answers: { field: string; value: string }[]; institutions: Institution[]; olevel: OlevelRow[]; jambOlevel: JambOlevel[];
  documents: ScreeningDocument[]; missing: Missing[]; prefill: Prefill; events: ScreeningEvent[]; changes: ChangeRow[]; status: AdmissionStatus;
}

export const SECTION_WORD: Record<string, string> = {
  personal: "Personal data", origin: "Origin and sponsorship", contact: "Address and contact", family: "Parent or guardian", kin: "Next of kin and guarantor", education: "Educational information", health: "Health", bank: "Bank details",
};
export const DOC_WORD: Record<string, string> = {
  OLEVEL_STATEMENT: "O'Level result / statement of result", BIRTH_CERT: "Birth certificate or declaration of age", LGA_ID: "Local government identification / certificate of origin", JAMB_SLIP: "UTME result slip",
  PASSPORT: "Passport photograph", JAMB_ADMISSION_LETTER: "JAMB admission letter", STATE_OF_ORIGIN: "Certificate of state of origin", MARRIAGE_CERT: "Marriage certificate or declaration", CHANGE_OF_NAME: "Change of name (where applicable)",
  PREVIOUS_QUALIFICATION: "Previous qualification (Direct Entry)", OTHER: "Other document",
};
export const STATE_WORD: Record<ScreeningState, [string, "grey" | "info" | "ok" | "bad" | "warn"]> = {
  DRAFT: ["DRAFT", "grey"], SUBMITTED: ["SUBMITTED — PENDING REVIEW", "info"], UNDER_REVIEW: ["IN REVIEW", "info"], RETURNED: ["RETURNED FOR CORRECTION", "warn"], SUCCESSFUL: ["SUCCESSFUL", "ok"], UNSUCCESSFUL: ["UNSUCCESSFUL", "bad"],
};
export const STATUS_KIND = (status: string): "ok" | "bad" | "info" => (status === "MATRICULATED" || status.endsWith("_SUCCESSFUL") ? "ok" : ["NOT_ADMITTED", "DECLINED", "CHANGE_OF_PROGRAMME_REQUIRED", "SCREENING_RETURNED"].includes(status) ? "bad" : "info");
export const whenAt = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
export const dayOf = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "2-digit", month: "2-digit", year: "numeric" }) : "—");
export function parseTracker(t: string | null | undefined): TrackerStep[] { try { return t ? (JSON.parse(t) as TrackerStep[]) : []; } catch { return []; } }
export interface Pipeline {
  session: string; jamb_uploaded: number; matched: number; unmatched: number; admitted: number; acceptance_pending: number; acceptance_paid: number; screening_pending: number; screening_submitted: number;
  screening_successful: number; screening_unsuccessful: number; screening_returned: number; change_requested: number; change_approved: number; fees_paid: number; registered: number; ready_for_matric: number; matriculated: number;
}
export interface ReviewRow {
  id: string; application_no: string; session: string; accepted_at: string | null; cleared_at: string | null; surname: string; other_names: string; jamb_reg_no: string; programme: string; entry_mode: string;
  programme_code: string | null; faculty_code: string | null; faculty: string | null; dept_code: string | null; department: string | null; screening_no: string | null; state: ScreeningState | null; version: number | null;
  submitted_at: string | null; review_started_at: string | null; decided_at: string | null; decision_reason: string | null; returned_note: string | null; remarks: string | null; decided_officer: string | null; documents: number;
  change_state: string | null; change_to: string | null; student_id: string | null; admission_no: string | null; matric_no: string | null; overdue: boolean;
}
export interface ReviewStats { total: number; pending: number; submitted: number; in_review: number; successful: number; unsuccessful: number; returned: number; change_requested: number; completed: number; overdue: number }
export interface ReviewList { session: string; rows: ReviewRow[]; stats: ReviewStats; policy: ScreeningPolicy | null; options: { faculty_code: string; faculty: string; dept_code: string | null; department: string | null; programme_code: string; programme: string }[] }
export interface ReviewDetail {
  application: ReviewRow; form: ScreeningForm | null; answers: { section: string; field: string; label: string; ord: number; value: string }[]; institutions: Institution[]; olevel: OlevelRow[]; jambOlevel: JambOlevel[];
  utme: { aggregate: number | null; subjects: string | null } | null; prefill: { sex: string | null; state_of_origin: string | null; lga: string | null; email: string; phone: string; next_of_kin: string | null; entry_mode: string; entry_level: number; date_of_birth: string | null };
  documents: ScreeningDocument[]; missing: Missing[]; events: ScreeningEvent[]; eligibility: { applied_result: string; alternatives: number; evaluated_at: string; rules_version: number | null; eligible_alternatives: string | null; reasons: string[] | null } | null;
  changes: ChangeRow[]; status: AdmissionStatus; tracker: string; entitlement: Entitlement;
}

/** V273: the reference lists the form chooses from */
export interface RefState { code: string; name: string; lgas: string }
export const MARITAL = ["Single", "Married", "Divorced", "Widowed", "Separated"];
export const RELIGIONS = ["Christianity", "Islam", "Traditional", "Other"];
export const BLOOD_GROUPS = ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"];
export const PHONE_FIELDS = ["mobile", "alt_mobile", "kin_mobile", "kin_alt_mobile", "guardian_mobile", "father_mobile", "mother_mobile", "guarantor_mobile", "whatsapp"];
export const EMAIL_FIELDS = ["personal_email", "kin_email", "guardian_email", "father_email", "mother_email"];
export const YEAR_FIELDS = ["secondary_graduation_year", "alevel_graduation_year"];
/** the same checks the database applies on submission, for the form to say so before */
export function fieldProblem(field: string, value: string, ctx: { states: RefState[]; countries: string[]; answers: Record<string, string> }): string | null {
  const v = (value ?? "").trim();
  if (!v) return null;
  if (PHONE_FIELDS.includes(field) && !/^0[0-9]{10}$/.test(v)) return "Eleven digits, starting with 0";
  if (EMAIL_FIELDS.includes(field) && !/^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$/.test(v)) return "Not shaped as an email address";
  if (field === "date_of_birth") { const d = new Date(v); if (!/^\d{4}-\d{2}-\d{2}$/.test(v) || isNaN(d.getTime()) || d >= new Date() || d < new Date(Date.now() - 100 * 365.25 * 86400000)) return "A past date as YYYY-MM-DD"; }
  if (YEAR_FIELDS.includes(field)) { const n = Number(v); if (!/^\d{4}$/.test(v) || n < 1950 || n > new Date().getFullYear()) return "A four-digit year"; }
  if (field === "bank_account_no" && !/^[0-9]{10}$/.test(v)) return "Ten digits";
  if (["primary_fees_per_term", "secondary_fees_per_term", "parent_income", "children"].includes(field) && !/^[0-9][0-9,]*(\.[0-9]+)?$/.test(v)) return "A number";
  if (field === "nationality" && ctx.countries.length && !ctx.countries.some((c) => c.toLowerCase() === v.toLowerCase())) return "Choose a country from the list";
  if (field === "state_of_origin" && ctx.states.length && !ctx.states.some((s) => s.name.toLowerCase() === v.toLowerCase())) return "Choose a state from the list";
  if (field === "lga" && ctx.states.length) { const st = ctx.states.find((s) => s.name.toLowerCase() === (ctx.answers.state_of_origin ?? "").toLowerCase()); if (!st || !(JSON.parse(st.lgas) as string[]).some((l) => l.toLowerCase() === v.toLowerCase())) return "Choose a local government of the chosen state"; }
  return null;
}
export const ageOn = (dob: string | null | undefined) => { if (!dob) return null; const d = new Date(dob); if (isNaN(d.getTime())) return null; const now = new Date(); let a = now.getFullYear() - d.getFullYear(); if (now.getMonth() < d.getMonth() || (now.getMonth() === d.getMonth() && now.getDate() < d.getDate())) a--; return a; };
