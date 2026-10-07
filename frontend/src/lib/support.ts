/** Student record support for the ICT Support Desk (V334): the shapes the support desk's screens share. A CPO sees
 *  students within the scope of their postings and does only what the Head granted the posting. */

export const CAPABILITIES: Record<string, [string, string]> = {
  VIEW_STUDENT: ["View student records", "The profile, the academic record, the registration, the history and the tickets of students within scope"],
  EDIT_CONTACT: ["Edit contact details", "Phone numbers, email, addresses, state of residence — the open contact fields"],
  EDIT_PERSONAL: ["Edit personal details", "Preferred name, marital status, religion, place of birth and the other open personal fields"],
  EDIT_FAMILY: ["Edit family, guardian and sponsor", "Parents, guardian, next of kin, sponsorship and scholarship — the open family and origin fields"],
  EDIT_PHOTO: ["Replace the photograph", "A replacement passport photograph, previewed before it is saved"],
  REQUEST_CHANGE: ["Request a Registry change", "Raise a change of nationality, state of origin or LGA for the Registry to decide; never written directly"],
  VIEW_PAYMENTS: ["View payment status", "Fees position, references and receipts — read only; the Bursary resolves payments"],
  VIEW_DOCUMENTS: ["View documents", "Admission documents, issued documents and receipts"],
  MANAGE_REGISTRATION: ["Manage course registration", "Choose, add, drop and submit through the registration engine's own rules"],
  EXPORT_STUDENTS: ["Export lists", "Excel and PDF of a student list within scope"],
  OVERRIDE_REGISTRATION: ["Support override of course registration", "Set aside only the registration window or the engine's menu, on the student's ticket, with a reason — never fees, units, GST, a mark or a closed semester"],
  RESET_PASSWORD: ["Reset student passwords", "Send the portal's own reset link, or issue a one-time temporary password at the desk on a ticket; a password is never seen or recorded"],
  INVESTIGATE_PAYMENT: ["Investigate payments", "Search payments by any number and read the gateway, finance, entitlement and verification diagnosis"],
  VERIFY_PAYMENT: ["Verify payments with the gateway", "Ask the gateway again through the payment service; it settles the original reference only"],
  SYNC_ENTITLEMENT: ["Refresh payment entitlement", "Re-apply what a confirmed payment entitles; never a payment, never a credit"],
  REGENERATE_RECEIPT: ["Regenerate receipts", "Tell the student a confirmed payment's receipt is ready; the number and the amount stay the Bursary's"],
  CREATE_TICKET: ["Raise tickets for students", "Open a support ticket on the student's behalf at the desk"],
  VIEW_SUPPORT_AUDIT: ["Read the support audit", "Every support act across the students within scope"],
};
export const CAPABILITY_CODES = Object.keys(CAPABILITIES);

export interface SupportRow {
  id: string; surname: string; other_names: string; matric_no: string | null; jamb_reg_no: string | null; admission_no: string | null;
  faculty: string | null; faculty_code: string | null; department: string | null; dept_code: string | null; programme: string; programme_code: string;
  current_level: number; status: string; current_session: string | null; registration: "REGISTERED" | "ENROLLED" | "NOT_REGISTERED" | string; classification: string | null; application_no?: string | null;
  entry_session: string | null; sex: string | null;
}
export interface SupportList {
  total: number; page: number; size: number; rows: SupportRow[]; scope: string; capabilities: string[];
  options?: { faculties: { code: string; name: string }[]; departments: { code: string; name: string; faculty_code: string }[]; programmes: { code: string; name: string; dept_code: string | null }[]; sessions: string[] };
}

export interface SupportProfile {
  record: Record<string, unknown> & {
    student: { id: string; matricNo: string | null; admissionNo: string | null; jambRegNo: string | null; surname: string; otherNames: string; sex: string | null; dateOfBirth: string | null; programmeCode: string; programmeName: string; deptCode: string | null; deptName: string | null; facultyCode: string | null; facultyName: string | null; entryMode: string | null; entrySession: string | null; entryLevel: number; currentLevel: number; status: string };
    biodata: { field: string; section: string; label: string; tier: string; hint: string | null; wide: boolean; ord: number; value: string | null }[];
    documents: { id: string; kind: string; detail: string | null; source: string | null; receivedOn: string | null; status: string | null }[];
    statusHistory: { id: string; fromStatus: string | null; toStatus: string; instrument: string | null; effectiveOn: string; reason: string | null }[];
    enrolments: { session: string; level: number; mode: string | null; feeCategory: string | null; enrolledAt: string | null }[];
    registrations: { id: string; session: string; semester: number; level: number; status: string; units?: number; submittedAt?: string | null; approvedAt?: string | null }[];
    pendingChanges: { id: string; field: string; label: string; fromValue: string | null; toValue: string; evidence: string | null; requestedAt: string; state: string }[];
    decidedChanges: { id: string; field: string; label: string; fromValue: string | null; toValue: string; evidence: string | null; requestedAt: string; state: string; decision: string | null; decidedAt: string | null }[];
  };
  portal: Record<string, unknown>;
  contact: { phone: string | null; email: string | null; address: string | null; reach_email: string | null; reach_phone: string | null };
  position: Record<string, unknown> | null;
  capabilities: string[];
  scope: string;
  agent: string;
  openedAt: string;
  ticket: { id: string; number: string; subject: string; status: string; category: string; category_code: string } | null;
  actions: SupportAction[];
  tickets: { id: string; number: string; subject: string; status: string; priority: string; category: string; created_at: string; updated_at: string; agent: string | null; escalated_office: string | null }[];
  academic: { application_no: string | null; session: string | null; semester: number };
  center: CenterItem[];
  escalateTo: string[];
  categories: { code: string; name: string; fields: string }[];
  history: { occurred_at: string; actor_name: string | null; actor_office: string; action: string; subject_type: string; reason: string | null }[];
  hasPassport: boolean;
}
export interface SupportAction {
  id: string; action: string; module: string; field: string | null; old_value: string | null; new_value: string | null; reason: string; session: string | null; semester: number | null; at: string;
  agent: string; agent_office: string; ticket_number: string | null; ticket_id: string | null; ticket_status: string | null;
  summary: string | null; outcome: string; override: boolean; normal_rule: string | null; description: string | null; method: string | null; payment_reference: string | null; result: string;
}
/** the Support Action Center: the acts the agent's postings allow on this student */
export interface CenterItem { code: string; label: string }
/** one rule of the registration engine, judged for a course: what blocks, and whether a support override may set it aside */
export interface Rule { ord: number; rule: string; label: string; passed: boolean; overridable: boolean; advisory: boolean; message: string }
export interface Checks { rules: Rule[]; course: { course_code: string; title: string; units: number; session: string; semester: number } | null; allowed: boolean; overridable: boolean; mayOverride: boolean }
export interface CurrentCourse {
  offering_id: string; course_code: string; title: string; units: number; entry_type: string; kind: string; basis: string; level: number; semester: number; session: string;
  status: string; registered_at: string | null; support_override_at: string | null; support_override_reason: string | null; marked: boolean;
}
export interface CurrentRegistration { registration: { id: string; status: string; level: number; submitted_at: string | null; approved_at: string | null; returned_comment: string | null; units: number } | null; courses: CurrentCourse[] }
export interface PaymentRow {
  reference: string; purpose: string; session: string; amount: number; generated_at: string; expires_at: string; confirmed_at: string | null; channel: string | null; receipt_no: string | null; state: string;
  student_id: string; student: string; number: string | null; jamb_reg_no: string | null; programme: string; gateway: string | null; gateway_ref: string | null; gateway_outcome: string | null; gateway_at: string | null;
}
export interface PaymentDiagnosis {
  payment: Record<string, unknown> & { reference: string; student_id: string; student: string; number: string | null; programme: string; session: string; purpose: string; amount: number;
    generated_at: string; expires_at: string; confirmed_at: string | null; channel: string | null; note: string | null; receipt_no: string | null; kind: string; invoice: string; gatewayRef: string | null; transactionRef: string | null };
  status: { current: string; gateway: string; finance: string; entitlement: string; verification: string };
  entitlementWords: string; entitlementState: Record<string, unknown>; registration: { semester: number; gate: string | null; status: string; clearsRegistration: boolean | null };
  attempts: { gateway: string; kind: string; opened_at: string; checked_at: string | null; checks: number; txn_ref: string | null }[];
  events: { gateway: string; source: string; event: string | null; gateway_ref: string | null; amount: number | null; status: string | null; signature_ok: boolean; outcome: string; received_at: string; resolved_at: string | null; resolution: string | null }[];
  refunds: { state: string; amount: number; proposed_at: string; approved_at: string | null; paid_at: string | null; rejected_why: string | null }[];
  related: { reference: string; amount: number; generated_at: string; confirmed_at: string | null; receipt_no: string | null }[];
  advice: { code: string; words: string; action: string }[]; actions: string[]; capabilities: string[];
  tickets: { id: string; number: string; subject: string; status: string; category: string }[];
}

export const ACTION_WORD: Record<string, string> = {
  CONTACT_EDITED: "Contact detail changed", PERSONAL_EDITED: "Personal detail changed", FAMILY_EDITED: "Family or sponsor detail changed", PHOTO_REPLACED: "Photograph replaced",
  CHANGE_REQUESTED: "Change requested of the Registry", REGISTRATION_CHOSEN: "Registration courses chosen", COURSE_ADDED: "Course added", COURSE_DROPPED: "Course dropped",
  REGISTRATION_SUBMITTED: "Registration submitted", RECORD_EXPORTED: "List exported", COURSE_RESTORED: "Course restored", PASSWORD_RESET: "Password reset initiated",
  PAYMENT_INVESTIGATED: "Payment investigated", PAYMENT_VERIFIED: "Payment verified with the gateway", ENTITLEMENT_REFRESHED: "Payment entitlement refreshed",
  RECEIPT_REGENERATED: "Receipt regenerated", ESCALATED: "Escalated", TICKET_CREATED: "Ticket raised", TICKET_RESOLVED: "Ticket resolved",
};
export const MODULE_WORD: Record<string, string> = { COURSE_REGISTRATION: "Course Registration", AUTHENTICATION: "Authentication", PAYMENT: "Payment", TICKET: "Ticket", STUDENT_RECORD: "Student Record", REPORTS: "Reports" };
export const RESULT_WORD: Record<string, [string, "ok" | "info" | "grey" | "warn" | "bad"]> = {
  COMPLETED: ["Completed", "ok"], RESOLVED: ["Resolved", "ok"], NO_CHANGE: ["No change", "grey"], ESCALATED: ["Escalated", "warn"],
};
/** the payment diagnosis in words */
export const PAY_WORD: Record<string, [string, "ok" | "info" | "grey" | "warn" | "bad"]> = {
  PAID: ["Paid", "ok"], PENDING: ["Pending", "warn"], EXPIRED: ["Expired", "grey"], FAILED: ["Failed", "bad"], SHORT_PAID: ["Short paid", "bad"],
  SUCCESS: ["Success", "ok"], NO_ANSWER: ["No answer", "warn"], NOT_STARTED: ["Not started", "grey"], NOT_USED: ["Not used (bank or Bursary)", "info"],
  VERIFIED: ["Verified", "ok"], NOT_CONFIRMED: ["Not confirmed", "warn"], UPDATED: ["Updated", "ok"], NOT_UPDATED: ["Not updated", "bad"], NOT_APPLICABLE: ["Follows the payment", "grey"],
  VERIFIED_BY_GATEWAY_REQUERY: ["Verified by gateway requery", "ok"], CONFIRMED_BY_GATEWAY_NOTIFICATION: ["Confirmed by the gateway's notification", "ok"],
  CONFIRMED_BY_BURSARY: ["Confirmed by the Bursary", "ok"], NOT_VERIFIED: ["Not verified", "warn"], CONFIRMED: ["Confirmed", "ok"],
};
export const OFFICE_WORD: Record<string, string> = { bursar: "The Bursary", ict: "The Director of ICT", records: "Examinations and Records", academic: "The Academic Office", registrar: "The Registry" };
export const SECTION_WORD: Record<string, string> = { personal: "Personal", contact: "Contact", origin: "Origin and sponsorship", family: "Family, guardian and next of kin", academic: "Academic", other: "Other" };

/** the fields that bear on identity and fee status: from the desk they go to the Registry as a request */
export const SENSITIVE = new Set(["nationality", "country_of_origin", "state_of_origin", "lga"]);
/** which capability writes a biodata field: by its tier, section and name; null where no support capability may (a locked field) */
export function capabilityFor(tier: string, section: string, field = ""): string | null {
  if (tier === "locked") return null;
  if (tier === "approval" || SENSITIVE.has(field)) return "REQUEST_CHANGE";
  if (section === "contact") return "EDIT_CONTACT";
  if (section === "family" || section === "origin") return "EDIT_FAMILY";
  return "EDIT_PERSONAL";
}
