/**
 * Course registration correction: the Director of ICT takes one student's wrongly counted course off one registration, with a
 * reason — the course, the curriculum and every other student untouched. A course without a result is withdrawn at once; one with a
 * result (any mark, F or ABS) is held for the Registrar or the Deputy Registrar, who confirm or decline it (not the officer who asked).
 * The Director may cancel a held removal or put an applied one back. The shapes the API answers with
 * (/api/v1/registration/corrections), the words for how a course came on and where a removal stands, and what may be asked.
 * Node-tested.
 */
import { shownCode } from "./course-code.ts";

/** how a course came onto the registration, read from the record (registration.entry_came), never a guess */
export type Came = "STUDENT" | "OFFICE" | "REGISTRY_LATE" | "OLD_PORTAL" | "CARRY_OVER" | "DEFERRED" | "UNKNOWN";
export type RemovalState = "PENDING" | "APPLIED" | "DECLINED" | "CANCELLED" | "UNDONE";

/** one of the student's registrations, to choose the session and semester from */
export interface StudentRegistration { registrationId: string; session: string; semester: number; level: number | null; status: string; courses: number }
/** GET /student?matric= — found by the matriculation number, or by the admission number while the student has none */
export interface CorrectionStudent {
  /** the number the student is found by: the matriculation number, else the admission number */
  id: string; matric: string | null; matricNo?: string | null; admissionNo?: string | null;
  name: string; programmeCode: string | null; programme: string | null; level: number | null; status: string;
  /** a Senate-approved graduate: the approved CGPA stays whatever is taken off */
  graduate: boolean; registrations: StudentRegistration[];
}

/** the number the student is known by on the record, with its label: the matriculation number, else the admission number while there is none */
export function studentNumber(s: Pick<CorrectionStudent, "matric" | "matricNo" | "admissionNo">): [string, string] {
  if (s.matricNo) return ["Matriculation number", s.matricNo];
  if (s.admissionNo) return ["Admission number", s.admissionNo];
  return ["Matriculation number", s.matric ?? "—"];
}
/** the same course on another of the student's registrations — a carry-over the removed result gave rise to, among them */
export interface Elsewhere {
  registrationId: string; offeringId: string; session: string; semester: number; courseCode: string; entryType: string | null; status: string; units: number;
  hasResult: boolean; result: string | null; removalRef: string | null;
}
/** GET /entries — one course on the registration as the Director reads it before a correction */
export interface CorrectionEntry {
  registrationId: string; offeringId: string; courseCode: string; codeAsTaken: string | null; title: string; units: number; status: string;
  entryType: string | null; basis: string | null; category: string | null; isElective: boolean; came: Came; hasResult: boolean; resultWords: string | null;
  removalId: string | null; removalRef: string | null; removalState: RemovalState | null; registrationStatus: string; level: number | null; elsewhere: Elsewhere[];
}
/** GET "" — a removal as it stands, newest first; matric is the number the student is found by (the matriculation number, else the
 *  admission number), so Open finds the student by it */
export interface Removal {
  id: string; ref: string; groupRef: string; studentId: string; matric: string | null; name: string; courseCode: string; codeAsTaken: string | null;
  title: string | null; session: string; semester: number; level: number | null; wasStatus: string; wasUnits: number; wasAdded: Came; hadResult: boolean;
  resultWords: string | null; graduate: boolean; reason: string; state: RemovalState; requestedByName: string | null; requestedOffice: string | null;
  requestedAt: string; decidedByName: string | null; decidedOffice: string | null; decidedAt: string | null; decisionNote: string | null;
  undoneByName: string | null; undoneAt: string | null; undoReason: string | null;
}
/** POST "" — the removals made under one reason */
export interface RequestAnswer {
  groupRef: string; graduate: boolean;
  removals: { id: string; ref: string; state: RemovalState; courseCode: string; session: string; semester: number }[];
}

/** the offices that take a course off (the database checks the active office again) and those that decide a held one */
export const REQUESTERS = ["ict", "super"];
export const DECIDERS = ["registrar", "dregistrar", "super"];
export const mayRequest = (office: string | null | undefined) => REQUESTERS.includes(office ?? "");
export const mayDecide = (office: string | null | undefined) => DECIDERS.includes(office ?? "");

export const CAME_WORD: Record<Came, string> = {
  STUDENT: "Chosen by the student",
  OFFICE: "Added by an office",
  REGISTRY_LATE: "Late registration by the Registry",
  OLD_PORTAL: "Old portal upload",
  CARRY_OVER: "Carry-over the results state",
  DEFERRED: "Deferred course",
  UNKNOWN: "Not recorded",
};
export const cameWord = (c: string | null | undefined) => CAME_WORD[(c ?? "UNKNOWN") as Came] ?? CAME_WORD.UNKNOWN;

/** where a removal stands, in the words the student's change history uses, and its tone */
export const STATE_WORD: Record<RemovalState, [string, "ok" | "warn" | "bad" | "grey" | "info"]> = {
  PENDING: ["Held for the Registry", "warn"],
  APPLIED: ["Withdrawn", "ok"],
  DECLINED: ["Declined by the Registry", "bad"],
  CANCELLED: ["Cancelled", "grey"],
  UNDONE: ["Put back", "grey"],
};
export const stateWord = (s: string | null | undefined): [string, "ok" | "warn" | "bad" | "grey" | "info"] =>
  STATE_WORD[s as RemovalState] ?? [s ? s.charAt(0) + s.slice(1).toLowerCase() : "—", "grey"];

/** a course counted on the registration: approved or registered */
export const counted = (status: string | null | undefined) => status === "APPROVED" || status === "REGISTERED";
/** a removal still standing: held for the Registry, or applied */
export const liveRemoval = (state: string | null | undefined) => state === "PENDING" || state === "APPLIED";
/** a removal the Director may still cancel (held) or put back (applied) */
export const undoable = liveRemoval;

/** a course on the record of a registration: neither dropped nor withdrawn (a course taken off by the Directorate of ICT is withdrawn) */
export const onRecord = (e: { status?: string | null }) => e.status !== "DROPPED" && e.status !== "WITHDRAWN";
/** a course taken off the registration (withdrawn): shown removed, never ticked or counted */
export const takenOff = (e: { status?: string | null }) => e.status === "WITHDRAWN";

/** the code a past course is shown under: the code it was taken under where the record keeps one, else the course's own */
export const codeTaken = (code: string | null | undefined, asTaken?: string | null) => shownCode(asTaken || code);

/** a course that may be taken off: counted, with no removal standing */
export const removable = (e: Pick<CorrectionEntry, "status" | "removalState">) => counted(e.status) && !liveRemoval(e.removalState);
/** the same course elsewhere may be named in the same request when it is counted there and no removal stands on it */
export const includable = (x: Pick<Elsewhere, "status" | "removalRef">) => counted(x.status) && !x.removalRef;
/** why the same course elsewhere cannot be named, or null when it can */
export function notIncludable(x: Pick<Elsewhere, "status" | "removalRef">): string | null {
  if (x.removalRef) return `${x.removalRef} stands on it`;
  if (!counted(x.status)) return `${(x.status || "not counted").toLowerCase()} on that registration`;
  return null;
}

const SEM = ["", "First", "Second", "Third"];
export const semesterWord = (n: number) => (SEM[n] ? `${SEM[n]} semester` : `Semester ${n}`);
export const choiceKey = (session: string, semester: number) => `${session}|${semester}`;

/** the student's registrations to choose from, newest first: one choice a session and semester */
export function semesterChoices(regs: StudentRegistration[]): StudentRegistration[] {
  const seen = new Set<string>();
  return [...regs]
    .sort((a, b) => b.session.localeCompare(a.session) || b.semester - a.semester)
    .filter((r) => { const k = choiceKey(r.session, r.semester); if (seen.has(k)) return false; seen.add(k); return true; });
}

/** the reason, as the database asks it: ten characters or more */
export function reasonProblem(reason: string, what = "why the course is taken off"): string | null {
  return reason.trim().length >= 10 ? null : `Say ${what}: ten characters or more. It goes on the record with your name.`;
}

/** the request: the course chosen and any of the same course elsewhere ticked, under one reason */
export function removalBody(studentId: string, entry: Pick<CorrectionEntry, "registrationId" | "offeringId">, also: Pick<Elsewhere, "registrationId" | "offeringId">[], reason: string) {
  const entries = [entry, ...also].map((x) => ({ registrationId: x.registrationId, offeringId: x.offeringId }));
  return { studentId, entries: entries.filter((x, i) => entries.findIndex((y) => y.registrationId === x.registrationId && y.offeringId === x.offeringId) === i), reason: reason.trim() };
}

/** how many of the courses named carry a result, and so are held for the Registrar or the Deputy Registrar (the University's decision) */
export function heldCount(entry: Pick<CorrectionEntry, "hasResult">, also: Pick<Elsewhere, "hasResult">[]): number {
  return (entry.hasResult ? 1 : 0) + also.filter((x) => x.hasResult).length;
}

/** what happens to the courses named together: those with a result held for the Registry, the others withdrawn at once */
export function heldWords(held: number, named: number): string {
  if (!held) return named === 1 ? "It carries no result: it is withdrawn at once." : `The ${named} courses named carry no result: each is withdrawn at once.`;
  if (held === named) return named === 1 ? "It carries a result: it is held for the Registry." : `Each of the ${named} courses named carries a result: each is held for the Registry.`;
  return `${held} of the ${named} courses named carr${held === 1 ? "ies" : "y"} a result and ${held === 1 ? "is" : "are"} held for the Registry; the others are withdrawn at once.`;
}

/** what was done, a line a removal: "RCR-2026-00001 · CSC 201, 2024/2025 First semester: withdrawn" */
export function answerLines(a: RequestAnswer): string[] {
  return a.removals.map((r) => `${r.ref} · ${shownCode(r.courseCode)}, ${r.session} ${semesterWord(r.semester)}: ${r.state === "APPLIED" ? "withdrawn" : r.state === "PENDING" ? "held for the Registrar or the Deputy Registrar" : stateWord(r.state)[0].toLowerCase()}`);
}

/** the decline's note, which the database asks for (ten characters or more); a confirmation's note is optional */
export function decideProblem(confirm: boolean, note: string): string | null {
  return confirm || note.trim().length >= 10 ? null : "Say why the removal is declined: ten characters or more.";
}
