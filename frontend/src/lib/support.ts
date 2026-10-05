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
};
export const CAPABILITY_CODES = Object.keys(CAPABILITIES);

export interface SupportRow {
  id: string; surname: string; other_names: string; matric_no: string | null; jamb_reg_no: string | null; admission_no: string | null;
  faculty: string | null; faculty_code: string | null; department: string | null; dept_code: string | null; programme: string; programme_code: string;
  current_level: number; status: string; current_session: string | null; registration: "REGISTERED" | "ENROLLED" | "NOT_REGISTERED" | string; classification: string | null;
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
  ticket: { id: string; number: string; subject: string; status: string; category: string } | null;
  actions: SupportAction[];
  tickets: { id: string; number: string; subject: string; status: string; priority: string; category: string; created_at: string; updated_at: string; agent: string | null }[];
  history: { occurred_at: string; actor_name: string | null; actor_office: string; action: string; subject_type: string; reason: string | null }[];
  hasPassport: boolean;
}
export interface SupportAction { id: string; action: string; field: string | null; old_value: string | null; new_value: string | null; reason: string; session: string | null; semester: number | null; at: string; agent: string; agent_office: string; ticket_number: string | null; ticket_id: string | null }

export const ACTION_WORD: Record<string, string> = {
  CONTACT_EDITED: "Contact detail changed", PERSONAL_EDITED: "Personal detail changed", FAMILY_EDITED: "Family or sponsor detail changed", PHOTO_REPLACED: "Photograph replaced",
  CHANGE_REQUESTED: "Change requested of the Registry", REGISTRATION_CHOSEN: "Registration courses chosen", COURSE_ADDED: "Course added", COURSE_DROPPED: "Course dropped",
  REGISTRATION_SUBMITTED: "Registration submitted", RECORD_EXPORTED: "List exported",
};
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
