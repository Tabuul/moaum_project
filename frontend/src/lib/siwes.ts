/** V752 — SIWES registration at 300 Level, Second Semester (the University's master prompt of 12 November 2026): the words, the
 *  student's next step and the export rows every SIWES screen shares (the student's page and dashboard card, the Academic Office's
 *  desk, the Bursary's fee panel and payments report). The rules are the database's (registration.siwes_eligibility, siwes_applies,
 *  finance.siwes_paid); nothing here decides who may register or what is owed — it says what the server said.
 *  V777 (the user's word of 22 November 2026, "yes charge every siwes course"): every SIWES course carries the fee, paid once a session
 *  before the student registers any of them, whatever the programme, level or semester. Two shapes of the student's page: SEMESTER
 *  (V752's: the Second Semester of a programme SIWES binds is the SIWES course alone, registered on the SIWES page) and COURSE (a SIWES
 *  course among the student's ordinary courses: the fee is paid on the SIWES page, the course is registered on Course Registration). */
import { dayWord, naira, num, type Money } from "./summer.ts";
import { shownCode } from "./course-code.ts";

export { naira, num, type Money };

/** a unit as the API names it: a code and name, or a name alone */
export type UnitRef = { code?: string | null; name?: string | null } | string | null | undefined;

export function unitName(u: UnitRef): string {
  if (u == null) return "";
  if (typeof u === "string") return u;
  return u.name ?? u.code ?? "";
}

export interface SiwesPeriod {
  state: "DRAFT" | "OPEN" | "CLOSED" | string;
  registrationOpens: string | null; registrationCloses: string | null;
  trainingStarts: string | null; trainingEnds: string | null;
  durationMonths: number | null;
  /** who last set it: the office (the period's own JSON) and the person's name (the desk's config adds it); never a person's id */
  note?: string | null; setAt?: string | null; setOffice?: string | null; setByName?: string | null;
}

export interface SiwesCourse {
  id?: string | null; code: string; title: string | null; units: number | null;
  /** K25: the course's state in the catalogue (LIVE; BOARD or SENATE, not yet live; ENDED), as the desk's configuration sends it */
  state?: "LIVE" | "BOARD" | "SENATE" | "ENDED" | string | null;
}

/** V777: a SIWES course that is the student's, as GET /me/siwes lists them (registration.siwes_reach): each with its own level and
 *  semester, and why it is theirs — HELD (on a registration of the session), CARRYOVER (failed, owed), STRUCTURE (their programme's
 *  structure at their level). `passed`: a published pass of an earlier session — neither owed nor asked for. `registrationStatus`: the
 *  status of the registration that holds the course (DRAFT, RETURNED, SUBMITTED, APPROVED or LOCKED), null when none holds it (a course
 *  owed or in the structure), absent from an older answer — read there as before: registered */
export interface SiwesOwnCourse {
  code: string; title?: string | null; units?: number | null; level?: number | null; semester?: number | null;
  basis?: string | null; state?: string | null;
  why?: "HELD" | "CARRYOVER" | "STRUCTURE" | string | null;
  held?: boolean | null; passed?: boolean | null;
  registrationStatus?: "DRAFT" | "RETURNED" | "SUBMITTED" | "APPROVED" | "LOCKED" | string | null;
}

/** what GET /api/v1/me/siwes answers: registration.siwes_eligibility for the student, as is */
export interface MySiwes {
  /** V777: eligible = bound to the SIWES semester (`bound`) or asked the fee for a SIWES course of theirs (mode COURSE) */
  eligible: boolean;
  /** registration.siwes_applies for the student and session: the SIWES rule binds their Second Semester (absent from an older answer) */
  applies?: boolean | null;
  /** V777: how SIWES reaches the student — SEMESTER (the Second Semester is SIWES alone, registered on the SIWES page; V752's shape),
   *  COURSE (a SIWES course among their ordinary courses: the fee is paid here, the course registered on Course Registration), or
   *  null (nothing to pay for). Absent from an older answer: SEMESTER */
  mode?: "SEMESTER" | "COURSE" | null;
  /** V777: V752's `eligible` — the student's Second Semester is SIWES alone */
  bound?: boolean | null;
  /** V777: the SIWES courses that are the student's (each with its own level and semester); `level`, `semester`, `course`,
   *  `semesterFees` are null and `otherCourses` empty for mode COURSE */
  courses?: SiwesOwnCourse[] | null;
  /** V777: where the course is registered — the SIWES page (SEMESTER) or Course Registration (COURSE) */
  registerOn?: "SIWES_PAGE" | "COURSE_REGISTRATION" | null;
  /** V777: the server's word that the student may pay the fee now (the fee published, nothing paid, a SIWES course theirs) */
  canPay?: boolean | null;
  reasons: string[];
  session: string | null;
  level: number | null;
  /** the SIWES semester's number (2): null for mode COURSE, where each course carries its own */
  semester: number | null;
  programme: { code: string; name: string } | null;
  department?: UnitRef;
  faculty?: UnitRef;
  course: SiwesCourse | null;
  period: SiwesPeriod | null;
  /** OPEN and today within the registration dates (Africa/Lagos), as the server reads it */
  registrationOpen: boolean;
  fee: { amount: Money; state: "DRAFT" | "PUBLISHED" | string } | null;
  paid: { reference: string | null; amount: Money; receiptNo: string | null; at: string | null; source: "PORTAL" | "OLD_PORTAL" | string } | null;
  openReference: { reference: string; amount: Money; expiresAt: string | null } | null;
  /** the SIWES registration: courseCode is the course it was made on, whatever the programme's mapping says since */
  registration: { id: string; status: string; at: string | null; courseCode?: string | null; registeredAt?: string | null } | null;
  /** the courses on the student's Second Semester registration for the session other than their SIWES course (the one registered, once
   *  registered): ordinary courses, carry-overs and deferred courses alike */
  otherCourses: string[];
  /** K10: the Second Semester school fees of the session, by the tests registration.siwes_register's fee gate applies
   *  (REG_SEMESTER_FEES_DUE): the SIWES course is registered only once they are stated and cleared (absent from an older answer) */
  semesterFees?: { cleared: boolean; outstanding: Money; stated?: boolean | null } | null;
  /** the server's word that the student may register the SIWES course now (false while the school fees hold it) */
  canRegister?: boolean | null;
  /** how the courses in the SIWES course's way leave the Second Semester, as Course Registration offers it (K11): the student's drop door
   *  only while add and drop is open, the reset when the reset door allows it. Sent by GET /me/siwes only while courses are in the way */
  clearing?: { addDropOpen?: boolean | null; resetAllowed?: boolean | null; resetWhy?: string | null } | null;
  /** the student's SIWES of every session — the payment that settled its fee and the SIWES registration, each or both — so a student
   *  SIWES no longer binds reaches the session it was theirs (GET /me/siwes; the desk's detail carries the same) */
  history?: SiwesHistoryRow[] | null;
}

/** the student's Fees & payments page (menu s/fees), where the Second Semester school fees are paid */
export const FEES_PAGE = { href: "/student/fees", label: "Fees & payments" } as const;

/** K10: the Second Semester school fees hold the SIWES course (not cleared, or not yet stated): only an explicit false says so */
export function schoolFeesOwed(d: Pick<MySiwes, "semesterFees"> | null | undefined): boolean {
  const f = d?.semesterFees;
  return !!f && (f.cleared === false || f.stated === false);
}

/** ": ₦100,000 outstanding", or nothing when the server names no amount */
function outstandingWords(d: Pick<MySiwes, "semesterFees">): string {
  const owed = num(d.semesterFees?.outstanding);
  return owed > 0 ? `: ${naira(owed)} outstanding` : "";
}

/** K10: why the school fees hold the SIWES course, as a clause: not yet stated by the Bursary, or not fully paid (and what is outstanding) */
export function schoolFeesWords(d: Pick<MySiwes, "semesterFees">, session: string | null | undefined): string {
  const s = session ?? "the session";
  return d.semesterFees?.stated === false
    ? `the Bursary has not yet stated the Second Semester school fees for ${s}`
    : `the Second Semester school fees for ${s} are not fully paid${outstandingWords(d)}`;
}

const sentence = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

/** the student's SIWES course: once registered, the course the SIWES registration was made on (registration.courseCode), even when the
 *  Academic Office has mapped the programme to another course since; before, the programme's course as mapped today. The title and
 *  units are known only while the two are the same course. */
export function siwesCourseOf(d: Pick<MySiwes, "course" | "registration"> | null | undefined): SiwesCourse | null {
  if (!d) return null;
  const code = d.registration?.courseCode;
  if (code) return d.course && d.course.code === code ? d.course : { code, title: null, units: null };
  return d.course ?? null;
}

/** the courses in the way of the SIWES course, as the server lists them — never the student's own SIWES course, even from an answer
 *  that still compares with today's mapping */
export function otherCoursesOf(d: Pick<MySiwes, "course" | "registration" | "otherCourses"> | null | undefined): string[] {
  const own = siwesCourseOf(d)?.code ?? null;
  return (d?.otherCourses ?? []).filter((c) => c !== own);
}

/** a reference drawn for the SIWES registration fee ("SIWES registration fee <session>"), or an old-portal "SIWES (legacy)"
 *  payment: never a school fee — paid and read on the SIWES page */
export function isSiwesPurpose(purpose: string | null | undefined): boolean {
  return /^siwes\b/i.test((purpose ?? "").trim());
}

/** why a student is not in SIWES registration, said to the student (registration.siwes_eligibility's reasons) */
export const REASON_WORD: Record<string, string> = {
  NOT_UNDERGRADUATE: "SIWES registration is for undergraduate students; postgraduate programmes are not part of it.",
  CCE: "Students of the Centre for Continuing Education are not part of SIWES registration.",
  NOT_IN_STUDY: "Your record is not active.",
  NOT_300_LEVEL: "SIWES registration is for 300 Level students, in the Second Semester.",
  NOT_CONFIGURED: "Your programme is not among those taking SIWES this session.",
  NO_PERIOD: "The Academic Office has not opened SIWES registration for this session.",
  NO_COURSE: "No SIWES course is set for your programme yet; the Academic Office sets it.",
  ALREADY_PASSED: "You have already passed your SIWES course.",
  // V777: a student the fee is asked of in principle (an undergraduate in study) who has no SIWES course to pay for
  NO_SIWES_COURSE: "Your programme carries no SIWES course at your level, and you hold or owe none: no SIWES fee is asked of you.",
};

/** the same reasons, short, for the desk's lists */
export const REASON_SHORT: Record<string, string> = {
  NOT_UNDERGRADUATE: "Not undergraduate",
  CCE: "CCE",
  NOT_IN_STUDY: "Not in study",
  NOT_300_LEVEL: "Not 300 Level",
  NOT_CONFIGURED: "Programme not taking SIWES",
  NO_PERIOD: "No SIWES period",
  NO_COURSE: "No SIWES course set",
  ALREADY_PASSED: "SIWES already passed",
  NO_SIWES_COURSE: "No SIWES course at the level",
};

export function reasonWord(code: string): string {
  return REASON_WORD[code] ?? code.replaceAll("_", " ").toLowerCase();
}

/** V777: the reasons of the bound shape that speak of the Academic Office's configuration (the programme taking part, the period, the
 *  course set, the 300 Level) say nothing true of a student whose programme simply carries no SIWES course at their level: beside
 *  NO_SIWES_COURSE they are left out, so the student is told the one reason that stands */
const CONFIGURATION = new Set(["NOT_300_LEVEL", "NOT_CONFIGURED", "NO_PERIOD", "NO_COURSE"]);

/** the reasons to say: all of them, but beside NO_SIWES_COURSE not those of the configuration */
export function reasonsToSay(codes: string[] | null | undefined): string[] {
  const all = codes ?? [];
  return all.includes("NO_SIWES_COURSE") ? all.filter((r) => !CONFIGURATION.has(r)) : all;
}

export function reasonWords(codes: string[] | null | undefined): string[] {
  return reasonsToSay(codes).map(reasonWord);
}

/** the reasons that leave a student outside SIWES altogether, as registration.siwes_applies reads them: with none of them, the SIWES
 *  rule binds the student's Second Semester whether or not they can register yet. NOT_IN_STUDY is one (K22: siwes_applies binds only
 *  a student in study, ACTIVE or PROBATION, by the roster's and the eligibility's own test); so is ALREADY_PASSED (a student who passed
 *  SIWES registers the Second Semester as before). V777: and NO_SIWES_COURSE (nothing to pay for) */
const OUTSIDE = new Set(["NOT_UNDERGRADUATE", "CCE", "NOT_IN_STUDY", "NOT_300_LEVEL", "NOT_CONFIGURED", "NO_PERIOD", "ALREADY_PASSED", "NO_SIWES_COURSE"]);

/** V777: whether the student's page is the COURSE shape — a SIWES course among their ordinary courses, the fee paid first */
export function isCourseMode(e: Pick<MySiwes, "mode"> | null | undefined): boolean {
  return e?.mode === "COURSE";
}

/** whether the SIWES rule binds the student's Second Semester: the server's `applies` when it sends it, else read from the reasons
 *  (never for the COURSE shape, whose semester is not SIWES alone) */
export function siwesApplies(e: Pick<MySiwes, "eligible" | "reasons" | "registration" | "applies" | "mode"> | null | undefined): boolean {
  if (!e) return false;
  if (e.mode === "COURSE") return false;
  if (typeof e.applies === "boolean") return e.applies;
  if (e.eligible || e.registration) return true;
  return !(e.reasons ?? []).some((r) => OUTSIDE.has(r));
}

/** what a SIWES student with ordinary Second Semester courses on the registration does: the student's own drop door takes any course
 *  but the SIWES course; ICT Support and the Academic Office drop them otherwise (a department has no drop door). With the server's word
 *  on the calendar (clearing, K11), only what Course Registration offers now: Remove while add and drop is open, the reset when the reset
 *  door allows it, otherwise the offices */
export function dropOthersWords(courses: string[], clearing?: MySiwes["clearing"]): string {
  const list = courses.join(", ");
  if (!clearing) return `Remove ${list} from your Second Semester registration on Course Registration; if you cannot, ask ICT Support or the Academic Office`;
  const c = siwesClearing({ addDropOpen: clearing.addDropOpen, resetAllowed: clearing.resetAllowed, count: courses.length });
  const one = courses.length === 1;
  if (c.remove) {
    return `Remove ${list} from your Second Semester registration on Course Registration while add and drop is open${c.reset ? ", or reset the registration there" : "; if you cannot, ask the Academic Office or ICT Support"}`;
  }
  if (c.reset) return `Add and drop is not open, so ${list} ${one ? "is" : "are"} not removed one by one: reset your Second Semester registration on Course Registration to clear ${one ? "it" : "them"}`;
  return `Add and drop is not open and your Second Semester registration cannot be reset now: ask the Academic Office or ICT Support to remove ${list}`;
}

/** Course Registration's Second Semester (V752: where the student removes or resets what stands in the SIWES course's way), or — V777 —
 *  the semester a SIWES course is taught in, where it is registered among the student's other courses */
export function courseRegistrationPage(session: string | null | undefined, semester: number | null | undefined = 2): { href: string; label: string } {
  return { href: `/student/register?${session ? `session=${encodeURIComponent(session)}&` : ""}semester=${semester ?? 2}`, label: "Course Registration" };
}

/** whether the student can clear the courses in the way themselves now (Remove or the reset on Course Registration): true from an older
 *  answer that does not say, as before */
export function clearsThemselves(clearing: MySiwes["clearing"]): boolean {
  return !clearing || clearing.addDropOpen === true || clearing.resetAllowed === true;
}

/** a carry-over or deferred course on a SIWES Second Semester: removed through the same drop door, it is owed still */
export function waitsWords(code: string): string {
  return `${code} waits for a later semester: the SIWES semester holds the SIWES course alone.`;
}

/** the entries a carry-over or a deferred course is: removed from the SIWES semester, they wait for a later one */
const WAITING = new Set(["CARRYOVER", "DEFERRED"]);

/** v4-1: what an office's registration table (ICT Support's student profile, the Student edit) says on a DROPPED course of a SIWES
 *  Second Semester in place of Restore — the database refuses every restore there, override or not (support_add_checks' SIWES rule): a
 *  carry-over or deferred course waits for a later semester; any other course is not put back, the SIWES course itself being registered
 *  on the student's SIWES page */
export function siwesDroppedWords(entryType: string | null | undefined): string {
  return WAITING.has(entryType ?? "") ? "Waits for a later semester: the SIWES semester holds the SIWES course alone"
    : "Not restored: the SIWES semester holds the SIWES course alone, registered on the student's SIWES page";
}

/** the courses on a SIWES Second Semester registration that stand in the way of the SIWES course, as the server counts them
 *  (otherCourses): never the student's SIWES course (the one registered, once registered), never a course dropped or withdrawn; the
 *  ordinary courses apart from the carry-overs and deferred courses, which wait for a later semester */
export function siwesInTheWay<T extends { courseCode: string; status: string; entryType: string }>(
  entries: T[] | null | undefined, d: Pick<MySiwes, "course" | "registration" | "otherCourses">,
): { ordinary: T[]; waiting: T[] } {
  const listed = new Set(otherCoursesOf(d));
  const standing = (entries ?? []).filter((e) => e.status !== "DROPPED" && e.status !== "WITHDRAWN" && listed.has(e.courseCode));
  return { ordinary: standing.filter((e) => !WAITING.has(e.entryType)), waiting: standing.filter((e) => WAITING.has(e.entryType)) };
}

/** the note Course Registration shows over a Second Semester the SIWES rule binds, by where the student stands: registered; the SIWES
 *  window not open now (before its first day, or closed: nothing is paid or registered, as the SIWES page says); the fee not yet
 *  published; paid and not registered; not paid */
export function siwesSemesterWords(d: Pick<MySiwes, "course" | "registration" | "paid" | "semesterFees" | "registrationOpen" | "period" | "fee">, session: string,
  today: string = lagosToday()): { title: string; words: string; tone: "info" | "ok" | "bad" } {
  const c = siwesCourseOf(d);
  if (d.registration) {
    return { tone: "ok", title: "Your Second Semester is SIWES (industrial training)",
      words: `Your SIWES course${c ? ` ${c.code}` : ""} is registered; print it on the SIWES page.` };
  }
  const alone = `In ${session} your Second Semester holds the SIWES course${c ? ` ${courseWords(c)}` : ""} alone: no other course and no carry-over.`;
  // the SIWES window as the SIWES page reads it (siwesNext): never "pay and register" while nothing is taken
  if (!d.registrationOpen) {
    const w = d.period ? windowWords(d.period, today) : { step: "CLOSED" as const, title: "SIWES registration is closed" };
    if (w.step === "NOT_OPEN") {
      return { tone: "info", title: w.title, words: `${alone} ${d.paid ? "Your SIWES registration fee is paid: register the course on the SIWES page once registration opens."
        : "Pay the SIWES registration fee and register the course on the SIWES page once registration opens."} The Second Semester school fees are paid as usual.` };
    }
    return { tone: "bad", title: w.title, words: `${alone} ${d.paid ? "Your SIWES registration fee is paid, but no SIWES course is registered now"
      : "No SIWES payment is taken and no SIWES course is registered now"}; ask the Academic Office.` };
  }
  if (!d.paid && d.fee?.state !== "PUBLISHED") {
    return { tone: "info", title: "Your Second Semester is SIWES (industrial training)",
      words: `${alone} The Bursary has not published the SIWES registration fee yet; pay it and register the course on the SIWES page once it does. The Second Semester school fees are paid as usual.` };
  }
  // K10: the SIWES course is registered only once the Second Semester school fees are cleared
  if (d.paid && schoolFeesOwed(d)) {
    return { tone: "info", title: "Pay the Second Semester school fees, then register your SIWES course",
      words: `Your SIWES registration fee is paid. ${sentence(schoolFeesWords(d, session))}; pay them on ${FEES_PAGE.label}, then register your SIWES course${c ? ` ${courseWords(c)}` : ""} on the SIWES page. In ${session} it is the only course of your Second Semester, with no carry-over.` };
  }
  if (d.paid) {
    return { tone: "info", title: "Your SIWES registration fee is paid",
      words: `Register your SIWES course${c ? ` ${courseWords(c)}` : ""} on the SIWES page: in ${session} it is the only course of your Second Semester, with no carry-over. The Second Semester school fees are paid as usual.` };
  }
  return { tone: "info", title: "Your Second Semester is SIWES (industrial training)",
    words: `In ${session} you register the SIWES course${c ? ` ${courseWords(c)}` : ""} alone in the Second Semester: no other course and no carry-over. Pay the SIWES registration fee and register the course on the SIWES page; the Second Semester school fees are paid as usual.` };
}

/** what an office's course menu says of a SIWES-bound Second Semester (window.siwes) in place of Add: the database refuses every add
 *  there, override or not (support_add_checks' SIWES rule) — the SIWES course is the student's to register on the SIWES page */
export const SIWES_OFFICE_ADD_WORDS = "Registered on the student's SIWES page once its fee is paid";
export const SIWES_OFFICE_NO_ADD = "The Second Semester is the student's SIWES semester: no course is added here, by override or otherwise. The SIWES course is registered on the student's SIWES page once its fee is paid.";

/** K11: what the reset does in a SIWES Second Semester (registration.student_reset while registration.siwes_sheds holds) */
export const SIWES_RESET_WORDS = "Clear this semester's registration at once: the courses, carry-overs and deferred courses are cleared; carry-overs and deferred courses wait for a later semester. Your results, payments and earlier semesters are not touched.";

/** K11: how the courses in the way of the SIWES course leave the Second Semester, by what the registration view allows: Remove (the
 *  student's drop door) only while add and drop is open; the reset when reset.allowed (reset_refusal alone, as the reset door judges
 *  it); otherwise the Academic Office or ICT Support, whose drop takes any course but the SIWES course there (K12) */
export function siwesClearing(o: { addDropOpen?: boolean | null; resetAllowed?: boolean | null; count: number }): { remove: boolean; reset: boolean; words: string } {
  if (o.count <= 0) return { remove: false, reset: false, words: "" };
  const remove = o.addDropOpen === true;
  const reset = o.resetAllowed === true;
  const them = o.count === 1 ? "it" : "them";
  const words = remove && reset ? `Remove ${them} below while add and drop is open, or reset the registration below.`
    : remove ? `Remove ${them} below while add and drop is open; if you cannot, ask the Academic Office or ICT Support.`
    : reset ? `Add and drop is not open, so ${them === "it" ? "it is" : "they are"} not removed one by one: reset the registration below to clear ${them}.`
    : `Add and drop is not open and the registration cannot be reset now: ask the Academic Office or ICT Support to remove ${them}.`;
  return { remove, reset, words };
}

/** a Second Semester registration of this session is the student's SIWES registration (V752's shape: a COURSE-shape SIWES course is
 *  an ordinary course of an ordinary registration, which prints as one) */
export function isSiwesRegistration(e: Pick<MySiwes, "session" | "registration"> | null | undefined, session: string, semester: number): boolean {
  return !!e && semester === 2 && e.session === session && !!e.registration;
}

// ── V777: the COURSE shape — a SIWES course among the student's ordinary courses ───────────────────────────────────────────────

/** "A", "A and B", "A, B and C" */
function listed(words: string[]): string {
  return words.length < 2 ? words.join("") : `${words.slice(0, -1).join(", ")} and ${words[words.length - 1]}`;
}

const isAre = (n: number) => (n === 1 ? "is" : "are");

/** the SIWES courses the fee is asked for: the student's own, never one already passed */
export function ownCourses(d: Pick<MySiwes, "courses"> | null | undefined): SiwesOwnCourse[] {
  return (d?.courses ?? []).filter((c) => !!c && !!c.code && c.passed !== true);
}

/** those already on a registration of the session (held, as the server says) and those still to register */
export function heldCourses(d: Pick<MySiwes, "courses"> | null | undefined): SiwesOwnCourse[] {
  return ownCourses(d).filter((c) => c.held === true);
}
export function coursesToRegister(d: Pick<MySiwes, "courses"> | null | undefined): SiwesOwnCourse[] {
  return ownCourses(d).filter((c) => c.held !== true);
}

/** where a held SIWES course stands on the registration that holds it, as the student reads it: UNSENT (the registration is a draft, or
 *  was returned to them: the course is on it, not submitted), AWAITING (submitted, waiting for approval), REGISTERED (approved or
 *  locked — and an older answer that does not say, read as before) */
export type HeldStanding = "UNSENT" | "AWAITING" | "REGISTERED";
export function heldStanding(c: Pick<SiwesOwnCourse, "registrationStatus">): HeldStanding {
  const s = c.registrationStatus;
  return s === "DRAFT" || s === "RETURNED" ? "UNSENT" : s === "SUBMITTED" ? "AWAITING" : "REGISTERED";
}

/** the held SIWES courses of the student that stand in the given way on their registration */
export function heldAs(d: Pick<MySiwes, "courses"> | null | undefined, standing: HeldStanding): SiwesOwnCourse[] {
  return heldCourses(d).filter((c) => heldStanding(c) === standing);
}

/** the held courses in words, each group by where it stands: "ZZG 301 (...) is already on your registration; ZZG 312 (...) is on your
 *  registration, not yet submitted" — registered ones first, then those waiting for approval, then those not submitted */
function heldClause(held: SiwesOwnCourse[]): string {
  const by = (s: HeldStanding) => held.filter((c) => heldStanding(c) === s);
  const done = by("REGISTERED"), waiting = by("AWAITING"), unsent = by("UNSENT");
  return [
    done.length ? `${ownCourseList(done)} ${isAre(done.length)} already on your registration` : "",
    waiting.length ? `${ownCourseList(waiting)} ${isAre(waiting.length)} on your registration, waiting for approval` : "",
    unsent.length ? `${ownCourseList(unsent)} ${isAre(unsent.length)} on your registration, not yet submitted` : "",
  ].filter(Boolean).join("; ");
}

/** where a SIWES course is taught, from its own level and semester: "300 Level, First Semester" (either half alone from an answer
 *  short of the other; empty with neither) */
export function courseWhere(c: Pick<SiwesOwnCourse, "level" | "semester">, sep = ", "): string {
  const semester = c.semester != null ? semesterWords(String(c.semester)) : "";
  return [c.level != null ? `${c.level} Level` : "", semester].filter(Boolean).join(sep);
}

/** the courses for a sentence, each with where it is taught: "ZZG 311 (300 Level, First Semester) and ZZG 312 (300 Level, Second Semester)".
 *  The code is shown without its curriculum mark ("MAC 399 BMAS" reads "MAC 399", as everywhere else); the key stays the raw code */
export function ownCourseList(cs: SiwesOwnCourse[]): string {
  return listed(cs.map((c) => { const w = courseWhere(c); return `${shownCode(c.code)}${w ? ` (${w})` : ""}`; }));
}

/** a course of the student's as a line: "ZZG 301 — SIWES (6 units) · 300 Level · First Semester" */
export function ownCourseLine(c: SiwesOwnCourse): string {
  return [courseWords({ code: shownCode(c.code), title: c.title ?? null, units: c.units ?? null }), courseWhere(c, " · ")].filter(Boolean).join(" · ");
}

/** the semesters the courses are taught in, once each, in order: where the student registers them on Course Registration */
export function courseSemesters(cs: SiwesOwnCourse[]): number[] {
  return [...new Set(cs.map((c) => c.semester).filter((s): s is number => typeof s === "number"))].sort((a, b) => a - b);
}

// V777: a SIWES course on Course Registration's menu (or the search) locked while its fee is unpaid, as the GST fee locks a GST/EPS course

/** what holds a SIWES course on the form: the fee unpaid, the fee not yet published, or a course that is not open to the student */
export type SiwesLockKind = "UNPAID" | "FEE_NOT_SET" | "NOT_IN_REACH";

/** the kind of hold a SIWES course's gate words name, by the code the database's message begins with (never shown to the student);
 *  words with none known are the fee's: it is what holds a SIWES course */
export function siwesLockKind(gate: string | null | undefined): SiwesLockKind {
  const code = (gate ?? "").split(":")[0].trim();
  return code === "SIWES_FEE_NOT_SET" ? "FEE_NOT_SET" : code === "SIWES_NOT_IN_REACH" ? "NOT_IN_REACH" : "UNPAID";
}

/** the pill on a locked row, and the hint over it */
export const SIWES_LOCK_PILL: Record<SiwesLockKind, string> = { UNPAID: "SIWES fee required", FEE_NOT_SET: "SIWES fee not published", NOT_IN_REACH: "Not open to you" };
export const SIWES_LOCK_TITLE: Record<SiwesLockKind, string> = {
  UNPAID: "Locked until the SIWES fee is paid",
  FEE_NOT_SET: "Locked until the Bursary publishes the SIWES fee and it is paid",
  NOT_IN_REACH: "Your programme carries no SIWES course at your level; ask the Academic Office",
};

/** the notes over the form for the SIWES courses it locks — one for each kind of hold, the fee unpaid first — saying what is done:
 *  pay the SIWES fee (once a session, whichever SIWES course), then register the course; or wait for the Bursary to publish it. The
 *  amount is named only when the answer has it (a published fee). The codes are shown without a curriculum mark. `shut`: the words of
 *  siwesPayShutWords, when the fee cannot be paid now (the SIWES window is not open): the note then offers no payment and says when */
export function siwesLockNotes(locked: { code: string; gate?: string | null }[], session: string, fee?: Money, shut?: string | null): { kind: "bad" | "info"; title: string; words: string; pay: boolean }[] {
  const by = (k: SiwesLockKind) => [...new Set(locked.filter((l) => siwesLockKind(l.gate) === k).map((l) => shownCode(l.code)))];
  const out: { kind: "bad" | "info"; title: string; words: string; pay: boolean }[] = [];
  const amount = num(fee) > 0 ? ` of ${naira(fee)}` : "";
  const unpaid = by("UNPAID");
  if (unpaid.length && shut) {
    out.push({ kind: "bad", pay: false, title: "SIWES fee required",
      words: `${listed(unpaid)} ${unpaid.length === 1 ? "carries" : "carry"} the SIWES registration fee${amount} for ${session}, paid once a session before ${unpaid.length === 1 ? "it is" : "they are"} registered. ${shut}` });
  } else if (unpaid.length) {
    out.push({ kind: "bad", pay: true, title: "SIWES fee required",
      words: `Pay the SIWES registration fee${amount} for ${session} to register ${listed(unpaid)}. It is paid once a session, whichever SIWES course you register: pay it on the SIWES page, then register the course here.` });
  }
  const unset = by("FEE_NOT_SET");
  if (unset.length) {
    out.push({ kind: "info", pay: false, title: "SIWES fee not published yet",
      words: `The Bursary has not published the SIWES registration fee for ${session}; ${listed(unset)} ${isAre(unset.length)} registered once it is published and paid.` });
  }
  const noReach = by("NOT_IN_REACH");
  if (noReach.length) {
    out.push({ kind: "info", pay: false, title: "SIWES course not open to you",
      words: `${listed(noReach)} ${noReach.length === 1 ? "is a SIWES course" : "are SIWES courses"}, but your programme carries no SIWES course at your level, so the fee cannot be paid for ${noReach.length === 1 ? "it" : "them"}: ask the Academic Office.` });
  }
  return out;
}

/** a SIWES course already on the student's registration with the fee unpaid (registered before every SIWES course carried it): the
 *  words of the note over the form, with the courses named. `shut`: the words of siwesPayShutWords, when the fee cannot be paid now
 *  (the SIWES window is not open) — in place of "you have to pay it now, on the SIWES page" */
export function siwesUnpaidRegisteredWords(codes: string[], session: string, fee?: Money, shut?: string | null): string {
  const amount = num(fee) > 0 ? ` of ${naira(fee)}` : "";
  return `${listed(codes)} ${isAre(codes.length)} on your registration, but the SIWES registration fee${amount} for ${session} is not paid. You registered ${codes.length === 1 ? "it" : "them"} before every SIWES course carried the fee; `
    + (shut ? `it is asked of every student who registers one, once a session. ${shut}` : "it is asked of every student who registers one, once a session, so you have to pay it now, on the SIWES page.");
}

/** where the student registers a SIWES course now the fee is paid: Course Registration of the semester it is taught in, one link for each semester */
export function registerLinks(d: Pick<MySiwes, "session" | "courses">): { href: string; label: string }[] {
  const semesters = courseSemesters(coursesToRegister(d));
  if (!semesters.length) return [];
  return semesters.map((s) => ({ href: courseRegistrationPage(d.session, s).href,
    label: semesters.length > 1 ? `Course Registration, ${semesterWords(String(s))}` : "Course Registration" }));
}

/** where the student submits the registration that holds a SIWES course only as a draft (or returned to them): Course Registration of
 *  the semester the course is taught in, one link for each semester — leaving out a semester registerLinks already links to */
export function submitLinks(d: Pick<MySiwes, "session" | "courses">): { href: string; label: string }[] {
  const semesters = courseSemesters(heldAs(d, "UNSENT"));
  const already = new Set(registerLinks(d).map((l) => l.href));
  const links = semesters.map((s) => ({ href: courseRegistrationPage(d.session, s).href,
    label: semesters.length > 1 ? `Course Registration, ${semesterWords(String(s))}` : "Course Registration" }));
  return links.filter((l) => !already.has(l.href));
}

export const PERIOD_WORD: Record<string, [string, "grey" | "info" | "ok" | "bad" | "warn"]> = {
  DRAFT: ["Draft", "grey"],
  OPEN: ["Open", "ok"],
  CLOSED: ["Closed", "bad"],
};

export function periodWords(p: Pick<SiwesPeriod, "state"> | null | undefined, openNow?: boolean): [string, "grey" | "info" | "ok" | "bad" | "warn"] {
  if (!p) return ["Not set", "grey"];
  if (p.state === "OPEN" && openNow === false) return ["Open — outside its dates", "warn"];
  return PERIOD_WORD[p.state] ?? [p.state, "grey"];
}

/** whether the period holds the programmes listed on the desk to SIWES alone in their 300 Level Second Semester: only a period that has
 *  been opened (registration.siwes_applies reads no draft, and none that is not set) */
export function periodHolds(p: Pick<SiwesPeriod, "state"> | null | undefined): boolean {
  return !!p && p.state !== "DRAFT";
}

/** the desk's first panel's row on what the listed programmes are held to: said as a fact only once the period is opened; while it is a
 *  draft (or not set) nobody is held, and the students of those programmes pay and register as every other student does */
export function heldToSiwesRow(p: Pick<SiwesPeriod, "state"> | null | undefined): [string, string] {
  return periodHolds(p)
    ? ["Held to SIWES alone", "300 Level · Second Semester of the programmes below"]
    : ["Held to SIWES alone", "Nobody yet: once the period is opened, the 300 Level · Second Semester of the programmes below. Until then their students pay the SIWES fee and register the course on Course Registration, like every other student."];
}

/** the question asked before a programme is taken out of SIWES for a session: what it ends is said only where it is in force */
export function removeProgrammeWords(name: string, code: string, session: string, p: Pick<SiwesPeriod, "state"> | null | undefined): string {
  const fee = "they register the Second Semester as before, and still pay the SIWES fee when they register a SIWES course.";
  return `Take ${name} (${code}) out of SIWES for ${session}? `
    + (periodHolds(p) ? `Its 300 Level students are then no longer held to the SIWES course alone: ${fee}` : `Its 300 Level students will not be held to the SIWES course alone when the period is opened: ${fee}`);
}

/** whether the desk shows its Unpaid courses tab: the list was read, or its read failed for a reason other than a refusal (403: the
 *  acting office does not read it, so the tab is not theirs) — a failed read keeps the tab, to say so, never a silent landing elsewhere */
export function unpaidTabShown(unpaid: unknown[] | null | undefined, problem: { status?: number } | null | undefined): boolean {
  return !!unpaid || (!!problem && problem.status !== 403);
}

/** "1 December 2026", or a dash */
export function dateWord(iso: string | null | undefined): string {
  return iso ? dayWord(iso) : "—";
}

/** "1 January 2027 – 30 June 2027 (6 months)": the training period of the session */
export function trainingWords(p: Pick<SiwesPeriod, "trainingStarts" | "trainingEnds" | "durationMonths"> | null | undefined): string {
  if (!p) return "Not yet dated";
  const months = p.durationMonths ? ` (${p.durationMonths} month${p.durationMonths === 1 ? "" : "s"})` : "";
  if (!p.trainingStarts && !p.trainingEnds) return months ? `Not yet dated${months}` : "Not yet dated";
  return `${dateWord(p.trainingStarts)} – ${dateWord(p.trainingEnds)}${months}`;
}

export function courseWords(c: SiwesCourse | null | undefined): string {
  if (!c) return "Not set";
  return `${c.code}${c.title ? ` — ${c.title}` : ""}${c.units != null ? ` (${c.units} unit${c.units === 1 ? "" : "s"})` : ""}`;
}

/** today's calendar date in Lagos, the day the University's dates are read on */
export function lagosToday(now: Date = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Africa/Lagos", year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
}

export type SiwesStep =
  | "NO_PERIOD" | "NOT_ELIGIBLE" | "FEE_NOT_SET" | "NOT_OPEN" | "CLOSED" | "PAY" | "PAY_REFERENCE"
  | "PAID_NOT_ELIGIBLE" | "PAID_CLOSED" | "DROP_OTHERS" | "PAY_SCHOOL_FEES" | "REGISTER" | "REGISTERED" | "ELSEWHERE" | "UNDONE"
  // V777 (the COURSE shape): a SIWES course already on the student's registration with its fee unpaid — they pay it now; the fee paid,
  // the course to register on Course Registration; the fee paid and the course on a registration not yet submitted (SUBMIT_REGISTRATION)
  // or submitted and waiting for approval (AWAITING_APPROVAL)
  | "PAY_HELD" | "REGISTER_COURSE" | "SUBMIT_REGISTRATION" | "AWAITING_APPROVAL";

/** a SIWES registration that no longer stands: its SIWES course dropped or withdrawn (an office undid it) */
const UNDONE = new Set(["DROPPED", "WITHDRAWN"]);

/** the sessions of the student's SIWES other than the one shown — a payment that settled the fee or a SIWES registration that stands in
 *  it — newest first, as GET /me/siwes lists them (history). A session whose SIWES was wholly undone (its registration dropped and no
 *  payment standing) is not the student's SIWES (v4-4) */
export function siwesElsewhere(d: Pick<MySiwes, "session" | "history"> | null | undefined): SiwesHistoryRow[] {
  return (d?.history ?? []).filter((h) => !!h && h.session !== d?.session && (!!h.paid || (!!h.registration && !UNDONE.has(h.registration.status ?? ""))))
    .sort((a, b) => (a.session < b.session ? 1 : a.session > b.session ? -1 : 0));
}

/** K30: the session shown, when its SIWES of the student's was wholly undone: its SIWES registration dropped or withdrawn by an office and
 *  no SIWES payment of theirs standing for it (history, as GET /me/siwes lists it); null otherwise */
export function siwesUndone(d: Pick<MySiwes, "session" | "history" | "paid" | "registration"> | null | undefined): SiwesHistoryRow | null {
  if (!d || d.paid || d.registration) return null;
  return (d.history ?? []).find((h) => !!h && h.session === d.session && !h.paid && !!h.registration && UNDONE.has(h.registration.status ?? "")) ?? null;
}

/** whether the dashboard shows the SIWES card: SIWES binds the student's Second Semester of the session, or they have paid or registered
 *  it — never for a student SIWES no longer binds (a past registrant, whose menu still carries the SIWES page), nor for a draft period */
export function siwesCardShown(d: MySiwes | null | undefined): boolean {
  // V777: and while a SIWES course is theirs to pay for (mode COURSE): the fee is asked before it is registered
  return !!d && (isCourseMode(d) || siwesApplies(d) || !!d.paid || !!d.registration);
}

/** V777: the COURSE shape's tiles — the session and where its courses are taught, the student, the fee, the courses: the training
 *  dates and registration window are the SIWES semester's (the programmes SIWES binds), never theirs */
function courseTiles(d: MySiwes): [string, string, string][] {
  const s = d.session ?? "this session";
  const own = ownCourses(d);
  const held = heldCourses(d);
  const toRegister = coursesToRegister(d);
  const where = [...new Set(own.map((c) => courseWhere(c, " · ")).filter(Boolean))];
  const published = d.fee?.state === "PUBLISHED";
  return [
    ["SIWES session", s, where.length === 1 ? where[0] : where.length ? `${own.length} courses` : "Every SIWES course is charged"],
    // a course only on a draft (or returned) registration is not registered: it is on the registration, not submitted
    ["You", held.length && !toRegister.length
      ? (held.some((c) => heldStanding(c) === "UNSENT") ? "Not submitted" : held.some((c) => heldStanding(c) === "AWAITING") ? "Awaiting approval" : "Registered")
      : "Eligible", d.programme?.name ?? ""],
    ["SIWES fee", d.paid ? "Paid" : published ? naira(d.fee?.amount) : "—",
      d.paid ? `${naira(d.paid.amount)} · ${dateWord(d.paid.at)}` : published ? "Not paid" : "Not published yet"],
    ["SIWES courses", String(own.length), own.map((c) => shownCode(c.code)).join(", ") || "—"],
  ];
}

/** the SIWES page's tiles — [label, value, sub] — by where the student stands (v4-2). On ELSEWHERE, the student's own SIWES sessions and
 *  nothing owed for the session shown: never this session's fee or training as theirs. A student SIWES does not bind this session, who
 *  has paid and registered nothing in it, owes nothing for it (a draft period binds nobody) */
export function siwesTiles(d: MySiwes, step: SiwesStep): [string, string, string][] {
  const s = d.session ?? "this session";
  if (isCourseMode(d)) return courseTiles(d);
  if (step === "ELSEWHERE") {
    return [
      ["Your SIWES", siwesElsewhere(d).map((h) => h.session).join(", ") || "—", "300 Level · Second Semester"],
      ["You", "Not this session", `SIWES is not part of your ${s} registration`],
      ["SIWES fee", "Nothing owed", `for ${s}`],
    ];
  }
  const owes = !!d.paid || !!d.registration || siwesApplies(d);
  const months = d.period?.durationMonths;
  return [
    ["SIWES session", d.session ?? "—", "300 Level · Second Semester"],
    ["You", d.registration ? "Registered" : step === "UNDONE" ? "SIWES undone" : d.eligible ? "Eligible" : d.paid ? "Paid" : "Not eligible",
      d.eligible || d.registration ? (d.programme?.name ?? "") : reasonWords(d.reasons)[0] ?? ""],
    ["SIWES fee", d.paid ? "Paid" : !owes ? "Nothing owed" : d.fee?.state === "PUBLISHED" ? naira(d.fee.amount) : "—",
      d.paid ? `${naira(d.paid.amount)} · ${dateWord(d.paid.at)}` : !owes ? ((d.reasons ?? []).includes("NO_PERIOD") ? `No SIWES registration is open for ${s}` : `SIWES is not yours in ${s}`)
        : d.fee?.state === "PUBLISHED" ? "Not paid" : "Not published yet"],
    ["Training", months ? `${months} month${months === 1 ? "" : "s"}` : "—", trainingWords(d.period)],
  ];
}

export interface SiwesNext {
  step: SiwesStep;
  title: string;
  words: string;
  tone: "info" | "ok" | "bad";
  /** the student may draw (or pay) the SIWES fee reference now */
  pay: boolean;
  /** the student may register the SIWES course now */
  register: boolean;
  /** a portal payment with a receipt on /student/receipt */
  receipt: boolean;
  /** the SIWES course registration form may be printed */
  print: boolean;
  /** the page the step is taken on, when it is not the SIWES page (the school fees: Fees & payments) */
  link: { href: string; label: string } | null;
}

/** the window's words when registration is not open now: before it opens, the day it opens; otherwise closed */
function windowWords(p: SiwesPeriod, today: string): { step: "NOT_OPEN" | "CLOSED"; title: string } {
  const opens = p.registrationOpens?.slice(0, 10);
  if (p.state !== "CLOSED" && opens && today < opens) return { step: "NOT_OPEN", title: `SIWES registration opens on ${dayWord(opens)}` };
  if (p.state === "DRAFT") return { step: "NOT_OPEN", title: "SIWES registration has not opened yet" };
  return { step: "CLOSED", title: "SIWES registration is closed" };
}

/** V777: a student SIWES binds (mode SEMESTER) whose First or Third Semester form holds a SIWES course while the SIWES window is not
 *  open: the server says the fee cannot be paid now (canPay false, the fee published and unpaid), though the form locks the course on
 *  the fee. The words say so — when SIWES registration opens, the fee is paid then; closed, the Academic Office — and null when the
 *  fee can be paid (or nothing says it cannot): the form then links to the SIWES page as ever */
export function siwesPayShutWords(d: Pick<MySiwes, "mode" | "canPay" | "fee" | "paid" | "registrationOpen" | "period"> | null | undefined, today: string = lagosToday()): string | null {
  if (!d || isCourseMode(d) || d.canPay !== false || d.registrationOpen !== false || d.paid || d.fee?.state !== "PUBLISHED") return null;
  const w = d.period ? windowWords(d.period, today) : { step: "CLOSED" as const, title: "SIWES registration is closed" };
  return w.step === "NOT_OPEN"
    ? `${w.title}: the SIWES registration fee cannot be paid before then. Pay it once SIWES registration opens, then register the course here.`
    : `${w.title}, so the SIWES registration fee cannot be paid now: ask the Academic Office.`;
}

/** V777: the next step of a student whose SIWES course is among their ordinary courses (mode COURSE): pay the fee — a student who holds
 *  an unpaid SIWES course from before the rule is told so, and that they pay it now — then register the course on Course Registration
 *  (never here: the SIWES page registers only the SIWES semester's course). No other course is "in the way" of it, and no school fees
 *  hold it here: Course Registration judges its own. The server's `registrationOpen` is the fee's being published; nothing is taken
 *  before it is */
function courseNext(d: MySiwes): SiwesNext {
  const base = { pay: false, register: false, receipt: false, print: false, link: null };
  const session = d.session ?? "the session";
  const portalPaid = !!d.paid && d.paid.source !== "OLD_PORTAL" && !!d.paid.reference;
  const fee = d.fee && d.fee.state === "PUBLISHED" ? d.fee.amount : null;
  const held = heldCourses(d);
  const toRegister = coursesToRegister(d);
  const codes = (cs: SiwesOwnCourse[]) => listed(cs.map((c) => shownCode(c.code))) || "your SIWES course";
  const toRegisterWords = ownCourseList(toRegister) || "your SIWES course";
  const toRegisterIs = isAre(toRegister.length || 1);
  const unsent = held.filter((c) => heldStanding(c) === "UNSENT");
  const awaiting = held.filter((c) => heldStanding(c) === "AWAITING");
  if (d.paid) {
    if (!toRegister.length && held.length) {
      // a course on a registration that is only a draft (or was returned) is not registered: submit the registration; one on a submitted
      // registration waits for its approval; only one on an approved registration is registered
      if (unsent.length) {
        return { ...base, step: "SUBMIT_REGISTRATION", tone: "info", receipt: portalPaid, link: courseRegistrationPage(d.session, courseSemesters(unsent)[0] ?? 2),
          title: `Submit your registration to register ${codes(unsent)}`,
          words: `The SIWES registration fee for ${session} is paid. ${sentence(heldClause(held))}: a SIWES course is registered only once the registration that holds it is submitted and approved. `
            + "Submit your registration on Course Registration." };
      }
      if (awaiting.length) {
        return { ...base, step: "AWAITING_APPROVAL", tone: "info", receipt: portalPaid, title: `${codes(awaiting)} ${isAre(awaiting.length)} waiting for approval`,
          words: `The SIWES registration fee for ${session} is paid. ${sentence(heldClause(held))}: a SIWES course is registered once the registration that holds it is approved.` };
      }
      return { ...base, step: "REGISTERED", tone: "ok", receipt: portalPaid, title: "SIWES course registered",
        words: `${codes(held)} ${isAre(held.length)} on your registration for ${session}, and the SIWES registration fee is paid.` };
    }
    return { ...base, step: "REGISTER_COURSE", tone: "info", receipt: portalPaid, link: courseRegistrationPage(d.session, courseSemesters(toRegister)[0] ?? 2),
      title: `Fee paid: register ${codes(toRegister)} on Course Registration`,
      words: `Your SIWES registration fee for ${session} is paid: it covers every SIWES course you register in the session. Register ${toRegisterWords} on Course Registration`
        + `${held.length ? `; ${heldClause(held)}` : ""}. Paying does not register it.${unsent.length ? " A course is registered only once the registration that holds it is submitted." : ""}` };
  }
  if (fee == null) {
    return { ...base, step: "FEE_NOT_SET", tone: "info", title: "The SIWES registration fee is not published yet",
      words: held.length
        ? `${ownCourseList(held)} ${isAre(held.length)} on your registration. The Bursary publishes the SIWES registration fee; you pay it here once it does.`
        : `The Bursary publishes the SIWES registration fee; ${toRegisterWords} ${toRegisterIs} registered only once it is published and paid.` };
  }
  const pay = d.canPay !== false;
  if (d.openReference) {
    return { ...base, step: "PAY_REFERENCE", tone: "info", pay, title: `Pay ${naira(d.openReference.amount)} to register ${codes(toRegister.length ? toRegister : held)}`,
      words: `Pay the SIWES registration fee against reference ${d.openReference.reference}${held.length && !toRegister.length ? "." : `, then register ${toRegisterWords} on Course Registration.`}` };
  }
  if (held.length) {
    return { ...base, step: "PAY_HELD", tone: "bad", pay, title: `Pay the SIWES registration fee of ${naira(fee)}`,
      words: `You registered ${ownCourseList(held)} for ${session} before every SIWES course carried the SIWES registration fee. It is asked of every student who registers one, once a session, `
        + `so you have to pay it now${toRegister.length ? `; then register ${ownCourseList(toRegister)} on Course Registration` : ""}.` };
  }
  return { ...base, step: "PAY", tone: "info", pay, title: `Pay the SIWES registration fee of ${naira(fee)}`,
    words: `Every SIWES course carries the fee, paid once a session. Pay it, then register ${toRegisterWords} on Course Registration.` };
}

/** the student's next step on the SIWES page and card, from the server's answer: never more than the server allows */
export function siwesNext(d: MySiwes, today: string = lagosToday()): SiwesNext {
  if (isCourseMode(d)) return courseNext(d);
  const base = { pay: false, register: false, receipt: false, print: false, link: null };
  const portalPaid = !!d.paid && d.paid.source !== "OLD_PORTAL" && !!d.paid.reference;
  const fee = d.fee && d.fee.state === "PUBLISHED" ? d.fee.amount : null;
  // once registered, the course registered (K7), never a course the programme was mapped to since
  const course = siwesCourseOf(d)?.code ?? "your SIWES course";
  if (d.registration) {
    const approved = ["APPROVED", "LOCKED"].includes(d.registration.status);
    return {
      ...base, step: "REGISTERED", tone: "ok", receipt: portalPaid, print: approved,
      title: "SIWES course registered",
      words: `${course} is your Second Semester registration for ${d.session ?? "the session"}${approved ? "" : ` (${d.registration.status.toLowerCase()})`}. Training: ${trainingWords(d.period)}.`,
    };
  }
  // SIWES does not bind the session shown, and the student's SIWES is in another: that session's SIWES is theirs, never "not eligible"
  const elsewhere = siwesElsewhere(d);
  if (!d.paid && !siwesApplies(d) && elsewhere.length) {
    const sessions = elsewhere.map((h) => h.session).join(", ");
    return { ...base, step: "ELSEWHERE", tone: "info", title: `Your SIWES is in ${sessions}`,
      words: `SIWES is not part of your registration for ${d.session ?? "this session"}. Your SIWES of ${sessions} — its payment and its registration — is listed below.` };
  }
  // K30: the session's SIWES wholly undone (its course dropped by an office, no SIWES payment of the student's standing for it) and SIWES
  // binding the student no more: said plainly, never "not in SIWES registration" — the menu no longer carries the page; a payment's link
  // on Fees & payments still leads here
  const undone = siwesUndone(d);
  if (!d.paid && !siwesApplies(d) && undone) {
    return { ...base, step: "UNDONE", tone: "info", title: `Your SIWES of ${undone.session} was undone`,
      words: `Your SIWES course${undone.registration?.courseCode ? ` ${undone.registration.courseCode}` : ""} of ${undone.session} was dropped by the Academic Office or ICT Support, `
        + `and no SIWES payment of yours stands for the session. SIWES is not part of your registration for ${undone.session}. If you believe this is wrong, ask your department or the Academic Office.` };
  }
  // V777: a student whose programme carries no SIWES course at their level, and who holds or owes none, has nothing to pay for, whatever
  // the period says: told the one reason that stands, never "not set for this session"
  if (!d.paid && (d.reasons ?? []).includes("NO_SIWES_COURSE")) {
    return { ...base, step: "NOT_ELIGIBLE", tone: "info", title: "No SIWES fee is asked of you", words: reasonWords(d.reasons).join(" ") };
  }
  if (!d.period && !d.paid) {
    return { ...base, step: "NO_PERIOD", tone: "info", title: "SIWES registration is not set for this session", words: REASON_WORD.NO_PERIOD };
  }
  if (!d.paid && !d.eligible) {
    return { ...base, step: "NOT_ELIGIBLE", tone: "bad", title: "You are not in SIWES registration", words: reasonWords(d.reasons).join(" ") || "You are not eligible for SIWES registration this session." };
  }
  if (d.paid) {
    const receipt = portalPaid;
    if (!d.eligible) {
      return { ...base, step: "PAID_NOT_ELIGIBLE", tone: "bad", receipt, title: "Your SIWES fee is paid, but you cannot register now",
        words: `${reasonWords(d.reasons).join(" ")} The payment is kept; ask the Academic Office.`.trim() };
    }
    if (!d.registrationOpen) {
      const w = d.period ? windowWords(d.period, today) : { step: "CLOSED" as const, title: "SIWES registration is closed" };
      return { ...base, step: w.step === "NOT_OPEN" ? "NOT_OPEN" : "PAID_CLOSED", tone: w.step === "NOT_OPEN" ? "info" : "bad", receipt,
        title: w.title, words: w.step === "NOT_OPEN" ? "Your SIWES fee is paid. Register your SIWES course once registration opens." : "Your SIWES fee is paid, but registration is closed; ask the Academic Office." };
    }
    // siwes_register refuses the other courses first, then the school fees (REG_SEMESTER_FEES_DUE): the steps follow that order
    const owed = schoolFeesOwed(d);
    const others = otherCoursesOf(d);
    if (others.length) {
      const list = others.join(", ");
      // what Course Registration offers now (clearing): Remove while add and drop is open, the reset when allowed, else the offices
      const c = d.clearing ? siwesClearing({ addDropOpen: d.clearing.addDropOpen, resetAllowed: d.clearing.resetAllowed, count: others.length }) : null;
      const title = !c || c.remove ? `Remove ${list} first` : c.reset ? "Reset your Second Semester registration first" : `Ask the Academic Office or ICT Support to remove ${list}`;
      return { ...base, step: "DROP_OTHERS", tone: "bad", receipt, title, link: c && (c.remove || c.reset) ? courseRegistrationPage(d.session) : null,
        words: `In the SIWES semester you register ${course} alone. ${dropOthersWords(others, d.clearing)}.${owed ? ` ${sentence(schoolFeesWords(d, d.session))}; they are paid on ${FEES_PAGE.label}.` : ""} Then register ${course} here.` };
    }
    if (owed) {
      return { ...base, step: "PAY_SCHOOL_FEES", tone: "bad", receipt, link: { ...FEES_PAGE },
        title: "Pay the Second Semester school fees, then register your SIWES course",
        words: `Your SIWES registration fee is paid, but ${schoolFeesWords(d, d.session)}. They are paid as every semester, on ${FEES_PAGE.label}; then register ${course} here.` };
    }
    // the server's canRegister when it sends one: never a Register the database would refuse
    const can = d.canRegister !== false;
    return { ...base, step: "REGISTER", tone: "info", receipt, register: can, title: `Fee paid: register ${course}`,
      words: can ? `Your SIWES registration fee is paid. Register ${course} for the Second Semester; it is approved as it is registered.`
        : `Your SIWES registration fee is paid, but ${course} cannot be registered yet; ask the Academic Office.` };
  }
  if (fee == null) {
    return { ...base, step: "FEE_NOT_SET", tone: "info", title: "The SIWES registration fee is not published yet", words: "The Bursary publishes the SIWES registration fee; you can pay it once it does." };
  }
  if (!d.registrationOpen) {
    const w = windowWords(d.period!, today);
    return { ...base, step: w.step, tone: w.step === "NOT_OPEN" ? "info" : "bad", title: w.title,
      words: w.step === "NOT_OPEN" ? `You pay the SIWES registration fee of ${naira(fee)} and register ${course} while registration is open.` : "No payment is taken and no SIWES course is registered now; ask the Academic Office." };
  }
  if (d.openReference) {
    return { ...base, step: "PAY_REFERENCE", tone: "info", pay: true, title: `Pay ${naira(d.openReference.amount)} to register ${course}`,
      words: `Pay the SIWES registration fee against reference ${d.openReference.reference}, then register ${course} here.` };
  }
  return { ...base, step: "PAY", tone: "info", pay: true, title: `Pay the SIWES registration fee of ${naira(fee)}`,
    words: `Pay the fee, then register ${course}: the only course you register in the Second Semester.` };
}

/** the SIWES rows the printed course registration form carries beside the ordinary ones */
export function siwesFormRows(d: Pick<MySiwes, "period" | "paid"> | null | undefined): [string, string][] {
  if (!d) return [];
  const rows: [string, string][] = [["Training period", trainingWords(d.period)]];
  if (d.paid?.reference) rows.push(["SIWES fee reference", d.paid.reference]);
  if (d.paid?.receiptNo) rows.push(["Receipt number", d.paid.receiptNo]);
  if (d.paid && d.paid.source === "OLD_PORTAL") rows.push(["SIWES fee", "Paid on the old portal"]);
  return rows;
}

// ── the Academic Office's desk ──────────────────────────────────────────────────────────────────────────────────────────────

/** V776: how a programme (or one curriculum of it) came by its SIWES course, as registration.siwes_course_source names it: SET on the
 *  desk; else written down from the catalogue by one of the desk's own acts (a programme added, a course added to the SIWES courses),
 *  only where the programme's 300 Level Second Semester is the SIWES semester — a SIWES course the programme's own 300 Level
 *  STRUCTURE carries (DEPARTMENT: the one SIWES course of its department, of an older answer). A written-down course stands as a set
 *  one does. Absent where there is no course, and from an older answer */
export type SiwesCourseSource = "SET" | "STRUCTURE" | "DEPARTMENT";

/** V776: a SIWES course the programme's own structure carries outside the Second Semester of 300 Level — the semester the desk sets a
 *  course for and SIWES holds alone. V777: it carries the SIWES fee all the same; its students pay it when they register the course,
 *  on Course Registration. `semester`: FIRST, SECOND or BOTH, as registration.siwes_courses_elsewhere names it */
export interface SiwesElsewhere { code: string; title?: string | null; level?: number | null; semester?: "FIRST" | "SECOND" | "BOTH" | string | null }

/** V776: what a programme's 300 Level Second Semester is (registration.siwes_semester_load): `attachment`, the SIWES semester — the
 *  SIWES course alone, no other required course; otherwise `otherRequired`, the required courses (Core, GST) it carries besides SIWES,
 *  which students bound to SIWES could no longer register. Absent from an older answer (nothing is then said of the semester) */
export interface SiwesSemesterLoad { attachment?: boolean | null; otherRequired?: { courses?: number | null; units?: number | null } | null }

/** V776: what the catalogue offers where no SIWES course is set or written down yet (the API leaves a key with nothing in it out):
 *  `found`, the one course the catalogue now gives — setting it takes it — and `choices`, every candidate (several of equal standing
 *  and no `found`: the Academic Office says which); `elsewhere`, the SIWES courses the programme carries outside the Second Semester of
 *  300 Level (V777: charged all the same, its students pay when they register them on Course Registration). `found` also comes beside a course written down from the catalogue (source STRUCTURE) when the catalogue would now give
 *  another, or the course has ended; a course set on the desk never has one */
export interface SiwesCourseOffer { found?: SiwesCourse | null; choices?: SiwesCourse[] | null; elsewhere?: SiwesElsewhere[] | null }

/** a curriculum of a programme taking SIWES (one its 300 Level students hold, or one a course is written down for; none: the row
 *  written down for every curriculum, which the API sends without the key) */
export interface SiwesConfigCurriculum extends SiwesCourseOffer {
  curriculum?: string | null;
  /** a course is written down (set, or recognised) for this very curriculum: false where the course read is the one written down for
   *  another curriculum, or for every curriculum */
  mapped?: boolean | null;
  course?: SiwesCourse | null;
  source?: SiwesCourseSource | string | null;
}

export interface SiwesConfigProgramme extends SiwesCourseOffer, SiwesSemesterLoad {
  code: string; name: string; department?: UnitRef; faculty?: UnitRef;
  /** the students eligible in the programme for the session (a count), as the API reports it */
  eligible?: number | boolean | null;
  course?: SiwesCourse | null;
  /** V776: how the course is known (SiwesCourseSource) */
  source?: SiwesCourseSource | string | null;
  curricula?: SiwesConfigCurriculum[];
}

/** V776: a SIWES course of the catalogue as the desk lists it (registration.siwes_course_list) — each department carries SIWES under its
 *  own code and title */
export interface SiwesCatalogueCourse {
  id?: string | null; code: string; title?: string | null; units?: number | null; level?: number | null;
  /** FIRST, SECOND or BOTH; any other semester of the catalogue by its number */
  semester?: "FIRST" | "SECOND" | "BOTH" | string | null;
  state?: "LIVE" | "BOARD" | "SENATE" | "ENDED" | string | null;
  curriculum?: string | null; departmentCode?: string | null; department?: string | null;
  /** its title reads SIWES or Industrial Training (the catalogue listed it as it was added); otherwise the Academic Office added it */
  byTitle?: boolean | null;
  /** on the SIWES courses (the catalogue's marker). False: listed only because it is set as a programme's SIWES course on the desk —
   *  it is not on the SIWES courses, and is not taken off them. Absent from an older answer, which listed marked courses alone */
  marked?: boolean | null;
  /** 300 Level, Second Semester, not ended: a programme can come by it without it being set */
  recognised?: boolean | null;
  /** the programmes whose structure carries it, and the level each carries it at */
  programmes?: { code: string; name?: string | null; level?: number | null }[] | null;
  /** the programmes (and curricula; none: every curriculum) whose SIWES course it is, and how: SET on the desk, or recognised
   *  (STRUCTURE, DEPARTMENT). An older answer listed those set on the desk, with no source */
  setFor?: SiwesCourseSetFor[] | null;
  /** the programme semesters that are attachment semesters because of it (V503: the semester holds the SIWES course alone); taking
   *  the course off the SIWES courses ends them */
  attachmentFor?: SiwesAttachment[] | null;
}

export interface SiwesCourseSetFor { code: string; curriculum?: string | null; source?: SiwesCourseSource | string | null }

/** a programme's attachment semester: the level, and the semester by its number (1, 2) */
export interface SiwesAttachment { code: string; name?: string | null; level?: number | null; semester?: number | string | null }

/** V776: 300 Level students of a programme taking SIWES (of one curriculum) whom no live SIWES course reaches. `paid` of them have paid
 *  on the portal or registered: SIWES holds those still, and they cannot register until the course is set; the rest are not bound.
 *  `found` and `choices`: what the catalogue offers the cohort now (SiwesCourseOffer) */
export interface SiwesUnreached extends SiwesCourseOffer {
  programmeCode: string; programme?: string | null; curriculum?: string | null; students?: number | null; paid?: number | null;
}

export interface SiwesConfig {
  session: string;
  period: SiwesPeriod | null;
  programmes: SiwesConfigProgramme[];
  candidates: { code: string; name: string }[];
  fee: { amount: Money; state: string } | null;
  sessions: (string | { name: string })[];
  /** if the API reports the caller's access; otherwise the acting office decides what the screen offers */
  access?: { set?: boolean; read?: boolean } | null;
  /** V776: the SIWES courses of the catalogue, and the cohorts no SIWES course reaches yet (both absent from an older answer) */
  siwesCourses?: SiwesCatalogueCourse[] | null;
  unreached?: SiwesUnreached[] | null;
}

/** K25: a SIWES course's catalogue state in words, with its tone: live, or not yet live (at the Board or Senate), or ended */
export const COURSE_STATE_WORD: Record<string, [string, "ok" | "warn" | "bad"]> = {
  LIVE: ["Live", "ok"],
  BOARD: ["Not yet live (Board)", "warn"],
  SENATE: ["Not yet live (Senate)", "warn"],
  ENDED: ["Ended", "bad"],
};

/** the state of a mapped course as the desk shows it; null when the answer carries none */
export function courseStateWord(c: Pick<SiwesCourse, "state"> | null | undefined): [string, "ok" | "warn" | "bad"] | null {
  const st = c?.state;
  if (!st) return null;
  return COURSE_STATE_WORD[st] ?? [`${st.charAt(0)}${st.slice(1).toLowerCase()}`, "warn"];
}

/** K25: the desk's warning on a mapped course that is not LIVE in the catalogue: one still before the Board or Senate is registrable but
 *  not yet approved (the 300 Level students registered a live course under V503: check it is the course they take); an ended one is not
 *  registered at all (SIWES_COURSE_MISSING). Null for a live course, or an answer that carries no state */
export function courseStateWarning(c: Pick<SiwesCourse, "code" | "state"> | null | undefined): string | null {
  const st = c?.state;
  if (!c || !st || st === "LIVE") return null;
  if (st === "ENDED") return `${c.code} has ended in the catalogue: no student registers it (SIWES_COURSE_MISSING). Set another course.`;
  const where = st === "BOARD" ? "the Board" : st === "SENATE" ? "Senate" : null;
  return `${c.code} is not yet live in the catalogue${where ? ` (still before ${where})` : ` (${st.toLowerCase()})`}. Check that it is the course the programme's 300 Level students take for SIWES, or set a live course.`;
}

/** every mapped course of the session's programmes that is not LIVE, once each programme and curriculum: what the desk warns of */
export function configWarnings(config: Pick<SiwesConfig, "programmes"> | null | undefined): { programme: string; curriculum: string | null; course: string; ended: boolean; words: string }[] {
  const out: { programme: string; curriculum: string | null; course: string; ended: boolean; words: string }[] = [];
  for (const p of config?.programmes ?? []) {
    for (const { curriculum, course: c } of programmeCourseLines(p)) {
      const words = courseStateWarning(c);
      if (c && words) out.push({ programme: p.name || p.code, curriculum, course: c.code, ended: c.state === "ENDED", words });
    }
  }
  return out;
}

// ── V776: a programme is added before its SIWES course is known; the SIWES courses are recognised from the catalogue ─────────────

/** how a programme's SIWES course is known, in words: set on this desk, or written down from the catalogue (the programme's own
 *  structure; an older answer: its department's one SIWES course) */
export const COURSE_SOURCE_WORD: Record<string, string> = {
  SET: "Set here",
  STRUCTURE: "Written down from the programme's own structure",
  DEPARTMENT: "Written down: its department's one SIWES course",
};

/** a course written down from the catalogue is written by the desk's own acts, never read afresh: what that means for the officer */
export const RECOGNISED_STANDS = "A course written down stands until the Academic Office sets another; the catalogue changing later does not move it.";

/** the sentence under the programmes taking SIWES: that the fee is every SIWES course's whether or not its programme is listed here,
 *  what listing a programme does (its 300 Level Second Semester is the SIWES course alone, registered on the SIWES page), how a
 *  programme comes by its course, and that a course once written down stands. Saving the period and adding a programme do not take
 *  every course by themselves: the course is written down only where the programme's Second Semester is the SIWES semester, or when a
 *  course added to the SIWES courses gives a waiting programme its own structure's course; otherwise the row says what is found and
 *  the Academic Office takes it */
export const PROGRAMMES_HINT = "Every SIWES course carries the SIWES registration fee, whether or not its programme is listed here: a student who registers one pays it first, "
  + "once a session, and registers the course on Course Registration. A programme listed here is also held to SIWES alone in its 300 Level Second Semester, "
  + "registered on the SIWES page once the period is open; a programme not listed keeps its Second Semester as before. A programme's SIWES course is the one set here. "
  + "A course its own 300 Level structure carries is written down as its course when the programme is added — only where its Second Semester is the SIWES semester, "
  + "the SIWES course alone — or when a course is added to the SIWES courses that gives a waiting programme its own structure's course; "
  + "otherwise the row says what the catalogue offers and the Academic Office takes the course. "
  + `${RECOGNISED_STANDS} `
  + "The course stands for every session, and the students it binds are the programme's 300 Level students of the session, once a SIWES course reaches them.";

/** the words of a course's source; nothing for an answer that carries none, or one not known here (never the code itself) */
export function courseSourceWords(source: string | null | undefined): string {
  return source ? COURSE_SOURCE_WORD[source] ?? "" : "";
}

/** the same for one curriculum of a programme: a course set here for another curriculum, or for every curriculum, and read for this
 *  one says which (mapped false beside SET) */
export function curriculumSourceWords(p: Pick<SiwesConfigProgramme, "curricula">, c: SiwesConfigCurriculum): string {
  if (c.source !== "SET" || c.mapped !== false || !c.course) return courseSourceWords(c.source);
  const from = (p.curricula ?? []).find((x) => x.mapped === true && x.course?.code === c.course?.code);
  if (!from) return COURSE_SOURCE_WORD.SET;
  return from.curriculum ? `Set here for ${from.curriculum}, read for ${c.curriculum ?? "this curriculum"} too` : "Set here for every curriculum";
}

/** a line of a programme's row on the desk: a curriculum (null: the programme whole), its SIWES course and how the course is known;
 *  with no course, what the catalogue offers now (`found`, `choices`, `elsewhere`: each present only when the answer carries it); with
 *  a course written down from the catalogue, `found` when the catalogue would now give another or the course has ended */
export interface SiwesCourseLine {
  curriculum: string | null; course: SiwesCourse | null; known: string; found?: SiwesCourse; choices?: SiwesCourse[]; elsewhere?: SiwesElsewhere[];
}

const aCourse = (c: SiwesCourse | null | undefined): c is SiwesCourse => !!c && !!c.code;

/** what the catalogue offers, as the answer carries it. Beside no course: the course found, the choices, the SIWES courses carried
 *  outside the Second Semester of 300 Level. Beside a course written down from the catalogue (source other than SET): the course found
 *  when it is another's — a course set on the desk has no such offer, from an older answer too. Nothing from an older answer */
function offerOf(o: SiwesCourseOffer & { course?: SiwesCourse | null; source?: string | null }): Pick<SiwesCourseLine, "found" | "choices" | "elsewhere"> {
  const found = o.found;
  if (o.course) return o.source && o.source !== "SET" && aCourse(found) && found.code !== o.course.code ? { found } : {};
  const choices = (o.choices ?? []).filter(aCourse);
  const elsewhere = (o.elsewhere ?? []).filter((e) => !!e && !!e.code);
  return { ...(aCourse(found) ? { found } : {}), ...(choices.length ? { choices } : {}), ...(elsewhere.length ? { elsewhere } : {}) };
}

/** a programme's SIWES course as its row lists it: one line for each curriculum its students hold (or one is written down for) where
 *  it has any, else the programme's own — the one rule the row, the warnings and the notice of a programme just added read */
export function programmeCourseLines(p: Pick<SiwesConfigProgramme, "course" | "source" | "curricula" | "found" | "choices" | "elsewhere">): SiwesCourseLine[] {
  const curricula = (p.curricula ?? []).filter((c) => c.curriculum);
  return curricula.length
    ? curricula.map((c) => ({ curriculum: c.curriculum ?? null, course: c.course ?? null, known: c.course ? curriculumSourceWords(p, c) : "", ...offerOf(c) }))
    : [{ curriculum: null, course: p.course ?? null, known: p.course ? courseSourceWords(p.source) : "", ...offerOf(p) }];
}

/** what a row says where no SIWES course is found for the programme (or one of its curricula), and what is done about it: by the
 *  offices that set it, or by a reader who asks the Academic Office */
export const NO_COURSE_FOUND = "No SIWES course found";

/** the pill of a row with no SIWES course written down though the catalogue offers one or several */
export const NO_COURSE_YET = "No SIWES course yet";

export function noCourseAction(maySet: boolean): string {
  return maySet ? "set it, or add the course to the SIWES courses below" : "the Academic Office sets it, or adds the course to the SIWES courses";
}

export function noCourseWords(maySet: boolean): string {
  return `${NO_COURSE_FOUND} — ${noCourseAction(maySet)}`;
}

/** "ZZK 397 SIWES II (6 units)": a course the catalogue offers, by its code, title and units */
export function offeredCourseWords(c: Pick<SiwesCourse, "code" | "title" | "units">): string {
  return `${c.code}${c.title ? ` ${c.title}` : ""}${c.units != null ? ` (${c.units} unit${c.units === 1 ? "" : "s"})` : ""}`;
}

/** the pill of a row whose SIWES course the programme carries outside the Second Semester of 300 Level (V777: not a dead end — its
 *  students pay the fee when they register the course, on Course Registration; nothing is set for it here) */
export const ON_COURSE_REGISTRATION = "Registered on Course Registration";

/** the First Semester (or another) in words where a course is not taught in the Second Semester; nothing for one that is (SECOND, BOTH) */
const outsideSecond = (semester: string | null | undefined): string => (semester && semester !== "SECOND" && semester !== "BOTH" ? semesterWords(semester) : "");

/** a SIWES course the programme carries outside the Second Semester of 300 Level, by where it stands: "a First Semester course (300
 *  Level)", "a 400 Level course" — a course of another level is that level's, whatever its semester */
export function elsewhereWhere(e: Pick<SiwesElsewhere, "level" | "semester">): string {
  const semester = outsideSecond(e.semester);
  if (e.level != null && e.level !== 300) return `a ${e.level} Level course`;
  if (semester) return `a ${semester} course${e.level != null ? ` (${e.level} Level)` : ""}`;
  return "a course outside the Second Semester of 300 Level";
}

/** the same inside brackets, for a list of several: "300 Level, First Semester", "400 Level" */
function elsewhereShort(e: Pick<SiwesElsewhere, "level" | "semester">): string {
  const semester = outsideSecond(e.semester);
  return [e.level != null ? `${e.level} Level` : null, semester || null].filter(Boolean).join(", ") || "outside the Second Semester of 300 Level";
}

/** what a programme or cohort with no SIWES course in the Second Semester of 300 Level but one carried elsewhere is told: where that
 *  course stands, and (V777: the University has decided every SIWES course is charged) what happens to its students — they pay the
 *  SIWES fee when they register it, on Course Registration. Plain: no "set it" invitation the database would refuse — Set course is
 *  for the semester SIWES holds alone. `words` and `action` are two sentences, each without its full stop; null with nothing carried
 *  elsewhere */
export function elsewhereWords(list: SiwesElsewhere[] | null | undefined, most = 3): { words: string; action: string } | null {
  const all = (list ?? []).filter((e) => !!e && !!e.code);
  if (!all.length) return null;
  const name = (e: SiwesElsewhere) => `${e.code}${e.title ? ` ${e.title}` : ""}`;
  const one = all.length === 1;
  const named = all.slice(0, most);
  const rest = all.length - named.length;
  const words = one ? `Its SIWES course ${name(all[0])} is ${elsewhereWhere(all[0])}`
    : `Its SIWES courses are ${named.map((e) => `${name(e)} (${elsewhereShort(e)})`).join("; ")}${rest > 0 ? `; and ${rest} more` : ""}`;
  return { words, action: `Its students pay the SIWES fee when they register ${one ? "it" : "one of them"}, on Course Registration` };
}

/** where no SIWES course is written down for a programme, a curriculum or a cohort: what the catalogue offers and what is done.
 *  FOUND, the one course the catalogue now gives (the row offers "Use it" to the offices that set; `action` is what the note under
 *  the table and a reader are told); CHOICES, several and no one of them at the head — never a guess, the Academic Office says
 *  which; ELSEWHERE, nothing at 300 Level in the Second Semester but a SIWES course the programme carries outside it (a First Semester
 *  or 400 Level course: where it stands, and that its students pay the SIWES fee when they register it, on Course Registration —
 *  nothing is invited that the database would refuse: Set course is for the semester SIWES holds alone); NONE, nothing: as before.
 *  An older answer, with none of the keys, is NONE */
export interface SiwesCourseHint { kind: "FOUND" | "CHOICES" | "ELSEWHERE" | "NONE"; found: SiwesCourse | null; words: string; action: string }

export function courseHint(o: SiwesCourseOffer | null | undefined, maySet: boolean): SiwesCourseHint {
  const found = o?.found;
  if (aCourse(found)) {
    return { kind: "FOUND", found, words: `Found in the catalogue: ${offeredCourseWords(found)}`,
      action: maySet ? "set it as the programme's course above" : "the Academic Office sets it" };
  }
  const choices = (o?.choices ?? []).filter(aCourse);
  if (choices.length) {
    const one = choices.length === 1;
    return { kind: "CHOICES", found: null, words: `${one ? "A SIWES course found" : "Several SIWES courses found"}: ${choices.map(offeredCourseWords).join("; ")}`,
      action: `${maySet ? "set" : "the Academic Office sets"} ${one ? "it, if it is the one" : "the one"} the programme's students register` };
  }
  const away = elsewhereWords(o?.elsewhere);
  if (away) return { kind: "ELSEWHERE", found: null, ...away };
  return { kind: "NONE", found: null, words: NO_COURSE_FOUND, action: noCourseAction(maySet) };
}

/** a hint as one sentence without its full stop: "Found in the catalogue: … — set it as the programme's course above"; an ELSEWHERE
 *  hint is two sentences, "Its SIWES course … is a 400 Level course. Its students pay the SIWES fee when they register it, on Course Registration" */
export function courseHintWords(h: Pick<SiwesCourseHint, "words" | "action"> & { kind?: SiwesCourseHint["kind"] }): string {
  return h.kind === "ELSEWHERE" ? `${h.words}. ${h.action}` : `${h.words} — ${h.action}`;
}

/** what a programme's 300 Level Second Semester is, said where a SIWES course is found and not yet taken: the SIWES semester — its
 *  students register the SIWES course alone — or a semester that also carries required courses, which students bound to SIWES could
 *  no longer register. A sentence without its full stop; empty from an older answer, and where the semester carries no other required
 *  course though it is not the SIWES semester */
export function secondSemesterWords(p: SiwesSemesterLoad | null | undefined): string {
  if (!p) return "";
  if (p.attachment === true) return "Its Second Semester is the SIWES semester: students register the SIWES course alone";
  const n = num(p.otherRequired?.courses);
  if (p.attachment !== false || n <= 0) return "";
  const u = num(p.otherRequired?.units);
  return `Its Second Semester also carries ${n} required course${n === 1 ? "" : "s"} (${u} unit${u === 1 ? "" : "s"}), which students bound to SIWES could no longer register`;
}

/** the amount the SIWES registration fee is, until the Bursary publishes another (Fee Setup) */
export const SIWES_FEE_STANDARD = 4000;

/** what "Use it" asks before it sets a course on a programme whose 300 Level Second Semester is not the SIWES semester, in the
 *  officer's words: what the Second Semester also carries, and that SIWES registration holds the 300 Level students to the SIWES
 *  course alone and asks them the fee (the published one when there is one) first. Null where the semester is the SIWES semester, and
 *  from an older answer that does not say (nothing is asked, as before) */
export function confirmUseItWords(p: SiwesSemesterLoad | null | undefined, course: Pick<SiwesCourse, "code" | "title">, fee?: SiwesConfig["fee"]): string | null {
  if (!p || p.attachment !== false) return null;
  const n = num(p.otherRequired?.courses);
  const u = num(p.otherRequired?.units);
  const amount = fee && fee.state === "PUBLISHED" && num(fee.amount) > 0 ? naira(fee.amount) : naira(SIWES_FEE_STANDARD);
  const carries = n > 0 ? `Its 300 Level Second Semester also carries ${n} required course${n === 1 ? "" : "s"} (${u} unit${u === 1 ? "" : "s"}). ` : "";
  return `${carries}SIWES registration holds its 300 Level students to the SIWES course alone in that semester and asks them ${amount} first. `
    + `Use ${course.code}${course.title ? ` ${course.title}` : ""} as the programme's SIWES course?`;
}

/** where a course written down from the catalogue stands beside what the catalogue now gives (the row's `found`): another course, or
 *  the course has ended — a sentence without its full stop, the row's "Use it" beside it */
export function foundInsteadWords(course: Pick<SiwesCourse, "code" | "state">, found: Pick<SiwesCourse, "code" | "title" | "units">): string {
  const instead = `catalogue now offers ${offeredCourseWords(found)} instead`;
  return course.state === "ENDED" ? `${course.code} has ended; the ${instead}` : `The ${instead}`;
}

/** the hint under the Set course form: the desk refuses a course the programme does not carry at 300 Level (SIWES_COURSE_LEVEL). V777:
 *  Set course names the course of the semester SIWES holds alone — a 300 Level, Second Semester course; a SIWES course at another
 *  level or in the First Semester is not set here, and carries the fee all the same: its students pay it when they register it */
export const SIWES_COURSE_LEVEL_HINT = "Set course names the programme's course for the semester SIWES holds alone: a 300 Level course, taught in the Second Semester. "
  + "A SIWES course at another level or in the First Semester is not set here; its students pay the SIWES fee when they register it, on Course Registration.";

const studentsWord = (n: number) => `${n.toLocaleString("en-NG")} student${n === 1 ? "" : "s"}`;

/** what SIWES does with a student no course reaches who has paid on the portal or registered */
const HELD = "held to SIWES, and cannot register until the course is set";

/** of a cohort no SIWES course reaches, those who have paid or registered — never said of them that they are not asked to pay.
 *  Never more than the cohort (the server counts the programme's and curriculum's payers; the cohort is its 300 Level students) */
export function paidHeldWords(paid: number | null | undefined, students: number | null | undefined): string {
  const all = num(students);
  const n = Math.min(num(paid), all);
  if (n <= 0) return "";
  if (n >= all) return `${all === 1 ? "the student has" : "all of them have"} paid or registered — ${HELD}`;
  return `${n.toLocaleString("en-NG")} of them ${n === 1 ? "has" : "have"} paid or registered — ${HELD}`;
}

export interface SiwesUnreachedLine {
  key: string; name: string;
  /** "2 students at 300 Level; 1 of them has paid or registered — held to SIWES, and cannot register until the course is set" */
  words: string;
  /** what the catalogue offers the cohort and what is done: a hint's sentence */
  course: string;
  /** what the programme's 300 Level Second Semester is (secondSemesterWords), said where a course is found or several are offered;
   *  absent where the answer does not say, and where nothing is offered */
  semester?: string;
}

/** the cohorts no SIWES course reaches yet, as the desk's note names them: each programme (and curriculum) with its number of 300
 *  Level students, how many of them have paid or registered, and what the catalogue offers it — and, where a course is offered, what
 *  the programme's Second Semester is (read from the programme's row, `programmes`); the numbers in all, the note's title and what
 *  holds them. Empty from an older answer; one without the newer keys says of every cohort that no course is found */
export function unreachedLines(config: Pick<SiwesConfig, "unreached"> & { programmes?: SiwesConfigProgramme[] | null } | null | undefined, maySet = false): {
  lines: SiwesUnreachedLine[]; students: number; paid: number; title: string; words: string;
} {
  const rows = (config?.unreached ?? []).filter((u) => !!u && num(u.students) > 0);
  const total = rows.reduce((n, u) => n + num(u.students), 0);
  const paid = rows.reduce((n, u) => n + Math.min(num(u.paid), num(u.students)), 0);
  return {
    lines: rows.map((u) => {
      const held = paidHeldWords(u.paid, u.students);
      const hint = courseHint(u, maySet);
      const programme = (config?.programmes ?? []).find((p) => p.code === u.programmeCode);
      const semester = hint.kind === "FOUND" || hint.kind === "CHOICES" ? secondSemesterWords(programme) : "";
      // the course written down for the programme has ended: said first, so "no course found" is not read beside a course the row lists
      const own = programmeCourseLines(programme ?? { code: u.programmeCode } as SiwesConfigProgramme).find((l) => (l.curriculum ?? "") === (u.curriculum ?? "") || !l.curriculum);
      const ended = own?.course && own.course.state === "ENDED" ? `${own.course.code} has ended. ` : "";
      return {
        key: `${u.programmeCode}|${u.curriculum ?? ""}`,
        name: `${u.programme || u.programmeCode}${u.curriculum ? ` (${u.curriculum})` : ""}`,
        words: `${studentsWord(num(u.students))} at 300 Level${held ? `; ${held}` : ""}`,
        course: `${ended}${courseHintWords(hint)}`,
        ...(semester ? { semester } : {}),
      };
    }),
    students: total,
    paid,
    title: total ? `No SIWES course reaches ${studentsWord(total)} at 300 Level yet` : "",
    words: total ? unreachedWords(paid, total) : "",
  };
}

/** V777: what the cohorts no SIWES course reaches wait for — to be held to the SIWES course alone, registered on the SIWES page: a
 *  SIWES course their programme carries is charged all the same, paid when they register it on Course Registration */
const UNREACHED_WAITS = "not held to the SIWES course alone until a SIWES course reaches them; a SIWES course their programme carries still asks them the SIWES fee when they register it, on Course Registration";

/** what holds the cohorts no SIWES course reaches: those who have not paid are not held to the SIWES course alone until a course
 *  reaches them (they pay the fee when they register a SIWES course on Course Registration); those who have paid on the portal or
 *  registered stay held to SIWES and wait for the course */
export function unreachedWords(paid = 0, students = 0): string {
  const waits = UNREACHED_WAITS;
  if (paid <= 0) return `They are ${waits}.`;
  if (paid >= students) return `They have paid or registered: they stay ${HELD}.`;
  return `Those who have paid or registered stay ${HELD}; the others are ${waits}.`;
}

/** what the desk says once a programme is added (POST /programmes answers the session's configuration): with no SIWES course written
 *  down for it, or for one of its curricula, so — a warning, never a bare success, saying what the catalogue offers (several: the one
 *  is set; one found: it is used on the row; nothing: as before); with one, the course. An answer that does not list the programme
 *  says only that it was added */
export function programmeAddedWords(config: { programmes?: SiwesConfigProgramme[] | null } | null | undefined, code: string, session: string): { words: string; tone: "ok" | "warn" } {
  const p = (config?.programmes ?? []).find((x) => x.code === code);
  const added = `${p?.name || code} takes SIWES in ${session}`;
  if (!p) return { words: added, tone: "ok" };
  const lines = programmeCourseLines(p);
  const none = lines.filter((l) => !l.course);
  if (none.length) {
    const which = none.filter((l) => l.curriculum).map((l) => l.curriculum).join(" and ");
    const waits = "Its 300 Level students are not held to the SIWES course alone until one is set; they pay the SIWES fee when they register a SIWES course, on Course Registration.";
    const hints = none.map((l) => courseHint(l, true));
    const offered = hints.find((h) => h.kind === "FOUND" || h.kind === "CHOICES");
    if (offered) {
      // what the programme's Second Semester is, said where a course is offered: the officer takes it knowing what that binds
      const semester = secondSemesterWords(p);
      return { tone: "warn", words: `${added}, but its SIWES course${which ? ` (${which})` : ""} is not set yet. ${offered.words} — `
        + `${offered.kind === "FOUND" ? "use it on the programme's row, or set another" : offered.action}. ${semester ? `${semester}. ` : ""}${waits}` };
    }
    // its SIWES course is carried outside the Second Semester of 300 Level: nothing to set that the database would not refuse (V777: its
    // students pay the fee when they register it, on Course Registration — said)
    const away = hints.find((h) => h.kind === "ELSEWHERE");
    if (away) return { tone: "warn", words: `${added}. ${courseHintWords(away)}.` };
    return { tone: "warn", words: `${added}, but no SIWES course is found for it${which ? ` (${which})` : ""} yet: set it, or add the course to the SIWES courses. ${waits}` };
  }
  const codes = [...new Set(lines.map((l) => l.course!.code))];
  return { tone: "ok", words: `${added}: ${codes.length === 1 ? `its SIWES course is ${codes[0]}`
    : `its SIWES courses are ${lines.map((l) => `${l.course!.code}${l.curriculum ? ` (${l.curriculum})` : ""}`).join(", ")}`}` };
}

/** a catalogue semester in words, as registration.siwes_course_list names it (a course's: FIRST, SECOND, BOTH; an attachment
 *  semester's: its number) */
export const SEMESTER_WORD: Record<string, string> = {
  FIRST: "First Semester", SECOND: "Second Semester", BOTH: "Both semesters", "1": "First Semester", "2": "Second Semester", "3": "Third Semester",
};

export function semesterWords(semester: string | null | undefined): string {
  return semester ? SEMESTER_WORD[semester] ?? `Semester ${semester}` : "";
}

/** "300 Level · Second Semester · CCMAS": where the catalogue holds a SIWES course */
export function levelSemesterWords(c: Pick<SiwesCatalogueCourse, "level" | "semester" | "curriculum">): string {
  return [c.level != null ? `${c.level} Level` : null, semesterWords(c.semester) || null, c.curriculum || null].filter(Boolean).join(" · ") || "—";
}

/** whether a listed course is on the SIWES courses: not only on the server's explicit word (marked false: it is listed because it is
 *  set as a programme's SIWES course on the desk). An older answer listed the courses on them alone */
export function onSiwesCourses(c: Pick<SiwesCatalogueCourse, "marked">): boolean {
  return c.marked !== false;
}

/** how the desk knows a course is a SIWES course: by its title (SIWES, Industrial Training — listed as it was added to the catalogue),
 *  or added here by the Academic Office; one not on the SIWES courses is listed because it is set as a programme's SIWES course */
export function siwesCourseKnownWords(c: Pick<SiwesCatalogueCourse, "byTitle" | "marked">): string {
  if (!onSiwesCourses(c)) return "Set as a programme's SIWES course";
  return c.byTitle ? "By its title" : "Added here";
}

/** why no programme comes by a SIWES course on its own, from the course's own fields (recognised false: not 300 Level, not taught in
 *  the Second Semester, or ended), and what it still counts for; null for a course a programme can come by, or an answer that does
 *  not say. V777: a course in force carries the SIWES fee whether or not a programme comes by it — said, so that "no programme comes
 *  by it" is never read as "not charged" */
export function notRecognisedWords(c: Pick<SiwesCatalogueCourse, "recognised" | "state" | "level" | "semester">): string | null {
  if (c.recognised !== false) return null;
  const ended = c.state === "ENDED";
  const level = c.level != null && c.level !== 300;
  const semester = !!c.semester && c.semester !== "SECOND" && c.semester !== "BOTH";
  const why = [
    ended ? "it has ended in the catalogue" : null,
    level ? `it is a ${c.level} Level course, not 300 Level` : null,
    semester ? `it is taught in the ${semesterWords(c.semester)}, not the Second` : null,
  ].filter(Boolean);
  const charged = ended ? "" : " Students who register it pay the SIWES fee all the same.";
  if (!why.length) return `No programme comes by it on its own: it is not a 300 Level, Second Semester course in force.${charged}`;
  // a Second Semester course in force at another level is still a programme's SIWES course where it is set for the programme
  return `No programme comes by it on its own: ${why.join("; ")}.${!ended && !semester ? " It is a programme's SIWES course only where it is set for the programme." : ""}${charged}`;
}

/** the names of the programmes the configuration knows (those taking SIWES, those that could, and those a SIWES course's structure
 *  or attachment semesters name), by code */
export function programmeNames(config: Pick<SiwesConfig, "programmes" | "candidates" | "siwesCourses"> | null | undefined): Record<string, string> {
  const out: Record<string, string> = {};
  for (const c of config?.siwesCourses ?? []) for (const p of [...(c.attachmentFor ?? []), ...(c.programmes ?? [])]) if (p.name) out[p.code] = p.name;
  for (const p of config?.candidates ?? []) if (p.name) out[p.code] = p.name;
  for (const p of config?.programmes ?? []) if (p.name) out[p.code] = p.name;
  return out;
}

/** the programmes whose structure carries a SIWES course, by name; one that carries it at another level than 300 says so (its
 *  students do not come by the course on their own); the first few named and the rest counted */
export function carriedByWords(c: Pick<SiwesCatalogueCourse, "programmes">, most = 6): string {
  const all = (c.programmes ?? []).map((p) => `${p.name || p.code}${p.level != null && p.level !== 300 ? ` (at ${p.level} Level)` : ""}`);
  if (!all.length) return "";
  return all.length > most ? `${all.slice(0, most).join("; ")}; and ${all.length - most} more` : all.join("; ");
}

/** a programme a course is written down for was recognised by it (STRUCTURE, DEPARTMENT), not set on the desk (SET; an older answer
 *  listed those set, with no source) */
const recognisedFor = (s: SiwesCourseSetFor) => !!s.source && s.source !== "SET";

const setForNames = (list: SiwesCourseSetFor[], names: Record<string, string>) =>
  list.map((s) => `${names[s.code] || s.code}${s.curriculum ? ` (${s.curriculum})` : ""}`).join("; ");

/** the programmes (and curricula) a SIWES course is set for on the desk, by name where the configuration knows it */
export function setForWords(c: Pick<SiwesCatalogueCourse, "setFor">, names: Record<string, string> = {}): string {
  return setForNames((c.setFor ?? []).filter((s) => !recognisedFor(s)), names);
}

/** the programmes (and curricula) a SIWES course was recognised for — written down as theirs without being set — by name */
export function recognisedForWords(c: Pick<SiwesCatalogueCourse, "setFor">, names: Record<string, string> = {}): string {
  return setForNames((c.setFor ?? []).filter(recognisedFor), names);
}

/** the attachment semesters that rest on a SIWES course — "B.Sc. Chemistry (300 Level, Second Semester)" — the first few named and
 *  the rest counted. None on a course that is not on the SIWES courses: no attachment semester rests on it */
export function attachmentForWords(c: Pick<SiwesCatalogueCourse, "attachmentFor" | "marked">, most = 6): string {
  if (!onSiwesCourses(c)) return "";
  const all = (c.attachmentFor ?? []).map((a) => {
    const where = [a.level != null ? `${a.level} Level` : null, a.semester != null ? semesterWords(String(a.semester)) || null : null].filter(Boolean).join(", ");
    return `${a.name || a.code}${where ? ` (${where})` : ""}`;
  });
  if (!all.length) return "";
  return all.length > most ? `${all.slice(0, most).join("; ")}; and ${all.length - most} more` : all.join("; ");
}

/** a course code as the catalogue holds it: capitals, single spaces */
export function courseCodeTyped(code: string | null | undefined): string {
  return (code ?? "").trim().toUpperCase().replace(/\s+/g, " ");
}

/** the programmes a course was recognised for by an act of the desk: those the list names after it (`after`: PUT /siwes-courses'
 *  answer) as recognised that the list before it did not — a course added to the SIWES courses has the programmes still waiting
 *  recognised again, by that course or by one the catalogue came to hold since they were added */
export function newlyRecognised(before: SiwesCatalogueCourse[] | null | undefined, after: SiwesCatalogueCourse[] | null | undefined): { code: string; curriculum: string | null; course: string }[] {
  const key = (course: string, s: SiwesCourseSetFor) => `${course}|${s.code}|${s.curriculum ?? ""}`;
  const had = new Set((before ?? []).flatMap((c) => (c.setFor ?? []).map((s) => key(c.code, s))));
  return (after ?? []).flatMap((c) => (c.setFor ?? []).filter((s) => recognisedFor(s) && !had.has(key(c.code, s)))
    .map((s) => ({ code: s.code, curriculum: s.curriculum ?? null, course: c.code })));
}

/** what the desk says once a course is added to the SIWES courses (PUT /siwes-courses answers the list): the course by the code the
 *  catalogue holds it under; where no programme comes by it on its own, why — a warning; and, given the list as it stood before
 *  (`before`: the configuration's — nothing is claimed without it), the waiting programmes that came by their course by the act */
export function siwesCourseAddedWords(list: SiwesCatalogueCourse[] | null | undefined, typed: string,
  before?: SiwesCatalogueCourse[] | null, names: Record<string, string> = {}): { words: string; tone: "ok" | "warn" } {
  const code = courseCodeTyped(typed);
  const c = (list ?? []).find((x) => x.code === code);
  const why = c ? notRecognisedWords(c) : null;
  const fresh = Array.isArray(before) ? newlyRecognised(before, list) : [];
  const told = fresh.slice(0, 4).map((f) => `${names[f.code] || f.code}${f.curriculum ? ` (${f.curriculum})` : ""} — ${f.course}`).join("; ");
  const recognised = fresh.length ? `Now written down as the course of: ${told}${fresh.length > 4 ? `; and ${fresh.length - 4} more` : ""}.` : "";
  // V777: marking a course starts charging it at once — said (where the reason no programme comes by it says so, it says it)
  const added = why ? `${code} is now a SIWES course` : `${code} is now a SIWES course, and carries the SIWES registration fee`;
  if (!why && !recognised) return { words: added, tone: "ok" };
  return { words: [`${added}.`, why, recognised].filter(Boolean).join(" "), tone: why ? "warn" : "ok" };
}

/** what the desk says instead of asking, when a course is set here as a programme's SIWES course: the database refuses taking it off while
 *  it is (SIWES_COURSE_IN_USE) — the officer is told which programme, and to set another course for it first. Empty when it is not set */
export function siwesCourseSetHereWords(c: Pick<SiwesCatalogueCourse, "code" | "setFor">, names: Record<string, string> = {}): string {
  const who = setForWords(c, names);
  return who ? `${c.code} is set here as the SIWES course of ${who}: set another course for ${(c.setFor ?? []).filter((s) => !recognisedFor(s)).length === 1 ? "it" : "them"} first, and then it can be taken off.` : "";
}

/** what "Not a SIWES course" does, asked before it is done (registration.siwes_mark_course's rules): the course stops charging the SIWES
 *  fee (V777: marking a course starts charging it, taking it off stops), the programmes it was only recognised for wait for a course
 *  again, and the attachment semesters that rest on it end — each named */
export function siwesCourseOffWords(c: Pick<SiwesCatalogueCourse, "code" | "title" | "setFor" | "attachmentFor" | "marked">, names: Record<string, string> = {}): string {
  const recognised = recognisedForWords(c, names);
  const one = (c.setFor ?? []).filter(recognisedFor).length === 1;
  const attachment = attachmentForWords(c, Infinity);
  return `Take ${c.code}${c.title ? ` — ${c.title}` : ""} off the SIWES courses?\n\n`
    + "The portal then reads it as an ordinary course: it stops charging the SIWES registration fee, and no programme comes by it as its SIWES course. "
    + (recognised ? `${one ? "The programme it was written down for" : "The programmes it was written down for"} (${recognised}) ${one ? "waits" : "wait"} for a SIWES course again: `
      + `${one ? "its" : "their"} 300 Level students are not held to the SIWES course alone until one is set or written down. ` : "")
    + "It stays off while its title stands, until it is added here again.\n\n"
    + (attachment ? `Taking it off also ends the attachment semester — the semester that holds the SIWES course alone — of ${attachment}.\n\n` : "")
    + "It is refused while the course is set here as a programme's SIWES course, while a student holds it, in a session still to come or running, on a registration that stands on the SIWES fee, "
    + "while students who have paid or registered for SIWES are reached by it, or while students are registered in an attachment semester it makes.";
}

/** the sentence under the SIWES courses: each department's own course, how one comes to be listed, and which of them carry the fee —
 *  every one that has not ended, paid once a session before any is registered (the amount named only once the Bursary has published
 *  it); a course listed only because a programme's SIWES course is set to it is charged to the students that programme holds to
 *  SIWES alone, and an ended course is not charged while it stays ended */
export function siwesCoursesHint(fee: SiwesConfig["fee"] | undefined): string {
  const amount = fee && fee.state === "PUBLISHED" && num(fee.amount) > 0 ? `${naira(fee.amount)} ` : "";
  return "Each department carries SIWES under its own course code and title; a course whose title reads SIWES or Industrial Training is listed "
    + `as it is added to the catalogue. Every course listed here that has not ended carries the ${amount}SIWES registration fee: a student pays it once a session, before registering any of them, `
    + "whatever the programme, level or semester. A course listed only because it is set as a programme's SIWES course is charged to the students that programme holds to SIWES alone, "
    + "and an ended course is not charged while it stays ended. Adding a course here starts charging it; taking one off stops.";
}

/** what adding a course here does for the programmes taking SIWES: a programme still waiting whose own 300 Level structure carries it
 *  and whose Second Semester is the SIWES semester is given it as its course; every other is left as it is, the row saying what is
 *  found; nothing written down moves */
export const SIWES_COURSE_ADD_HINT = "As a course is added here, a programme still waiting for a SIWES course whose own 300 Level structure carries it, and whose Second Semester is the SIWES semester, is given it as its course; "
  + "every other programme is left as it is, its row saying what is found. A course already set or written down for a programme is not moved.";

export function sessionNames(list: (string | { name: string })[] | null | undefined): string[] {
  return (list ?? []).map((s) => (typeof s === "string" ? s : s.name)).filter(Boolean);
}

/** the offices that set the SIWES period, programmes and courses (the API's and the database's setters) */
export const SIWES_SETTERS = ["academic", "registrar", "dregistrar", "super"];

export interface PeriodForm {
  state: string; registrationOpens: string; registrationCloses: string; trainingStarts: string; trainingEnds: string; durationMonths: string; note: string;
}

/** what the database will refuse in a period, said before it is sent (the database checks again) */
export function periodProblems(f: PeriodForm): string[] {
  const out: string[] = [];
  const months = Number(f.durationMonths);
  if (!f.durationMonths || !Number.isInteger(months) || months < 1 || months > 12) out.push("The duration is a whole number of months, 1 to 12.");
  if (f.state === "OPEN") {
    if (!f.registrationOpens || !f.registrationCloses) out.push("Opening registration needs the opening and closing dates.");
    if (!f.trainingStarts || !f.trainingEnds) out.push("Opening registration needs the training's start and expected completion dates.");
  }
  if (f.registrationOpens && f.registrationCloses && f.registrationOpens > f.registrationCloses) out.push("Registration closes on or after the day it opens.");
  if (f.trainingStarts && f.trainingEnds && f.trainingStarts >= f.trainingEnds) out.push("Training ends after it starts.");
  return out;
}

export function emptyPeriodForm(p: SiwesPeriod | null | undefined): PeriodForm {
  return {
    state: p?.state ?? "DRAFT",
    registrationOpens: p?.registrationOpens?.slice(0, 10) ?? "",
    registrationCloses: p?.registrationCloses?.slice(0, 10) ?? "",
    trainingStarts: p?.trainingStarts?.slice(0, 10) ?? "",
    trainingEnds: p?.trainingEnds?.slice(0, 10) ?? "",
    durationMonths: String(p?.durationMonths ?? 6),
    note: p?.note ?? "",
  };
}

/** the desk's lists: ELIGIBLE (the default, sent when the address names none) and ALL (every student of the programmes taking SIWES at
 *  300 Level, the ineligible with their reasons: the API is sent no status) beside the API's own */
export const STATUSES = ["ELIGIBLE", "PAID", "UNPAID", "REGISTERED", "NOT_REGISTERED", "ALL"] as const;
export type SiwesStatus = (typeof STATUSES)[number];

export const STATUS_WORD: Record<SiwesStatus, string> = {
  ELIGIBLE: "Eligible students",
  PAID: "Paid",
  UNPAID: "Yet to pay",
  REGISTERED: "Registered",
  NOT_REGISTERED: "Yet to register",
  ALL: "All students in SIWES programmes",
};

/** the list the address asks for: ELIGIBLE when it names none */
export function shownStatus(status: string | null | undefined): SiwesStatus {
  return (STATUSES as readonly string[]).includes(status ?? "") ? (status as SiwesStatus) : "ELIGIBLE";
}

/** the status the API is sent for the list the address asks for: ELIGIBLE by default, nothing for ALL */
export function apiStatus(status: string | null | undefined): string | undefined {
  const s = shownStatus(status);
  return s === "ALL" ? undefined : s;
}

export const SOURCES = ["PORTAL", "OLD_PORTAL"] as const;
export const SOURCE_WORD: Record<string, string> = { PORTAL: "Portal", OLD_PORTAL: "Old portal" };

export function sourceWord(s: string | null | undefined): string {
  return s ? SOURCE_WORD[s] ?? s : "";
}

export interface SiwesStudentRow {
  studentId: string; matricNo: string | null; name: string; programmeCode: string | null; programme: string | null;
  department: string | null; faculty: string | null; level: number | null;
  /** registration.siwes_reasons empty, and the reasons when not (absent from an older answer) */
  eligible?: boolean | null; reasons?: string[] | null;
  paid: boolean; paymentSource: string | null; paymentReference: string | null; paidAt: string | null; amount: Money;
  registered: boolean; registeredAt: string | null; courseCode: string | null;
}

export interface SiwesStudentPage { total: number; page: number; size: number; rows: SiwesStudentRow[] }

/** "Not eligible: Not 300 Level, No SIWES course set" — the short word of each reason */
export function notEligibleWords(reasons: string[] | null | undefined): string {
  const w = reasonsToSay(reasons).map((r) => REASON_SHORT[r] ?? r.replaceAll("_", " ").toLowerCase());
  return w.length ? `Not eligible: ${w.join(", ")}` : "Not eligible";
}

/** where a student on the desk stands: registered, paid and not registered, not paid — or, for a student of a programme taking SIWES
 *  who is not eligible and has paid nothing, why not (never "Yet to pay": they owe nothing) */
export function rowState(r: Pick<SiwesStudentRow, "paid" | "registered" | "eligible" | "reasons">): [string, "ok" | "warn" | "bad" | "grey"] {
  if (r.registered) return ["Registered", "ok"];
  if (r.paid) return ["Paid, not registered", "warn"];
  if (r.eligible === false) return [notEligibleWords(r.reasons), "grey"];
  return ["Yet to pay", "bad"];
}

/** a faculty, department or programme of the figures: unpaid and notRegistered are the API's own counts (eligible students yet to pay
 *  or register), which a paid or registered student no longer eligible does not enter */
export interface SiwesGroup {
  code: string | null; name: string | null; eligible: number; paid: number; registered: number;
  unpaid?: number | null; notRegistered?: number | null;
}

export interface SiwesStats {
  eligible: number; paid: number; registered: number; unpaid: number; notRegistered: number;
  amountPaid: Money; amountOutstanding: Money;
  byFaculty: SiwesGroup[]; byDepartment: SiwesGroup[]; byProgramme: SiwesGroup[];
}

/** the desk's filters as the address carries them */
export interface SiwesFilters {
  session?: string; faculty?: string; department?: string; programme?: string; status?: string; q?: string; source?: string;
}

const CODE = /^[A-Za-z0-9 _./-]{1,40}$/;

export function readSiwesFilters(p: Record<string, string | string[] | undefined>): SiwesFilters {
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string).trim() : "");
  const out: SiwesFilters = {};
  if (/^\d{4}\/\d{4}$/.test(s("session"))) out.session = s("session");
  for (const k of ["faculty", "department", "programme"] as const) if (CODE.test(s(k))) out[k] = s(k);
  // ELIGIBLE is the default and stays out of the address
  if ((STATUSES as readonly string[]).includes(s("status")) && s("status") !== "ELIGIBLE") out.status = s("status");
  if ((SOURCES as readonly string[]).includes(s("source"))) out.source = s("source");
  if (s("q")) out.q = s("q").slice(0, 80);
  return out;
}

/** the filters (and a page) as a query string for the API or a link: empty ones left out */
export function siwesQuery(f: SiwesFilters, extra: Record<string, string | number | undefined | null> = {}): string {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries({ ...f, ...extra })) if (v !== undefined && v !== null && v !== "") q.set(k, String(v));
  return q.toString();
}

/** the University's structure as /ref/structure answers it (bounded by the API to the office: a Head of Department's own faculty and
 *  department alone) */
export interface UnitTree {
  faculties: { code: string; name: string; departments: { code: string; name: string; programmes: { code: string; name: string; archived?: boolean }[] }[] }[];
}

export type Opt = [string, string];

/** the faculties, departments and programmes a SIWES list may be filtered by: the structure the office reads, narrowed by the faculty and
 *  department chosen; the programmes are those taking SIWES when the configuration names any */
export function unitOptions(tree: UnitTree, f: Pick<SiwesFilters, "faculty" | "department">, configured: string[] = []): { faculties: Opt[]; departments: Opt[]; programmes: Opt[] } {
  const only = new Set(configured);
  const facs = tree.faculties;
  const depts = facs.filter((x) => !f.faculty || x.code === f.faculty).flatMap((x) => x.departments);
  const progs = depts.filter((d) => !f.department || d.code === f.department).flatMap((d) => d.programmes)
    .filter((p) => !p.archived && (!only.size || only.has(p.code)));
  return {
    faculties: facs.map((x) => [x.code, x.name]),
    departments: depts.map((d) => [d.code, d.name]),
    programmes: progs.map((p) => [p.code, p.name]),
  };
}

/** the words of the filters, for a list's subtitle and an export's: "2025/2026 · Faculty of Science · Paid" */
export function scopeWords(f: SiwesFilters, o: { faculties: Opt[]; departments: Opt[]; programmes: Opt[] }, more: (string | null | undefined)[] = []): string {
  const nameOf = (list: Opt[], code: string | undefined) => (code ? list.find(([c]) => c === code)?.[1] ?? code : null);
  return [f.session, nameOf(o.faculties, f.faculty), nameOf(o.departments, f.department), nameOf(o.programmes, f.programme), ...more].filter(Boolean).join(" · ");
}

export const STUDENT_HEAD = ["Matric Number", "Name", "Faculty", "Department", "Programme", "Level", "Session", "Semester", "SIWES Course",
  "Status", "Fee Paid", "Amount (₦)", "Payment Date", "Payment Reference", "Payment Source", "Registered", "Registration Date"];

const dayOnly = (iso: string | null | undefined) => (iso ? iso.slice(0, 10) : "");

/** a desk row as the Excel workbook and the printed list carry it: its status as the screen words it (an ineligible student's reasons) */
export function studentLine(r: SiwesStudentRow, session: string): (string | number | null)[] {
  return [r.matricNo ?? "", r.name, r.faculty ?? "", r.department ?? "", r.programme ?? r.programmeCode ?? "", r.level ?? "", session, "Second",
    r.courseCode ?? "", rowState(r)[0], r.paid ? "Yes" : "No", r.paid ? num(r.amount) : "", dayOnly(r.paidAt), r.paymentReference ?? "", sourceWord(r.paymentSource),
    r.registered ? "Yes" : "No", dayOnly(r.registeredAt)];
}

export const GROUP_HEAD = ["Name", "Code", "Eligible", "Paid", "Yet to Pay", "Registered", "Yet to Register"];

/** a group as the screen and its exports print it: yet to pay and yet to register as the API counts them, the same as the tiles; worked
 *  out from eligible only for an answer that does not carry them */
export function groupLine(g: SiwesGroup): (string | number)[] {
  const unpaid = g.unpaid != null ? num(g.unpaid) : Math.max(0, num(g.eligible) - num(g.paid));
  const notRegistered = g.notRegistered != null ? num(g.notRegistered) : Math.max(0, num(g.eligible) - num(g.registered));
  return [g.name ?? g.code ?? "", g.code ?? "", num(g.eligible), num(g.paid), unpaid, num(g.registered), notRegistered];
}

/** a session of a student's SIWES record, as registration.siwes_student_detail's history[] carries it: the payment that settled the
 *  session's fee and the SIWES registration, each or both */
export interface SiwesHistoryRow {
  session: string;
  paid: { reference: string | null; amount: Money; receiptNo?: string | null; paidAt?: string | null; at?: string | null; source?: string | null } | null;
  registration: { id?: string; at?: string | null; registeredAt?: string | null; status?: string | null; courseCode?: string | null } | null;
}

// ── V777: SIWES courses on a registration of the session with no SIWES fee paid — the Bursary's list ─────────────────────────────

/** a SIWES course standing on a registration of the session whose student has paid no SIWES fee (GET /api/v1/siwes/admin/unpaid-entries;
 *  registration.siwes_entries_unpaid): those who registered one before every SIWES course carried the fee are asked to pay it now.
 *  `payable`: the SIWES page asks them for the fee now (the session is their current one) */
export interface SiwesUnpaidEntry {
  studentId: string; matricNo: string | null; name: string; programme: string | null; currentLevel: number | null;
  courseCode: string; courseTitle: string | null; level: number | null; semester: number | null;
  registrationStatus: string | null; payable: boolean;
}

/** a row of the list read from the names the API gives it (camelCase, or the database's own) */
export function unpaidEntry(raw: Record<string, unknown>): SiwesUnpaidEntry {
  const pick = (...ks: string[]) => { for (const k of ks) if (raw[k] != null && raw[k] !== "") return raw[k]; return null; };
  const text = (...ks: string[]) => { const v = pick(...ks); return v == null ? null : String(v); };
  const int = (...ks: string[]) => { const v = pick(...ks); const n = v == null ? NaN : Number(v); return Number.isFinite(n) ? n : null; };
  return {
    studentId: text("studentId", "student_id") ?? "", matricNo: text("matricNo", "matric_no", "matric"), name: text("name") ?? "",
    programme: text("programme"), currentLevel: int("currentLevel", "current_level"),
    courseCode: text("courseCode", "course_code") ?? "", courseTitle: text("courseTitle", "course_title"),
    level: int("level"), semester: int("semester"), registrationStatus: text("registrationStatus", "registration_status"),
    payable: raw.payable === true,
  };
}

/** the answer's rows: the array the API sends (or the rows of a page), each read; nothing from an answer that is neither */
export function unpaidEntries(raw: unknown): SiwesUnpaidEntry[] {
  const list = Array.isArray(raw) ? raw : raw && typeof raw === "object" && Array.isArray((raw as { rows?: unknown }).rows) ? (raw as { rows: unknown[] }).rows : [];
  return list.filter((r): r is Record<string, unknown> => !!r && typeof r === "object").map(unpaidEntry);
}

/** the page the API answers ({ rows, total, students }: it pages the list as the desk's students are paged): how many rows there are in
 *  all (null from an answer that does not say, as a bare array does not) — so a screen fetches the pages that follow */
export function unpaidTotal(raw: unknown): number | null {
  const t = raw && typeof raw === "object" && !Array.isArray(raw) ? (raw as { total?: unknown }).total : null;
  return t == null || t === "" || !Number.isFinite(Number(t)) ? null : Number(t);
}

/** where the course is taught, "300 Level, First Semester": the registration's own level and semester */
export function unpaidWhere(r: Pick<SiwesUnpaidEntry, "level" | "semester">): string {
  return courseWhere({ level: r.level, semester: r.semester });
}

/** where a student on the list stands: asked to pay now, or not asked in this session (it is not their current one) */
export function unpaidStanding(r: Pick<SiwesUnpaidEntry, "payable">): [string, "bad" | "grey"] {
  return r.payable ? ["Asked to pay now", "bad"] : ["Not asked in this session", "grey"];
}

/** the figures over the list: the courses, the students holding them (each once), those asked to pay now, and what they owe at the
 *  fee in force (null while none is published) */
export function unpaidTotals(rows: Pick<SiwesUnpaidEntry, "studentId" | "payable">[], fee: Money | null | undefined): { entries: number; students: number; payable: number; owed: number | null } {
  const students = new Set(rows.map((r) => r.studentId));
  const payable = new Set(rows.filter((r) => r.payable).map((r) => r.studentId));
  const amount = fee == null || fee === "" ? null : num(fee);
  return { entries: rows.length, students: students.size, payable: payable.size, owed: amount != null && amount > 0 ? payable.size * amount : null };
}

export const UNPAID_WORDS = "Students who hold a SIWES course on a registration of the session and have paid no SIWES fee for it. Every SIWES course carries the fee, "
  + "paid once a session; a student who registered a course before the rule is asked to pay it now, on the SIWES page. Nothing here changes a registration.";

export const UNPAID_HEAD = ["Matric Number", "Name", "Programme", "Level", "SIWES Course", "Title", "Course Level", "Semester", "Registration", "Status"];

/** a row of the list as the Excel workbook and the printed list carry it */
export function unpaidLine(r: SiwesUnpaidEntry): (string | number | null)[] {
  return [r.matricNo ?? "", r.name, r.programme ?? "", r.currentLevel ?? "", r.courseCode, r.courseTitle ?? "", r.level ?? "",
    r.semester != null ? semesterWords(String(r.semester)) : "", r.registrationStatus ? capital(r.registrationStatus) : "", unpaidStanding(r)[0]];
}

export const HISTORY_HEAD = ["Session", "Fee paid", "Registration"];

const capital = (s: string) => s.charAt(0).toUpperCase() + s.slice(1).toLowerCase();

/** a history row as its three columns: the session; the fee paid (reference, amount, date, the old portal named); the registration
 *  (course, status, date) */
export function historyLine(h: SiwesHistoryRow): [string, string, string] {
  const p = h.paid;
  const paidAt = p ? p.paidAt ?? p.at ?? null : null;
  const r = h.registration;
  return [
    h.session,
    p ? [p.reference ?? "No reference", naira(p.amount), paidAt ? dateWord(paidAt) : null, p.source === "OLD_PORTAL" ? "old portal" : null].filter(Boolean).join(" · ") : "Not paid",
    r ? [r.courseCode ?? "SIWES course", r.status ? capital(r.status) : null, (r.registeredAt ?? r.at) ? dateWord(r.registeredAt ?? r.at) : null].filter(Boolean).join(" · ") : "Not registered",
  ];
}

// ── the Bursary ──────────────────────────────────────────────────────────────────────────────────────────────────────────────

/** a restatement of the fee waiting for the Bursar: the published amount stays in force until it is published */
export interface SiwesFeeDraft { amount: Money; note?: string | null; by?: string | null; byName?: string | null; at?: string | null }

/** a change on the fee's history (finance.siwes_fee_view): `by` is the person's id, never shown; `byName` their name */
export interface SiwesFeeChange {
  action: string | null; amount: Money; wasAmount?: Money; wasState?: string | null; note?: string | null;
  by?: string | null; byName?: string | null; office?: string | null; at: string | null;
}

/** what GET /api/v1/finance/siwes/fee answers: the fee in force (amount and state), the draft waiting beside it, and every change */
export interface SiwesFeeView {
  session: string; amount: Money; state: "DRAFT" | "PUBLISHED" | string | null;
  publishedAt?: string | null; publishedBy?: string | null; publishedByName?: string | null;
  draft?: SiwesFeeDraft | null;
  note?: string | null;
  history: SiwesFeeChange[];
}

export const FEE_STATERS = ["bursar", "studentaccounts", "super"];
export const FEE_PUBLISHERS = ["bursar", "super"];

export const FEE_STATE_WORD: Record<string, [string, "grey" | "ok" | "warn"]> = {
  DRAFT: ["Draft", "warn"],
  PUBLISHED: ["Published", "ok"],
};

const given = (m: Money) => m != null && m !== "";

/** K13: the refund desk refunds a SIWES payment whole or not at all (a smaller proposal is refused REFUND_SIWES_PART, the fee being all
 *  or nothing), and once (V762, K36: more than is left on it is refused REFUND_SIWES_GIVEN_BACK): what the proposal form says beside the
 *  amount, for a payment whose purpose is SIWES; part (shown as a fault) when the amount typed differs, in the words of the refusal it meets */
export function siwesRefundHint(purpose: string | null | undefined, paid: Money, typed: Money): { words: string; part: boolean } | null {
  if (!isSiwesPurpose(purpose) || !given(paid)) return null;
  const part = given(typed) && num(typed) !== num(paid);
  const why = !part ? "" : num(typed) > num(paid) ? "; more than was paid is refused" : "; a part is refused";
  return { part, words: `A SIWES registration fee is refunded once, whole or not at all: the whole ${naira(paid)} of the payment${why}.` };
}

/** the fee in force (published: what students pay) and the restatement waiting for the Bursar, apart. A fee never published is its
 *  draft alone; a DRAFT answer carrying no draft is read as that draft. */
export function feeStanding(v: SiwesFeeView | null | undefined): {
  inForce: { amount: Money; at: string | null; byName: string | null } | null;
  draft: SiwesFeeDraft | null;
} {
  if (!v) return { inForce: null, draft: null };
  const inForce = v.state === "PUBLISHED" && given(v.amount) ? { amount: v.amount, at: v.publishedAt ?? null, byName: v.publishedByName ?? null } : null;
  const draft = v.draft && given(v.draft.amount) ? v.draft
    : v.state === "DRAFT" && given(v.amount) ? { amount: v.amount, note: v.note ?? null } : null;
  return { inForce, draft };
}

/** V777: what the SIWES fee is paid for, on the Bursary's fee panel: every SIWES course carries it, once a session, whoever registers
 *  one — the amount named only once the Bursary has published it (`inForce`: the fee in force) */
export function siwesFeeScopeWords(inForce: Money | null | undefined): string {
  const amount = num(inForce) > 0 ? ` of ${naira(inForce)}` : "";
  return `Every SIWES course carries the SIWES registration fee${amount}: it is paid once a session by every student who registers one, whatever the programme, level or semester, `
    + "before the course is registered. A student who registers several SIWES courses in a session pays it once.";
}

/** who made a change or a draft: the person's name (with the office), else the office alone — never the person's id */
export function byWords(byName: string | null | undefined, office: string | null | undefined): string {
  if (byName) return office ? `${byName} (${office})` : byName;
  return office ?? "";
}

/** a change on the fee's history, in words */
export function feeChange(h: SiwesFeeChange): { at: string | null; by: string; what: string; amount: Money; was: Money; note: string } {
  return {
    at: h.at ?? null,
    by: byWords(h.byName, h.office),
    what: (h.action ?? "").replaceAll("_", " ").toLowerCase(),
    amount: h.amount ?? null,
    was: h.wasAmount ?? null,
    note: h.note ?? "",
  };
}

export interface SiwesPaymentRow {
  reference: string; studentId: string; matricNo: string | null; name: string; programme: string | null; department: string | null; faculty: string | null;
  amount: Money; gateway: string | null; gatewayReference: string | null; receiptNo: string | null; confirmedAt: string | null; source: string | null;
  /** the payment settles the student's fee for the session (finance.siwes_paid); otherwise it settles nothing (a credit, an old-portal
   *  payment made twice, or money given back) */
  settles?: boolean | null;
  creditState?: "OPEN" | "APPLIED" | "REFUNDED" | string | null;
  /** the money given back on the payment: refunds approved or paid on the refund desk, or its credit recorded refunded */
  refunded?: Money;
  /** K31: the database's words when the payment waits on the Bursary's bank check (V561), and its code for that wait (BankCheckState);
   *  absent when it waits on nothing, and on a payment given back (K35) */
  bankCheck?: string | null;
  bankCheckState?: BankCheckState | string | null;
}

/** a page of payments with the totals of every payment the filters select (not only the page), as finance.siwes_payments sums them:
 *  amount is everything received; amountSettling what settles students' fees; amountRefunded what was given back; amountCredits the rest
 *  (amount − settling − refunded): money held that settles nothing — credits open or applied, and old-portal duplicates */
export interface SiwesPaymentPage {
  total: number; amount: Money; amountSettling?: Money; amountCredits?: Money; amountRefunded?: Money; page?: number; size?: number; rows: SiwesPaymentRow[];
}

export const CREDIT_STATE_WORD: Record<string, string> = { OPEN: "open", APPLIED: "applied", REFUNDED: "refunded" };

const creditWord = (s: string) => CREDIT_STATE_WORD[s] ?? s.toLowerCase();

/** whether a payment settles the student's fee, is held as a credit, or was given back, in words (null from an answer that does not say) */
export function paymentStanding(r: Pick<SiwesPaymentRow, "settles" | "creditState" | "refunded">): [string, "ok" | "warn" | "grey"] | null {
  if (r.settles === true) return [r.creditState ? `Settles the fee (its credit ${creditWord(r.creditState)})` : "Settles the fee", "ok"];
  if (r.creditState) return [`Held as a credit — ${creditWord(r.creditState)}`, r.creditState === "OPEN" ? "warn" : "grey"];
  if (num(r.refunded) > 0) return ["Refunded on the refund desk", "grey"];
  if (r.settles === false) return ["Does not settle the fee", "warn"];
  return null;
}

export interface PaymentTotals { amount: number; settling: number; credits: number; refunded: number }

/** the totals of a list of payments, summed as finance.siwes_payments sums them — the fallback for an answer that carries no totals: a
 *  payment that settles the fee is settling; of every other payment, what was given back is refunded and the rest is held (credits and
 *  duplicates alike), so settling + credits + refunded = amount */
export function paymentSums(rows: Pick<SiwesPaymentRow, "amount" | "settles" | "creditState" | "refunded">[]): PaymentTotals {
  let amount = 0, settling = 0, credits = 0, refunded = 0;
  for (const r of rows) {
    const a = num(r.amount);
    amount += a;
    if (r.settles === true) { settling += a; continue; }
    const back = Math.min(a, num(r.refunded) > 0 ? num(r.refunded) : r.creditState === "REFUNDED" ? a : 0);
    refunded += back;
    credits += a - back;
  }
  return { amount, settling, credits, refunded };
}

/** the totals the tiles and the exports show: the API's, over every payment the filters select; summed from the rows only when the
 *  answer carries none (fromRows says so) */
export function paymentTotals(page: Pick<SiwesPaymentPage, "amount" | "amountSettling" | "amountCredits" | "amountRefunded" | "rows">,
  rows: Pick<SiwesPaymentRow, "amount" | "settles" | "creditState" | "refunded">[] = page.rows): PaymentTotals & { fromRows: boolean } {
  if (given(page.amount) && given(page.amountSettling) && given(page.amountCredits) && given(page.amountRefunded)) {
    return { amount: num(page.amount), settling: num(page.amountSettling), credits: num(page.amountCredits), refunded: num(page.amountRefunded), fromRows: false };
  }
  return { ...paymentSums(rows), fromRows: true };
}

export const PAYMENT_HEAD = ["Reference", "Matric Number", "Name", "Faculty", "Department", "Programme", "Amount (₦)", "Gateway", "Gateway Reference",
  "Receipt Number", "Confirmed", "Source", "Settles the Fee", "Refunded (₦)", "Bank Check"];

export function paymentLine(r: SiwesPaymentRow): (string | number | null)[] {
  return [r.reference, r.matricNo ?? "", r.name, r.faculty ?? "", r.department ?? "", r.programme ?? "", num(r.amount), r.gateway ?? "",
    r.gatewayReference ?? "", r.receiptNo ?? "", dayOnly(r.confirmedAt), sourceWord(r.source), paymentStanding(r)?.[0] ?? "",
    num(r.refunded) > 0 ? num(r.refunded) : "", paymentGivenBack(r) ? "" : bankHoldPill(r)?.[0] ?? ""];
}

/** K19: how a SIWES credit was settled, as the database records it (finance.siwes_credit.settled_kind, written by what settled it) */
export type SettledKind = "SETTLES" | "MOVED" | "DESK_REFUND" | "HAND_REFUND";

/** K31: which of V561's waits holds an old-portal SIWES payment, as the database names it (finance.siwes_bank_hold; the API's
 *  bankCheckState, passed through): UNCHECKED, a possible bank double charge not yet checked with the bank; PROPOSED, a withdrawal as
 *  never received of a record of its day waiting for the second Bursary officer; NOT_RECEIVED, the bank check found this very record
 *  never received (it waits to be withdrawn); NOT_RECEIVED_WAITING, the check found another record of its day never received — this one,
 *  received, waits until that one is withdrawn (K20, s5-1) */
export type BankCheckState = "UNCHECKED" | "PROPOSED" | "NOT_RECEIVED" | "NOT_RECEIVED_WAITING";

const BANK_CHECK_STATES: readonly string[] = ["UNCHECKED", "PROPOSED", "NOT_RECEIVED", "NOT_RECEIVED_WAITING"];

/** a SIWES credit as GET /api/v1/finance/siwes/credits lists it: a payment for a session already paid, held for the Bursar. reason is
 *  why it arose; settledNote the note it was settled with (free text). The database decides what may be done with it: canRefund and
 *  canReopen are the tests finance.siwes_credit_settle and siwes_credit_reopen apply; settles, that its payment is now the one that
 *  settles the fee; settledKind, how it was settled; automatic, that the database settled it itself (SETTLES, MOVED, DESK_REFUND) */
export interface SiwesCredit {
  id: string; studentId: string | null; name: string; matricNo: string | null; session: string | null; reference: string; amount: Money;
  state: string; reason: string | null; settledNote: string | null; paidAt: string | null; settledAt: string | null; settledByName: string | null;
  automatic: boolean; settles: boolean; canRefund: boolean; canReopen: boolean;
  /** K15: the database's words when the credit's payment waits on the Bursary's bank check (V561: an old-portal payment that may be a
   *  bank double charge — another of the same student, session, item, day and amount under another payment number — is refunded only
   *  once the bank check on Old Fees History finds it received) — an open credit, or one that settles the fee meanwhile; null otherwise */
  bankCheck: string | null;
  /** K31: the database's code for that wait, as the API passes it (never read from the words); null when none, or one not known here */
  bankCheckState: BankCheckState | null;
  /** K19: how it was settled; null while open */
  settledKind: SettledKind | string | null;
}

/** Old Fees History, where the Bursary records the bank's answer on a possible bank double charge (V561) */
export const OLD_FEES_PAGE = { href: "/finance/legacy-fees", label: "Old Fees History" } as const;
/** the offices whose menu carries Old Fees History (the Super Administrator reaches every page) */
export const OLD_FEES_OFFICES = ["bursar", "studentaccounts", "super"];
/** the offices that read the SIWES registration desk (the API's READER_OFFICES): the desk's figures are linked for them alone */
export const SIWES_DESK_READERS = ["academic", "registrar", "dregistrar", "super", "hod", "siwes", "dean", "facultyofficer", "bursar", "studentaccounts", "ict", "vc", "dvc"];

/** K19: how a credit was settled, in words — never read from its note, which is free text */
export const SETTLED_KIND_WORD: Record<string, string> = {
  SETTLES: "settles the fee in its place (the portal)",
  MOVED: "moved by a payment correction",
  DESK_REFUND: "refunded on the refund desk",
  HAND_REFUND: "refunded by the Bursar",
};

/** the kinds the database settles itself: never reopened or refunded by hand */
const AUTOMATIC_KINDS = new Set(["SETTLES", "MOVED", "DESK_REFUND"]);

/** when and how a settled credit was settled, and by whom when the Bursar did it by hand: "13 November 2026 · refunded by the Bursar ·
 *  OKAFOR, Chidi"; empty for an open credit */
export function settledWords(c: Pick<SiwesCredit, "state" | "settledKind" | "settledAt" | "settledByName" | "automatic">): string {
  if (c.state === "OPEN") return "";
  const how = c.settledKind ? SETTLED_KIND_WORD[c.settledKind] ?? c.settledKind.replaceAll("_", " ").toLowerCase() : c.automatic ? "by the portal" : null;
  const who = c.settledKind === "HAND_REFUND" || (!c.settledKind && !c.automatic) ? c.settledByName : null;
  return [c.settledAt ? dateWord(c.settledAt) : null, how, who].filter(Boolean).join(" · ");
}

/** K31: the wait's code as the database sent it (the API's bankCheckState, or the database's own bank_check_state) — never read from the
 *  words; null when none is sent or the code is not one known here */
export function bankCheckStateOf(c: { bankCheckState?: string | null }): BankCheckState | null {
  return c.bankCheckState && BANK_CHECK_STATES.includes(c.bankCheckState) ? (c.bankCheckState as BankCheckState) : null;
}

/** v4-3, K31: the pill over a held payment's words, by the database's code — never "check with the bank" once the check is recorded,
 *  and "never received" on the record the bank never received alone, never on the one it did receive (s5-1) */
export const BANK_CHECK_PILL: Record<BankCheckState, [string, "warn" | "bad"]> = {
  UNCHECKED: ["Check with the bank first", "warn"],
  PROPOSED: ["Withdrawal waiting", "warn"],
  NOT_RECEIVED: ["Found never received", "bad"],
  NOT_RECEIVED_WAITING: ["Waits on another record's withdrawal", "warn"],
};

/** the pill of words that come with no code known here (an answer older or newer than this screen): held, without naming which wait */
export const BANK_HOLD_PILL: [string, "warn"] = ["Held for the bank check", "warn"];

/** the pill of a payment or credit that waits on the bank check: its code's, else the plain hold for words with no known code; null
 *  when nothing waits */
export function bankHoldPill(c: { bankCheck?: string | null; bankCheckState?: string | null }): [string, "warn" | "bad"] | null {
  const state = bankCheckStateOf(c);
  return state ? BANK_CHECK_PILL[state] : c.bankCheck ? BANK_HOLD_PILL : null;
}

export interface BankHold { state: BankCheckState | null; pill: [string, "warn" | "bad"]; words: string; page: { href: string; label: string } | null }

/** a wait on the bank check as the screens show it: the pill of its code, the database's words as a sentence, and where the check and
 *  the withdrawals are recorded (Old Fees History, linked for the offices whose menu carries it); null when nothing waits */
function bankHold(c: { bankCheck?: string | null; bankCheckState?: string | null }, office: string | null | undefined): BankHold | null {
  const pill = bankHoldPill(c);
  if (!pill) return null;
  const raw = c.bankCheck ?? "";
  const words = raw ? raw.charAt(0).toUpperCase() + raw.slice(1) : "";
  return { state: bankCheckStateOf(c), pill, words: !words || /[.!?]$/.test(words) ? words : `${words}.`,
    page: OLD_FEES_OFFICES.includes(office ?? "") ? { ...OLD_FEES_PAGE } : null };
}

/** K35: a payment given back — its credit refunded, or, with no credit, refunded on the refund desk. It waits on nothing, by the credits
 *  list's rule (a refunded credit carries no hold, creditBankCheck): the hold's "not refunded or moved" never stands beside the money
 *  already refunded on the same row. The database sends no hold for it (finance.siwes_payments); this keeps an older answer the same */
export function paymentGivenBack(r: Pick<SiwesPaymentRow, "creditState" | "refunded">): boolean {
  return r.creditState === "REFUNDED" || (!r.creditState && num(r.refunded) > 0);
}

/** K31: a payment of the Bursary's list held for the bank check (finance.siwes_payments' bank_check and bank_check_state); none on a
 *  payment given back (K35) */
export function paymentBankCheck(r: Pick<SiwesPaymentRow, "bankCheck" | "bankCheckState" | "creditState" | "refunded">, office: string | null | undefined): BankHold | null {
  return paymentGivenBack(r) ? null : bankHold(r, office);
}

const UUID_TEXT = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** a credit row read from the names the API gives it (camelCase, or the database's own) */
export function creditRow(raw: Record<string, unknown>): SiwesCredit {
  const pick = (...ks: string[]) => { for (const k of ks) if (raw[k] != null && raw[k] !== "") return raw[k]; return null; };
  const text = (...ks: string[]) => { const v = pick(...ks); return v == null ? null : String(v); };
  // an action's flag: only an explicit true counts, so a flag missing never offers an action the database would refuse
  const yes = (...ks: string[]) => ks.some((k) => raw[k] === true);
  const student = text("student");
  const studentIsId = !!student && UUID_TEXT.test(student);
  const settledNote = text("settledNote", "settled_note", "note");
  const settledKind = text("settledKind", "settled_kind");
  const bankCheck = text("bankCheck", "bank_check");
  return {
    id: String(raw.id ?? ""),
    studentId: text("studentId", "student_id") ?? (studentIsId ? student : null),
    name: (studentIsId ? null : student) ?? text("name", "studentName", "student_name") ?? "",
    matricNo: text("matric", "matricNo", "matric_no"),
    session: text("session"),
    reference: text("reference") ?? "",
    amount: (pick("amount") as Money) ?? null,
    state: text("state") ?? "OPEN",
    reason: text("reason"),
    settledNote,
    paidAt: text("paidAt", "paid_at", "confirmedAt", "confirmed_at", "createdAt", "created_at"),
    settledAt: text("settledAt", "settled_at"),
    settledByName: text("settledByName", "settled_by_name"),
    // the API's word when it sends one; else how it was settled (K19) — never the note, which is free text
    automatic: typeof raw.automatic === "boolean" ? raw.automatic : AUTOMATIC_KINDS.has(settledKind ?? ""),
    settles: yes("settles"),
    canRefund: yes("canRefund", "can_refund"),
    canReopen: yes("canReopen", "can_reopen"),
    bankCheck,
    bankCheckState: bankCheckStateOf({ bankCheckState: text("bankCheckState", "bank_check_state") }),
    settledKind,
  };
}

/** what the credits panel offers on a credit: Refund and Reopen only where the database said they pass, never on a credit whose note the
 *  database wrote or whose payment settles the fee now — that one reads "Settles the fee now" — nor on one held for the bank check (K15) */
export function creditActions(c: Pick<SiwesCredit, "automatic" | "settles" | "canRefund" | "canReopen"> & { bankCheck?: string | null; bankCheckState?: string | null }): { refund: boolean; reopen: boolean; settlesNow: boolean } {
  const hands = !c.automatic && !c.settles;
  return { refund: hands && c.canRefund && !c.bankCheck && !c.bankCheckState, reopen: hands && c.canReopen, settlesNow: c.settles };
}

/** K33: what a reopened credit became, from POST /credits/{id}/reopen's answer (the credit as it then stands, in the database's names).
 *  Reopened, it is put under the one rule again: while another payment settles the student's fee it is an open credit, the Bursar's to
 *  refund; where nothing else settles the fee by then (the payment that settled it given back, moved or archived), it settles it */
export function reopenedWords(raw: unknown): string {
  const o = raw && typeof raw === "object" ? (raw as Record<string, unknown>) : {};
  const state = typeof o.state === "string" ? o.state : null;
  const kind = o.settled_kind ?? o.settledKind;
  if (state === "APPLIED" && kind === "SETTLES") return "Reopened: it now settles the student's fee, as no other payment does";
  if (state === "OPEN") return "Reopened: an open credit again";
  return "Reopened";
}

/** K15, K20, K31: why a credit waits for the Bursary's bank check, in the database's words, under the pill of the database's code for
 *  that wait (never read from the words), and where the check and the withdrawals are recorded (Old Fees History, linked for the offices
 *  whose menu carries it); null when it does not wait. A credit that settles the fee meanwhile (the record of its day found never
 *  received settling nothing, K27: its credit APPLIED) still says what it waits on; a refunded one waits on nothing */
export function creditBankCheck(c: Pick<SiwesCredit, "state" | "bankCheck"> & { bankCheckState?: string | null }, office: string | null | undefined): BankHold | null {
  if (c.state === "REFUNDED") return null;
  return bankHold(c, office);
}
