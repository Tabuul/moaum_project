/** V735 — the Summer Semester for final-year and spillover students: the words and sums every Summer screen shares (the student's
 *  page, the Academic Office's desk, the Bursary's fees). The rules are the database's (registration.summer_eligibility,
 *  summer_courses, summer_account); nothing here decides who may take the Summer or what is owed — it says what the server said. */

export type Money = number | string | null | undefined;

export interface SummerPeriod {
  session: string; state: "PLANNED" | "OPEN" | "CLOSED"; registration_opens: string | null; registration_closes: string | null;
  exams_from: string | null; exams_to: string | null; results_due: string | null;
  categories: string[] | null; programmes: string[] | null; levels: number[] | null;
  set_at?: string | null; reason?: string | null; open_now?: boolean;
  exam_session_id?: string | null; exam_state?: string | null;
}

export interface SummerEligibility { eligible: boolean; category: string | null; outstanding: number; reason: string | null }

export interface SummerCourse {
  course_code: string; title: string | null; units: number | null; course_semester: number | null; both_semesters: boolean;
  original_session: string | null; original_semester: number | null; attempts: number; basis: "CARRY_OVER" | "AUTHORISED";
  status: "OUTSTANDING" | "SELECTED" | "REGISTERED"; selectable: boolean; reason: string | null; course_fee: Money;
}

export interface SummerAccount {
  session: string; programmeFee: Money; programmeFeeState: "DUE" | "PAID" | null; coursesSelected: number; coursesPaid: number;
  courseFeesDue: Money; programmeFeeDue: Money; due: Money; paid: Money; openReference: string | null;
  /** V739: the open reference's own amount (an open reference is shown only when it may be paid) and the unapplied Summer credit */
  openAmount?: Money; credit?: Money;
  registration: { id: string; status: string; approvedAt: string | null; courses: number } | null;
}

export interface SummerRegistered {
  course_code: string; title: string | null; units: number | null; course_semester: number | null; original_session: string | null;
  original_semester: number | null; status: string; paid_reference: string | null; receipt_no: string | null; registration_status: string;
  lecturer: string | null;
}

export interface SummerPayment { reference: string; amount: Money; purpose: string; confirmed_at: string | null; receipt_no: string | null; generated_at: string; expires_at: string | null }

export interface MySummer {
  session: string | null;
  period: SummerPeriod | null;
  eligibility?: SummerEligibility;
  courses?: SummerCourse[];
  fee?: { fee_id: string; programme_fee: Money; course_fee: Money } | null;
  account?: SummerAccount;
  registered?: SummerRegistered[];
  payments?: SummerPayment[];
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

export const CATEGORY_WORD: Record<string, string> = {
  FINAL_YEAR: "Final year",
  SPILLOVER: "Spillover",
  BEYOND_DURATION: "Beyond the programme's length",
  AUTHORISED: "Authorised by the Academic Office",
};
export const CATEGORIES = ["FINAL_YEAR", "SPILLOVER", "BEYOND_DURATION", "AUTHORISED"] as const;

export function categoryWord(c: string | null | undefined): string {
  return c ? CATEGORY_WORD[c] ?? c : "—";
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
  NOT_FINAL_OR_SPILLOVER: "The Summer Semester is for students in their final year, in spillover, or past the programme's length.",
  CATEGORY_NOT_IN_SUMMER: "This Summer Semester is not open to students in your position.",
  NO_OUTSTANDING_COURSE: "You have no outstanding course: every course you registered is passed, or its result is awaited.",
};

export function notEligibleWord(reason: string | null | undefined): string {
  return reason ? NOT_ELIGIBLE_WORD[reason] ?? reason : "You are not eligible for this Summer Semester.";
}

/** why a course is not selectable now */
export const COURSE_REASON_WORD: Record<string, string> = {
  COURSE_UNKNOWN: "Not in the course catalogue",
  COURSE_ENDED: "The course has ended; ask your department",
  PASSED: "Passed",
  RESULT_AWAITED: "Its result this session is awaited",
  ALREADY_REGISTERED: "Registered",
  ALREADY_SELECTED: "Selected — pay to register",
};

export function courseReasonWord(r: string | null | undefined): string {
  return r ? COURSE_REASON_WORD[r] ?? r : "";
}

export function semesterWord(n: number | null | undefined): string {
  return n === 1 ? "First" : n === 2 ? "Second" : n === 3 ? "Summer" : "—";
}

/** "First semester, 2024/2025" — where a course was last failed */
export function failedInWord(c: Pick<SummerCourse, "original_session" | "original_semester" | "basis">): string {
  if (c.basis === "AUTHORISED" && !c.original_session) return "Named by the Academic Office";
  if (!c.original_session) return "—";
  return `${semesterWord(c.original_semester)} semester, ${c.original_session}`;
}

export const PERIOD_WORD: Record<string, [string, "grey" | "info" | "ok" | "bad" | "warn"]> = {
  PLANNED: ["Planned", "grey"],
  OPEN: ["Open", "ok"],
  CLOSED: ["Closed", "bad"],
};

export function periodWords(p: SummerPeriod | null | undefined): [string, "grey" | "info" | "ok" | "bad" | "warn"] {
  if (!p) return ["Not set", "grey"];
  if (p.state === "OPEN" && p.open_now === false) return ["Open — outside its dates", "warn"];
  return PERIOD_WORD[p.state] ?? [p.state, "grey"];
}

/** what selecting these courses adds to what is owed: the programme fee once a Summer (unless charged already), and a fee a course */
export function selectionCost(picked: number, account: Pick<SummerAccount, "programmeFeeState"> | null | undefined,
                              fee: { programme_fee: Money; course_fee: Money } | null | undefined): number {
  if (!fee || picked <= 0) return 0;
  const programme = account?.programmeFeeState ? 0 : num(fee.programme_fee);
  return programme + picked * num(fee.course_fee);
}

/** the student's next step, in words */
/** "1 December 2026" from a calendar date */
export function dayWord(iso: string): string {
  return new Date(`${iso.slice(0, 10)}T00:00:00Z`).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric", timeZone: "UTC" });
}

export function nextStep(d: MySummer, today: string = new Date().toISOString().slice(0, 10)): string {
  const a = d.account;
  const p = d.period;
  if (!p) return "No Summer Semester is set.";
  if (!d.eligibility?.eligible && !(a && (num(a.due) > 0 || num(a.paid) > 0))) return notEligibleWord(d.eligibility?.reason);
  // V739: after the close nothing more is taken — an unpaid selection is removed, never "paid"
  if (a && num(a.due) > 0) return p.open_now ? `Pay ${naira(a.due)} to register the courses you selected.` : "Registration is closed: remove the course you selected and did not pay; nothing more is taken.";
  if (!p.open_now) {
    // V739: an open or planned Summer before its window says when it opens, not that it is closed
    if (p.state !== "CLOSED" && p.registration_opens && today < p.registration_opens.slice(0, 10)) return `Registration opens on ${dayWord(p.registration_opens)}.`;
    return p.state === "PLANNED" ? "Registration has not opened yet." : "Registration is closed.";
  }
  if (!d.fee) return "The Bursary has not published the Summer Semester fees yet.";
  const left = (d.courses ?? []).filter((c) => c.selectable).length;
  if (a && a.coursesPaid > 0) return left ? "Registered. You may add more of your outstanding courses." : "Registered for every outstanding course you may take.";
  return left ? "Select your outstanding courses, then pay." : "No outstanding course can be selected now.";
}

/** the payment state of a row on the desk */
export const PAYMENT_STATE_WORD: Record<string, [string, "grey" | "info" | "ok" | "bad" | "warn"]> = {
  NOT_STARTED: ["Not started", "grey"],
  UNPAID: ["Unpaid", "bad"],
  PART_PAID: ["Part paid", "warn"],
  PAID: ["Paid", "ok"],
};

export function paymentStateWords(s: string | null | undefined): [string, "grey" | "info" | "ok" | "bad" | "warn"] {
  return (s && PAYMENT_STATE_WORD[s]) || ["—", "grey"];
}

export const FEE_STATE_WORD: Record<string, [string, "grey" | "info" | "ok" | "bad" | "warn"]> = {
  DRAFT: ["Draft", "warn"],
  PUBLISHED: ["Published", "ok"],
  WITHDRAWN: ["Withdrawn", "grey"],
};

/** the session's Summer path segment pair: "2025/2026" → "2025/2026" (the API takes /{session}/{year}) */
export function sessionPath(session: string): string {
  return session.split("/").map(encodeURIComponent).join("/");
}
