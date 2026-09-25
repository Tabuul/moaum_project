/** Student statistics (V257): the shapes the engine returns and the filters every screen carries. One set of
 *  filters is read from the address, sent to the API unchanged, and carried forward on every drill-down. */

export interface StatCounts { total: number; paid: number; registered: number; paid_not_registered: number; not_paid: number; no_charge: number; not_registered: number; payable?: number; paid_amount?: number; outstanding?: number }
export interface StatFaculty extends StatCounts { faculty_code: string; faculty: string }
export interface StatDepartment extends StatFaculty { dept_code: string; department: string }
export interface StatProgramme extends StatDepartment { programme_code: string; programme: string }
export interface StatDegree extends StatCounts { degree_type: string }
export interface StatScope { kind: "UNIVERSITY" | "PG_SCHOOL" | "COLLEGE" | "FACULTY" | "DEPARTMENT"; label: string; faculty?: string; department?: string; money: boolean }
export interface StatSummary {
  scope: StatScope; session: string; semester: number | null; totals: StatCounts;
  byFaculty: StatFaculty[]; byDepartment: StatDepartment[]; byProgramme: StatProgramme[]; byDegreeType: StatDegree[];
  options: { sessions: string[]; semesters: number[]; programmes: { faculty_code: string; faculty: string; dept_code: string; department: string; programme_code: string; programme: string }[]; levels: number[]; statuses: string[]; degreeTypes: string[] };
  window: { number: number; registration_opens: string | null; registration_closes: string | null; state: string }[];
}
export interface StatRow {
  student_id: string; surname: string; other_names: string; number: string; faculty_code: string; faculty: string; dept_code: string; department: string;
  programme_code: string; programme: string; level: number; status: string; entry_mode: string; is_pg: boolean; is_chs: boolean; degree_type: string | null;
  payable?: number; paid_amount?: number; outstanding?: number; pay_status: string; paid: boolean; last_paid_at: string | null; last_reference?: string | null;
  registered: boolean; registration_status: string | null; registered_at: string | null;
}
export interface StatPage { scope: StatScope; session: string; semester: number | null; which: Which; total: number; page: number; size: number; rows: StatRow[] }

export type Which = "ALL" | "PAID" | "REGISTERED" | "PAID_NOT_REGISTERED" | "NOT_PAID" | "NO_CHARGE" | "NOT_REGISTERED";
export const WHICH_WORD: Record<Which, string> = {
  ALL: "All students", PAID: "School fees paid", REGISTERED: "Course registered", PAID_NOT_REGISTERED: "Paid but not registered",
  NOT_PAID: "Not paid", NO_CHARGE: "No charge stated", NOT_REGISTERED: "Not registered",
};
export const DEGREE_WORD: Record<string, string> = { PGD: "Postgraduate Diploma", MASTERS: "Master's", MPHIL: "M.Phil.", PHD: "Ph.D." };
export const SEMESTER_WORD = (n: number | null | string) => (n == null || n === "" ? "Whole session" : Number(n) === 1 ? "First semester" : Number(n) === 2 ? "Second semester" : "Third semester");

export interface StatFilters { session: string; semester: string; fac: string; dept: string; prog: string; level: string; status: string; degree: string }
export const EMPTY_FILTERS: StatFilters = { session: "", semester: "", fac: "", dept: "", prog: "", level: "", status: "", degree: "" };

/** the filters as the address carries them; anything malformed is dropped rather than sent */
export function readStatFilters(p: Record<string, string | string[] | undefined>): StatFilters {
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  return {
    session: /^\d{4}\/\d{4}$/.test(s("session")) ? s("session") : "",
    semester: /^[123]$/.test(s("semester")) ? s("semester") : "",
    fac: s("fac").slice(0, 20), dept: s("dept").slice(0, 20), prog: s("prog").slice(0, 20),
    level: /^\d{3}$/.test(s("level")) ? s("level") : "",
    status: ["ACTIVE", "PROBATION", "ADMITTED"].includes(s("status")) ? s("status") : "",
    degree: ["PGD", "MASTERS", "MPHIL", "PHD"].includes(s("degree")) ? s("degree") : "",
  };
}

export function statQuery(f: Partial<StatFilters>, extra: Record<string, string | number | undefined> = {}): string {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(f)) if (v) q.set(k, String(v));
  for (const [k, v] of Object.entries(extra)) if (v !== undefined && v !== "" && v !== null) q.set(k, String(v));
  return q.toString();
}

/** the address of the students behind a figure, carrying every filter forward */
export function detailHref(f: StatFilters, which: Which, more: Partial<StatFilters> = {}): string {
  return `/stats/students?${statQuery({ ...f, ...more }, { which })}`;
}
