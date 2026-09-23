/** The two registers the returns desk lists whole — every student, every member of staff — with
 *  the filter parameters each takes. The API (reports/registers) does the filtering; this is the
 *  shared shape the desk, the printable view and the Excel export read. */

export interface Opt { code: string; name: string; faculty_code?: string; department_code?: string }

export interface StudentRow {
  id: string; matric_no: string | null; admission_no: string | null; surname: string; other_names: string;
  sex: string | null; status: string; entry_mode: string; entry_session: string; level: number;
  programme_code: string; programme: string; department: string | null; faculty: string;
}
export interface StudentOptions {
  faculties: Opt[]; departments: Opt[]; programmes: Opt[]; sessions: { name: string }[];
  levels: number[]; statuses: string[]; entryModes: string[];
}
export interface StaffRow {
  id: string; staff_number: string; surname: string; given_names: string; email: string | null; phone: string | null;
  sex: string | null; rank: string | null; conuass_step: number | null; date_first_appointment: string | null;
  department_code: string | null; department: string | null; faculty: string | null;
  category: string; grade: string | null; step: number | null; appointment_date: string | null; status: string; offices: string | null;
}
export interface StaffOptions {
  faculties: Opt[]; departments: Opt[]; ranks: string[]; categories: string[]; statuses: string[]; offices: Opt[];
}
export interface RegisterPage<R, O> { total: number; page: number; size: number; rows: R[]; options: O }

/** one filter control: the query key, its label, and where its options come from */
export interface FilterSpec { key: string; label: string; options: "faculties" | "departments" | "programmes" | "sessions" | "levels" | "statuses" | "entryModes" | "ranks" | "categories" | "offices" | "sex"; wide?: boolean }

export const STUDENT_FILTERS: FilterSpec[] = [
  { key: "faculty", label: "Faculty", options: "faculties" },
  { key: "department", label: "Department", options: "departments" },
  { key: "programme", label: "Programme", options: "programmes", wide: true },
  { key: "level", label: "Level", options: "levels" },
  { key: "sex", label: "Sex", options: "sex" },
  { key: "status", label: "Status", options: "statuses" },
  { key: "entryMode", label: "Entry mode", options: "entryModes" },
  { key: "session", label: "Entry session", options: "sessions" },
];
export const STAFF_FILTERS: FilterSpec[] = [
  { key: "faculty", label: "Faculty", options: "faculties" },
  { key: "department", label: "Department", options: "departments" },
  { key: "rank", label: "Rank", options: "ranks" },
  { key: "category", label: "Category", options: "categories" },
  { key: "status", label: "Status", options: "statuses" },
  { key: "office", label: "Office held", options: "offices", wide: true },
];

export const STUDENT_KEYS = ["faculty", "department", "programme", "level", "sex", "status", "entryMode", "session", "q"] as const;
export const STAFF_KEYS = ["faculty", "department", "rank", "category", "status", "office", "q"] as const;

/** the query string the API takes, from the page's search params */
export function registerQuery(p: Record<string, string | string[] | undefined>, keys: readonly string[]): string {
  const u = new URLSearchParams();
  for (const k of keys) {
    const v = p[k];
    if (typeof v === "string" && v.trim()) u.set(k, v.trim());
  }
  return u.toString();
}

export const words = (s: string | null | undefined) =>
  (s ?? "").split("_").map((w) => (w ? w.charAt(0) + w.slice(1).toLowerCase() : w)).join(" ");

export const STUDENT_HEADERS = ["Matric no.", "Admission no.", "Surname", "Other names", "Sex", "Faculty", "Department", "Programme", "Level", "Status", "Entry mode", "Entry session"];
export const studentSheetRow = (r: StudentRow): (string | number | null)[] => [
  r.matric_no, r.admission_no, r.surname, r.other_names, r.sex, r.faculty, r.department, r.programme, Number(r.level), words(r.status), words(r.entry_mode), r.entry_session,
];
export const STAFF_HEADERS = ["Staff no.", "Surname", "Given names", "Sex", "Rank", "CONUASS/CONTISS step", "Category", "Faculty", "Department", "Grade", "Step", "First appointment", "Status", "Offices held", "Email", "Phone"];
export const staffSheetRow = (r: StaffRow): (string | number | null)[] => [
  r.staff_number, r.surname, r.given_names, r.sex, r.rank, r.conuass_step, words(r.category), r.faculty, r.department, r.grade, r.step,
  r.date_first_appointment ?? r.appointment_date, words(r.status), r.offices, r.email, r.phone,
];
