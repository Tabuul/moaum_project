/** GST & EPS (V314): what the two offices' desks and the student's GST & EPS page read from /api/v1/gst and /api/v1/me/gst. */

export type GstOffice = "GST" | "EPS";

export const OFFICE_WORD: Record<GstOffice, string> = { GST: "General Studies (GST)", EPS: "Entrepreneurship Studies (EPS)" };
export const OFFICE_SHORT: Record<GstOffice, string> = { GST: "GST", EPS: "EPS" };

export interface GstCounts {
  total: number; required: number; paid: number; unpaid: number; pending: number; not_stated: number; registered: number; not_registered: number;
  /** V366: the whole register in scope, those the office's courses do not concern (never unpaid), carryovers, completed, still owing, ₦0 exemptions, paid but not required */
  population?: number; not_applicable?: number; carryover?: number; completed?: number; outstanding_students?: number; exempt?: number; review?: number;
  gst_registered: number; eps_registered: number; paid_not_registered: number; registered_unpaid: number; male: number; female: number;
  course_registrations: number; revenue: number; outstanding: number;
  /** V323: of the paid, how many through this portal and how many reconciled from the old one */
  paid_legacy?: number; paid_current?: number;
}
/** V323: the old-portal GST payments of a session as the reconciliation stands */
export interface LegacySummary {
  legacy_rows: number; successful: number; failed: number; gst_rows: number; unprocessed: number; matched: number; reconciled: number; requires_review: number; duplicates: number;
  rejected: number; unmatched: number; legacy_amount: number; legacy_successful_amount: number; reconciled_amount: number; variance: number; legacy_students: number;
  reconciled_students: number; entitled_students: number;
}
export interface GstGroup extends GstCounts {
  faculty_code?: string; faculty?: string; dept_code?: string; department?: string; programme_code?: string; programme?: string; level?: number; sex?: string | null;
}
export interface GstCourseRow {
  offering_id: string; course_code: string; title: string; units: number; level: number; semester: number; general_office: string; dept_code: string; department: string;
  lecturer_id: string | null; lecturer: string | null; state: string; registered: number; entitled: number; sheet_id: string | null; stage: string | null; graded: number; published_at: string | null;
}
export interface GstFeeRule {
  id: string; session: string; amount: number; level: number | null; entry_mode: string | null; faculty_code: string | null; faculty: string | null;
  programme_code: string | null; programme: string | null; effective_from: string; note: string | null; stated_office: string | null; stated_at: string;
  superseded_at: string | null; stated_by: string | null;
}
export interface GstSetting { required_for_gst_eps: boolean; required_for_all: boolean; covers_eps: boolean; updated_office?: string | null; updated_at?: string | null }
/** V367: a GST/EPS course bound to programmes but not opened for the session — its students owe nothing until it is */
export interface GstGap { course_code: string; title: string; level: number; semester: number; office: string; programmes: number; levels: string }

/** V366: the Bursary's standing for a session — who owes the fee because a GST/EPS course requires it, who does not */
export interface GstStanding {
  undergraduates: number; applicable: number; not_applicable: number; paid: number; exempt: number; owing: number; not_stated: number; review: number; outstanding: number;
  gst_required: number; eps_required: number; carryover: number;
}
export interface GstFeePage {
  session: string; sessions: { name: string; state: string }[]; setting: GstSetting; rules: GstFeeRule[]; history: GstFeeRule[]; paid: { students: number; amount: number };
  standing?: GstStanding;
  gaps?: GstGap[];
}
export interface GstOptions {
  faculties: { code: string; name: string }[]; departments: { code: string; name: string; faculty_code: string }[];
  programmes: { code: string; name: string; dept_code: string; faculty_code: string }[]; levels: number[]; courses: { code: string; title: string; level: number; semester: number }[];
}
export interface GstDashboardData {
  office: GstOffice; session: string; semester: number | null; filters: Record<string, string>;
  sessions: { name: string; state: string }[]; semesters: { number: number; state: string }[];
  fee: { rules: GstFeeRule[]; setting: GstSetting }; totals: GstCounts;
  byLevel: GstGroup[]; byFaculty: GstGroup[]; byDepartment: GstGroup[]; byProgramme: GstGroup[]; byGender: GstGroup[];
  courses: GstCourseRow[]; results: { pending: number; submitted: number; published: number; activeCourses: number; totalCourses: number; registrations: number };
  legacy?: LegacySummary | null;
  gaps?: GstGap[];
  /** V369: what waits on the courses page — moves to confirm, requests to answer, requests made */
  waiting?: GstWaiting;
  options: GstOptions; now: string;
}

/** V369: course moves someone else made, waiting for the office to confirm; requests between the GST and EPS offices */
export interface GstWaiting { moves_to_confirm: number; requests_to_answer: number; requests_made: number }
export interface GstStudentRow {
  student_id: string; number: string; surname: string; other_names: string; sex: string | null; faculty_code: string; faculty: string; dept_code: string; department: string;
  programme_code: string; programme: string; level: number; status: string; entry_mode: string; required: boolean; fee: number; stated: boolean; paid: number;
  entitled: boolean; pay_state: string; reference: string | null; paid_at: string | null; gst_registered: boolean; eps_registered: boolean; gst_courses: number; eps_courses: number;
  registered_at: string | null; registered_courses: string | null; result_stages: string | null;
  /** V366: the office's own answer for the student — whether its courses concern them, why, the courses owed */
  office_required?: boolean; office_reason?: string; office_carryover?: boolean; office_completed?: boolean; office_owed?: string | null; review?: boolean;
  gst_reason?: string; eps_reason?: string;
}
export interface GstStudentPage { office: GstOffice; session: string; semester: number | null; eligibility?: string; total: number; page: number; size: number; rows: GstStudentRow[] }

export const GST_FILTER_KEYS = ["session", "semester", "fac", "dept", "prog", "level", "sex", "status", "course", "payment", "registration", "eligibility", "q"] as const;
export type GstFilterKey = (typeof GST_FILTER_KEYS)[number];
export type GstFilters = Partial<Record<GstFilterKey, string>>;

export function readGstFilters(p: Record<string, string | string[] | undefined>): GstFilters {
  const f: GstFilters = {};
  for (const k of GST_FILTER_KEYS) {
    const v = p[k];
    if (typeof v === "string" && v) f[k] = v.slice(0, 80);
  }
  return f;
}

export function gstQuery(f: GstFilters, extra?: Record<string, string | number | undefined>): string {
  const q = new URLSearchParams();
  for (const k of GST_FILTER_KEYS) if (f[k]) q.set(k, String(f[k]));
  for (const [k, v] of Object.entries(extra ?? {})) if (v !== undefined && v !== "") q.set(k, String(v));
  return q.toString();
}

export const PAY_WORD: Record<string, [string, "ok" | "bad" | "warn" | "grey" | "info"]> = {
  PAID: ["Paid", "ok"], NOT_PAID: ["Not paid", "bad"], PENDING: ["Reference open", "warn"], NOT_STATED: ["No fee stated", "grey"], NOT_REQUIRED: ["Not required", "grey"],
  EXEMPT: ["No fee for them", "info"],
};

/** V366: who a list holds — the students the office's courses concern (the default), one kind of them, or those it does not concern */
export const ELIGIBILITY_WORD: Record<string, string> = {
  REQUIRED: "Required", CARRYOVER: "Carryover", COMPLETED: "Completed this session", NOT_APPLICABLE: "Not applicable", REVIEW: "Paid, not required (review)", ALL: "Every undergraduate",
};

/** V366: why a student owes GST or EPS, or does not — the reason codes finance.gst_eps_eligibility gives */
export function reasonWord(code: string | null | undefined): string {
  if (!code) return "—";
  const office = code.startsWith("EPS") ? "EPS" : "GST";
  const words: Record<string, string> = {
    REQUIRED_COURSE_OFFERING: `A ${office} course the programme offers at this level runs this session`,
    REQUIRED_CARRYOVER: `A ${office} course failed earlier is carried over and runs this session`,
    REQUIRED_REGISTERED: `A ${office} course is on the registration this session`,
    ALREADY_COMPLETED: `The ${office} courses of this level are already passed`,
    COURSE_NOT_OFFERED: `The ${office} course does not run this session`,
    NOT_APPLICABLE: `No ${office} course is offered to the programme at this level, and none is carried over`,
    NOT_COVERED_BY_GST_FEE: "An EPS course is owed, but the GST payment does not cover EPS: no fee is due for it",
  };
  if (code === "PROGRAMME_NOT_ELIGIBLE") return "The programme is not an undergraduate programme: GST and EPS do not apply";
  if (code === "STUDENT_NOT_ACTIVE") return "Not an active student: nothing is owed while that status stands";
  return words[code.replace(/^(GST|EPS)_/, "")] ?? code;
}

/** V366: a GST/EPS course's place in the student's requirement — where it comes from, and where it stands */
export const SOURCE_WORD: Record<string, string> = { COURSE_OFFERING: "Programme course at this level", CARRYOVER: "Carryover", REGISTERED: "On the registration" };
export const COURSE_STATUS_WORD: Record<string, [string, "ok" | "bad" | "warn" | "grey" | "info"]> = {
  OUTSTANDING: ["Owed", "warn"], REGISTERED: ["Registered", "info"], COMPLETED: ["Passed this session", "ok"], FAILED: ["Failed this session", "bad"],
  ALREADY_PASSED: ["Already passed", "ok"], NOT_OFFERED: ["Not run this session", "grey"],
};

/** V366: "why is this student paying GST/EPS?" — finance.gst_eps_explain */
export interface GstEpsCourse {
  course_code: string; title: string; units: number; office: "GST" | "EPS" | string; level: number; semesters: number[] | null; offering_id: string | null;
  source: "COURSE_OFFERING" | "CARRYOVER" | "REGISTERED" | string; counts: boolean; status: string; registered: boolean;
  failed_in: string | null; last_grade: string | null; passed_in: string | null;
}
export interface GstEpsEligibility {
  applicable: boolean; required: boolean; covers_eps: boolean; level: number | null; gst_required: boolean; eps_required: boolean;
  gst_reason: string; eps_reason: string; reason: string; gst_courses: string[]; eps_courses: string[]; gst_carryovers: string[]; eps_carryovers: string[];
  gst_completed: string[]; eps_completed: string[];
}
export interface GstEpsExplain {
  session: string; semesters: { number: number; state: string }[];
  student: { id: string; number: string | null; surname: string; otherNames: string; level: number; status: string; entryMode: string | null; programmeCode: string; programme: string;
    category: string | null; deptCode: string | null; department: string | null; facultyCode: string | null; faculty: string | null } | null;
  eligibility: GstEpsEligibility;
  entitlement: { state: string; required: boolean; stated: boolean; fee: number; paid: number; entitled: boolean; review: boolean; reference: string | null; receipt_no: string | null };
  courses: GstEpsCourse[];
}
export const STAGE_WORD: Record<string, [string, "ok" | "bad" | "warn" | "grey" | "info"]> = {
  ENTRY: ["Pending", "warn"], VERIFICATION: ["Submitted", "info"], DEPT_BOARD: ["Submitted", "info"], FACULTY_SCRUTINY: ["Submitted", "info"], FACULTY_COMPILATION: ["Submitted", "info"],
  FACULTY_BOARD: ["Submitted", "info"], RECORDS: ["Submitted", "info"], SENATE: ["Submitted", "info"], PUBLISHED: ["Published", "ok"],
};

/** the quick questions on the dashboard: one click applies the filters that answer it */
export const QUICK: { key: string; label: string; filters: GstFilters; both?: boolean }[] = [
  { key: "paid", label: "Students who paid GST", filters: { payment: "PAID" } },
  { key: "unpaid", label: "Students who have not paid", filters: { payment: "NOT_PAID" } },
  { key: "paid-not-registered", label: "Paid but not registered", filters: { payment: "PAID", registration: "NOT_REGISTERED" } },
  { key: "registered", label: "Registered students", filters: { registration: "REGISTERED" } },
  { key: "registered-unpaid", label: "Registered but not paid", filters: { registration: "REGISTERED", payment: "NOT_PAID" } },
  { key: "level100", label: "100 Level students", filters: { level: "100" } },
  { key: "carryover", label: "Carryover students", filters: { eligibility: "CARRYOVER" } },
  { key: "not-applicable", label: "Not applicable (no course owed)", filters: { eligibility: "NOT_APPLICABLE" } },
];

export const naira = (n: number | string | null | undefined) => (n == null ? "—" : "₦" + Number(n).toLocaleString("en-NG", { maximumFractionDigits: 0 }));
export const num = (n: number | string | null | undefined) => Number(n ?? 0).toLocaleString();
export const pct = (part: number | string | null | undefined, whole: number | string | null | undefined) => {
  const w = Number(whole ?? 0);
  return w ? `${Math.round((100 * Number(part ?? 0)) / w)}%` : "—";
};
export const dayOf = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }) : "—");
