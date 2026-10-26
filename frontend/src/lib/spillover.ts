/** V637: a spillover student's fees, as the Fees page, the dashboard and the Bursary's list say them. A spillover student (SP1/SP2 at
 *  the final level, or above it) pays a semester's spillover fee only for a semester they register a course in (V616), never a full
 *  session for being in spillover. The server works out every figure; this file only words them. Node-tested. */

export interface SpilloverCourse { code: string; title: string; units: number; session: string }
/** V664: where one semester stands — its own fee, the payments applied to it (school fees paid go to the whole-session item first,
 *  then the first semester, then the second, as the registration gate reads them), what is left, and whether it is ready */
export type SemesterFeeStatus = "PAID" | "PART_PAID" | "PAYMENT_REQUIRED" | "NOT_STATED" | "NOT_REGISTERED" | "NOTHING_OWED";
export interface SpilloverSemester {
  semester: number; fee: number | string; registered: boolean; carryovers: number; courses: SpilloverCourse[];
  owed?: number | string; paid?: number | string; outstanding?: number | string; status?: SemesterFeeStatus; cleared?: boolean;
  /** what is still to pay for the semester to be cleared — anything earlier left unpaid, and its own */
  toClear?: number | string;
}
export interface SpilloverPanel {
  session: string; state: string | null; year: number | null; label: string; registeredSemesters: number[];
  semesters: SpilloverSemester[]; sessionFee: number | string; due: number | string; paid: number | string; balance: number | string;
  sessionOwed?: number | string; sessionPaid?: number | string;
}

const SEM = ["", "First", "Second", "Third"];
export const semesterWord = (n: number) => `${SEM[n] ?? `Semester ${n}`} semester`;
const num = (v: unknown) => Number(v ?? 0);

/** what the student is asked to pay for, and whether it is paid */
export type SpilloverStatus = "NOTHING_YET" | "PAYMENT_REQUIRED" | "PAYMENT_VERIFIED" | "NOT_STATED";

export function spilloverStatus(sp: SpilloverPanel): SpilloverStatus {
  const registered = sp.semesters.filter((s) => s.registered);
  if (!registered.length) return "NOTHING_YET";
  if (num(sp.balance) >= 1) return "PAYMENT_REQUIRED";
  if (num(sp.due) <= 0 && registered.every((s) => num(s.fee) <= 0)) return "NOT_STATED";
  return "PAYMENT_VERIFIED";
}

/** the heading: "SP1 – First semester spillover fee", "SP1 – First & second semester spillover fees", or the SP year alone */
export function spilloverTitle(sp: SpilloverPanel): string {
  const reg = sp.semesters.filter((s) => s.registered).map((s) => s.semester).sort();
  if (!reg.length) return `${sp.label} · spillover`;
  if (reg.length === 1) return `${sp.label} – ${semesterWord(reg[0])} spillover fee`;
  return `${sp.label} – ${reg.map((n) => SEM[n] ?? n).join(" & ")} semester spillover fees`;
}

/** one semester's line: what it would cost, whether it is owed, and the carry-overs that belong to it */
export function semesterLine(s: SpilloverSemester): string {
  const carry = s.carryovers ? `${s.carryovers} carry-over course${s.carryovers === 1 ? "" : "s"} from this semester. ` : "";
  // V664: the server says where the semester stands; its own payment, never another semester's
  if (s.status === "PAID") return `${carry}A course is registered in it and its spillover fee is paid.`;
  if (s.status === "PART_PAID" || s.status === "PAYMENT_REQUIRED") {
    return `${carry}A course is registered in it: ${nairaWords(s.outstanding)} of its spillover fee is still to pay. A payment for another semester does not cover it.`;
  }
  if (s.registered) {
    return num(s.fee) > 0 ? `${carry}A course is registered in it, so its spillover fee is owed.` : `${carry}A course is registered in it; no spillover fee is stated for your programme yet.`;
  }
  return num(s.fee) > 0
    ? `${carry}Nothing is owed for it unless you register a course in it; its spillover fee is then owed.`
    : `${carry}Nothing is owed for it unless you register a course in it.`;
}

const nairaWords = (v: unknown) => `₦${num(v).toLocaleString("en-NG", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

/** V664: one semester's state, as the semester row and the registration page say it */
export const SEMESTER_STATUS_WORDS: Record<SemesterFeeStatus, [string, "ok" | "bad" | "info" | "warn" | "grey"]> = {
  PAID: ["Paid · ready for registration", "ok"],
  PART_PAID: ["Part paid · payment required", "bad"],
  PAYMENT_REQUIRED: ["Payment required", "bad"],
  NOT_STATED: ["Fee not yet stated", "warn"],
  NOT_REGISTERED: ["Owed once a course is saved", "info"],
  NOTHING_OWED: ["Nothing owed", "grey"],
};

/** V664: what the registration page says about the semester being registered — the obligation, paid, what is left, and what to do */
export function registeringWords(s: SpilloverSemester): { title: string; body: string; pay: boolean; amount: number } {
  const Which = semesterWord(s.semester);          // "Second semester"
  const which = Which.toLowerCase();                // mid-sentence
  const amount = num(s.toClear ?? s.outstanding);
  switch (s.status) {
    case "PAID":
      return { title: `${which.toUpperCase()} SPILLOVER FEE PAID`, pay: false, amount,
        body: `${Which} spillover fee ${nairaWords(s.owed)} is paid. You can register your ${which} courses.` };
    case "PART_PAID":
    case "PAYMENT_REQUIRED":
      return { title: `${which.toUpperCase()} PAYMENT REQUIRED`, pay: true, amount,
        body: `${Which} registration requires payment of the ${which} spillover fee: ${nairaWords(s.owed)} due, ${nairaWords(s.paid)} paid, ${nairaWords(s.outstanding)} outstanding. `
          + (num(s.toClear) > num(s.outstanding) + 0.5 ? `With what is still owed before it, ${nairaWords(s.toClear)} is to pay. ` : "")
          + "A payment for another semester does not cover it. Pay it, then submit; your courses stay on the draft meanwhile." };
    case "NOT_STATED":
      return { title: `${which.toUpperCase()} SPILLOVER FEE NOT YET STATED`, pay: false, amount,
        body: `No spillover fee is stated for the ${which} for your programme yet; the Bursary states it, and the registration waits for it.` };
    case "NOTHING_OWED":
      return { title: `NOTHING OWED FOR THE ${which.toUpperCase()} YET`, pay: false, amount,
        body: `You have no carry-over course from the ${which}. Nothing is owed for it unless you register a course in it.` };
    default:
      return { title: `IN SPILLOVER, YOU PAY FOR THE SEMESTERS YOU REGISTER`, pay: false, amount,
        body: `${s.carryovers ? `You have ${s.carryovers} ${which} carry-over course${s.carryovers === 1 ? "" : "s"}. ` : ""}Nothing is owed for the ${which} until a course of it is saved on your registration`
          + (num(s.fee) > 0 ? `; its spillover fee of ${nairaWords(s.fee)} is then payable, and the registration is submitted once it is paid.` : ".")
          + " A payment for another semester does not cover it." };
  }
}

export const STATUS_WORDS: Record<SpilloverStatus, [string, "ok" | "bad" | "info" | "warn"]> = {
  NOTHING_YET: ["Nothing to pay until you register", "info"],
  PAYMENT_REQUIRED: ["Payment required", "bad"],
  PAYMENT_VERIFIED: ["Payment verified", "ok"],
  NOT_STATED: ["Spillover fee not yet stated", "warn"],
};

/** the Bursary's list: where a spillover student stands for the session */
export type ListState = "NOT_REGISTERED" | "NO_CHARGE" | "OWES" | "PART_PAID" | "PAID" | "PAID_ABOVE";
export const LIST_STATE_WORDS: Record<ListState, [string, "ok" | "bad" | "info" | "warn" | "grey"]> = {
  NOT_REGISTERED: ["No course registered", "grey"],
  NO_CHARGE: ["No spillover fee stated", "warn"],
  OWES: ["Owes", "bad"],
  PART_PAID: ["Part paid", "warn"],
  PAID: ["Paid", "ok"],
  PAID_ABOVE: ["Paid above what is owed", "info"],
};
