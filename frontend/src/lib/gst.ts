/** GST & EPS (V314): what the two offices' desks and the student's GST & EPS page read from /api/v1/gst and /api/v1/me/gst. */

export type GstOffice = "GST" | "EPS";

export const OFFICE_WORD: Record<GstOffice, string> = { GST: "General Studies (GST)", EPS: "Entrepreneurship Studies (EPS)" };
export const OFFICE_SHORT: Record<GstOffice, string> = { GST: "GST", EPS: "EPS" };

export interface GstCounts {
  total: number; required: number; paid: number; unpaid: number; pending: number; not_stated: number; registered: number; not_registered: number;
  gst_registered: number; eps_registered: number; paid_not_registered: number; registered_unpaid: number; male: number; female: number;
  course_registrations: number; revenue: number; outstanding: number;
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
export interface GstFeePage {
  session: string; sessions: { name: string; state: string }[]; setting: GstSetting; rules: GstFeeRule[]; history: GstFeeRule[]; paid: { students: number; amount: number };
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
  options: GstOptions; now: string;
}
export interface GstStudentRow {
  student_id: string; number: string; surname: string; other_names: string; sex: string | null; faculty_code: string; faculty: string; dept_code: string; department: string;
  programme_code: string; programme: string; level: number; status: string; entry_mode: string; required: boolean; fee: number; stated: boolean; paid: number;
  entitled: boolean; pay_state: string; reference: string | null; paid_at: string | null; gst_registered: boolean; eps_registered: boolean; gst_courses: number; eps_courses: number;
  registered_at: string | null; registered_courses: string | null; result_stages: string | null;
}
export interface GstStudentPage { office: GstOffice; session: string; semester: number | null; total: number; page: number; size: number; rows: GstStudentRow[] }

export const GST_FILTER_KEYS = ["session", "semester", "fac", "dept", "prog", "level", "sex", "status", "course", "payment", "registration", "q"] as const;
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
};
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
];

export const naira = (n: number | string | null | undefined) => (n == null ? "—" : "₦" + Number(n).toLocaleString("en-NG", { maximumFractionDigits: 0 }));
export const num = (n: number | string | null | undefined) => Number(n ?? 0).toLocaleString();
export const pct = (part: number | string | null | undefined, whole: number | string | null | undefined) => {
  const w = Number(whole ?? 0);
  return w ? `${Math.round((100 * Number(part ?? 0)) / w)}%` : "—";
};
export const dayOf = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }) : "—");
