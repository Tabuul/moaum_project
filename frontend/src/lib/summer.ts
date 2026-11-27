/** V735, V779 — the Summer Semester for final-year and spillover students: the words and sums every Summer screen shares (the student's
 *  page, the Academic Office's desk, the Bursary's fees). The rules are the database's (registration.summer_eligibility_of,
 *  summer_selectable, summer_select, summer_verify, summer_summary); nothing here decides who may take the Summer, which course a
 *  student may select, whether a selection stands or what is owed — it says what the server said.
 *
 *  V779: the Summer is open to every final-year and spillover student; the student selects the courses they believe they still owe
 *  from both semesters, the Academic Office verifies each against the record (four states), and a missing result is never read as
 *  a pass. A student-selected course is never called a "carry-over" in anything a student reads. */

export type Money = number | string | null | undefined;
export type Tone = "grey" | "info" | "ok" | "bad" | "warn";

/** the four stored states of a selection (registration.summer_selection.state) */
export type Verification = "PENDING_VERIFICATION" | "CONFIRMED_OUTSTANDING" | "NOT_OUTSTANDING" | "REJECTED";
export type VerifiedVia = "RESULTS" | "AUTHORISATION" | "OFFICER";
export type Evidence = "RESULT_FAILED" | "RESULT_PASSED" | "RESULT_AWAITED" | "NO_RESULT";
export type SummerBasis = "CARRY_OVER" | "AUTHORISED" | "STUDENT_SELECTED";
export type ReviewFlag = "PASSED_ON_RECORD" | "EVIDENCE_CHANGED" | "ENTRY_REMOVED";

export const VERIFICATIONS: Verification[] = ["PENDING_VERIFICATION", "CONFIRMED_OUTSTANDING", "NOT_OUTSTANDING", "REJECTED"];

export interface SummerPeriod {
  session: string; state: "PLANNED" | "OPEN" | "CLOSED"; registration_opens: string | null; registration_closes: string | null;
  exams_from: string | null; exams_to: string | null; results_due: string | null;
  categories: string[] | null; programmes: string[] | null; levels: number[] | null;
  set_at?: string | null; reason?: string | null; open_now?: boolean;
  exam_session_id?: string | null; exam_state?: string | null;
  /** V779: the most courses a student may hold in this Summer (null: no ceiling) */
  max_courses?: number | null;
  /** V779: paid courses not yet verified, read live — only in a single-period answer and only when the Summer holds a paid selection */
  unverified?: number | null;
  /** V779: what the examination acts were let through on, and why */
  overrides?: { act: "OPEN" | "RELEASE"; reason: string; unverified: number; set_at: string }[] | null;
}

/** `outstanding` is the live count the student's own page reads from their results; the dashboard's card reads no result and gives null */
export interface SummerEligibility { eligible: boolean; category: string | null; outstanding: number | null; reason: string | null }

export interface SummerCourse {
  course_code: string; title: string | null; units: number | null; course_semester: number | null; both_semesters: boolean;
  /** V779: the level of the programme's structure the course sits at (null: a course outside the structure) */
  level?: number | null; programme_basis?: string | null; is_gst?: boolean;
  /** where the course came from: the programme's structure, a detected carry-over, or the Academic Office's authorisation */
  source?: "STRUCTURE" | "CARRY_OVER" | "AUTHORISED";
  evidence?: Evidence | null;
  original_session: string | null; original_semester: number | null; original_source?: "RESULTS" | "STUDENT" | null; attempts: number;
  /** V771: the course as the student took it, when its code or title has changed since */
  as_taken_code?: string | null; as_taken_title?: string | null; as_taken_session?: string | null; as_taken_semester?: number | null; as_taken_units?: number | null;
  /** how the selection came in; for a course not yet selected, what it would be */
  basis: SummerBasis;
  status: "OUTSTANDING" | "SELECTED" | "REGISTERED" | "TAKEN_OFF";
  selection_id?: string | null; verification?: Verification | null; verified_via?: VerifiedVia | null; decision_reason?: string | null;
  clarification_open?: boolean; clarification_note?: string | null; student_note?: string | null;
  selectable: boolean; reason: string | null; course_fee: Money;
}

export interface SummerAccount {
  session: string; programmeFee: Money; programmeFeeState: "DUE" | "PAID" | null; coursesSelected: number; coursesPaid: number;
  courseFeesDue: Money; programmeFeeDue: Money; due: Money; paid: Money; openReference: string | null;
  /** V739: the open reference's own amount (an open reference is shown only when it may be paid) and the unapplied Summer credit */
  openAmount?: Money; credit?: Money;
  registration: { id: string; status: string; approvedAt: string | null; courses: number } | null;
}

/** V779: one line of what the student is charged — the programme fee, then a course fee for each selected course */
export interface SummerLine { kind: "PROGRAMME" | "COURSE"; code: string | null; title: string | null; amount: Money; state: string; verification?: Verification | null }

/** V779 (registration.summer_summary): the student's counts and the itemised sum, from the server */
export interface SummerSummary {
  selected: number; pending: number; confirmed: number; notOutstanding: number; rejected: number; clarifications: number; registered: number;
  units: number; unitsRegistered: number; due: Money; paid: Money;
  paymentStatus?: "NOT_STARTED" | "UNPAID" | "PART_PAID" | "PAID"; registrationStatus?: "NOT_STARTED" | "SELECTED" | "REGISTERED";
  /** a selection waiting to be read against results exists, so the page asks the server to reconcile */
  reconcilable?: boolean;
  lines?: SummerLine[];
  formula?: SummerFormula;
}
export interface SummerFormula { programme: Money; perCourse: Money; courses: number; total?: Money }

export interface SummerRegistered {
  course_code: string; title: string | null; units: number | null; course_semester: number | null; original_session: string | null;
  original_semester: number | null; status: string; paid_reference: string | null; receipt_no: string | null; registration_status: string;
  lecturer: string | null;
  /** V779: how the course came in and whether the Academic Office has verified it */
  basis?: SummerBasis | null; verification?: Verification | null; verified_via?: VerifiedVia | null; category_label?: string | null;
}

export interface SummerPayment { reference: string; amount: Money; purpose: string; confirmed_at: string | null; receipt_no: string | null; generated_at: string; expires_at: string | null }

export interface MySummer {
  session: string | null;
  period: SummerPeriod | null;
  eligibility?: SummerEligibility;
  courses?: SummerCourse[];
  fee?: { fee_id: string; programme_fee: Money; course_fee: Money } | null;
  account?: SummerAccount;
  summary?: SummerSummary;
  registered?: SummerRegistered[];
  payments?: SummerPayment[];
}

/** V779: what GET /me/summer/card answers for the dashboard — the summary, the period, the eligibility and the fee, nothing else */
export type MySummerCard = Pick<MySummer, "session" | "period" | "eligibility" | "fee" | "summary">;

/** V779 (registration.summer_confirmation): what the printed confirmation is made of */
export interface SummerConfirmationRow {
  course_code: string; title: string | null; units: number | null; course_semester: number | null; original_session: string | null; original_semester: number | null;
  category_label: string | null; registration_status: "REGISTERED" | "SELECTED" | "TAKEN_OFF"; verification: Verification | null; verified_via?: VerifiedVia | null;
  decision_reason?: string | null; clarification_note?: string | null;
}
export interface SummerConfirmation {
  session: string; generatedAt: string; status: "REGISTERED" | "SELECTED_UNPAID" | "NONE";
  student: { name: string; number: string | null; programme: string | null; department: string | null; faculty: string | null; level: number | null; category: string | null };
  period: { registration_opens: string | null; registration_closes: string | null; exams_from: string | null; exams_to: string | null; results_due: string | null; state: string };
  rows: SummerConfirmationRow[];
  totals: { courses: number; units: number; unitsRegistered: number; programmeFee: Money; courseFees: Money; total: Money; paid: Money; due: Money };
  payments: { reference: string; amount: Money; receipt_no: string | null; confirmed_at: string | null }[];
  notice: string;
}

/** where the printed confirmation's student stands. REGISTERED: the registration stands (the server's status: a paid course with its
 *  entry on an approved Summer registration). PAID_PENDING: a course is paid but the registration has not taken it (the server says
 *  SELECTED_UNPAID while a row's registration_status is REGISTERED, which is its charge's PAID; the Academic Office puts right what
 *  stopped it). UNPAID: nothing selected is paid. */
export type ConfirmationState = "REGISTERED" | "PAID_PENDING" | "UNPAID";
export function confirmationState(c: Pick<SummerConfirmation, "status" | "rows">): ConfirmationState {
  if (c.status === "REGISTERED") return "REGISTERED";
  return c.rows.some((r) => r.registration_status === "REGISTERED") ? "PAID_PENDING" : "UNPAID";
}

/** the title the confirmation carries: a registration once it stands, otherwise a summary of the selection that says what it waits for
 *  (a state, or the server's status as before) */
export function confirmationTitle(state: ConfirmationState | string | null | undefined): string {
  return state === "REGISTERED" ? "Summer Semester Registration Confirmation"
    : state === "PAID_PENDING" ? "Summer Semester Selection Summary (registration pending)"
    : "Summer Semester Selection Summary (payment outstanding)";
}

/** the confirmation's Status line: what is true of the student's Summer as printed */
export function confirmationStatusWord(c: Pick<SummerConfirmation, "status" | "rows" | "totals">): string {
  const state = confirmationState(c);
  if (state === "REGISTERED") return "Registered";
  if (state === "PAID_PENDING") return num(c.totals.due) > 0 ? "Paid in part, registration pending" : "Paid, registration pending";
  return "Selected, payment outstanding";
}

/** a course's registration word on the printed confirmation: a paid course the registration has not taken is not called registered */
export function confirmationRowWord(state: ConfirmationState, registrationStatus: string): string {
  return state === "PAID_PENDING" && registrationStatus === "REGISTERED" ? "Paid, not yet registered" : registrationStatusWord(registrationStatus);
}

/** a reference drawn for the Summer Semester fees (finance.payment_reference.purpose), never a school-fee one: paid from the Summer page */
export function isSummerPurpose(purpose: string | null | undefined): boolean {
  return (purpose ?? "").startsWith("Summer semester fees");
}

export const num = (m: Money): number => (m == null || m === "" ? 0 : Number(m));

export function naira(m: Money): string {
  if (m == null || m === "") return "—";
  return `₦${Number(m).toLocaleString("en-NG", { minimumFractionDigits: 0, maximumFractionDigits: 2 })}`;
}

/** "1 course", "3 courses" */
export function plural(n: number, one: string, many = `${one}s`): string {
  return `${n} ${n === 1 ? one : many}`;
}

/* ───────────────────────── who the student is: the category ───────────────────────── */

export const CATEGORY_WORD: Record<string, string> = {
  FINAL_YEAR: "Final-year student",
  SPILLOVER: "Spillover student",
  BEYOND_DURATION: "Spillover student",
  AUTHORISED: "Authorised by the Academic Office",
};
export const CATEGORIES = ["FINAL_YEAR", "SPILLOVER", "BEYOND_DURATION", "AUTHORISED"] as const;

export function categoryWord(c: string | null | undefined): string {
  return c ? CATEGORY_WORD[c] ?? c : "—";
}

/** the category as a pill reads it: FINAL-YEAR STUDENT, SPILLOVER STUDENT */
export function categoryPill(c: string | null | undefined): string {
  return categoryWord(c).toUpperCase();
}

/** V779: the three boxes of the period's "Who it is for": Spillover writes SPILLOVER and BEYOND_DURATION (either admits a spillover student) */
export const CATEGORY_BOXES: { id: "FINAL_YEAR" | "SPILLOVER" | "AUTHORISED"; label: string; writes: string[] }[] = [
  { id: "FINAL_YEAR", label: "Final-year", writes: ["FINAL_YEAR"] },
  { id: "SPILLOVER", label: "Spillover", writes: ["SPILLOVER", "BEYOND_DURATION"] },
  { id: "AUTHORISED", label: "Authorised", writes: ["AUTHORISED"] },
];

/** the boxes a period's stored categories tick (none stored: every box) */
export function boxesOf(categories: string[] | null | undefined): Set<string> {
  if (!categories || categories.length === 0) return new Set(CATEGORY_BOXES.map((b) => b.id));
  return new Set(CATEGORY_BOXES.filter((b) => b.writes.some((w) => categories.includes(w))).map((b) => b.id));
}

/** the categories written for the boxes ticked */
export function categoriesOf(boxes: Iterable<string>): string[] {
  const on = new Set(boxes);
  return CATEGORY_BOXES.filter((b) => on.has(b.id)).flatMap((b) => b.writes);
}

/** "Final-year, Spillover, Authorised": who a period is for, each box said once */
export function periodForWord(categories: string[] | null | undefined): string {
  const on = boxesOf(categories);
  return CATEGORY_BOXES.filter((b) => on.has(b.id)).map((b) => b.label).join(", ");
}

/** who a period is open to, as a sentence to the student: "Open to final-year and spillover students, and to students the Academic Office authorises." */
export function periodForSentence(categories: string[] | null | undefined): string {
  const on = boxesOf(categories);
  const kinds = [on.has("FINAL_YEAR") ? "final-year" : null, on.has("SPILLOVER") ? "spillover" : null].filter(Boolean) as string[];
  const main = kinds.length ? `${kinds.join(" and ")} students` : "";
  const auth = on.has("AUTHORISED") ? "students the Academic Office authorises" : "";
  if (main && auth) return `Open to ${main}, and to ${auth}.`;
  return main ? `Open to ${main}.` : auth ? `Open to ${auth}.` : "Open to no one.";
}

/** why a student may not take the Summer, said to the student */
export const NOT_ELIGIBLE_WORD: Record<string, string> = {
  NO_STUDENT: "Your record could not be read.",
  NO_SUMMER: "No Summer Semester is set for this session.",
  NOT_UNDERGRADUATE: "The Summer Semester is for undergraduate students of the regular programmes.",
  NOT_STUDYING: "Your record is not active.",
  GRADUATED: "Your award is approved; there is nothing left to take.",
  PROGRAMME_NOT_IN_SUMMER: "Your programme is not among those this Summer Semester runs for.",
  LEVEL_NOT_IN_SUMMER: "Your level is not among those this Summer Semester runs for.",
  NOT_FINAL_OR_SPILLOVER: "The Summer Semester is for students in their final year or in spillover.",
  CATEGORY_NOT_IN_SUMMER: "This Summer Semester is not open to students in your position.",
};

export function notEligibleWord(reason: string | null | undefined): string {
  return reason ? NOT_ELIGIBLE_WORD[reason] ?? reason : "You are not eligible for this Summer Semester.";
}

/** V779: what the API says when a selection is refused for eligibility (SUMMER_NOT_ELIGIBLE) — the screens show the server's own
 *  message; this is the same sentence, for a test to hold the two together */
export function notEligibleRefusal(reason: string | null | undefined): string {
  if (reason === "GRADUATED") return "your award is approved";
  if (reason === "NOT_FINAL_OR_SPILLOVER") return "the Summer Semester is for final-year and spillover students";
  return `you are not eligible for the Summer Semester (${reason ?? "reason not given"})`;
}
export const NOT_FINAL_OR_SPILLOVER_HINT = "The Academic Office may authorise a student for an approved academic reason.";

/* ───────────────────────── a course: why it is or is not selectable ───────────────────────── */

/** why a course is not selectable now: one word for each reason registration.summer_selectable gives, and no other (a course of both
 *  semesters held in the First or Second Semester of the session is selectable: V735's once-a-session rule lets a Summer entry repeat it; nor is a course whose result of
 *  the session is awaited, since V787: that is the evidence's word, EVIDENCE_WORD, not a reason) */
export const COURSE_REASON_WORD: Record<string, string> = {
  COURSE_UNKNOWN: "Not in the course catalogue",
  COURSE_ENDED: "The course has ended; ask your department",
  PASSED: "Passed",
  ALREADY_REGISTERED: "Registered",
  ALREADY_SELECTED: "Selected — pay to register",
  SIWES_OWN_PAGE: "SIWES is registered on its own page",
  DECIDED_NOT_OUTSTANDING: "Found not outstanding by the Academic Office",
  DECIDED_REJECTED: "Rejected by the Academic Office",
};

export function courseReasonWord(r: string | null | undefined): string {
  return r ? COURSE_REASON_WORD[r] ?? r : "";
}

export function semesterWord(n: number | null | undefined): string {
  return n === 1 ? "First" : n === 2 ? "Second" : n === 3 ? "Summer" : "—";
}

/** a course's own semester: "Both" when it is taught in the first and the second */
export function courseSemesterWord(c: Pick<SummerCourse, "both_semesters" | "course_semester">): string {
  return c.both_semesters ? "Both" : semesterWord(c.course_semester);
}

/** where the student owes the course: "Second semester, 2024/2025", what is known of it, or "Not stated" — the Academic Office's own
 *  naming of a course says so */
export function failedInWord(c: Pick<SummerCourse, "original_session" | "original_semester" | "basis">): string {
  if (c.basis === "AUTHORISED" && !c.original_session) return "Named by the Academic Office";
  if (!c.original_session && !c.original_semester) return "Not stated";
  if (!c.original_session) return `${semesterWord(c.original_semester)} semester`;
  if (!c.original_semester) return c.original_session;
  return `${semesterWord(c.original_semester)} semester, ${c.original_session}`;
}

/** whether the original session and semester came from the student's results or from what the student said */
export function originSourceWord(s: string | null | undefined): string {
  return s === "RESULTS" ? "from your results" : s === "STUDENT" ? "as you stated" : "";
}

/** V771: "Taken as CSC 305, Operating systems, 3 units" — the course as the student took it, when it differs from the one on offer now */
export function asTakenWord(c: Pick<SummerCourse, "course_code" | "title" | "units" | "as_taken_code" | "as_taken_title" | "as_taken_units">): string | null {
  if (!c.as_taken_code && !c.as_taken_title) return null;
  const sameCode = !c.as_taken_code || c.as_taken_code === c.course_code;
  const sameTitle = !c.as_taken_title || (c.as_taken_title ?? "").trim().toLowerCase() === (c.title ?? "").trim().toLowerCase();
  if (sameCode && sameTitle) return null;
  const bits = [c.as_taken_code ?? c.course_code, c.as_taken_title ?? c.title].filter(Boolean) as string[];
  if (c.as_taken_units != null) bits.push(plural(c.as_taken_units, "unit"));
  return `Taken as ${bits.join(", ")}`;
}

/* ───────────────────────── verification: the four states ───────────────────────── */

/** V779: the four states of a selection, said to the student and on the desk (the dash is an en dash) */
export const VERIFICATION_WORD: Record<Verification, string> = {
  PENDING_VERIFICATION: "Student selected – pending verification",
  CONFIRMED_OUTSTANDING: "Academically confirmed outstanding",
  NOT_OUTSTANDING: "Not outstanding – result verified",
  REJECTED: "Rejected – incorrect course selection",
};
const VERIFICATION_TONE: Record<Verification, Tone> = {
  PENDING_VERIFICATION: "warn", CONFIRMED_OUTSTANDING: "ok", NOT_OUTSTANDING: "grey", REJECTED: "bad",
};

export function verificationWord(v: string | null | undefined): string {
  return v ? VERIFICATION_WORD[v as Verification] ?? v : "";
}
export function verificationTone(v: string | null | undefined): Tone {
  return (v && VERIFICATION_TONE[v as Verification]) || "grey";
}
/** the word and the tone together, as paymentStateWords gives them */
export function verificationWords(v: string | null | undefined): [string, Tone] {
  return [verificationWord(v) || "—", verificationTone(v)];
}

/** the short form the printed confirmation and the public registration check carry beside a course: a pending course reads "Pending
 *  verification" and is never called a carry-over; the four states in full are printed once under the table */
export const PRINT_VERIFICATION_WORD: Record<Verification, string> = {
  PENDING_VERIFICATION: "Pending verification",
  CONFIRMED_OUTSTANDING: "Confirmed outstanding",
  NOT_OUTSTANDING: "Not outstanding",
  REJECTED: "Rejected",
};
export function printVerificationWord(v: string | null | undefined): string {
  return v ? PRINT_VERIFICATION_WORD[v as Verification] ?? v : "";
}

/** how a selection was confirmed, said to the student */
export const VIA_WORD: Record<VerifiedVia, string> = {
  RESULTS: "Confirmed by your results",
  AUTHORISATION: "Named by the Academic Office",
  OFFICER: "Confirmed by the Academic Office",
};
export function viaWord(v: string | null | undefined): string {
  return v ? VIA_WORD[v as VerifiedVia] ?? v : "";
}

/** what the results say of a selected course (registration.summer_selection_evidence) */
export const EVIDENCE_WORD: Record<Evidence, string> = {
  RESULT_FAILED: "Confirmed by results (failed)",
  RESULT_PASSED: "Result on record: passed",
  RESULT_AWAITED: "Result awaited",
  NO_RESULT: "No result on record",
};
export function evidenceWord(e: string | null | undefined): string {
  return e ? EVIDENCE_WORD[e as Evidence] ?? e : "";
}
/** a pass on record against a selection is the Office's concern, a failure is what it rests on */
export function evidenceTone(e: string | null | undefined): Tone {
  return e === "RESULT_FAILED" ? "info" : e === "RESULT_PASSED" ? "warn" : "grey";
}

/** the registration category by how the course came in — never "Carry-over" for a course the student selected */
export const REGISTRATION_CATEGORY_WORD: Record<SummerBasis, string> = {
  CARRY_OVER: "Carry-over",
  AUTHORISED: "Authorised course",
  STUDENT_SELECTED: "Student-selected course",
};
export function registrationCategoryWord(basis: string | null | undefined): string {
  return basis ? REGISTRATION_CATEGORY_WORD[basis as SummerBasis] ?? basis : "—";
}

/** why a selection waits for the Academic Office's decision (the review flags) */
export const REVIEW_REASON_WORD: Record<ReviewFlag, string> = {
  PASSED_ON_RECORD: "A pass is on record: decide",
  EVIDENCE_CHANGED: "The result this rested on changed",
  ENTRY_REMOVED: "The course was taken off the registration: decide",
};
/** a selection of the Office's authorisation is flagged EVIDENCE_CHANGED when the authorisation it rested on no longer stands (revoked,
 *  or the course no longer named): no result is involved, so the words say what changed */
export const AUTHORISATION_GONE_WORD = "The authorisation it rested on no longer stands: decide";
export function reviewReasonWord(flag: string | null | undefined, basis?: string | null): string {
  if (flag === "EVIDENCE_CHANGED" && basis === "AUTHORISED") return AUTHORISATION_GONE_WORD;
  return flag ? REVIEW_REASON_WORD[flag as ReviewFlag] ?? flag : "";
}

/* ───────────────────────── the Bursar's Summer credits ───────────────────────── */

/** the settled note the student's own new selection writes on the programme fee credit it uses to pay the fee again (V779, D6) */
export const REINSTATED_NOTE = "Reinstated as the programme fee: ";
/** the settled note a payment correction writes on the credit it moved (V742) */
export const MOVED_NOTE = "Moved by a payment correction: ";

export interface SummerCreditShape {
  state: "OPEN" | "APPLIED" | "REFUNDED"; settled_note: string | null; source?: "PAYMENT" | "DECISION"; note?: string | null;
  course_code?: string | null; charge_kind?: "PROGRAMME" | "COURSE" | null; selection_state?: Verification | null;
}

/** a credit of the programme fee: its source charge is the PROGRAMME charge (or, without the kind, a DECISION credit with no course) */
export function isProgrammeCredit(x: Pick<SummerCreditShape, "source" | "course_code" | "charge_kind">): boolean {
  return x.charge_kind ? x.charge_kind === "PROGRAMME" : x.source === "DECISION" && !x.course_code;
}

/** the Course column of a credit: the course, "Programme fee", or a dash for money beyond its charges */
export function creditItemWord(x: Pick<SummerCreditShape, "source" | "course_code" | "charge_kind">): string {
  return isProgrammeCredit(x) ? "Programme fee" : x.course_code ?? "—";
}

/** the Source column of a credit: a pill and the line under it. A programme fee credit is made whenever the student's last Summer course
 *  goes, by a decision or not (unselected, the window closed, taken back), so it is not called a decision; its note says what happened */
export function creditSourceWords(x: SummerCreditShape): { pill: string | null; line: string } {
  if (x.source === "DECISION" && isProgrammeCredit(x)) {
    return { pill: "PROGRAMME FEE", line: x.note?.trim() || "No Summer course of the student remains" };
  }
  if (x.source === "DECISION") {
    const why = x.selection_state ? verificationWord(x.selection_state) : "Found not outstanding or rejected";
    return { pill: "DECISION", line: `${why}${x.note ? ` · ${x.note}` : ""}` };
  }
  return { pill: null, line: `Payment beyond its charges${x.note ? ` · ${x.note}` : ""}` };
}

/** whether the Bursar is offered Reopen on a settled credit: never on one a payment correction moved (the move records it), nor on one
 *  the student's new selection used to pay the programme fee again — that money pays a PAID charge, and the database refuses its
 *  reopen (SUMMER_CREDIT_REINSTATED) */
export function creditReopenable(x: Pick<SummerCreditShape, "state" | "settled_note">): boolean {
  const n = x.settled_note ?? "";
  return x.state !== "OPEN" && !n.startsWith(MOVED_NOTE) && !n.startsWith(REINSTATED_NOTE);
}

/** a course of the pool by what is owed: true when the results or the Office say the student owes it, so "My outstanding" lists it */
export function isOwed(c: Pick<SummerCourse, "evidence" | "basis">): boolean {
  return c.evidence === "RESULT_FAILED" || c.basis === "CARRY_OVER" || c.basis === "AUTHORISED";
}

/** the status pill of a course in the pool: Selected: unpaid, Registered, Taken off, Outstanding (only when it is owed); null for a
 *  structure course nothing says is owed — the pool is wide, and "Outstanding" is never said of a course nothing shows is owed */
export function courseStatusWords(c: Pick<SummerCourse, "status" | "evidence" | "basis">): [string, Tone] | null {
  if (c.status === "REGISTERED") return ["Registered", "ok"];
  if (c.status === "SELECTED") return ["Selected: unpaid", "warn"];
  if (c.status === "TAKEN_OFF") return ["Taken off", "grey"];
  return isOwed(c) ? ["Outstanding", "info"] : null;
}

/** the registration status of one of the student's selections, in the My selections table */
export function registrationStatusWord(status: string): string {
  return status === "REGISTERED" ? "Registered" : status === "SELECTED" ? "Selected: unpaid" : status === "TAKEN_OFF" ? "Taken off" : "Not registered";
}

/* ───────────────────────── the pool: search, filter, group ───────────────────────── */

export interface PoolFilter { q?: string; level?: number | "all" | null; semester?: 1 | 2 | "all" | null; scope?: "all" | "outstanding" | "selected" }

/** a course the picker's "Selected" filter shows: one selected, registered or taken off. A course the Academic Office decided before it
 *  was paid comes back from the server OUTSTANDING with its reason (DECIDED_NOT_OUTSTANDING, DECIDED_REJECTED) and is shown under All
 *  courses, not here; the filter and its count both read this */
export function inSelectedScope(c: Pick<SummerCourse, "status">): boolean {
  return c.status !== "OUTSTANDING";
}

/** the pool narrowed: search matches the code, the title and the code and title the course was taken as, case-insensitively and
 *  without regard to the spaces in a code ("csc301" finds CSC 301); a both-semesters course is in each semester */
export function filterPool(courses: SummerCourse[], f: PoolFilter): SummerCourse[] {
  const term = (f.q ?? "").trim().toLowerCase();
  const squash = (s: string) => s.toLowerCase().replace(/\s+/g, "");
  const level = f.level === "all" || f.level == null ? null : f.level;
  const sem = f.semester === "all" || f.semester == null ? null : f.semester;
  const scope = f.scope ?? "all";
  return courses.filter((c) => {
    if (level !== null && c.level !== level) return false;
    if (sem !== null && !(c.both_semesters || c.course_semester === sem)) return false;
    if (scope === "outstanding" && !isOwed(c)) return false;
    if (scope === "selected" && !inSelectedScope(c)) return false;
    if (!term) return true;
    const hay = [c.course_code, c.title, c.as_taken_code, c.as_taken_title].filter(Boolean).map((x) => String(x));
    return hay.some((h) => h.toLowerCase().includes(term) || squash(h).includes(squash(term)));
  });
}

export interface PoolGroup { level: number | null; label: string; courses: SummerCourse[] }

/** the pool under "NNN Level" headings: level ascending (a course outside the structure last), each group by semester then code */
export function groupByLevel(courses: SummerCourse[]): PoolGroup[] {
  const by = new Map<number | null, SummerCourse[]>();
  for (const c of courses) {
    const k = c.level ?? null;
    const list = by.get(k);
    if (list) list.push(c); else by.set(k, [c]);
  }
  const keys = [...by.keys()].sort((a, b) => (a === null ? 1 : b === null ? -1 : a - b));
  return keys.map((k) => ({
    level: k,
    label: k === null ? "Other courses" : `${k} Level`,
    courses: (by.get(k) ?? []).slice().sort((a, b) => (a.course_semester ?? 9) - (b.course_semester ?? 9) || a.course_code.localeCompare(b.course_code)),
  }));
}

/** the numbers on the picker's filters; `inSelected` is what the "Selected" filter shows (filterPool's own test), so its count and its
 *  list agree */
export function poolCounts(courses: SummerCourse[]): { total: number; selectable: number; outstanding: number; selected: number; registered: number; decided: number; inSelected: number } {
  return {
    total: courses.length,
    selectable: courses.filter((c) => c.selectable).length,
    outstanding: courses.filter(isOwed).length,
    selected: courses.filter((c) => c.status === "SELECTED").length,
    registered: courses.filter((c) => c.status === "REGISTERED").length,
    decided: courses.filter((c) => c.verification === "NOT_OUTSTANDING" || c.verification === "REJECTED").length,
    inSelected: courses.filter(inSelectedScope).length,
  };
}

/** the levels the pool holds, ascending, for the picker's Level filter */
export function poolLevels(courses: SummerCourse[]): number[] {
  return [...new Set(courses.map((c) => c.level).filter((l): l is number => typeof l === "number"))].sort((a, b) => a - b);
}

/** "Where did you owe it?": the last six sessions up to and including the Summer's own, newest first, from the University's calendar */
export function lastSessions(names: string[], session: string | null | undefined, n = 6): string[] {
  return [...new Set(names)].filter((s) => !session || s <= session).sort().reverse().slice(0, n);
}

/** the call's cap: the server refuses more than this many distinct courses at once */
export const SELECT_LIMIT = 30;

/* ───────────────────────── money ───────────────────────── */

/** what selecting these courses adds to what is owed: the programme fee once a Summer (unless charged already), and a fee a course */
export function selectionCost(picked: number, account: Pick<SummerAccount, "programmeFeeState"> | null | undefined,
                              fee: { programme_fee: Money; course_fee: Money } | null | undefined): number {
  if (!fee || picked <= 0) return 0;
  const programme = account?.programmeFeeState ? 0 : num(fee.programme_fee);
  return programme + picked * num(fee.course_fee);
}

/** the sum the courses ticked add, as the sticky bar says it: the programme fee once a Summer (unless it is charged already), then a fee a
 *  course — "₦50,000 + 4 × ₦5,000 = ₦70,000", or "4 × ₦5,000 = ₦20,000" when the programme fee stands; its total is selectionCost's */
export function selectionFormula(picked: number, account: Pick<SummerAccount, "programmeFeeState"> | null | undefined,
                                 fee: { programme_fee: Money; course_fee: Money } | null | undefined): string {
  if (!fee || picked <= 0) return "";
  const total = selectionCost(picked, account, fee);
  return account?.programmeFeeState
    ? `${picked} × ${naira(fee.course_fee)} = ${naira(total)}`
    : `${naira(fee.programme_fee)} + ${picked} × ${naira(fee.course_fee)} = ${naira(total)}`;
}

/** the itemised charges of the Fees panel: the server's lines, else (an older answer) built from the account and the selected courses */
export function chargeLines(d: Pick<MySummer, "summary" | "account" | "courses">): SummerLine[] {
  if (d.summary?.lines) return d.summary.lines;
  const lines: SummerLine[] = [];
  const a = d.account;
  if (a?.programmeFeeState) lines.push({ kind: "PROGRAMME", code: null, title: "Programme fee", amount: a.programmeFee, state: a.programmeFeeState });
  for (const c of d.courses ?? []) {
    if (c.status === "SELECTED" || c.status === "REGISTERED") {
      lines.push({ kind: "COURSE", code: c.course_code, title: c.title, amount: c.course_fee, state: c.status === "REGISTERED" ? "PAID" : "DUE", verification: c.verification ?? null });
    }
  }
  return lines;
}

/** "₦50,000 + 4 × ₦5,000 = ₦70,000": the server's own sum, from summary.formula (or the three figures); the total is the server's when it
 *  gives one */
export function feeFormula(x: Pick<SummerSummary, "formula"> | SummerFormula | null | undefined): string {
  if (!x) return "";
  const f: SummerFormula | undefined = "formula" in x ? x.formula : (x as SummerFormula);
  if (!f) return "";
  const total = f.total != null && f.total !== "" ? num(f.total) : num(f.programme) + f.courses * num(f.perCourse);
  return `${naira(f.programme)} + ${f.courses} × ${naira(f.perCourse)} = ${naira(total)}`;
}

/** the state of one charge line, said plainly */
export function chargeStateWord(s: string | null | undefined): string {
  return s === "PAID" ? "Paid" : s === "DUE" ? "Owed" : s === "CANCELLED" ? "Cancelled" : s ? s.toLowerCase() : "—";
}

/** "Selected 4 · pending verification 3 · confirmed 1 · not outstanding or rejected 0 · registered 2 · units 12 · payable ₦20,000" */
export function countsLine(s: SummerSummary | null | undefined): string {
  if (!s) return "";
  return `Selected ${s.selected} · pending verification ${s.pending} · confirmed ${s.confirmed} · not outstanding or rejected ${s.notOutstanding + s.rejected} · registered ${s.registered} · units ${s.units} · payable ${naira(s.due)}`;
}

/* ───────────────────────── the student's page: one sentence, the notes ───────────────────────── */

/** "1 December 2026" from a calendar date */
export function dayWord(iso: string): string {
  return new Date(`${iso.slice(0, 10)}T00:00:00Z`).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric", timeZone: "UTC" });
}

/** the plain note under the next step when no earlier result is on the portal: a missing result is never read as nothing owed */
export const INCOMPLETE_RESULTS_WORD = "Your earlier results may not all be on the portal yet. Select the courses you believe you still owe; the Academic Office will verify them. Nothing here says you owe nothing.";

/** the note is shown to an eligible student whose results show no course owed */
export function incompleteResultsNote(d: Pick<MySummer, "eligibility">): string | null {
  return d.eligibility?.eligible && (d.eligibility.outstanding ?? 0) === 0 ? INCOMPLETE_RESULTS_WORD : null;
}

/** the student's next step, in words (the page and the dashboard's card read it from the server's summary) */
export function nextStep(d: MySummer, today: string = new Date().toISOString().slice(0, 10)): string {
  const a = d.account;
  const s = d.summary;
  const p = d.period;
  if (!p) return "No Summer Semester is set.";
  const due = num(s?.due ?? a?.due);
  const paid = num(s?.paid ?? a?.paid);
  const took = due > 0 || paid > 0 || (s?.selected ?? 0) > 0;
  if (!d.eligibility?.eligible && !took) return notEligibleWord(d.eligibility?.reason);
  // V739: after the close nothing more is taken — an unpaid selection is removed, never "paid"
  if (due > 0) return p.open_now ? `Pay ${naira(due)} to register the courses you selected.` : "Registration is closed: remove the course you selected and did not pay; nothing more is taken.";
  if (!p.open_now) {
    // V739: an open or planned Summer before its window says when it opens, not that it is closed
    if (p.state !== "CLOSED" && p.registration_opens && today < p.registration_opens.slice(0, 10)) return `Registration opens on ${dayWord(p.registration_opens)}.`;
    return p.state === "PLANNED" ? "Registration has not opened yet." : "Registration is closed.";
  }
  if (!d.fee) return "The Bursary has not published the Summer Semester fees yet.";
  const registered = s?.registered ?? a?.coursesPaid ?? 0;
  const pending = s?.pending ?? 0;
  if (registered > 0 && pending > 0) return `${plural(registered, "course")} registered, ${pending} waiting for the Academic Office to verify.`;
  if (d.courses && d.courses.length > 0 && !d.courses.some((c) => c.selectable)) return "Nothing more can be selected now.";
  if (registered > 0) return `${plural(registered, "course")} registered. You may select more courses while registration is open.`;
  return "Search your programme's courses and select the ones you believe you still owe, then pay. The Academic Office verifies each against your record.";
}

/** the dashboard's card shows for a student the Summer is for, and for one who has anything selected, decided or registered in it */
export function showSummerCard(d: MySummerCard | null | undefined): boolean {
  if (!d?.period) return false;
  const s = d.summary;
  const took = !!s && (s.selected > 0 || s.notOutstanding > 0 || s.rejected > 0 || s.registered > 0 || num(s.due) > 0 || num(s.paid) > 0);
  if (took) return true;
  return !!d.eligibility?.eligible && d.period.state !== "CLOSED";
}

/** the card's title: "Summer Semester 2025/2026 · SPILLOVER STUDENT" */
export function cardTitle(d: MySummerCard): string {
  const s = d.period?.session ?? d.session ?? "";
  return `Summer Semester ${s}${d.eligibility?.eligible && d.eligibility.category ? ` · ${categoryPill(d.eligibility.category)}` : ""}`;
}

export const PERIOD_WORD: Record<string, [string, Tone]> = {
  PLANNED: ["Planned", "grey"],
  OPEN: ["Open", "ok"],
  CLOSED: ["Closed", "bad"],
};

export function periodWords(p: SummerPeriod | null | undefined): [string, Tone] {
  if (!p) return ["Not set", "grey"];
  if (p.state === "OPEN" && p.open_now === false) return ["Open — outside its dates", "warn"];
  return PERIOD_WORD[p.state] ?? [p.state, "grey"];
}

/** the payment state of a row on the desk */
export const PAYMENT_STATE_WORD: Record<string, [string, Tone]> = {
  NOT_STARTED: ["Not started", "grey"],
  UNPAID: ["Unpaid", "bad"],
  PART_PAID: ["Part paid", "warn"],
  PAID: ["Paid", "ok"],
};

export function paymentStateWords(s: string | null | undefined): [string, Tone] {
  return (s && PAYMENT_STATE_WORD[s]) || ["—", "grey"];
}

export const FEE_STATE_WORD: Record<string, [string, Tone]> = {
  DRAFT: ["Draft", "warn"],
  PUBLISHED: ["Published", "ok"],
  WITHDRAWN: ["Withdrawn", "grey"],
};

/** the session's Summer path segment pair: "2025/2026" → "2025/2026" (the API takes /{session}/{year}) */
export function sessionPath(session: string): string {
  return session.split("/").map(encodeURIComponent).join("/");
}

/* ───────────────────────── the Academic Office's desk ───────────────────────── */

/** the offices that may decide a selection, set a period and act (the API's SETTERS); every other reader sees the desk without the bars */
export const SETTER_OFFICES = ["academic", "registrar", "dregistrar", "super"];
export function maySetSummer(office: string | null | undefined): boolean {
  return SETTER_OFFICES.includes(office ?? "");
}

export type DeskView = "review" | "students" | "reports" | "courses" | "period";
export const DESK_VIEWS: { id: DeskView; label: string }[] = [
  { id: "review", label: "Verification" },
  { id: "students", label: "Students" },
  { id: "reports", label: "Reports" },
  { id: "courses", label: "Courses" },
  { id: "period", label: "Period and acts" },
];

/** the view the address asks for, else Verification for the offices that verify and Students for those that read */
export function deskView(raw: string | string[] | undefined, maySet: boolean): DeskView {
  const v = typeof raw === "string" ? raw : "";
  return (DESK_VIEWS.find((x) => x.id === v)?.id) ?? (maySet ? "review" : "students");
}

/** what the desk's page reads for the view shown: the view's own reads for a session whose Summer is set ("view"); for a session with
 *  no Summer yet, the Period and acts tab of an office that may set one is built with no period and nothing read of it ("new-period":
 *  the form sets the Summer of that session; only the authorisations to look at again are read); anything else reads nothing and the
 *  desk says the session has no Summer Semester yet ("none") */
export function deskReads(view: DeskView, known: boolean, maySet: boolean): "view" | "new-period" | "none" {
  if (known) return "view";
  return view === "period" && maySet ? "new-period" : "none";
}

/** the queue's states, as the chips say them */
export const STATE_FILTER_WORD: Record<string, string> = {
  PENDING_VERIFICATION: "Pending", CONFIRMED_OUTSTANDING: "Confirmed", NOT_OUTSTANDING: "Not outstanding", REJECTED: "Rejected", ANY: "Any",
};
export const FLAG_FILTER_WORD: Record<string, string> = { REVIEW: "Needs review", CLARIFICATION: "Clarification asked" };
/** staff screens may name the basis; a student's never says "carry-over" of a course the student selected */
export const BASIS_WORD: Record<SummerBasis, string> = { CARRY_OVER: "Carry-over", AUTHORISED: "Authorised", STUDENT_SELECTED: "Student-selected" };

const QUEUE_KEYS = ["faculty", "dept", "programme", "level", "state", "evidence", "flag", "basis", "paid", "q"] as const;
const ROSTER_KEYS = ["faculty", "dept", "programme", "level", "category", "pay", "reg", "scope", "q"] as const;
const REPORT_KEYS = ["group", "faculty", "dept", "programme", "level", "category", "state", "pay", "reg"] as const;
export const QUEUE_PARAMS = QUEUE_KEYS;
export const ROSTER_PARAMS = ROSTER_KEYS;
export const REPORT_PARAMS = REPORT_KEYS;

const ALLOWED: Record<string, string[] | "number" | "text"> = {
  state: ["PENDING_VERIFICATION", "CONFIRMED_OUTSTANDING", "NOT_OUTSTANDING", "REJECTED", "ANY"],
  evidence: ["RESULT_FAILED", "RESULT_PASSED", "RESULT_AWAITED", "NO_RESULT"],
  flag: ["REVIEW", "CLARIFICATION"],
  basis: ["CARRY_OVER", "AUTHORISED", "STUDENT_SELECTED"],
  paid: ["PAID", "UNPAID"],
  pay: ["NOT_STARTED", "UNPAID", "PART_PAID", "PAID"],
  reg: ["REGISTERED", "NOT_REGISTERED"],
  scope: ["SELECTED", "ELIGIBLE", "ALL"],
  category: ["FINAL_YEAR", "SPILLOVER", "AUTHORISED"],
  group: ["ALL", "FACULTY", "DEPARTMENT", "PROGRAMME", "LEVEL", "CATEGORY"],
  level: "number",
  faculty: "text", dept: "text", programme: "text", q: "text",
};

/** the filters of an address, each kept only when its value is one the API takes (never forwarded as the person typed it) */
export function pickFilters(sp: Record<string, string | string[] | undefined>, keys: readonly string[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (const k of keys) {
    const raw = sp[k];
    const v = typeof raw === "string" ? raw.trim() : "";
    if (!v) continue;
    const rule = ALLOWED[k];
    if (Array.isArray(rule)) { if (rule.includes(v)) out[k] = v; continue; }
    if (rule === "number") { if (/^\d{2,4}$/.test(v)) out[k] = v; continue; }
    if (k === "q") { out[k] = v.slice(0, 80); continue; }
    if (/^[A-Za-z0-9 ._&/-]{1,60}$/.test(v)) out[k] = v;
  }
  return out;
}

/** the page number of an address (1-based), at least 1 */
export function pageOf(raw: string | string[] | undefined): number {
  const n = typeof raw === "string" ? Number(raw) : 1;
  return Number.isInteger(n) && n >= 1 && n <= 100000 ? n : 1;
}

/** a query string from the values given, leaving out what is empty */
export function queryString(values: Record<string, string | number | null | undefined>): string {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(values)) if (v !== null && v !== undefined && String(v) !== "") q.set(k, String(v));
  return q.toString();
}

/** the desk's own address for a view with its filters: the session, the view, the filters and the page (1 is left out) */
export function deskHref(session: string | null, view: DeskView, filters: Record<string, string> = {}, page = 1): string {
  const qs = queryString({ session, view, ...filters, page: page > 1 ? page : null });
  return `/summer${qs ? `?${qs}` : ""}`;
}

/** the queue's default state: the work to do for the offices that verify, everything for those that read */
export function defaultQueueState(maySet: boolean): string {
  return maySet ? "PENDING_VERIFICATION" : "ANY";
}

/** a row as the decision's preview reads it: the queue's own charge columns (registration.summer_queue) */
export interface DecisionPreviewRow {
  student_id?: string | null; charge_state?: string | null;
  /** the amount of the selection's own live COURSE charge (DUE or PAID); null when it has none */
  charge_amount?: Money;
  /** the amount of the student's PAID programme charge of the session; null when none is PAID */
  programme_fee_paid?: Money;
  /** how many of the student's selections of the session hold a COURSE charge that is DUE or PAID */
  courses_standing?: number | string | null;
}

const given = (m: unknown): boolean => m != null && m !== "";

/** what the Office is told before it decides Not outstanding or Reject, from the rows ticked: the fee of each paid course is held as a
 *  Summer credit and its entry withdrawn, and — as registration.summer_verify does — a student's paid programme fee is held too when
 *  the decision takes the last of their courses that stand (a selection whose course charge is DUE or PAID). The sum is given only when
 *  every paid row says its amount and, for each student with a paid programme fee, how many of their courses stand; otherwise the words
 *  say what is held without a figure, never a guess. */
export function decisionPreview(rows: DecisionPreviewRow[]): { count: number; paid: number; amount: number | null; programme: number; programmeStudents: number; sentence: string } {
  const paidRows = rows.filter((r) => r.charge_state === "PAID");
  const coursesKnown = paidRows.every((r) => given(r.charge_amount));
  const courseSum = paidRows.reduce((s, r) => s + num(r.charge_amount), 0);
  // the programme fee: for each student, the rows ticked that hold a live course charge, against how many of theirs stand
  const live = new Map<string, DecisionPreviewRow[]>();
  for (const r of rows) {
    if (r.charge_state !== "PAID" && r.charge_state !== "DUE") continue;
    const k = r.student_id ?? "";
    const list = live.get(k);
    if (list) list.push(r); else live.set(k, [r]);
  }
  let programme = 0;
  let programmeStudents = 0;
  let programmeKnown = true;
  for (const list of live.values()) {
    const fee = list.find((r) => given(r.programme_fee_paid))?.programme_fee_paid;
    if (!given(fee)) continue;                                    // no programme fee paid: nothing of it to hold
    const standing = list.find((r) => given(r.courses_standing))?.courses_standing;
    if (!given(standing)) { programmeKnown = false; continue; }
    if (list.length >= Number(standing)) { programme += num(fee); programmeStudents += 1; }
  }
  const amount = coursesKnown && programmeKnown ? courseSum + programme : null;
  const head = `${plural(rows.length, "course")}, ${paidRows.length} paid`;
  const programmeWords = `the programme fee of ${plural(programmeStudents, "student")} whose last Summer course it takes (${naira(programme)})`;
  const unknownProgramme = "A paid programme fee is held too when the decision takes a student's last Summer course.";
  let sentence: string;
  if (amount !== null) {
    sentence = amount === 0 && paidRows.length === 0
      ? `${head}: nothing has been paid, so nothing is held.`
      : paidRows.length > 0
        ? `${head}: ${naira(amount)} will be held as Summer credit and the entries withdrawn.${programme > 0 ? ` That includes ${programmeWords}.` : ""}`
        : `${head}: ${naira(amount)} will be held as Summer credit: ${programmeWords}.`;
  } else if (paidRows.length === 0) {
    sentence = `${head}: no course has been paid. ${unknownProgramme}`;
  } else {
    sentence = `${head}: the fee of each paid course will be held as Summer credit and its entry withdrawn.`
      + (!programmeKnown ? ` ${unknownProgramme}` : programme > 0 ? ` So is ${programmeWords}.` : "");
  }
  return { count: rows.length, paid: paidRows.length, amount, programme, programmeStudents, sentence };
}

/** the reason a decision needs: ten characters or more, trimmed (the student is shown it) */
export const REASON_MIN = 10;
export function reasonOk(reason: string | null | undefined): boolean {
  return (reason ?? "").trim().length >= REASON_MIN;
}

/** the ids in chunks of at most n (the API takes 200 a decision) */
export function chunk<T>(items: T[], n = 200): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += n) out.push(items.slice(i, i + n));
  return out;
}

/** the file name a download carries, from its Content-Disposition (never a path) */
export function dispositionName(header: string | null | undefined, fallback: string): string {
  const m = /filename\*?=(?:UTF-8'')?"?([^";]+)"?/i.exec(header ?? "");
  const name = m ? decodeURIComponent(m[1]).replace(/[\\/]/g, "-").trim() : "";
  return name || fallback;
}

/** the queue's row — registration.summer_queue, as the API gives it */
export interface SummerSelectionRow {
  total?: number; selection_id: string; student_id: string; matric_no: string | null; name: string; programme: string | null;
  dept_code: string | null; faculty_code: string | null; level: number | null; summer_level: number | null; category: string | null;
  course_code: string; title: string | null; units: number | null; course_semester: number | null; original_session: string | null;
  original_semester: number | null; original_source: "RESULTS" | "STUDENT" | null; basis: SummerBasis; state: Verification;
  verified_via: VerifiedVia | null; decision_reason: string | null; evidence: Evidence | null; evidence_at: string | null; needs_review: boolean;
  review_flag: ReviewFlag | null; clarification_open: boolean; clarification_note: string | null; student_note: string | null;
  charge_state: string | null; entry_live: boolean | null; selected_at: string | null; decided_office: string | null; decided_at: string | null;
  /** the amount of the selection's own live COURSE charge (DUE or PAID); null when it has none — with the two below, the sum a decision holds */
  charge_amount?: Money;
  /** the amount of the student's PAID programme charge of the session; null when none is PAID */
  programme_fee_paid?: Money;
  /** how many of the student's selections of the session hold a COURSE charge that is DUE or PAID */
  courses_standing?: number | null;
}
export interface SummerFacet { code: string; name: string }
export interface SummerSelectionsView {
  session: string; total: number; page: number; size: number; rows: SummerSelectionRow[];
  facets: { faculties: SummerFacet[]; departments: SummerFacet[]; programmes: SummerFacet[]; levels: number[] };
  counts: { PENDING_VERIFICATION: number; CONFIRMED_OUTSTANDING: number; NOT_OUTSTANDING: number; REJECTED: number; review: number; clarification: number };
}
export interface SummerDecideAnswer { batch: string; decided: number; unchanged: number; credited: Money; withdrawn: number; refused: { id: string; code: string; message: string }[] }
export interface SummerReconcileAnswer { read: number; left: number; confirmed: number; takenBack: number; flagged: number; reverted: number; unchanged: number; since?: string }
export interface SummerReviewRow {
  id?: string; batch_ref: string; action: string; from_state: string | null; to_state: string | null; via: string; evidence: string | null; reason: string | null;
  note: string | null; money_effect: string; credit_amount: Money; removal_ref: string | null; actor_id?: string | null; actor_name?: string | null; actor_office: string | null; at: string;
}
export interface SummerSelectionDetail {
  selection: SummerSelectionRow;
  student: { id: string; number: string | null; name: string; programme: string | null; department: string | null; faculty: string | null; level: number | null; summerLevel: number | null; category: string | null };
  evidenceRows: { course_code: string; session: string; semester: number; outcome: string | null; points: number | null }[];
  history: SummerReviewRow[];
  others: { selection_id: string; course_code: string; title: string | null; units: number | null; basis: SummerBasis; state: Verification; evidence: Evidence | null; needs_review: boolean }[];
  charge: { state: string | null; amount: Money; paidReference: string | null; receiptNo: string | null } | null;
}

/** the roster's row — registration.summer_roster, as the API gives it */
export interface SummerRosterRow {
  total?: number; student_id: string; matric_no: string | null; name: string; programme_code: string | null; programme: string | null; dept_code: string | null;
  department: string | null; faculty_code: string | null; faculty: string | null; level: number | null; summer_level: number | null; eligible: boolean | null;
  category: string | null; reason: string | null; results: number | null; selected: number; pending: number; confirmed: number; not_outstanding: number;
  rejected: number; flagged: number; clarifications: number; courses_paid: number; units: number; programme_fee_due: Money; programme_fee_paid: Money;
  course_fees_due: Money; course_fees_paid: Money; payment_state: string; registration_status: string | null; courses_registered: number;
  results_published: number; results_passed: number; results_failed: number;
}
/** the figures over the whole roster (the ALL row of summer_report, with the names V735 gave the ones that survive): each may be absent */
export interface SummerRosterSummary {
  eligible?: number; commenced?: number; completed?: number; registeredCourses?: number; owing?: number; paid?: number;
  programmeFeesPaid?: Money; courseFeesPaid?: Money; feesOutstanding?: Money; resultsPublished?: number; resultsPassed?: number; resultsFailed?: number;
  missingHistoryStudents?: number; pending?: number; confirmed?: number; notOutstanding?: number; rejected?: number; coursesSelected?: number; creditsOpen?: Money; feesPaid?: Money;
}
export interface SummerIssue { id: string; student_id: string; number: string | null; name: string; course_code: string | null; error: string; raised_at: string; reference: string | null }
export interface SummerRosterView {
  session: string; period: SummerPeriod | null; identifiedAt: string | null; total: number; page: number; size: number; rows: SummerRosterRow[];
  issues?: SummerIssue[]; summary: SummerRosterSummary | null;
}

/** a report row: the figures of one group of students (registration.summer_report, camelCase) */
export interface SummerReportRow {
  groupCode: string | null; groupName: string | null; eligible: number; eligibleFinalYear: number; eligibleSpillover: number; eligibleAuthorised: number;
  missingHistoryStudents: number; studentsSelected: number; coursesSelected: number; pending: number; confirmed: number; notOutstanding: number; rejected: number;
  clarifications: number; flagged: number; registeredStudents: number; registeredCourses: number; unitsSelected: number; studentsNotStarted: number;
  studentsUnpaid: number; studentsPartPaid: number; studentsPaid: number; feesPaid: Money; feesDue: Money; creditsOpen: Money; selectionsNoResult: number;
}
export interface SummerReportView { session: string; group: string; rows: SummerReportRow[]; scope?: { office: string | null; faculty: string | null; dept: string | null }; at?: string | null }

/** "students_part_paid" → "studentsPartPaid" on the keys of a row, so a report row reads the same whichever spelling the API used */
export function camelKeys<T = Record<string, unknown>>(row: Record<string, unknown>): T {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(row)) out[k.replace(/_([a-z0-9])/g, (_, c: string) => c.toUpperCase())] = v;
  return out as T;
}

const REPORT_NUMBERS = ["eligible", "eligibleFinalYear", "eligibleSpillover", "eligibleAuthorised", "missingHistoryStudents", "studentsSelected", "coursesSelected", "pending",
  "confirmed", "notOutstanding", "rejected", "clarifications", "flagged", "registeredStudents", "registeredCourses", "unitsSelected", "studentsNotStarted", "studentsUnpaid",
  "studentsPartPaid", "studentsPaid", "selectionsNoResult"] as const;

/** a report row as the screen reads it: camelCase, every count a number (a figure the API left out is 0) */
export function reportRow(raw: Record<string, unknown>): SummerReportRow {
  const r = camelKeys<Record<string, unknown>>(raw);
  const out: Record<string, unknown> = { groupCode: r.groupCode ?? null, groupName: r.groupName ?? null, feesPaid: r.feesPaid ?? 0, feesDue: r.feesDue ?? 0, creditsOpen: r.creditsOpen ?? 0 };
  for (const k of REPORT_NUMBERS) out[k] = Number(r[k] ?? 0);
  return out as unknown as SummerReportRow;
}

/** the sum of a column of report rows, for the totals line of a grouped report */
export function reportTotal(rows: SummerReportRow[], key: (typeof REPORT_NUMBERS)[number] | "feesPaid" | "feesDue" | "creditsOpen"): number {
  return rows.reduce((s, r) => s + num(r[key] as Money), 0);
}

/** one line saying whose figures a report shows, for an office held to its own unit */
export function scopeLine(scope: { office?: string | null; faculty?: string | null; dept?: string | null } | null | undefined): string | null {
  if (!scope) return null;
  if (scope.dept) return `Your office sees the department ${scope.dept} only.`;
  if (scope.faculty) return `Your office sees the faculty ${scope.faculty} only.`;
  return null;
}

/** the decisions of the bulk bar, with the words the dialog and the notice use */
export const DECISION_WORD: Record<string, { label: string; done: string; needsReason: boolean }> = {
  CONFIRM: { label: "Confirm", done: "confirmed outstanding", needsReason: false },
  NOT_OUTSTANDING: { label: "Not outstanding", done: "found not outstanding", needsReason: true },
  REJECT: { label: "Reject", done: "rejected", needsReason: true },
  REOPEN: { label: "Reopen", done: "reopened", needsReason: false },
};

/** the Summer's own words of a review row's action in the selection's history */
export const REVIEW_ACTION_WORD: Record<string, string> = {
  CONFIRMED: "Confirmed", NOT_OUTSTANDING: "Found not outstanding", REJECTED: "Rejected", REOPENED: "Reopened", CLARIFICATION_ASKED: "Clarification asked",
  CLARIFICATION_ANSWERED: "Student answered", FLAGGED: "Flagged for review", FLAG_CLEARED: "Flag cleared",
};

/* ───────────────────────── the Summer's examination session on the examinations desk ───────────────────────── */

/** the place of the Summer Semester's examination session: the third semester's main, full-time sitting of a session (the row
 *  registration.summer_set_period dates and the Summer's examination gate reads) */
export function isSummerSitting(e: { semester: number | string; kind: string; stream?: string | null }): boolean {
  return Number(e.semester) === 3 && e.kind === "MAIN" && (e.stream ?? "REGULAR") === "REGULAR";
}

/** what the examinations desk's edit may do to a row's session, semester, type and students, from the Summer's examination gate (V779,
 *  SUMMER_EXAM_IDENTITY): "summer-fixed" — the Summer's own sitting, open or with its sheets released, keeps its place; "into-summer" —
 *  an open or released row the edit would move into that place (refused for a session that has a Summer); null — nothing of the
 *  Summer's. A row with score sheets keeps its place anyway (the desk's own rule) */
export function summerSittingEdit(
  row: { semester: number; kind: string; stream?: string | null; state: string; sheetsReleasedAt?: string | null },
  to: { semester: number | string; kind: string; stream?: string | null },
): "summer-fixed" | "into-summer" | null {
  const live = row.state === "OPEN" || !!row.sheetsReleasedAt;
  if (!live) return null;
  if (isSummerSitting(row)) return "summer-fixed";
  return isSummerSitting(to) ? "into-summer" : null;
}
