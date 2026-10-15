/** The Student Query (V469): the filters the query builder carries in the address, the shapes the engine returns, the words the
 *  screen uses and the presets — each preset only a set of filters, read by the one engine (/api/v1/stats/students/query). */

export interface QueryFilters {
  type: string; route: string; centre: string; studyMode: string;
  fac: string; dept: string; prog: string; pgAward: string;
  session: string; semester: string; admissionSession: string; level: string;
  status: string; sex: string; matriculated: string; finalYear: string; spillover: string;
  graduation: string; registration: string; fees: string; classification: string;
  jupebCombination: string; jupebSubject: string; prelimRoute: string;
  entryYear: string; matricYear: string; jambYear: string; q: string;
}

export const QUERY_KEYS: (keyof QueryFilters)[] = [
  "type", "route", "centre", "studyMode", "fac", "dept", "prog", "pgAward", "session", "semester", "admissionSession", "level",
  "status", "sex", "matriculated", "finalYear", "spillover", "graduation", "registration", "fees", "classification",
  "jupebCombination", "jupebSubject", "prelimRoute", "entryYear", "matricYear", "jambYear", "q",
];

export const EMPTY_QUERY: QueryFilters = Object.fromEntries(QUERY_KEYS.map((k) => [k, ""])) as unknown as QueryFilters;

const CODE = /^[A-Z][A-Z0-9_]{0,40}$/;
const UNIT = /^[A-Za-z0-9][A-Za-z0-9_./ -]{0,29}$/;
const SESSION = /^\d{4}\/\d{4}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const YEAR = /^(19[5-9]\d|20\d\d|2100)$/;
const ONE_OF: Partial<Record<keyof QueryFilters, string[]>> = {
  sex: ["M", "F"], matriculated: ["YES", "NO"], finalYear: ["YES", "NO"], graduation: ["GRADUATED", "NOT_GRADUATED"],
  registration: ["REGISTERED", "NOT_REGISTERED"], fees: ["OUTSTANDING", "COMPLETED"], classification: ["CLASSIFIED", "REQUIRES_CLASSIFICATION"],
};

/** the filters as the address carries them; anything malformed is dropped rather than sent (the server checks again) */
export function readQueryFilters(p: Record<string, string | string[] | undefined>): QueryFilters {
  const out: QueryFilters = { ...EMPTY_QUERY };
  for (const k of QUERY_KEYS) {
    const raw = typeof p[k] === "string" ? (p[k] as string).trim() : "";
    if (!raw) continue;
    let ok = false;
    const allowed = ONE_OF[k];
    if (allowed) ok = allowed.includes(raw);
    else if (k === "fac" || k === "dept" || k === "prog") ok = UNIT.test(raw);
    else if (k === "session" || k === "admissionSession") ok = SESSION.test(raw);
    else if (k === "semester") ok = /^[123]$/.test(raw);
    else if (k === "level") ok = /^\d{1,3}$/.test(raw);
    else if (k === "jupebCombination" || k === "jupebSubject") ok = UUID.test(raw);
    else if (k === "entryYear" || k === "matricYear" || k === "jambYear") ok = YEAR.test(raw);
    else if (k === "pgAward") ok = raw === "-" || CODE.test(raw);
    else if (k === "q") ok = raw.length <= 80;
    else ok = CODE.test(raw);
    if (ok) out[k] = k === "q" ? raw.slice(0, 80) : raw;
  }
  if (out.type === "ALL") out.type = "";
  return out;
}

/** the filters (and anything extra, such as the page) as a query string, empty values left out */
export function queryString(f: Partial<QueryFilters>, extra: Record<string, string | number | undefined | null> = {}): string {
  const q = new URLSearchParams();
  for (const k of QUERY_KEYS) { const v = f[k]; if (v) q.set(k, v); }
  for (const [k, v] of Object.entries(extra)) if (v !== undefined && v !== null && v !== "") q.set(k, String(v));
  return q.toString();
}

/** a change of one filter, with the filters that depended on it cleared (type → route → … → programme; the type's own filters) */
export function withChange(f: QueryFilters, key: keyof QueryFilters, value: string): QueryFilters {
  const n: QueryFilters = { ...f, [key]: value };
  const after: Partial<Record<keyof QueryFilters, (keyof QueryFilters)[]>> = {
    type: ["route", "centre", "studyMode", "fac", "dept", "prog", "pgAward", "level", "jupebCombination", "jupebSubject", "prelimRoute", "classification"],
    fac: ["dept", "prog"],
    dept: ["prog"],
    jupebCombination: ["jupebSubject"],
  };
  for (const k of after[key] ?? []) n[k] = "";
  return n;
}

export interface QueryScope { kind: string; label: string; faculty?: string | null; department?: string | null; programmeType?: string | null }

export interface QueryRow {
  source: "REGISTER" | "JUPEB" | "PRELIMINARY"; learner_id: string; student_id: string | null;
  surname: string; other_names: string; sex: string | null;
  matric_no: string | null; jamb_no: string | null; application_no: string | null; admission_no: string | null;
  programme_type: string | null; programme_type_name: string | null; proposed_type: string | null;
  classification_status: "CLASSIFIED" | "REQUIRES_CLASSIFICATION"; classification_note: string | null;
  admission_route: string | null; admission_route_name: string | null; study_mode: string | null; centre_code: string | null; centre_name: string | null;
  faculty_code: string | null; faculty: string | null; dept_code: string | null; department: string | null;
  programme_code: string | null; programme: string | null; programme_is_target: boolean; pg_award: string | null;
  level: number | null; admission_session: string | null; current_session: string | null; status: string;
  matriculated: boolean; final_year: boolean; spillover_state: string | null; application_status: string | null;
  jupeb_combination: string | null; prelim_name: string | null; registration_status: string | null; fee_status?: string | null;
}

export interface QueryPage { scope: QueryScope; session: string; total: number; page: number; size: number; rows: QueryRow[] }

export interface TypeCard { id: string; code: string; name: string; description: string | null; display_order: number; active: boolean; count: number }
export interface Breakdown { faculty_code: string | null; faculty: string | null; dept_code?: string | null; department?: string | null; programme_code?: string | null; programme?: string | null; count: number }

export interface QuerySummary {
  scope: QueryScope; session: string; types: TypeCard[]; requiresClassification: number; total: number;
  byFaculty: Breakdown[]; byDepartment: Breakdown[]; byProgramme: Breakdown[];
}

export interface QueryOptions {
  scope: QueryScope; currentSession: string; type: string | null;
  types: { id: string; code: string; name: string; description: string | null; display_order: number; active: boolean }[];
  routes: { code: string; name: string }[]; centres: { code: string; name: string }[];
  studyModes: string[]; statuses: string[]; levels: number[]; admissionSessions: string[];
  programmes: { faculty_code: string; faculty: string; dept_code: string; department: string; programme_code: string; programme: string }[];
  pgAwards: string[]; prelimRoutes: { code: string; name: string }[]; jupebCombinations: { id: string; name: string }[];
  jupebSubjects: { id: string; code: string; title: string }[];
  sessions: string[]; learnerSessions: string[]; semesters: number[]; fees: boolean; classifies: boolean;
}

/** the statuses a learner may have — the register's, the JUPEB learner's (COMPLETED) and a learner who joined the register (PROGRESSED) */
export const STATUS_WORD: Record<string, string> = {
  CURRENT: "Current students (all who have not left)", ACTIVE: "Active", ADMITTED: "Admitted", PROBATION: "On probation", DEFERRED: "Deferred",
  SUSPENDED: "Suspended", RUSTICATED: "Rusticated", WITHDRAWN: "Withdrawn", VOLUNTARY_WITHDRAWAL: "Voluntary withdrawal", EXPELLED: "Expelled",
  TRANSFERRED_OUT: "Transferred out", GRADUATED: "Graduated", COMPLETED: "Completed", DECEASED: "Deceased", DORMANT: "Dormant", PROGRESSED: "Progressed to the register",
};
export const statusWord = (s: string | null | undefined) => (s ? STATUS_WORD[s] ?? s.charAt(0) + s.slice(1).toLowerCase().replace(/_/g, " ") : "—");

export const MODE_WORD: Record<string, string> = {
  FULL_TIME: "Full-time", PART_TIME: "Part-time", SANDWICH: "Sandwich", EVENING: "Evening", WEEKEND: "Weekend", DISTANCE_LEARNING: "Distance learning", OTHER: "Other",
};
export const modeWord = (m: string | null | undefined) => (m ? MODE_WORD[m] ?? m : "—");

export const SPILLOVER_WORD: Record<string, string> = {
  ANY: "Any spillover", NONE: "Not spillover", SPILLOVER_YEAR_1: "Spillover — first year", SPILLOVER_YEAR_2: "Spillover — second year",
  SPILLOVER_YEAR_3: "Spillover — third year", SPILLOVER_LIMIT_REACHED: "Spillover limit reached",
};

export const SEX_WORD: Record<string, string> = { M: "Male", F: "Female" };
export const awardWord = (a: string) => (a === "-" ? "Award not stated" : a);

/** V475: where a student stands past the programme's length, as the cohort engine says — SP1, SP2 (each a session, both semesters),
 *  SP3 where the limit allows it, or the limit reached; nothing for a student within the programme's length */
export function spilloverWord(state: string | null | undefined): { short: string; long: string } | null {
  if (!state) return null;
  const m = /^SPILLOVER_YEAR_(\d)$/.exec(state);
  if (m) return { short: `SP${m[1]}`, long: `Spillover year ${m[1]} (SP${m[1]})` };
  if (state === "SPILLOVER_LIMIT_REACHED") return { short: "SP limit", long: "Spillover limit reached" };
  return null;
}

/** "Undergraduate Student", "JUPEB Student" — the learner named by type where the context needs it */
export const typeStudentWord = (name: string | null | undefined) => (name ? `${name} Student` : "Requires classification");

/** the level as the list shows it: a register level, "Preliminary", or a dash for a JUPEB learner */
export function levelWord(r: Pick<QueryRow, "source" | "level">): string {
  if (r.level != null) return `${r.level}`;
  return r.source === "PRELIMINARY" ? "Preliminary" : "—";
}

export interface Preset { key: string; label: string; filters: Partial<QueryFilters>; fees?: boolean; group?: "faculty" | "department" | "programme" }

/** the quick queries: each only a set of filters (or, for "by faculty / department / programme", a breakdown of the same selection) */
export const PRESETS: Preset[] = [
  { key: "ALL", label: "All students", filters: {} },
  { key: "CURRENT", label: "Current students", filters: { status: "CURRENT" } },
  { key: "ACTIVE", label: "Active students", filters: { status: "ACTIVE" } },
  { key: "FINAL_YEAR", label: "Final year students", filters: { status: "CURRENT", finalYear: "YES" } },
  { key: "GRADUATED", label: "Graduated students", filters: { graduation: "GRADUATED" } },
  { key: "SPILLOVER", label: "Spillover students", filters: { status: "CURRENT", spillover: "ANY" } },
  { key: "DEFERRED", label: "Deferred students", filters: { status: "DEFERRED" } },
  { key: "MATRICULATED", label: "Matriculated", filters: { matriculated: "YES" } },
  { key: "NOT_MATRICULATED", label: "Not yet matriculated", filters: { status: "CURRENT", matriculated: "NO" } },
  { key: "REGISTERED", label: "With registered courses", filters: { status: "CURRENT", registration: "REGISTERED" } },
  { key: "NOT_REGISTERED", label: "Without course registration", filters: { status: "CURRENT", registration: "NOT_REGISTERED" } },
  { key: "OUTSTANDING", label: "With outstanding fees", filters: { status: "CURRENT", fees: "OUTSTANDING" }, fees: true },
  { key: "COMPLETED_FEES", label: "With completed fees", filters: { status: "CURRENT", fees: "COMPLETED" }, fees: true },
  { key: "BY_FACULTY", label: "Students by faculty", filters: {}, group: "faculty" },
  { key: "BY_DEPARTMENT", label: "Students by department", filters: {}, group: "department" },
  { key: "BY_PROGRAMME", label: "Students by programme", filters: {}, group: "programme" },
];

/** a preset applied: the student type and the office's own choice of session kept, everything else replaced */
export function applyPreset(f: QueryFilters, p: Preset): QueryFilters {
  return { ...EMPTY_QUERY, type: f.type, session: f.session, semester: f.semester, ...p.filters };
}

/** the filters in force, in words, each with the key that clears it — the "filters applied" summary and the export's heading */
export function activeFilters(f: QueryFilters, o: QueryOptions | null): { key: keyof QueryFilters; label: string; value: string }[] {
  const out: { key: keyof QueryFilters; label: string; value: string }[] = [];
  const name = <T extends { code: string; name: string }>(list: T[] | undefined, code: string) => list?.find((x) => x.code === code)?.name ?? code;
  const prog = o?.programmes.find((p) => p.programme_code === f.prog);
  const fac = o?.programmes.find((p) => p.faculty_code === f.fac);
  const dept = o?.programmes.find((p) => p.dept_code === f.dept);
  const push = (key: keyof QueryFilters, label: string, value: string) => { if (f[key]) out.push({ key, label, value }); };
  push("type", "Programme type", name(o?.types, f.type));
  push("route", "Admission route", name(o?.routes, f.route));
  push("centre", "Centre", name(o?.centres, f.centre));
  push("studyMode", "Study mode", modeWord(f.studyMode));
  push("fac", "Faculty", fac?.faculty ?? f.fac);
  push("dept", "Department", dept?.department ?? f.dept);
  push("prog", "Programme", prog?.programme ?? f.prog);
  push("pgAward", "PG type", awardWord(f.pgAward));
  push("prelimRoute", "Preliminary type", o?.prelimRoutes.find((x) => x.code === f.prelimRoute)?.name ?? f.prelimRoute);
  push("jupebCombination", "JUPEB combination", o?.jupebCombinations.find((x) => x.id === f.jupebCombination)?.name ?? "Selected combination");
  push("jupebSubject", "JUPEB subject", (() => { const s = o?.jupebSubjects.find((x) => x.id === f.jupebSubject); return s ? `${s.code} — ${s.title}` : "Selected subject"; })());
  push("session", "Session", f.session);
  push("semester", "Semester", f.semester === "1" ? "First semester" : f.semester === "2" ? "Second semester" : "Third semester");
  push("admissionSession", "Admission session", f.admissionSession);
  push("level", "Level", `${f.level} Level`);
  push("status", "Status", statusWord(f.status));
  push("sex", "Gender", SEX_WORD[f.sex] ?? f.sex);
  push("matriculated", "Matriculated", f.matriculated === "YES" ? "Yes" : "Not yet");
  push("finalYear", "Final year", f.finalYear === "YES" ? "Final year only" : "Not final year");
  push("spillover", "Spillover", SPILLOVER_WORD[f.spillover] ?? f.spillover);
  push("graduation", "Graduation", f.graduation === "GRADUATED" ? "Graduated" : "Not graduated");
  push("registration", "Course registration", f.registration === "REGISTERED" ? "Registered" : "Not registered");
  push("fees", "School fees", f.fees === "OUTSTANDING" ? "Outstanding" : "Completed");
  push("classification", "Classification", f.classification === "REQUIRES_CLASSIFICATION" ? "Requires classification" : "Classified");
  push("entryYear", "Entry year", f.entryYear);
  push("matricYear", "Matriculation year", f.matricYear);
  push("jambYear", "JAMB year", f.jambYear);
  push("q", "Search", `“${f.q}”`);
  return out;
}

/** the export's heading: "STUDENT TYPE: POSTGRADUATE" (or ALL STUDENT TYPES) and the filters applied in words */
export function exportHeading(f: QueryFilters, o: QueryOptions | null): { title: string; sub: string; meta: [string, string][] } {
  const type = f.type ? (o?.types.find((t) => t.code === f.type)?.name ?? f.type) : "All student types";
  const rest = activeFilters(f, o).filter((x) => x.key !== "type");
  return {
    title: `STUDENT TYPE: ${type.toUpperCase()}`,
    sub: rest.length ? rest.map((x) => `${x.label}: ${x.value}`).join(" · ") : "No other filter",
    meta: [["Student type", type], ...rest.map((x) => [x.label, x.value] as [string, string])],
  };
}
