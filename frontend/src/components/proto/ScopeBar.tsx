"use client";

/**
 * scopeBar(what, opts) — proto/part21.html. One bar, every list: faculty,
 * department, programme, level, course, session and semester, the trail it
 * makes, and the count it selects. A change goes into the URL (so the page
 * re-reads its lists in that scope) and into a cookie (so the scope holds
 * between screens). The ceiling is the office's: a selector the office may
 * not widen is disabled and says why.
 */
import { usePathname, useSearchParams } from "next/navigation";
import { STUDENT_LEVELS } from "@/lib/levels";
import { useQueryNav } from "@/lib/query-nav";
import { Ico } from "./ui";
import { EMPTY_SCOPE, SCOPE_COOKIE, SCOPE_KEYS, type Scope } from "@/lib/scope";

export interface ScopeStructure {
  faculties: { code: string; name: string; collegeCode?: string | null; departments: { code: string; name: string; programmes: { code: string; name: string; archived?: boolean }[] }[] }[];
  /** V756: the sessions that had a Summer Semester (registration.summer_period) */
  summerSessions?: string[];
}

/** V756: semester 3's name — the Summer only on the regular (full-time) stream of a session that had a Summer Semester; a CCE or
 *  postgraduate stream's semester 3 is its own third. With no session (or no list of Summer sessions) to read it by, a word that is
 *  never wrong. A page that names no stream reads as one listing every stream (the safe words); a page of one stream passes it.
 *  V756: a page that lists every stream at once (stream "ALL": the result sets and class lists of the full-time, CCE and postgraduate
 *  streams together) holds in a Summer session's semester 3 the Summer's classes and the third semester's, and says both. */
export type SemesterStream = "REGULAR" | "CCE" | "PG" | "ALL";
export function thirdSemester(session: string | null | undefined, stream: string | null | undefined,
  summerSessions: readonly string[] | null | undefined): "Summer" | "Third" | "Summer or third" | "Summer and third" {
  if (stream === "ALL") {
    if (!session || !summerSessions) return "Summer or third";
    return summerSessions.includes(session) ? "Summer and third" : "Third";
  }
  if (stream && stream !== "REGULAR") return "Third";
  if (!session || !summerSessions) return "Summer or third";
  return summerSessions.includes(session) ? "Summer" : "Third";
}

/** V756: a semester's word inside a sentence — First, Second and Third in lower case, the Summer always capitalised */
export const semesterInSentence = (w: string) => (w.startsWith("Summer") ? w : w.toLowerCase());

export interface Ceiling {
  fac?: string;
  dept?: string;
  prog?: string;
  why?: string;
}

const LEVELS = STUDENT_LEVELS;

/** the scope holds between screens: a cookie the server pages read */
function remember(next: Scope) {
  try {
    document.cookie = `${SCOPE_COOKIE}=${encodeURIComponent(JSON.stringify(next))}; path=/; max-age=2592000; samesite=lax`;
  } catch {
    /* the URL still carries it */
  }
}

function Sel({
  id,
  label,
  opts,
  value,
  disabled,
  anyLabel,
  onChange,
}: {
  id: string;
  label: string;
  opts: [string, string][];
  value: string;
  disabled?: boolean;
  anyLabel: string;
  onChange: (v: string) => void;
}) {
  return (
    <div className="scope__f">
      <label htmlFor={id}>{label}</label>
      <select id={id} className="ws__select" disabled={disabled} value={value} onChange={(e) => onChange(e.target.value)}>
        <option value="">{anyLabel}</option>
        {opts.map((o) => (
          <option key={o[0]} value={o[0]}>
            {o[1]}
          </option>
        ))}
      </select>
    </div>
  );
}

export function ScopeBar({
  scope,
  structure,
  sessions,
  courses,
  what,
  count,
  of,
  withCourse,
  ceiling = {},
  hide = [],
  onExport,
  withSummer = false,
  stream = "ALL",
}: {
  scope: Scope;
  structure: ScopeStructure;
  sessions: string[];
  /** the courses the programme and semester select, when the course selector is wanted */
  courses?: { code: string; title: string; semester: number }[];
  what: string;
  count: number;
  of: number;
  withCourse?: boolean;
  ceiling?: Ceiling;
  /** selectors to omit entirely — e.g. a lecturer or HOD is bound to their own courses/department */
  hide?: ("fac" | "dept" | "prog" | "level")[];
  onExport?: () => void;
  /** V739: offer semester 3 (the Summer Semester, or a CCE or postgraduate third semester) beside the first and second */
  withSummer?: boolean;
  /** V756: the stream the page reads (?stream=), which decides whether semester 3 is the Summer; a page that names none lists every
   *  stream together (ALL: semester 3 of a Summer session is "Summer and third semester"); a page of the regular stream passes REGULAR */
  stream?: SemesterStream;
}) {
  const queryNav = useQueryNav();
  const pathname = usePathname();
  const params = useSearchParams();

  const s: Scope = { ...scope, fac: ceiling.fac ?? scope.fac, dept: ceiling.dept ?? scope.dept, prog: ceiling.prog ?? scope.prog };
  const f = structure.faculties.find((x) => x.code === s.fac) ?? null;
  const d = f?.departments.find((x) => x.code === s.dept) ?? null;
  const p = d?.programmes.find((x) => x.code === s.prog) ?? null;

  function set(patch: Partial<Scope>) {
    const next: Scope = { ...s, ...patch };
    if (patch.fac !== undefined) { next.dept = ""; next.prog = ""; next.course = ""; }
    if (patch.dept !== undefined) { next.prog = ""; next.course = ""; }
    if (patch.prog !== undefined) next.course = "";
    if (patch.sem !== undefined) next.course = "";
    const q = new URLSearchParams(params.toString());
    for (const k of SCOPE_KEYS) {
      if (next[k]) q.set(k, next[k]);
      else q.delete(k);
    }
    remember(next);
    queryNav(`${pathname}?${q.toString()}`);
  }

  const trail: string[] = [f ? `Faculty of ${f.name}` : "The University"];
  if (d) trail.push(d.name);
  if (p) trail.push(p.name);
  if (s.level) trail.push(`${s.level} Level`);
  if (s.course) trail.push(s.course);
  // V756: semester 3 is the Summer only on the regular stream of a session that had one (structure.summerSessions)
  const third = `${thirdSemester(s.session, stream, structure.summerSessions)} semester`;
  if (s.sem) trail.push(s.sem === "1" ? "First semester" : s.sem === "2" ? "Second semester" : third);

  const courseOpts: [string, string][] = (courses ?? [])
    .filter((c) => !s.sem || s.sem === "3" || c.semester === Number(s.sem))   // V739: a Summer class is a course of either semester
    .map((c) => [c.code, `${c.code} ${c.title}`]);
  const locked = !!(ceiling.fac || ceiling.dept || ceiling.prog);
  const narrowed = SCOPE_KEYS.some((k) => k !== "session" && s[k] && s[k] !== EMPTY_SCOPE[k]);

  return (
    <div className="scope">
      <div className="scope__row">
        {hide.includes("fac") ? null : <Sel id="sc-fac" label="Faculty" opts={structure.faculties.map((x) => [x.code, x.name])} value={s.fac} disabled={!!ceiling.fac} anyLabel="All faculties" onChange={(v) => set({ fac: v })} />}
        {hide.includes("dept") ? null : <Sel id="sc-dept" label="Department" opts={f ? f.departments.map((x) => [x.code, x.name]) : []} value={s.dept} disabled={!!ceiling.dept || !f} anyLabel={f ? "All departments" : "Choose a faculty first"} onChange={(v) => set({ dept: v })} />}
        {hide.includes("prog") ? null : <Sel id="sc-prog" label="Programme" opts={d ? d.programmes.map((x) => [x.code, x.name]) : []} value={s.prog} disabled={!!ceiling.prog || !d} anyLabel={d ? "All programmes" : "Choose a department first"} onChange={(v) => set({ prog: v })} />}
        {hide.includes("level") ? null : <Sel id="sc-level" label="Level" opts={LEVELS.map((l) => [l, `${l} Level`])} value={s.level} anyLabel="All levels" onChange={(v) => set({ level: v })} />}
        {withCourse ? (
          <Sel id="sc-course" label="Course" opts={courseOpts} value={s.course} disabled={!p} anyLabel={p ? "All courses" : "Choose a programme first"} onChange={(v) => set({ course: v })} />
        ) : null}
        <Sel id="sc-session" label="Session" opts={sessions.map((x) => [x, x])} value={s.session} anyLabel={s.session || "Session"} onChange={(v) => set({ session: v || s.session })} />
        <Sel id="sc-sem" label="Semester" opts={withSummer || s.sem === "3" ? [["1", "First semester"], ["2", "Second semester"], ["3", third]] : [["1", "First semester"], ["2", "Second semester"]]} value={s.sem} anyLabel="Both semesters" onChange={(v) => set({ sem: v })} />
      </div>
      <div className="scope__sum">
        <span className="trail">
          {trail.map((t, i) => (
            <span key={i}>
              {i ? <span style={{ color: "var(--faint)" }}> &rsaquo; </span> : null}
              {t}
            </span>
          ))}
        </span>
        <span className="count">
          Showing <b className="tnum">{count.toLocaleString()}</b> {what} of <span className="tnum">{of.toLocaleString()}</span>
        </span>
        {locked ? (
          <span className="lock">
            <Ico name="shield" size={13} w={2} />
            {ceiling.why ?? "Your office bounds this scope."}
          </span>
        ) : narrowed ? (
          <button className="scope__clear" onClick={() => set({ ...EMPTY_SCOPE, session: s.session })}>
            Clear the scope
          </button>
        ) : null}
        {onExport ? (
          <button className="scope__clear" onClick={onExport}>
            Export this list
          </button>
        ) : null}
      </div>
    </div>
  );
}
