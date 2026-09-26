/** Deferment (V259, revised by V264): the shapes the API returns, the words every screen uses for them, the approval
 *  timeline, and the document viewer that opens a supporting document in a modal on the same page (never a new tab,
 *  never a public URL: the bytes come through the authorised door and live only in this browser). */
import { Pil } from "@/components/proto/ui";

export interface Deferment {
  id: string; reference: string; student_id: string; kind: "SEMESTER" | "SESSION"; session: string; semester: number | null;
  reason_code: string; reason: string; needs_document: boolean; needs_words: boolean; explanation: string | null; declared: boolean; state: string;
  extension_of: string | null; period_from: string | null; return_session: string | null; return_semester: number | null; return_on: string | null;
  submitted_at: string | null; dept_at: string | null; dept_note: string | null; fac_at: string | null; fac_note: string | null;
  decided_at: string | null; decision_note: string | null; correction_note: string | null; cancel_note: string | null;
  prior_status: string | null; activated_at: string | null; returned_at: string | null; return_note: string | null; created_at: string; updated_at: string;
  bursary_at: string | null; bursary_note: string | null; bursary_last_fee_amount: number | null; bursary_last_fee_ref: string | null; bursary_last_fee_at: string | null;
  bursary_last_fee_session: string | null; bursary_balance: number | null; bursary_balance_session: string | null;
  batch_id: string | null; forwarded_at: string | null; dvc_at: string | null; dvc_note: string | null; returned_from_state: string | null; returned_by_office: string | null;
  extension_semesters: number | null; courses_affected: number | null; effect_applied_at: string | null; fee_id: string | null;
  surname: string; other_names: string; number: string; level: number; student_status: string; entry_mode: string; entry_session: string;
  programme_code: string; programme: string; dept_code: string; department: string; faculty_code: string; faculty: string; college_code: string | null;
  return_status: string | null; stage_label: string; stage_office: string | null;
  dept_officer: string | null; faculty_officer: string | null; decided_officer: string | null; returned_officer: string | null;
  bursary_officer: string | null; dvc_officer: string | null; forwarded_officer: string | null;
  fee_reference: string | null; fee_amount: number | null; fee_receipt_no: string | null; fee_confirmed_at: string | null; fee_state: string | null;
  batch_reference: string | null; batch_forwarded_at: string | null; downloadable?: boolean;
}
export interface DefermentDoc { id: string; kind: string; filename: string; content_type: string; size_bytes: number; uploaded_at: string; verified_at: string | null }
export interface DefermentEvent { action: string; from_state: string | null; to_state: string | null; actor_office: string | null; note: string | null; at: string; actor: string | null }
export interface FeeView { id: string; reference: string; amount: number; state: string; created_at: string; expires_at: string | null; confirmed_at: string | null; receipt_no: string | null; used_by: string | null; fee_now: number }
export interface Timeline {
  entry_session: string; entry_level: number; final_level: number; semesters_per_session: number;
  original_semesters: number; original_completion_session: string; original_completion_semester: number; original_completion_on: string | null;
  approved_semesters: number; approved_sessions: number; approved_count: number;
  adjusted_semesters: number; adjusted_completion_session: string; adjusted_completion_semester: number; adjusted_completion_on: string | null;
  live_state: string | null; live_return_session: string | null; live_return_semester: number | null; live_return_on: string | null;
}
export interface Effect {
  kind: string; period: string; duration_semesters: number; courses_affected: number; effect_applied_at: string | null; cgpa: number | null;
  extension_semesters: number; original_semesters: number; adjusted_semesters: number; original_completion: string; adjusted_completion: string; adjusted_completion_on: string | null;
  expected_return: string; entry_session: string; matric_no: string | null; applied: boolean;
}
export interface DeferredCourse {
  id: string; deferment_id: string; reference: string; deferment_state: string; course_code: string; title: string; units: number; original_session: string; original_semester: number;
  source: string; status: "DEFERRED" | "REGISTERED" | "COMPLETED"; taken_session: string | null; taken_semester: number | null; grade: string | null; due: boolean;
}
export interface Financials {
  last_fee_amount: number | null; last_fee_ref: string | null; last_fee_at: string | null; last_fee_session: string | null; last_fee_channel: string | null; last_fee_receipt: string | null;
  balance: number | null; due: number | null; paid: number | null; balance_session: string | null; position_status: string | null; has_arrears: boolean | null; found: boolean;
}
export interface Batch {
  id: string; reference: string; session: string | null; semester: number | null; forwarded_at: string; forwarded_by: string | null; office: string | null; note: string | null; count: number;
  forwarded_officer: string | null; awaiting_dvc: number; waiting_sbc: number; approved: number; rejected: number; returned: number; dvc_status: "OPEN" | "DECIDED";
}
export interface DefermentFull extends Deferment {
  documents: DefermentDoc[]; history: DefermentEvent[]; effect: Effect | null; deferredCourses: DeferredCourse[];
  previous?: { reference: string; kind: string; session: string; semester: number | null; state: string; submitted_at: string | null; decided_at: string | null; stage_label: string }[];
  registration?: { session: string; semester: number; status: string; submitted_at: string | null }[];
  fees?: { payable: number; paid: number; outstanding: number; status: string };
  financials?: Financials;
  standing?: { standing?: string; cgpa?: number | null };
  timeline?: Timeline | null;
  may?: Record<string, boolean>;
}
export interface Reason { code: string; label: string; needs_document: boolean; needs_words: boolean }
export interface MyDeferments {
  eligibility: { eligible: boolean; reason: string | null; used: number; allowed: number; live_reference: string | null };
  fee: FeeView | null;
  requests: Deferment[]; reasons: Reason[]; sessions: { name: string; semesters: number; state: string }[];
  current: { session?: string; semester?: number | null }; setting: { max_sessions: number; allow_extension: boolean; fee: number };
  timeline: Timeline | null; deferredCourses: DeferredCourse[];
}

type Kind = "grey" | "info" | "warn" | "ok" | "bad";
/** the official words for each state, as the Registry's procedure names them */
export const STATE: Record<string, [string, Kind]> = {
  DRAFT: ["Draft", "grey"], SUBMITTED: ["WAITING BURSARY ACTION", "info"], CORRECTION_REQUIRED: ["RETURNED FOR CORRECTION", "warn"],
  BURSARY_APPROVED: ["WAITING HOD ACTION", "info"], DEPT_RECOMMENDED: ["WAITING FACULTY ACTION", "info"], FAC_RECOMMENDED: ["WAITING ACADEMIC OFFICE ACTION", "info"],
  FORWARDED_TO_DVC: ["FORWARDED TO DVC", "info"], DVC_APPROVED: ["WAITING SBC ACTION", "warn"],
  APPROVED: ["APPROVED", "ok"], ACTIVE: ["APPROVED · IN FORCE", "ok"], COMPLETED: ["COMPLETED", "ok"], REJECTED: ["REJECTED", "bad"], CANCELLED: ["CANCELLED", "grey"],
};
export const IN_REVIEW = new Set(["SUBMITTED", "BURSARY_APPROVED", "DEPT_RECOMMENDED", "FAC_RECOMMENDED", "FORWARDED_TO_DVC", "DVC_APPROVED"]);
export const OPEN = new Set(["DRAFT", "CORRECTION_REQUIRED"]);
export const LIVE = new Set([...IN_REVIEW, "APPROVED", "ACTIVE"]);
export const OFFICE_OF: Record<string, string> = {
  SUBMITTED: "Bursary", BURSARY_APPROVED: "Head of Department", DEPT_RECOMMENDED: "Faculty", FAC_RECOMMENDED: "Academic Office",
  FORWARDED_TO_DVC: "Deputy Vice-Chancellor (Academic)", DVC_APPROVED: "Senate Business Committee", CORRECTION_REQUIRED: "You", DRAFT: "You",
};
export const RETURN: Record<string, [string, Kind]> = {
  UPCOMING: ["Upcoming", "grey"], DUE: ["Due", "warn"], OVERDUE: ["Overdue", "bad"], RETURNED: ["Returned", "ok"],
};
export const FEE_STATE: Record<string, [string, Kind]> = {
  PENDING: ["PAYMENT PENDING", "warn"], CONFIRMED: ["PAID", "ok"], EXPIRED: ["REFERENCE EXPIRED", "bad"], CANCELLED: ["CANCELLED", "grey"],
};
export const COURSE_STATE: Record<string, [string, Kind]> = { DEFERRED: ["DEFERRED", "info"], REGISTERED: ["REGISTERED", "warn"], COMPLETED: ["COMPLETED", "ok"] };
export const DOC_KIND: Record<string, string> = { MEDICAL: "Medical documentation", FINANCIAL: "Financial evidence", OFFICIAL_LETTER: "Official letter", EMPLOYER_LETTER: "Employer letter", OTHER: "Other supporting evidence" };
export const ACTION_WORD: Record<string, string> = {
  CREATED: "Request opened", UPDATED: "Request changed", DOCUMENT: "Document uploaded", FEE_PAID: "Application fee confirmed", SUBMITTED: "Submitted", RESUBMITTED: "Corrected and resubmitted",
  BURSARY_APPROVE: "Approved by the Bursary", RECOMMEND: "Approved by the Head of Department", FAC_RECOMMEND: "Approved by the Faculty", FORWARD: "Forwarded to the DVC by the Academic Office",
  DVC_APPROVE: "Approved by the Deputy Vice-Chancellor", SBC_APPROVE: "Approved by the Senate Business Committee", APPROVE: "Approved", EFFECT_APPLIED: "Academic effect applied",
  REJECT: "Rejected", CORRECTION: "Returned for correction", CANCEL: "Cancelled", ACTIVATED: "Deferment came into force", RETURNED: "Return confirmed",
  VIEWED: "Opened", DOCUMENT_VIEWED: "Document viewed", DOWNLOADED: "Application downloaded",
};
export const SEM = (n: number | null | undefined) => (n == null ? "" : n === 1 ? "First semester" : n === 2 ? "Second semester" : "Third semester");
export const periodOf = (d: { kind: string; session: string; semester: number | null }) => d.kind === "SESSION" ? `${d.session} session` : `${d.session} · ${SEM(d.semester)}`;
export const returnOf = (d: { return_session: string | null; return_semester: number | null }) => d.return_session ? `${d.return_session} · ${SEM(d.return_semester)}` : "—";
export const dayOf = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }) : "—");
export const whenAt = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
export const naira = (n: number | string | null | undefined) => (n === null || n === undefined ? "—" : `₦${Number(n).toLocaleString("en-NG", { maximumFractionDigits: 0 })}`);

export function StatePil({ state }: { state: string }) {
  const [w, k] = STATE[state] ?? [state, "grey"];
  return <Pil kind={k}>{w}</Pil>;
}
export function ReturnPil({ status }: { status: string | null }) {
  if (!status) return null;
  const [w, k] = RETURN[status] ?? [status, "grey"];
  return <Pil kind={k}>{w}</Pil>;
}
export function FeePil({ state }: { state: string | null | undefined }) {
  if (!state) return <Pil kind="grey">NOT PAID</Pil>;
  const [w, k] = FEE_STATE[state] ?? [state, "grey"];
  return <Pil kind={k}>{w}</Pil>;
}

export function readBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result).split(",")[1] ?? "");
    reader.onerror = () => reject(new Error("read failed"));
    reader.readAsDataURL(file);
  });
}

/** the approval timeline: every desk in the order the procedure names, done · current · to come */
export interface Step { key: string; label: string; when: string | null; who: string | null; note: string | null; done: boolean; current: boolean; failed?: boolean }
export function stepsOf(d: Deferment): Step[] {
  const s = d.state;
  const idx: Record<string, number> = { DRAFT: 0, CORRECTION_REQUIRED: 0, SUBMITTED: 1, BURSARY_APPROVED: 2, DEPT_RECOMMENDED: 3, FAC_RECOMMENDED: 4, FORWARDED_TO_DVC: 5, DVC_APPROVED: 6, APPROVED: 7, ACTIVE: 8, COMPLETED: 9, REJECTED: -1, CANCELLED: -1 };
  const at = idx[s] ?? 0;
  const mk = (key: string, label: string, n: number, when: string | null, who: string | null, note: string | null): Step => ({ key, label, when, who, note, done: !!when || at > n, current: at === n });
  const steps: Step[] = [
    mk("submitted", "Application submitted", 1, d.submitted_at, `${d.surname}, ${d.other_names}`, null),
    mk("bursary", "Bursary approved", 2, d.bursary_at, d.bursary_officer, d.bursary_note),
    mk("hod", "Head of Department approved", 3, d.dept_at, d.dept_officer, d.dept_note),
    mk("faculty", "Faculty approved", 4, d.fac_at, d.faculty_officer, d.fac_note),
    mk("academic", "Forwarded to the DVC by the Academic Office", 5, d.forwarded_at, d.forwarded_officer, d.batch_reference ? `Batch ${d.batch_reference}` : null),
    mk("dvc", "Deputy Vice-Chancellor approved", 6, d.dvc_at, d.dvc_officer, d.dvc_note),
    mk("sbc", "Senate Business Committee approved", 7, ["APPROVED", "ACTIVE", "COMPLETED"].includes(s) ? d.decided_at : null, ["APPROVED", "ACTIVE", "COMPLETED"].includes(s) ? d.decided_officer : null, ["APPROVED", "ACTIVE", "COMPLETED"].includes(s) ? d.decision_note : null),
    mk("active", "Deferment in force", 8, d.activated_at, null, null),
    mk("returned", "Return confirmed", 9, d.returned_at, d.returned_officer, d.return_note),
  ];
  // a waiting stage is the "current" one: the step after the last done
  if (s === "SUBMITTED") steps[1].current = true;
  if (s === "REJECTED" || s === "CANCELLED") {
    const k = s === "REJECTED" ? "Rejected" : "Cancelled";
    steps.push({ key: s.toLowerCase(), label: `${k}${d.returned_by_office ? ` by the ${OFFICE_WORD[d.returned_by_office] ?? d.returned_by_office}` : ""}`, when: s === "REJECTED" ? d.decided_at : d.updated_at, who: s === "REJECTED" ? d.decided_officer : null, note: s === "REJECTED" ? d.decision_note : d.cancel_note, done: true, current: true, failed: true });
  }
  if (s === "CORRECTION_REQUIRED") steps.push({ key: "correction", label: `Returned for correction by the ${OFFICE_WORD[d.returned_by_office ?? ""] ?? "desk"}`, when: d.updated_at, who: null, note: d.correction_note, done: true, current: true, failed: true });
  return steps;
}
export const OFFICE_WORD: Record<string, string> = { bursar: "Bursary", hod: "Head of Department", dean: "Dean", facultyofficer: "Faculty Officer", academic: "Academic Office", dvc: "Deputy Vice-Chancellor", registrar: "Registrar", dregistrar: "Deputy Registrar", super: "Super Administrator", student: "student" };

export function ApprovalTimeline({ d, compact }: { d: Deferment; compact?: boolean }) {
  const steps = stepsOf(d);
  const cur = STATE[d.state]?.[0] ?? d.state;
  return (
    <ol className="plain" style={{ display: "grid", gap: compact ? 4 : 8 }}>
      {steps.map((st) => (
        <li key={st.key} className="row row--base" style={{ gap: "var(--s-3)", flexWrap: "wrap", opacity: st.done || st.current ? 1 : 0.55 }}>
          <span className="tnum" style={{ minWidth: 18, textAlign: "center", color: st.failed ? "var(--red-ink)" : st.done ? "var(--green-ink)" : st.current ? "var(--amber-ink)" : "var(--faint)" }}>{st.failed ? "✕" : st.done ? "✓" : st.current ? "●" : "○"}</span>
          <span className={st.done || st.current ? "b600" : ""}>{st.label}{st.current && !st.done ? <span className="sub2"> · {cur}</span> : null}</span>
          {st.when ? <span className="tnum sub2">{whenAt(st.when)}</span> : st.current ? <span className="sub2">Current stage</span> : null}
          {st.who ? <span className="sub2">— {st.who}</span> : null}
          {st.note && !compact ? <span className="sub2" style={{ flexBasis: "100%", paddingLeft: 30 }}>{st.note}</span> : null}
        </li>
      ))}
    </ol>
  );
}

/** the academic effect of a deferment, as a key-value block */
export function effectPairs(e: Effect): [string, string][] {
  return [
    ["Deferment type", e.kind === "SESSION" ? "Academic session" : "Semester"], ["Deferred period", e.period],
    ["Duration deferred", `${e.duration_semesters} semester${e.duration_semesters === 1 ? "" : "s"}${e.kind === "SESSION" ? " (1 academic session)" : ""}`],
    ["Courses affected", String(e.courses_affected)], ["CGPA effect", "No negative effect — deferred courses carry no grade, no attempted units, no quality points"],
    ["Programme duration extension", `+${e.extension_semesters} semester${e.extension_semesters === 1 ? "" : "s"}`],
    ["Original duration", `${e.original_semesters} semesters`], ["Adjusted duration", `${e.adjusted_semesters} semesters`],
    ["Original expected completion", e.original_completion], ["Adjusted expected completion", `${e.adjusted_completion}${e.adjusted_completion_on ? ` (${dayOf(e.adjusted_completion_on)})` : ""} — updated automatically`],
    ["Expected return", e.expected_return], ["Entry session", `${e.entry_session} — unchanged`], ["Matriculation number", `${e.matric_no ?? "—"} — unchanged`],
  ];
}
