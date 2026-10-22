/** V637: a spillover student's fees, as the Fees page, the dashboard and the Bursary's list say them. A spillover student (SP1/SP2 at
 *  the final level, or above it) pays a semester's spillover fee only for a semester they register a course in (V616), never a full
 *  session for being in spillover. The server works out every figure; this file only words them. Node-tested. */

export interface SpilloverCourse { code: string; title: string; units: number; session: string }
export interface SpilloverSemester { semester: number; fee: number | string; registered: boolean; carryovers: number; courses: SpilloverCourse[] }
export interface SpilloverPanel {
  session: string; state: string | null; year: number | null; label: string; registeredSemesters: number[];
  semesters: SpilloverSemester[]; sessionFee: number | string; due: number | string; paid: number | string; balance: number | string;
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
  if (s.registered) {
    return num(s.fee) > 0 ? `${carry}A course is registered in it, so its spillover fee is owed.` : `${carry}A course is registered in it; no spillover fee is stated for your programme yet.`;
  }
  return num(s.fee) > 0
    ? `${carry}Nothing is owed for it unless you register a course in it; its spillover fee is then owed.`
    : `${carry}Nothing is owed for it unless you register a course in it.`;
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
