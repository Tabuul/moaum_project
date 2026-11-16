/**
 * The check of an old-portal registration or results file, put together from its batches. The portal checks a file a batch at a
 * time (each batch run and undone), so each batch's answer is against the record as it stands: the counts add up, the keyed facts
 * (the courses as taken, the students, the new registrations) are united, and a student's GPA picture is the record's before with
 * every batch's difference added — the CGPA after is the weighted points over the units counted.
 */

/** one row of the file as the loader read it against the record; the course as taken where the upload records it, and what
 *  became of the student's entry (entryStatus: ADDED, ALREADY_ON_RECORD, UNITS_CORRECTED, UNITS_ON_PORTAL…; null when the row
 *  never reached an entry) — on a results row the status says what became of the result */
export type LegacyLine = {
  line: string | null; matric: string; course: string; session: string; semester: number; status: string; detail: string | null;
  uploadedCode?: string | null; uploadedTitle?: string | null; uploadedUnits?: string | null; category?: string | null;
  matchedCourse?: string | null; currentTitle?: string | null; currentUnits?: number | null;
  version?: "EXISTING" | "NEW" | null; match?: string | null; action?: string | null; entryStatus?: string | null;
};

/** a course as the file has it for a class: the code as taken, its title and credit units, against today's catalogue */
export type CourseFact = {
  courseCode: string; codeAsTaken: string; title: string; units: number; currentTitle: string | null; currentUnits: number | null;
  session: string; semester: number; stream: string | null; match: string | null; made: boolean; existed: boolean; matrics: string[];
};

/** a student's figures at a moment: units counted, weighted points, CGPA, and each semester's GPA keyed "session|semester" */
export type GpaPicture = { tcr: number; twgp: number; cgpa: number | null; sem: Record<string, number | null> };
export type GpaFact = { matric: string; name: string; before: GpaPicture; after: GpaPicture };

/** what the loader answers for a batch */
export type CheckAnswer = Record<string, unknown> & {
  lines?: LegacyLine[]; courses?: CourseFact[]; gpa?: GpaFact[];
  students_affected?: string[]; graduates?: string[]; registrations_new?: string[];
};

/** a semester whose GPA the file moves */
export type SemesterMove = { key: string; session: string; semester: number; before: number | null; after: number | null };
/** a student whose GPA or CGPA the file moves */
export type GpaMove = {
  matric: string; name: string; tcrBefore: number; tcrAfter: number; twgpBefore: number; twgpAfter: number;
  cgpaBefore: number | null; cgpaAfter: number | null; semesters: SemesterMove[];
};

export type MergedCheck = {
  totals: Record<string, number>; lines: LegacyLine[]; courses: CourseFact[]; gpa: GpaMove[];
  studentsAffected: string[]; graduates: string[]; registrationsNew: string[];
};

/** a CGPA or GPA as the record rounds it: two places, half away from zero */
export function round2(x: number): number {
  return Math.sign(x) * Math.round((Math.abs(x) + Number.EPSILON) * 100) / 100;
}

const num = (v: unknown): number | null => {
  if (v == null || v === "") return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
};

/** the key a course as taken is united under across the batches (a class a batch made and undid has an id of its own) */
export function courseKey(c: Pick<CourseFact, "courseCode" | "session" | "semester" | "stream" | "codeAsTaken" | "title" | "units">): string {
  return [c.courseCode, c.session, c.semester, c.stream ?? "", c.codeAsTaken, c.title, c.units].join("|");
}

/** the batches' answers as one check */
export function mergeChecks(batches: CheckAnswer[]): MergedCheck {
  const totals: Record<string, number> = {};
  const lines: LegacyLine[] = [];
  const courses = new Map<string, CourseFact & { anyMade: boolean }>();
  const affected = new Set<string>();
  const graduates = new Set<string>();
  const regsNew = new Set<string>();
  const gpa = new Map<string, { name: string; before: GpaPicture; dTcr: number; dTwgp: number; sems: Map<string, { before: number | null; after: number | null }> }>();

  for (const b of batches) {
    for (const [k, v] of Object.entries(b)) if (typeof v === "number" && k !== "semester") totals[k] = (totals[k] ?? 0) + v;
    if (Array.isArray(b.lines)) lines.push(...b.lines);
    for (const c of b.courses ?? []) {
      const key = courseKey(c);
      const had = courses.get(key);
      if (!had) {
        courses.set(key, { ...c, matrics: [...new Set(c.matrics ?? [])], anyMade: !!c.made, existed: !!c.existed });
      } else {
        had.anyMade = had.anyMade || !!c.made;
        had.existed = had.existed || !!c.existed;
        for (const m of c.matrics ?? []) if (!had.matrics.includes(m)) had.matrics.push(m);
        if (had.currentTitle == null) had.currentTitle = c.currentTitle;
        if (had.currentUnits == null) had.currentUnits = c.currentUnits;
        if (had.match == null) had.match = c.match;
      }
    }
    for (const m of b.students_affected ?? []) affected.add(m);
    for (const m of b.graduates ?? []) graduates.add(m);
    for (const r of b.registrations_new ?? []) regsNew.add(r);
    for (const g of b.gpa ?? []) {
      const before = g.before ?? { tcr: 0, twgp: 0, cgpa: null, sem: {} };
      const after = g.after ?? before;
      let s = gpa.get(g.matric);
      if (!s) {
        s = { name: g.name, before: { tcr: num(before.tcr) ?? 0, twgp: num(before.twgp) ?? 0, cgpa: num(before.cgpa), sem: before.sem ?? {} }, dTcr: 0, dTwgp: 0, sems: new Map() };
        gpa.set(g.matric, s);
      }
      s.dTcr += (num(after.tcr) ?? 0) - (num(before.tcr) ?? 0);
      s.dTwgp += (num(after.twgp) ?? 0) - (num(before.twgp) ?? 0);
      const keys = new Set([...Object.keys(before.sem ?? {}), ...Object.keys(after.sem ?? {})]);
      for (const k of keys) {
        const was = num(before.sem?.[k]);
        const now = num(after.sem?.[k]);
        if (was === now) continue;
        const had = s.sems.get(k);
        if (!had) s.sems.set(k, { before: was, after: now });
        // the same semester moved by two batches: its GPA before, with both differences
        else had.after = had.after != null && was != null && now != null ? round2(had.after + (now - was)) : now;
      }
    }
  }

  const moves: GpaMove[] = [...gpa.entries()].map(([matric, s]) => {
    const tcrAfter = s.before.tcr + s.dTcr;
    const twgpAfter = round2(s.before.twgp + s.dTwgp);
    return {
      matric, name: s.name, tcrBefore: s.before.tcr, tcrAfter, twgpBefore: s.before.twgp, twgpAfter,
      cgpaBefore: s.before.cgpa, cgpaAfter: tcrAfter > 0 ? round2(twgpAfter / tcrAfter) : null,
      // a semester two batches moved and put back where it was is not a change
      semesters: [...s.sems.entries()].filter(([, v]) => v.before !== v.after).map(([key, v]) => {
        const [session, semester] = key.split("|");
        return { key, session, semester: Number(semester), before: v.before, after: v.after };
      }).sort((a, b) => a.key.localeCompare(b.key)),
    };
  })
    // a student whose units counted and points are where they were, with no semester moved, is not a student whose GPA moves
    // (a registration-only semester, or batches whose differences cancel)
    .filter((g) => g.tcrAfter !== g.tcrBefore || round2(g.twgpAfter) !== round2(g.twgpBefore) || g.semesters.length > 0)
    .sort((a, b) => a.matric.localeCompare(b.matric));

  return {
    totals, lines,
    courses: [...courses.values()].map(({ anyMade, ...c }) => ({ ...c, made: anyMade && !c.existed }))
      .sort((a, b) => a.courseCode.localeCompare(b.courseCode) || a.session.localeCompare(b.session) || a.semester - b.semester || a.title.localeCompare(b.title)),
    gpa: moves,
    studentsAffected: [...affected].sort(), graduates: [...graduates].sort(), registrationsNew: [...regsNew].sort(),
  };
}

/** rows that do not reach the record in any form: the loader's own refusals and repeats */
const NOT_LOADED = new Set(["REFUSED", "NO_STUDENT", "DUPLICATE_IN_FILE", "DUPLICATE_CONFLICT"]);

/** the courses the file names by a code whose title differs from every title the course has had — each one the office confirms
 *  before the file goes up: the code as written, the file's title, today's title */
export function newTitleCourses(lines: LegacyLine[]): { code: string; title: string; currentTitle: string; matchedCourse: string; rows: number }[] {
  const out = new Map<string, { code: string; title: string; currentTitle: string; matchedCourse: string; rows: number }>();
  for (const l of lines) {
    if (l.match !== "CODE_ONLY_NEW_TITLE" || NOT_LOADED.has(l.status)) continue;
    const code = (l.uploadedCode ?? l.course ?? "").trim();
    const title = (l.uploadedTitle ?? "").trim();
    const key = `${code.toUpperCase()}|${title}`;
    const had = out.get(key);
    if (had) had.rows++;
    else out.set(key, { code, title, currentTitle: l.currentTitle ?? "", matchedCourse: l.matchedCourse ?? l.course, rows: 1 });
  }
  return [...out.values()].sort((a, b) => a.code.localeCompare(b.code) || a.title.localeCompare(b.title));
}

/** the courses whose credit units in the file differ from the units the student's programme takes them at today */
export function unitDifferences(courses: CourseFact[]): CourseFact[] {
  return courses.filter((c) => c.currentUnits != null && Number(c.currentUnits) !== Number(c.units));
}

/** the courses as taken of the check, counted from the united facts: recorded new by the file, and already on record before it */
export function versionCounts(courses: CourseFact[]): { made: number; existed: number } {
  return { made: courses.filter((c) => c.made).length, existed: courses.filter((c) => c.existed).length };
}

/** an entry that takes the file's credit units: added, already on record as the file has it, or corrected to the file's */
export const UNITS_APPLIED = new Set(["ADDED", "ADDED_TO_OPEN_REGISTRATION", "ALREADY_ON_RECORD", "UNITS_CORRECTED", "AS_TAKEN_CORRECTED", "AS_TAKEN_LINKED", "CATEGORY_CORRECTED"]);
/** an entry whose course stays on record as it is (a result on the portal, units the Senate set, an office that does not correct the
 *  record, other units under the old rule, a dropped course) — the file's credit units are not applied to it */
export const KEPT_AS_ON_RECORD = new Set(["UNITS_ON_PORTAL", "UNITS_BY_AMENDMENT", "AS_TAKEN_DIFFERS", "UNITS_DIFFER", "DROPPED_ON_RECORD"]);

/** for each course of the check (in its order), how many of its rows take the file's credit units and how many stay as on record —
 *  read in one pass over the rows, however many courses the file names. A row is read by what became of its entry (on a results
 *  row the status speaks of the result); a row that reached no entry, or whose writes were undone, counts for neither */
export function unitsApplied(courses: CourseFact[], lines: LegacyLine[]): { applied: number; kept: number }[] {
  const key = (code: string, session: string, semester: number, title: string, units: number) => [code, session, Number(semester), title, Number(units)].join("|");
  const counts = new Map<string, { applied: number; kept: number }>();
  for (const l of lines) {
    if (NOT_LOADED.has(l.status)) continue;
    const entry = l.entryStatus ?? l.status;
    const applied = UNITS_APPLIED.has(entry);
    if (!applied && !KEPT_AS_ON_RECORD.has(entry)) continue;
    const k = key(l.matchedCourse ?? l.course, l.session, l.semester, (l.uploadedTitle ?? "").trim().replace(/\s+/g, " "), Number(l.uploadedUnits));
    const c = counts.get(k) ?? { applied: 0, kept: 0 };
    if (applied) c.applied++; else c.kept++;
    counts.set(k, c);
  }
  return courses.map((c) => ({ ...(counts.get(key(c.courseCode, c.session, c.semester, c.title, c.units)) ?? { applied: 0, kept: 0 }) }));
}

/* ── a row's status in words, shared by the check, the upload's result and an upload's report ── */

/** V472: each row's status in words — what the upload did, or (on the check before it) what it will do */
export const LINE_WORD: Record<string, [string, string]> = {
  ADDED: ["Added", "Will be added"],
  ADDED_TO_OPEN_REGISTRATION: ["Added to a registration open on the portal", "Will be added to a registration open on the portal"],
  ALREADY_ON_RECORD: ["Already on record", "Already on record — nothing changes"],
  UNITS_DIFFER: ["On record at other units — left as it is", "On record at other units — left as it is"],
  DROPPED_ON_RECORD: ["Dropped on record — left as it is", "Dropped on record — left as it is"],
  NO_STUDENT: ["No such student", "No such student"],
  NO_COURSE: ["No such course", "No such course"],
  DUPLICATE_IN_FILE: ["Repeated in the file", "Repeated in the file"],
  REFUSED: ["Refused", "Will be refused"],
  RESULT_POSTED: ["Result posted", "Result will be posted"],
  HELD: ["Held — student not loaded yet", "Will be held — student not loaded yet"],
  // V771: a held result its upload's rollback dropped (it never posts under a rolled-back upload)
  HELD_ROLLED_BACK: ["Held, dropped with the rollback", "Held, dropped with the rollback"],
  NO_MARK: ["No mark, or a mark over 100", "No mark, or a mark over 100"],
  // V614: the mark read as the whole (an exam over 60 or alone, a Total, a CA over 40), and a result already on record
  RESULT_AS_TOTAL: ["Result posted — the whole mark, of 100", "Result will be posted — the whole mark, of 100"],
  RESULT_REPLACED: ["Result posted over an earlier upload's", "Result will replace an earlier upload's"],
  RESULT_ALREADY_ON_RECORD: ["Same result already on record — not posted again", "Same result already on record — not posted again"],
  RESULT_ON_PORTAL: ["A result entered on the portal is on record — kept", "A result entered on the portal is on record — kept"],
  // the course as taken: the file's title, credit units and category, against what is on record
  AS_TAKEN_MISSING: ["Course title, credit units or category missing", "Course title, credit units or category missing"],
  AS_TAKEN_INVALID: ["Course title, credit units or category not readable", "Course title, credit units or category not readable"],
  COURSE_AMBIGUOUS: ["The code is held by more than one course", "The code is held by more than one course"],
  DUPLICATE_CONFLICT: ["Repeated in the file with other values", "Repeated in the file with other values"],
  COURSE_ON_RECORD_ELSEWHERE: ["On record under another course of the code", "On record under another course of the code"],
  REMOVED_ON_RECORD: ["Taken off the registration — not brought back", "Taken off the registration — not brought back"],
  REMOVAL_PENDING: ["A removal awaits the Registry — left as it is", "A removal awaits the Registry — left as it is"],
  UNITS_CORRECTED: ["Units corrected to the file's", "Units will be corrected to the file's"],
  AS_TAKEN_CORRECTED: ["Code or title corrected to the file's", "Code or title will be corrected to the file's"],
  AS_TAKEN_LINKED: ["Recorded as taken — nothing else changed", "Will be recorded as taken — nothing else changes"],
  CATEGORY_CORRECTED: ["Category corrected to the file's", "Category will be corrected to the file's"],
  UNITS_ON_PORTAL: ["A result entered on the portal stands — left as it is", "A result entered on the portal stands — left as it is"],
  UNITS_BY_AMENDMENT: ["Units the Senate set — left as they are", "Units the Senate set — left as they are"],
  AS_TAKEN_DIFFERS: ["On record differently — left as it is", "On record differently — left as it is"],
};
export const lineWord = (status: string, preview: boolean) => (LINE_WORD[status] ?? [status, status])[preview ? 1 : 0];
/** a row's status as a pill: what will load (or is left as it is) and needs a look, or what will not load */
export const lineTone = (status: string): "info" | "warn" | "bad" =>
  status === "RESULT_AS_TOTAL" || status === "RESULT_ALREADY_ON_RECORD" || status === "AS_TAKEN_LINKED" || status === "ADDED" || status === "RESULT_POSTED"
    || status === "ALREADY_ON_RECORD" ? "info"
    : status === "UNITS_DIFFER" || status === "DROPPED_ON_RECORD" || status === "ADDED_TO_OPEN_REGISTRATION" || status === "HELD"
      || status === "RESULT_REPLACED" || status === "RESULT_ON_PORTAL" || status === "UNITS_CORRECTED" || status === "AS_TAKEN_CORRECTED"
      || status === "CATEGORY_CORRECTED" || status === "UNITS_ON_PORTAL" || status === "UNITS_BY_AMENDMENT" || status === "AS_TAKEN_DIFFERS"
      || status === "REMOVED_ON_RECORD" || status === "REMOVAL_PENDING" ? "warn" : "bad";
/** how the loader matched the file's course: by code and title, by a title or code the course had, or by the code alone (a title
 *  new to the course — the office confirms it before the file goes up) */
export const MATCH_WORD: Record<string, string> = {
  CODE_AND_TITLE: "Code and title",
  TITLE_FROM_HISTORY: "A title it had",
  FORMER_CODE: "A code it had",
  CODE_ONLY_NEW_TITLE: "Code only — new title",
  AMBIGUOUS: "More than one course",
};
/** a refusal in words, without the portal's code in front of it ("REGISTRATION_ONCE_A_SESSION: …") */
export const plainDetail = (d: string | null | undefined) => (d ?? "").replace(/^[A-Z][A-Z_]+:\s*/, "");
