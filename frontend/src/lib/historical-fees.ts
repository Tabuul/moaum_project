/**
 * V654: historical school fees and the graduate's financial clearance, as /api/v1/finance/historical answers. The account is the
 * database's (finance.historical_rows); these are its types, its words, and the pure shapes the screens and exports build from it.
 * V665: approved waivers and adjustments (waived) lower what a period owes; reconciliation runs keep a population's standing.
 */

export type PeriodStatus = "CLEARED" | "PARTIALLY_PAID" | "OUTSTANDING" | "CREDIT" | "REQUIRES_REVIEW" | "PENDING_APPROVAL" | "BEING_ASSESSED";
export type FinancialStatus = "FINANCIALLY_CLEARED" | "FINANCIAL_OBLIGATION" | "FINANCIAL_CLEARANCE_PENDING" | "HISTORICAL_FEE_REVIEW_REQUIRED" | "NO_HISTORICAL_PERIOD";
export type AssessmentState = "DRAFT" | "PENDING_BURSAR_APPROVAL" | "RETURNED_FOR_CORRECTION" | "APPROVED" | "REJECTED" | "CANCELLED" | "SUPERSEDED";
type Tone = "ok" | "warn" | "bad" | "grey" | "info";
type Money = number | string;

export interface Period {
  session: string; semester: number; level: number | null; programme_code?: string; assessed: Money | null; source?: "ASSESSMENT" | "STRUCTURE" | "NONE";
  source_ref?: string | null; assessment_id?: string | null; structure_amount?: Money | null; structure_lines?: number; pending_id?: string | null;
  pending_ref?: string | null; pending_amount?: Money | null; paid: Money; outstanding: Money | null; credit: Money; status: PeriodStatus;
  /** V665: the approved waivers and adjustments of the period */
  waived?: Money | null;
  /** V683: what is under review for the period — the graduate's open evidence (the period's), the session's archived school-fee payments
   *  not yet settled, its payments under another purpose; PAYMENT_UNDER_REVIEW on a period not settled where any stands */
  review?: "PAYMENT_UNDER_REVIEW" | null; evidence_id?: string | null; evidence_ref?: string | null; evidence_state?: EvidenceState | null;
  archived_count?: number; archived_amount?: Money | null; other_count?: number; other_amount?: Money | null;
}

export interface SessionGroup { session: string; periods: Period[]; assessed: number; waived: number; paid: number; outstanding: number; credit: number; review: number }

export interface Assessment {
  id: string; reference: string; session: string; semester: number; level: number | null; amount: Money; components?: string | null; source: string;
  source_reference: string | null; reason?: string; remarks?: string | null; state: AssessmentState; created_at: string; created_office?: string | null;
  created_by_name: string | null; submitted_at: string | null; decided_at?: string | null; decided_office?: string | null; decided_by_name?: string | null;
  decision_note?: string | null; batch: string | null; corrects?: string | null; superseded_by?: string | null; mine?: boolean;
}

export interface StudentRow {
  student_id: string; surname: string; other_names: string; matric_no: string | null; admission_no: string | null; jamb_reg_no: string | null; status: string;
  entry_session: string | null; programme_code: string; programme: string; department: string | null; faculty: string | null; first_session: string | null;
  graduation_session: string | null; periods: number | null; assessed: Money | null; paid: Money | null; outstanding: Money | null; credit: Money | null;
  owing_periods: number | null; review_periods: number | null; pending_periods: number | null; partial_periods: number | null; owing: string | null;
  financial_status: FinancialStatus | null; last_payment_at: string | null; refreshed_at: string | null; bursary_clearance: string | null; clearance_ref: string | null;
  /** V720: undergraduate or postgraduate, the level now, the sessions owed in whole and in part */
  postgraduate?: boolean; current_level?: number | null; whole_sessions?: number | null; part_sessions?: number | null;
}

export interface StudentAccount {
  student: { id: string; surname: string; other_names: string; matric_no: string | null; admission_no: string | null; jamb_reg_no: string | null; status: string;
    entry_session: string | null; entry_level: number | null; current_level: number | null; programme_code: string; programme: string; department: string | null;
    faculty: string | null; graduation_session: string | null };
  start: string | null; periods: Period[]; assessments: Assessment[];
  payments?: { reference: string; session: string; purpose: string; amount: Money; generated_at: string; confirmed_at: string | null; channel: string | null;
    receipt_no: string | null; paid_as: string | null }[];
  reallocations?: { realloc_ref: string; kind: string; reference: string; amount: Money; from_purpose: string; from_session: string; to_purpose: string;
    to_session: string; executed_at: string; status: string }[];
  clearance: { id: string; reference: string; session: string; started_at: string; completed_at: string | null; overall: string | null; bursary: string | null;
    bursary_at: string | null; verify_code: string } | null;
  /** V665 */
  waivers?: Waiver[];
  otherPayments?: OtherPayment[];
  awaitingFinalClearance?: boolean;
  /** V683: the graduate's payment evidence, and where each verified one's payment stands */
  evidence?: (Evidence & { payment: string | null; payment_state: PaymentState | null })[];
}

export type WaiverState = "PENDING_BURSAR_APPROVAL" | "APPROVED" | "REJECTED" | "WITHDRAWN" | "REVOKED";
export type WaiverKind = "WAIVER" | "ADJUSTMENT";

/** V665: a waiver or adjustment of a past period — proposed by one officer, decided by another of the Bursar's office */
export interface Waiver {
  id: string; reference: string; session: string; semester: number; kind: WaiverKind; amount: Money; reason: string; authority: string; state: WaiverState;
  created_at: string; created_office?: string | null; created_by_name: string | null; mine?: boolean; decided_at: string | null; decided_office?: string | null;
  decided_by_name?: string | null; decision_note?: string | null; revoked_at?: string | null; revoked_by_name?: string | null; revoke_reason?: string | null;
  evidence?: number | { id: string; filename: string; content_type: string; size_bytes: number; added_at: string; added_by: string | null }[];
  student_id?: string; surname?: string; other_names?: string; matric_no?: string | null; student_status?: string; programme?: string;
  assessed?: Money | null; paid?: Money; outstanding?: Money | null; period?: Period | null;
}

/** V665: a payment outside school fees in a session the student owes, for the Bursary to look at */
export interface OtherPayment {
  student_id: string; payment_id: string; reference: string; session: string; purpose: string; amount: Money; confirmed_at: string; channel: string | null;
  kind: "OUTSTANDING_FEES" | "OTHER"; desk_status: string | null;
}

export const WAIVER_WORDS: Record<WaiverState, [string, Tone]> = {
  PENDING_BURSAR_APPROVAL: ["Pending Bursar approval", "warn"], APPROVED: ["Approved — in force", "ok"], REJECTED: ["Rejected", "bad"],
  WITHDRAWN: ["Withdrawn", "grey"], REVOKED: ["Revoked", "grey"],
};
export const KIND_WORDS: Record<WaiverKind, string> = { WAIVER: "Waiver", ADJUSTMENT: "Adjustment" };

/** the amount a waiver may be: more than nothing and no more than the period still owes (the database decides again) */
export function waiverAmountProblem(amount: string, outstanding: Money | null | undefined): string | null {
  const a = Number(amount.replace(/[^0-9.]/g, ""));
  if (!amount.trim() || !Number.isFinite(a) || a <= 0) return "Enter the amount to waive.";
  if (a > num(outstanding)) return `At most what the period still owes (${naira(outstanding)}).`;
  return null;
}

export type ReconStatus = "CLEARED" | "OWING" | "REQUIRES_REVIEW" | "PENDING_APPROVAL" | "PAYMENT_REVIEW" | "NO_PERIOD";
export type ReconPopulation = "AWAITING_GRADUATION" | "UNDER_CLEARANCE" | "GRADUATES" | "ALL";

export const RECON_WORDS: Record<ReconStatus, [string, Tone]> = {
  CLEARED: ["Cleared", "ok"], OWING: ["Owing", "bad"], REQUIRES_REVIEW: ["Requires historical review", "bad"], PENDING_APPROVAL: ["Pending Bursar approval", "warn"],
  PAYMENT_REVIEW: ["Owing — other payments to review", "warn"], NO_PERIOD: ["No historical period", "grey"],
};
export const POPULATION_WORDS: Record<ReconPopulation, string> = {
  AWAITING_GRADUATION: "Approved graduands awaiting final clearance", UNDER_CLEARANCE: "Students under final clearance", GRADUATES: "Graduated students",
  ALL: "Graduands, graduates and students under final clearance",
};

/** V665: a reconciliation run (CLEARANCE-RECON/YYYY/NNNNNN) with its totals */
export interface ReconRun {
  id: string; reference: string; population: ReconPopulation; scope: string | null; students: number; capped: boolean; cleared: number; owing: number; review: number;
  pending: number; payment_review: number; no_period: number; assessed: Money; paid: Money; waived: Money; outstanding: Money; run_at: string;
  finished_at?: string | null; run_office: string | null; run_by_name: string | null;
}

export interface ReconRow {
  student_id: string; student: string; matric_no: string | null; jamb_reg_no: string | null; faculty: string | null; department: string | null; programme: string;
  status: ReconStatus; student_status: string; awaiting_graduation: boolean; graduation_session: string | null; periods: number; assessed: Money; paid: Money;
  waived: Money; outstanding: Money; credit: Money; owing: string | null; review_periods: string | null; pending_periods: string | null; other_payments: number;
  other_amount: Money; process_id: string | null; clearance_ref: string | null; bursary_state: string | null;
}

export const RECON_HEAD = ["S/N", "Student Name", "Matric No.", "JAMB No.", "Faculty", "Department", "Programme", "Graduation Session", "Academic Status",
  "Assessed (₦)", "Paid (₦)", "Waived / Adjusted (₦)", "Outstanding (₦)", "Sessions Owing", "For Review", "Other Payments (₦)", "Reconciliation Status",
  "Final Clearance", "Bursary Stage"];

/** a run's rows as the report writes them: S/N first and numeric, numbers as text, amounts as numbers */
export function reconRows(rows: ReconRow[]): (string | number)[][] {
  return rows.map((r, i) => [
    i + 1, r.student, r.matric_no ?? "", r.jamb_reg_no ?? "", r.faculty ?? "", r.department ?? "", r.programme, r.graduation_session ?? "",
    r.student_status === "GRADUATED" ? "Graduated" : r.awaiting_graduation ? "Award approved — awaiting final clearance" : r.student_status.replace(/_/g, " ").toLowerCase(),
    num(r.assessed), num(r.paid), num(r.waived), num(r.outstanding), r.owing ?? "", [r.review_periods, r.pending_periods].filter(Boolean).join("; "),
    num(r.other_amount), RECON_WORDS[r.status]?.[0] ?? r.status, r.clearance_ref ?? "Not started", r.bursary_state ? r.bursary_state.replace(/_/g, " ").toLowerCase() : "",
  ]);
}

export interface Setting { assess_from: string | null; start: string | null; online_payment: boolean; set_at: string | null; reason: string | null; refreshed_at: string | null; set_by: string | null }
export interface Desk { office: string; permissions: string[]; setting: Setting; sessions: string[]; sources: string[] }

export interface Figures {
  graduates: number; with_outstanding: number; cleared: number; requires_review: number; pending_approval: number; partially_paid: number; no_outstanding: number;
  with_credit: number; no_period: number; auto_assessed: number; graduated_with_obligation: number; assessed: Money; paid: Money; outstanding: Money; credit: Money;
  assessments: { state: AssessmentState; n: number; amount: Money }[]; batchesPending: number; unsummarised: number; refreshedAt: string | null; start: string | null;
  /** V665 */
  waivers?: { pending: number; pending_amount: Money; approved: number; approved_amount: Money };
  awaitingGraduation?: number;
  /** V668: the final clearances waiting only on the Bursary, and how many are ready */
  readyToGraduate?: { ready: number; waiting: number };
  /** V683: graduates' payment evidence by state, and graduates with a school-fee payment archived for review */
  evidence?: { submitted: number; submitted_amount: Money; more_information: number; verified: number; verified_to_put_right: number; rejected: number };
  archivedSchoolFees?: { students: number; amount: Money };
  /** V720: the whole population by standing (ACTIVE / GRADUATED) and programme type (UG / PG) */
  population?: PopulationRow[];
}
export interface PopulationRow { standing: "ACTIVE" | "GRADUATED"; type: "UG" | "PG"; students: number; with_outstanding: number; whole_sessions: number; part_sessions: number; requires_review: number; outstanding: Money; paid: Money }

export const PERIOD_WORDS: Record<PeriodStatus, [string, Tone]> = {
  CLEARED: ["Cleared", "ok"], PARTIALLY_PAID: ["Partially paid", "warn"], OUTSTANDING: ["Outstanding", "bad"], CREDIT: ["Credit / overpayment", "info"],
  REQUIRES_REVIEW: ["Requires historical review", "bad"], PENDING_APPROVAL: ["Pending Bursar approval", "warn"], BEING_ASSESSED: ["Being assessed by the Bursary", "grey"],
};

export const FINANCIAL_WORDS: Record<FinancialStatus, [string, Tone]> = {
  FINANCIALLY_CLEARED: ["Financially cleared", "ok"], FINANCIAL_OBLIGATION: ["Financial obligation", "bad"],
  FINANCIAL_CLEARANCE_PENDING: ["Financial clearance pending", "warn"], HISTORICAL_FEE_REVIEW_REQUIRED: ["Historical fee review required", "bad"],
  NO_HISTORICAL_PERIOD: ["No historical period", "grey"],
};

export const STATE_WORDS: Record<AssessmentState, [string, Tone]> = {
  DRAFT: ["Draft", "grey"], PENDING_BURSAR_APPROVAL: ["Pending Bursar approval", "warn"], RETURNED_FOR_CORRECTION: ["Returned for correction", "warn"],
  APPROVED: ["Approved — in force", "ok"], REJECTED: ["Rejected", "bad"], CANCELLED: ["Withdrawn", "grey"], SUPERSEDED: ["Superseded by a correction", "grey"],
};

export const SOURCE_WORDS: Record<string, string> = {
  HISTORICAL_FEE_STRUCTURE: "Historical fee structure", HISTORICAL_FEE_VERSION: "Historical fee structure version", COHORT_FEE_RECORD: "Cohort fee record",
  STUDENT_SPECIFIC_APPROVED_FEE: "Student-specific approved fee", OFFICIAL_FEE_DOCUMENT: "Official fee document", MANUAL_HISTORICAL_ASSESSMENT: "Manual historical assessment",
  LEGACY_MIGRATION: "Old portal (legacy migration)", OTHER_APPROVED_SOURCE: "Other approved source",
};

/** a document or approval is named for these sources (the database refuses them without one) */
export const SOURCE_NEEDS_REFERENCE = new Set(["STUDENT_SPECIFIC_APPROVED_FEE", "OFFICIAL_FEE_DOCUMENT", "OTHER_APPROVED_SOURCE", "COHORT_FEE_RECORD"]);

export const semesterWords = (n: number) => (n === 1 ? "First semester" : n === 2 ? "Second semester" : n === 3 ? "Third semester" : `Semester ${n}`);
export const num = (v: Money | null | undefined) => (v == null || v === "" ? 0 : Number(v));
export const naira = (v: Money | null | undefined) => `₦${num(v).toLocaleString("en-NG", { minimumFractionDigits: 0, maximumFractionDigits: 2 })}`;
export const can = (desk: Pick<Desk, "permissions"> | null, p: string) => !!desk && desk.permissions.includes(p);
/** V740/V741: a session the student was admitted in, before their first year of study — kept only to hold money, nothing due, and no
 *  assessment may be made on it (the API refuses HFA_BEFORE_FIRST_YEAR) */
export const beforeFirstYear = (p: Pick<Period, "source" | "source_ref">) => p.source === "STRUCTURE" && (p.source_ref ?? "").includes("before the first year of study");

/** the periods by session, with the session's totals (only an official amount counts; a period for review counts nothing owed) */
export function bySession(periods: Period[]): SessionGroup[] {
  const out: SessionGroup[] = [];
  for (const p of [...periods].sort((a, b) => (a.session === b.session ? a.semester - b.semester : a.session < b.session ? -1 : 1))) {
    let g = out[out.length - 1];
    if (!g || g.session !== p.session) { g = { session: p.session, periods: [], assessed: 0, waived: 0, paid: 0, outstanding: 0, credit: 0, review: 0 }; out.push(g); }
    g.periods.push(p);
    g.assessed += num(p.assessed);
    g.waived += num(p.waived);
    g.paid += num(p.paid);
    g.outstanding += num(p.outstanding);
    g.credit += num(p.credit);
    if (p.status === "REQUIRES_REVIEW" || p.status === "PENDING_APPROVAL" || p.status === "BEING_ASSESSED") g.review += 1;
  }
  return out;
}

export function totals(periods: Period[]): { assessed: number; waived: number; paid: number; outstanding: number; credit: number; review: number; owing: string[] } {
  const groups = bySession(periods);
  return {
    assessed: groups.reduce((n, g) => n + g.assessed, 0), waived: groups.reduce((n, g) => n + g.waived, 0), paid: groups.reduce((n, g) => n + g.paid, 0),
    outstanding: groups.reduce((n, g) => n + g.outstanding, 0), credit: groups.reduce((n, g) => n + g.credit, 0),
    review: groups.reduce((n, g) => n + g.review, 0),
    owing: periods.filter((p) => num(p.outstanding) > 0).map((p) => `${p.session} ${semesterWords(p.semester).toLowerCase()}`),
  };
}

/** the components typed on the form, as the API takes them; blank rows left out, an amount read as naira */
export function readComponents(rows: { item: string; amount: string }[]): { item: string; amount: number }[] {
  return rows.filter((r) => r.item.trim() || r.amount.trim()).map((r) => ({ item: r.item.trim(), amount: Number(r.amount.replace(/[^0-9.]/g, "")) }));
}

export const REPORT_HEAD = ["S/N", "Student Name", "Matric No.", "JAMB No.", "Faculty", "Department", "Programme", "Academic Status", "Programme Type", "Graduation Session", "Fee Session", "Semester",
  "Level", "Amount Assessed (₦)", "Amount Paid (₦)", "Outstanding (₦)", "Assessment Source", "Assessment Status", "Financial Clearance Status",
  "Bursar Approval Status", "Date"];

export interface ReportRow {
  student: string; matric_no: string | null; jamb_reg_no: string | null; faculty: string | null; department: string | null; programme: string;
  graduation_session: string | null; session: string; semester: number; level: number | null; assessed: Money | null; paid: Money; outstanding: Money | null;
  credit: Money; source: string; source_ref: string | null; status: PeriodStatus; assessment_state: AssessmentState | null; financial_status: FinancialStatus;
  bursary_clearance: string | null; dated: string | null;
  /** V720 */
  academic_status?: string; programme_type?: string;
}

/** the historical fee report's rows: S/N first and numeric, matriculation and JAMB numbers as text, amounts as numbers */
export function reportRows(rows: ReportRow[]): (string | number)[][] {
  return rows.map((r, i) => [
    i + 1, r.student, r.matric_no ?? "", r.jamb_reg_no ?? "", r.faculty ?? "", r.department ?? "", r.programme, standingWords(r.academic_status), r.programme_type ?? "", r.graduation_session ?? "", r.session,
    semesterWords(r.semester), r.level ?? "", r.assessed == null ? "" : num(r.assessed), num(r.paid), r.outstanding == null ? "" : num(r.outstanding),
    r.source === "ASSESSMENT" ? `Approved assessment ${r.source_ref ?? ""}`.trim() : r.source === "STRUCTURE" ? r.source_ref ?? "Fee structure" : "None — requires review",
    PERIOD_WORDS[r.status]?.[0] ?? r.status, FINANCIAL_WORDS[r.financial_status]?.[0] ?? r.financial_status,
    r.assessment_state ? STATE_WORDS[r.assessment_state]?.[0] ?? r.assessment_state : r.source === "STRUCTURE" ? "Not needed (fee structure)" : "—",
    r.dated ? r.dated.slice(0, 10) : "",
  ]);
}

/** V720: a status as the reports print it */
export const standingWords = (status: string | null | undefined) => (!status ? "" : status === "GRADUATED" ? "Graduated" : status === "ACTIVE" ? "Studying" : status.charAt(0) + status.slice(1).toLowerCase().replace(/_/g, " "));

export const CLEARANCE_HEAD = ["S/N", "Student Name", "Matric No.", "JAMB No.", "Faculty", "Department", "Programme", "Academic Status", "Programme Type", "Graduation Session", "Historical Sessions With Debt", "Sessions Owed In Whole", "Sessions Owed In Part",
  "Total Assessed (₦)", "Total Paid (₦)", "Total Outstanding (₦)", "Financial Status", "Clearance Status", "Last Payment Date", "Bursary Officer", "Bursar Approval"];

export interface ClearanceRow {
  student: string; matric_no: string | null; jamb_reg_no: string | null; faculty: string | null; department: string | null; programme: string;
  graduation_session: string | null; owing: string | null; assessed: Money; paid: Money; outstanding: Money; credit: Money; financial_status: FinancialStatus;
  last_payment_at: string | null; bursary_clearance: string | null; bursary_officer: string | null; bursary_at: string | null;
  /** V720 */
  academic_status?: string; programme_type?: string; whole_sessions?: number | null; part_sessions?: number | null;
}

export function clearanceRows(rows: ClearanceRow[]): (string | number)[][] {
  return rows.map((r, i) => [
    i + 1, r.student, r.matric_no ?? "", r.jamb_reg_no ?? "", r.faculty ?? "", r.department ?? "", r.programme, standingWords(r.academic_status), r.programme_type ?? "", r.graduation_session ?? "", r.owing ?? "—",
    r.whole_sessions ?? 0, r.part_sessions ?? 0,
    num(r.assessed), num(r.paid), num(r.outstanding), FINANCIAL_WORDS[r.financial_status]?.[0] ?? r.financial_status,
    r.bursary_clearance ? r.bursary_clearance.replace(/_/g, " ").toLowerCase() : "Not started", r.last_payment_at ? r.last_payment_at.slice(0, 10) : "",
    r.bursary_officer ?? "", r.bursary_at ? `${r.bursary_clearance === "CLEARED" ? "Cleared" : "Decided"} ${r.bursary_at.slice(0, 10)}` : "",
  ]);
}

/** the student's statement rows: session, semester, level, assessed, waived or adjusted (V665), paid, outstanding */
export function statementRows(periods: Period[]): (string | number)[][] {
  return [...periods].sort((a, b) => (a.session === b.session ? a.semester - b.semester : a.session < b.session ? -1 : 1)).map((p, i) => [
    i + 1, p.session, semesterWords(p.semester), p.level ?? "", p.assessed == null ? "Being assessed" : num(p.assessed), num(p.waived), num(p.paid),
    p.outstanding == null ? "—" : num(p.outstanding), PERIOD_WORDS[p.status]?.[0] ?? p.status,
  ]);
}
export const STATEMENT_HEAD = ["S/N", "Session", "Semester", "Level", "Assessed (₦)", "Waived / adjusted (₦)", "Paid (₦)", "Outstanding (₦)", "Status"];

/* ── V683: payment evidence a graduate submits for a past semester, reviewed by the Bursary ── */

export type EvidenceState = "SUBMITTED" | "MORE_INFORMATION_REQUIRED" | "VERIFIED" | "REJECTED" | "WITHDRAWN";
export type EvidenceChannel = "BANK" | "OLD_PORTAL" | "ONLINE" | "OTHER";
/** where a payment stands against the graduate's session: counted, or what is still to be done before it counts */
export type PaymentState = "COUNTED" | "ARCHIVED" | "OTHER_STUDENT" | "NOT_SCHOOL_FEES" | "OTHER_SESSION" | "NOT_CONFIRMED";

export interface Evidence {
  id: string; reference: string; session: string; semester: number; amount: Money; paid_on: string | null; channel: EvidenceChannel; payment_reference: string;
  note?: string | null; state: EvidenceState; submitted_at: string; updated_at?: string; decided_at: string | null; decision_note: string | null;
  files?: { id: string; filename: string }[];
}

/** one candidate payment on record for the evidence (finance.historical_evidence_candidates), or one found by another number */
export interface Candidate {
  payment_id: string; reference: string; receipt_no: string | null; student_id: string | null; matric_no: string | null; name: string | null; session: string | null;
  purpose: string; amount: Money; confirmed_at: string; channel: string | null; archived: boolean; why: "NUMBER" | "SESSION" | "ARCHIVED" | "SEARCH";
  state: PaymentState; verified_for: string | null;
}

export const EVIDENCE_WORDS: Record<EvidenceState, [string, Tone]> = {
  SUBMITTED: ["With the Bursary", "warn"], MORE_INFORMATION_REQUIRED: ["More information needed", "bad"], VERIFIED: ["Verified", "ok"],
  REJECTED: ["Not accepted", "bad"], WITHDRAWN: ["Withdrawn", "grey"],
};

export const CHANNEL_WORDS: Record<EvidenceChannel, string> = {
  BANK: "At a bank (teller)", OLD_PORTAL: "On the old portal", ONLINE: "Online (card or transfer)", OTHER: "Otherwise",
};

/** a payment's standing against the session, and what the Bursary does about it (each with its own approval) */
export const PAYMENT_STATE_WORDS: Record<PaymentState, [string, Tone, string]> = {
  COUNTED: ["Counted as the session's school fees", "ok", "Nothing more: the account reads it."],
  ARCHIVED: ["Archived for review", "warn", "Settle it on the Payment Archive; it counts once reconciled."],
  OTHER_STUDENT: ["On another student's record", "warn", "Move it to this graduate with a payment swap; it counts once approved."],
  NOT_SCHOOL_FEES: ["Under another purpose", "warn", "Correct its purpose with a payment reallocation; it counts once approved."],
  OTHER_SESSION: ["Under another session", "warn", "Correct its session with a payment reallocation; it counts once approved."],
  NOT_CONFIRMED: ["Not confirmed", "bad", "Only a confirmed payment counts."],
};

/** where each correction is made */
export const PAYMENT_STATE_DESK: Partial<Record<PaymentState, [string, string]>> = {
  ARCHIVED: ["Payment Archive", "/finance/payment-archive"], OTHER_STUDENT: ["Payment swaps", "/finance/payment-swaps"],
  NOT_SCHOOL_FEES: ["Payment reallocations", "/finance/payment-reallocations"], OTHER_SESSION: ["Payment reallocations", "/finance/payment-reallocations"],
};

export const WHY_WORDS: Record<Candidate["why"], string> = {
  NUMBER: "Its number is the one on the evidence", SESSION: "The graduate's payment in the session", ARCHIVED: "The graduate's archived payment",
  SEARCH: "Found by the number searched",
};

/** what is under review for a period, in words — the student's own view says "your" */
export function reviewWords(p: Period, studentView = false): string[] {
  if (p.review !== "PAYMENT_UNDER_REVIEW") return [];
  const out: string[] = [];
  if (p.evidence_ref) {
    out.push(`${studentView ? "Your" : "The graduate's"} payment evidence ${p.evidence_ref} ${p.evidence_state === "MORE_INFORMATION_REQUIRED" ? "needs more information" : "is with the Bursary"}`);
  }
  if (num(p.archived_amount) > 0) out.push(`A school fees payment of this session (${naira(p.archived_amount)}) is archived for review`);
  if (num(p.other_amount) > 0) out.push(`A payment of this session under another purpose (${naira(p.other_amount)}) is being checked`);
  return out;
}

/** the periods the graduate may give evidence for: not settled, and with no evidence of theirs already open */
export function evidencePeriods(periods: Period[], evidence: Evidence[]): Period[] {
  const open = new Set(evidence.filter((e) => e.state === "SUBMITTED" || e.state === "MORE_INFORMATION_REQUIRED").map((e) => `${e.session}|${e.semester}`));
  return periods.filter((p) => p.status !== "CLEARED" && p.status !== "CREDIT" && !open.has(`${p.session}|${p.semester}`));
}

export interface EvidenceForm { amount: string; paidOn: string; channel: EvidenceChannel | ""; reference: string; note: string }

/** the evidence form's first problem, or null (the database decides again) */
export function evidenceProblem(f: EvidenceForm, today: string): string | null {
  const a = Number(f.amount.replace(/[^0-9.]/g, ""));
  if (!f.amount.trim() || !Number.isFinite(a) || a <= 0) return "Enter the amount you paid.";
  if (f.paidOn && f.paidOn > today) return "The day you paid cannot be in the future.";
  if (!f.channel) return "Say how you paid.";
  const r = f.reference.trim();
  if (r.length < 4 || r.length > 80) return "Give the receipt, teller or transaction number on your evidence (4 to 80 characters).";
  if (f.note.length > 1000) return "The note is up to 1,000 characters.";
  return null;
}

/** the evidence form as the API takes it */
export function evidenceBody(f: EvidenceForm): { amount: number; paidOn: string | null; channel: string; reference: string; note: string | null } {
  return { amount: Number(f.amount.replace(/[^0-9.]/g, "")), paidOn: f.paidOn || null, channel: f.channel, reference: f.reference.trim(), note: f.note.trim() || null };
}
