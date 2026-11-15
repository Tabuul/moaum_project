/** V752 — SIWES registration at 300 Level, Second Semester (the University's master prompt of 12 November 2026): the words, the
 *  student's next step and the export rows every SIWES screen shares (the student's page and dashboard card, the Academic Office's
 *  desk, the Bursary's fee panel and payments report). The rules are the database's (registration.siwes_eligibility, siwes_applies,
 *  finance.siwes_paid); nothing here decides who may register or what is owed — it says what the server said. */
import { dayWord, naira, num, type Money } from "./summer.ts";

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

/** what GET /api/v1/me/siwes answers: registration.siwes_eligibility for the student, as is */
export interface MySiwes {
  eligible: boolean;
  /** registration.siwes_applies for the student and session: the SIWES rule binds their Second Semester (absent from an older answer) */
  applies?: boolean | null;
  reasons: string[];
  session: string | null;
  level: number | null;
  semester: number;
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
};

export function reasonWord(code: string): string {
  return REASON_WORD[code] ?? code.replaceAll("_", " ").toLowerCase();
}

export function reasonWords(codes: string[] | null | undefined): string[] {
  return (codes ?? []).map(reasonWord);
}

/** the reasons that leave a student outside SIWES altogether, as registration.siwes_applies reads them: with none of them, the SIWES
 *  rule binds the student's Second Semester whether or not they can register yet. NOT_IN_STUDY is one (K22: siwes_applies binds only
 *  a student in study, ACTIVE or PROBATION, by the roster's and the eligibility's own test); so is ALREADY_PASSED (a student who passed
 *  SIWES registers the Second Semester as before). */
const OUTSIDE = new Set(["NOT_UNDERGRADUATE", "CCE", "NOT_IN_STUDY", "NOT_300_LEVEL", "NOT_CONFIGURED", "NO_PERIOD", "ALREADY_PASSED"]);

/** whether the SIWES rule binds the student's Second Semester: the server's `applies` when it sends it, else read from the reasons */
export function siwesApplies(e: Pick<MySiwes, "eligible" | "reasons" | "registration" | "applies"> | null | undefined): boolean {
  if (!e) return false;
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

/** Course Registration's Second Semester, where the student removes or resets what stands in the SIWES course's way */
export function courseRegistrationPage(session: string | null | undefined): { href: string; label: string } {
  return { href: `/student/register?${session ? `session=${encodeURIComponent(session)}&` : ""}semester=2`, label: "Course Registration" };
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

/** a Second Semester registration of this session is the student's SIWES registration */
export function isSiwesRegistration(e: Pick<MySiwes, "session" | "registration"> | null | undefined, session: string, semester: number): boolean {
  return !!e && semester === 2 && e.session === session && !!e.registration;
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
  | "PAID_NOT_ELIGIBLE" | "PAID_CLOSED" | "DROP_OTHERS" | "PAY_SCHOOL_FEES" | "REGISTER" | "REGISTERED" | "ELSEWHERE" | "UNDONE";

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
  return !!d && (siwesApplies(d) || !!d.paid || !!d.registration);
}

/** the SIWES page's tiles — [label, value, sub] — by where the student stands (v4-2). On ELSEWHERE, the student's own SIWES sessions and
 *  nothing owed for the session shown: never this session's fee or training as theirs. A student SIWES does not bind this session, who
 *  has paid and registered nothing in it, owes nothing for it (a draft period binds nobody) */
export function siwesTiles(d: MySiwes, step: SiwesStep): [string, string, string][] {
  const s = d.session ?? "this session";
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

/** the student's next step on the SIWES page and card, from the server's answer: never more than the server allows */
export function siwesNext(d: MySiwes, today: string = lagosToday()): SiwesNext {
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

export interface SiwesConfigProgramme {
  code: string; name: string; department?: UnitRef; faculty?: UnitRef;
  /** the students eligible in the programme for the session (a count), as the API reports it */
  eligible?: number | boolean | null;
  course: SiwesCourse | null;
  curricula?: { curriculum: string | null; course: SiwesCourse | null }[];
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
    const curricula = (p.curricula ?? []).filter((c) => c.curriculum);
    const courses: [string | null, SiwesCourse | null][] = curricula.length ? curricula.map((c) => [c.curriculum, c.course]) : [[null, p.course]];
    for (const [curriculum, c] of courses) {
      const words = courseStateWarning(c);
      if (c && words) out.push({ programme: p.name || p.code, curriculum, course: c.code, ended: c.state === "ENDED", words });
    }
  }
  return out;
}

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
  const w = (reasons ?? []).map((r) => REASON_SHORT[r] ?? r.replaceAll("_", " ").toLowerCase());
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
