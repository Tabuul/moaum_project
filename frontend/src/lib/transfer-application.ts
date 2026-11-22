/** V766 — inter-university transfer applications online: a student of another university applies on their own at /transfer/apply,
 *  pays the application fee the Bursar publishes for the session (possibly nothing), uploads the documents asked for and submits; the
 *  Registry checks the documents, the Head of Department of the programme applied for recommends (a level, or a reason to decline), the
 *  Registry approves into V588/V763's incoming transfer, and another officer decides it on the Inter-University Transfer page. Every word
 *  and every rule the screens show is here: the states in the applicant's and the office's words, the form's checks in the order the page
 *  asks, the documents' checklist and the checks a file passes in the browser, the Registry's buttons and why one is closed. The rules
 *  that hold are the database's (admissions.iut_*); this says what it said, and stops a form going up that it would refuse. */

/** an application number: IUT/APP/2026/000001 — never a batch reference (IUT/2026/000014) */
export const IUT_APPLICATION_NO = /^IUT\/APP\/[0-9]{4}\/[0-9]{6}$/i;

export function isTransferApplicationNo(s: string | null | undefined): boolean {
  return IUT_APPLICATION_NO.test(String(s ?? "").trim());
}

/** the cookie the sign-in leaves for a transfer applicant ("1", read by the home page as moaum_jupeb is): their portal is /transfer/portal */
export const IUT_COOKIE = "moaum_iut";

export const STATES = ["DRAFT", "SUBMITTED", "CORRECTION_REQUIRED", "WITH_HOD", "RECOMMENDED", "NOT_RECOMMENDED", "APPROVED", "ADMITTED", "REJECTED", "WITHDRAWN"] as const;
export type IutState = (typeof STATES)[number];
/** D11: the one state the applicant's own data gives for a recommendation, a decline and an approval (admissions.iut_state_shown): the
 *  API never tells the applicant which of the three it is before another officer decides the transfer */
export const WITH_REGISTRY = "WITH_REGISTRY";
const WITH_THE_REGISTRY = ["RECOMMENDED", "NOT_RECOMMENDED", "APPROVED", WITH_REGISTRY];

/** the documents' limits (D12): PDF, JPEG or PNG, at most 5 MB each */
export const MAX_DOCUMENT_BYTES = 5 * 1024 * 1024;
export const DOCUMENT_TYPES = ["application/pdf", "image/jpeg", "image/png"] as const;

/** the offices that keep the Registry desk (SETTERS / KEEPERS) and the department desk */
export const KEEPERS = ["academic", "registrar", "dregistrar", "super"];
export const DEPARTMENT = ["hod", "dean", "super"];
export const FEE_STATERS = ["bursar", "studentaccounts", "super"];
export const FEE_PUBLISHERS = ["bursar", "super"];

export type Pill = "grey" | "info" | "ok" | "bad" | "warn";
export type Tone = "info" | "ok" | "bad";
type Money = number | string | null | undefined;

// ── the shapes the API answers (SPEC §3.3–§3.6; null keys are left out) ─────────────────────────────────────────────────

export interface PublicProgramme { code: string; name: string; dept?: string | null; deptName?: string | null; faculty?: string | null; facultyName?: string | null; levels: number[] }
export interface PublicUniversity { code: string; name: string; country?: string | null }
export interface DocumentKind {
  code: string; label: string; hint?: string | null; required: boolean; imagesAllowed?: boolean | null;
  transferCode?: string | null; ord?: number | null; active?: boolean | null;
}
/** the window as GET /api/v1/public/inter-university-transfer gives it (iut_public, and the PublicWindow keys the API adds) */
export interface IutPublicWindow {
  status?: string | null; opensOn?: string | null; closesOn?: string | null; message?: string | null;
  type?: string | null; label?: string | null; session?: string | null; open?: boolean | null; opensAt?: string | null; closesAt?: string | null;
  applicationPath?: string | null; applicationUrl?: string | null;
}
export interface PublicOptions {
  session?: string | null; window?: IutPublicWindow | null; fee?: { amount?: Money; published?: boolean | null } | null;
  programmes?: PublicProgramme[]; universities?: PublicUniversity[]; documents?: DocumentKind[]; maxDocumentBytes?: number | null;
}

export interface IutDocument {
  id: string; kind: string; label?: string | null; required?: boolean | null; filename: string; contentType?: string | null; bytes?: number | null;
  uploadedAt?: string | null; status: "PENDING" | "ACCEPTED" | "REJECTED" | string; note?: string | null; reviewedAt?: string | null; supersededAt?: string | null;
}
export interface IutReference {
  reference: string; amount: Money; expiresAt?: string | null; confirmedAt?: string | null; receiptNo?: string | null; channel?: string | null; settles?: boolean | null;
  /** what the refund desk gave back on a confirmed payment (its refunds approved or paid, at most the amount), as the Bursary's report counts it */
  refunded?: Money;
}
export interface IutEvent { at: string; action: string; fromState?: string | null; toState?: string | null; note?: string | null; byName?: string | null; office?: string | null }
export interface IutView {
  id: string; applicationNo: string; session: string; state: IutState | string;
  /** the session's window as it stands today (iut_window_status): OPEN, CLOSED, SCHEDULED or EXPIRED */
  windowStatus?: string | null; createdAt?: string | null; updatedAt?: string | null;
  applicant?: { surname?: string | null; otherNames?: string | null; sex?: string | null; dateOfBirth?: string | null; jambRegNo?: string | null; email?: string | null; phone?: string | null };
  previous?: {
    universityCode?: string | null; universityName?: string | null; universityNamed?: string | null; matricNo?: string | null; programme?: string | null;
    level?: number | null; entrySession?: string | null; cgpa?: Money; cgpaScale?: number | null;
  };
  applied?: {
    programme?: string | null; programmeName?: string | null; dept?: string | null; deptName?: string | null; faculty?: string | null; facultyName?: string | null;
    college?: string | null; collegeName?: string | null; level?: number | null; levelsOpen?: number[] | null;
  };
  reason?: string | null;
  fee?: { settled?: boolean | null; basis?: "PAID" | "NONE_DUE" | string | null; settledAt?: string | null; due?: Money; references?: IutReference[] | null } | null;
  kinds?: DocumentKind[]; documents?: IutDocument[]; superseded?: IutDocument[];
  submittedAt?: string | null; lastSubmittedAt?: string | null; withdrawnAt?: string | null;
  notice?: { kind: "CORRECTION" | "REJECTED" | string; note?: string | null } | null;
  hod?: { decision?: "ACCEPT" | "DECLINE" | string | null; level?: number | null; note?: string | null; byName?: string | null; office?: string | null; at?: string | null } | null;
  registry?: { note?: string | null; byName?: string | null; office?: string | null; at?: string | null; approvalRef?: string | null } | null;
  transfer?: { id?: string | null; batchId?: string | null; batchRef?: string | null; status?: string | null; preparedBy?: string | null; preparedByName?: string | null } | null;
  /** portalOpened: the student door has been used once, so the student portal keeps its own password from then on (D18) */
  student?: { id?: string | null; admissionNo?: string | null; matricNo?: string | null; level?: number | null; portalOpened?: boolean | null } | null;
  history?: IutEvent[];
}
/** GET /api/v1/transfer-applications/me: the latest application's view, and the account around it */
export interface IutMe extends IutView {
  account?: { email?: string | null; phone?: string | null } | null;
  applications?: { id: string; applicationNo: string; session: string; state: string }[];
  canApplyAgain?: boolean | null; openSession?: string | null;
}

// ── money, dates ──────────────────────────────────────────────────────────────────────────────────────────────────────────

export function num(m: Money): number {
  const n = typeof m === "number" ? m : Number(m ?? NaN);
  return Number.isFinite(n) ? n : 0;
}
export function naira(m: Money): string {
  return `₦${num(m).toLocaleString("en-NG", { maximumFractionDigits: 2 })}`;
}
/** a day in words, "15 November 2026", read in Lagos; a bare date (YYYY-MM-DD) is that day */
export function dayWords(iso: string | null | undefined): string {
  if (!iso) return "";
  const bare = /^\d{4}-\d{2}-\d{2}$/.test(iso);
  const d = new Date(bare ? `${iso}T12:00:00Z` : iso);
  if (Number.isNaN(d.getTime())) return "";
  return d.toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric", timeZone: bare ? "UTC" : "Africa/Lagos" });
}
/** today's date in Lagos, YYYY-MM-DD (the day the database reads an age on) */
export function lagosToday(now: Date = new Date()): string {
  return new Date(now.getTime() + 60 * 60 * 1000).toISOString().slice(0, 10);
}
const sizeWords = (bytes: number) => (bytes >= 1024 * 1024 ? `${(bytes / (1024 * 1024)).toFixed(1)} MB` : `${Math.max(1, Math.round(bytes / 1024))} KB`);
export { sizeWords };
const list = (xs: string[]) => xs.join("; ");

// ── the states in words ───────────────────────────────────────────────────────────────────────────────────────────────

/** what the applicant's banner says needs the view around the state: the date, the note, the programme, the next step */
export type ApplicantContext = Partial<Pick<IutView, "fee" | "kinds" | "documents" | "submittedAt" | "lastSubmittedAt" | "withdrawnAt" | "notice" | "applied" | "session" | "student" | "state">>;

/** D11: what the applicant reads at each state (SPEC §6). RECOMMENDED, NOT_RECOMMENDED and APPROVED read alike: "With the Registry for a
 *  decision", so nothing of the outcome reaches the applicant before the second officer decides — and the API gives the applicant
 *  WITH_REGISTRY for all three, read the same. */
export function applicantWords(state: string, v: ApplicantContext = {}): { stage: string; words: string; tone: Tone } {
  const programme = v.applied?.programmeName ?? v.applied?.programme ?? "the programme you applied for";
  switch (state) {
    case "DRAFT": return { stage: "Not yet submitted", words: `Not yet submitted. Next: ${nextStep({ ...v, state })}.`, tone: "info" };
    case "SUBMITTED": {
      const on = dayWords(v.lastSubmittedAt ?? v.submittedAt);
      return { stage: "Submitted", words: `Submitted${on ? ` on ${on}` : ""}. The Registry is checking your documents.`, tone: "info" };
    }
    case "CORRECTION_REQUIRED": {
      const note = (v.notice?.kind === "CORRECTION" ? v.notice.note : null)?.trim().replace(/[.\s]+$/, "");
      return { stage: "Returned to you", words: `Returned to you${note ? `: ${note}` : ""}. Replace the documents marked and submit again.`, tone: "bad" };
    }
    case "WITH_HOD": return { stage: "With the department", words: `Your documents are checked. The Head of Department of ${programme} is assessing your application.`, tone: "info" };
    case "RECOMMENDED": case "NOT_RECOMMENDED": case "APPROVED": case WITH_REGISTRY:
      return { stage: "With the Registry", words: "With the Registry for a decision.", tone: "info" };
    case "ADMITTED": {
      const no = v.student?.admissionNo ?? v.student?.matricNo ?? null;
      // the level admitted at (the API's student.level: the Head of Department's), never the one applied for
      const level = v.student?.level ?? null;
      // this password opens the student door only at its first sign-in (D18: carried over then); after it, the portal's own
      const password = v.student?.portalOpened ? "your student portal's own password" : "this password";
      return {
        stage: "Admitted",
        words: `Admitted to ${programme}${level ? `, ${level} Level` : ""}${v.session ? `, ${v.session}` : ""}.${no ? ` Admission number ${no}.` : ""} Sign in as a student with ${no ? "it" : "your admission number"} and ${password}.`,
        tone: "ok",
      };
    }
    case "REJECTED": {
      const note = (v.notice?.kind === "REJECTED" ? v.notice.note : null)?.trim().replace(/[.\s]+$/, "");
      return { stage: "Not admitted", words: `Not admitted.${note ? ` Reason: ${note}.` : ""}`, tone: "bad" };
    }
    case "WITHDRAWN": {
      const on = dayWords(v.withdrawnAt);
      return { stage: "Withdrawn", words: `Withdrawn${on ? ` on ${on}` : ""}.`, tone: "info" };
    }
    default: return { stage: state, words: state, tone: "info" };
  }
}

/** what the offices read at each state, with the pill's colour */
export const OFFICE_WORDS: Record<IutState, [string, Pill]> = {
  DRAFT: ["Not yet submitted", "grey"],
  SUBMITTED: ["Submitted: documents to check", "warn"],
  CORRECTION_REQUIRED: ["Returned to the applicant", "info"],
  WITH_HOD: ["With the Head of Department", "info"],
  RECOMMENDED: ["Recommended: for the Registry's decision", "warn"],
  NOT_RECOMMENDED: ["Not recommended: for the Registry's decision", "warn"],
  APPROVED: ["Approved: waiting for another officer", "info"],
  ADMITTED: ["Admitted", "ok"],
  REJECTED: ["Rejected", "bad"],
  WITHDRAWN: ["Withdrawn", "grey"],
};
export function officeWords(state: string): [string, Pill] {
  return OFFICE_WORDS[state as IutState] ?? [state, "grey"];
}

/** a session's applications by state in the offices' words, in the order of the states (as the list's chips read them), the states
 *  with none left out; empty when there are none */
export function countWords(counts: Record<string, number> | null | undefined): string {
  const c = counts ?? {};
  const known = new Set<string>(STATES);
  return [...STATES, ...Object.keys(c).filter((s) => !known.has(s))]
    .filter((s) => (c[s] ?? 0) > 0)
    .map((s) => `${officeWords(s)[0]} · ${c[s]}`)
    .join("; ");
}

/** the history's actions in words; the applicant reads only the ones shown to them, in their own words where those differ */
const EVENT: Record<string, string> = {
  CREATED: "Application started", EDITED: "Particulars changed", FEE_NONE_DUE: "No application fee due", FEE_PAID: "Application fee paid",
  FEE_PAID_AGAIN: "A second payment received: owed back", DOCUMENT_UPLOADED: "Document uploaded", DOCUMENT_REMOVED: "Document removed",
  DOCUMENT_ACCEPTED: "Document accepted", DOCUMENT_REJECTED: "Document rejected", SUBMITTED: "Submitted", RESUBMITTED: "Submitted again",
  RETURNED: "Returned to the applicant for correction", SENT_TO_HOD: "Sent to the Head of Department", RECOMMENDED: "Recommended by the Head of Department",
  NOT_RECOMMENDED: "Not recommended by the Head of Department", SENT_BACK_TO_HOD: "Sent back to the Head of Department",
  UNIVERSITY_SET: "University set from the list", APPROVED: "Approved by the Registry: another officer decides the transfer",
  TRANSFER_REJECTED: "The transfer was rejected by the deciding officer: back with the Registry", ADMITTED: "Admitted", REJECTED: "Rejected by the Registry",
  WITHDRAWN: "Withdrawn",
};
const EVENT_APPLICANT: Record<string, string> = {
  RETURNED: "Returned to you for correction", SENT_TO_HOD: "Documents checked: with the Head of Department", REJECTED: "Not admitted", WITHDRAWN: "Withdrawn at your request",
};
export function eventWords(action: string, forApplicant = false): string {
  return (forApplicant ? EVENT_APPLICANT[action] : undefined) ?? EVENT[action] ?? action.replace(/_/g, " ").toLowerCase();
}

/** where the application stands, 0 to 4, for the progress list: with the applicant; with the Registry's check; with the department;
 *  with the Registry for a decision; decided */
export const STAGES: [string, string][] = [
  ["Your application", "Particulars, the fee, the documents, then submit"],
  ["The Registry checks your documents", "Each document is accepted, or returned to you to replace"],
  ["The Head of Department assesses it", "The department of the programme you applied for"],
  ["The Registry decides", "Then another officer confirms the transfer"],
  ["Decided", "Admitted, not admitted, or withdrawn"],
];
export function stageIndex(state: string): number {
  switch (state) {
    case "DRAFT": case "CORRECTION_REQUIRED": return 0;
    case "SUBMITTED": return 1;
    case "WITH_HOD": return 2;
    case "RECOMMENDED": case "NOT_RECOMMENDED": case "APPROVED": case WITH_REGISTRY: return 3;
    default: return 4;
  }
}

// ── the fee ───────────────────────────────────────────────────────────────────────────────────────────────────────────

/** the payment that settled the application, when one did */
export function settlingReference(v: Pick<IutView, "fee">): IutReference | null {
  return (v.fee?.references ?? []).find((r) => r.settles && r.confirmedAt) ?? null;
}

/** a fee of nothing published after the application was made under a fee (the Bursar restated it): nothing is to pay, and the
 *  application is settled once the applicant asks for a reference (iut_fee_reference_draw settles it NONE_DUE) */
export function zeroDue(v: Partial<Pick<IutView, "fee">>): boolean {
  const f = v.fee ?? null;
  return !f?.settled && f?.due != null && f.due !== "" && Number.isFinite(Number(f.due)) && num(f.due) === 0;
}

/** an application closed before its fee was paid (withdrawn as a draft): no fee is taken on it, and the API gives no fee due */
export function feeClosed(v: Partial<Pick<IutView, "fee" | "state">>): boolean {
  return !v.fee?.settled && !!v.state && v.state !== "DRAFT";
}

/** the fee in words: none due, paid with its receipt, none taken on an application withdrawn unpaid, or what is to pay */
export function feeWords(v: Partial<Pick<IutView, "fee" | "session" | "state">>): string {
  const f = v.fee ?? null;
  if (f?.settled) {
    if (f.basis === "NONE_DUE") return `No application fee is due${v.session ? ` for ${v.session}` : ""}.`;
    const r = settlingReference(v);
    return r ? `Paid ${naira(r.amount)}${r.confirmedAt ? ` on ${dayWords(r.confirmedAt)}` : ""}${r.receiptNo ? `, receipt ${r.receiptNo}` : ""}.` : "Paid.";
  }
  if (feeClosed(v)) return `No application fee is taken on ${v.state === "WITHDRAWN" ? "a withdrawn" : "this"} application.`;
  if (zeroDue(v)) return `No application fee is due${v.session ? ` for ${v.session}` : ""}: confirm it below, then upload your documents.`;
  if (f?.due != null && f.due !== "" && num(f.due) > 0) return `${naira(f.due)} to pay. Your documents are uploaded after it.`;
  return "The application fee is not published yet. The Bursary publishes it.";
}

/** what is still owed back on a confirmed payment that did not settle the application, the refund desk's refunds taken off; nothing on
 *  the payment that settled it, or on one not paid */
export function stillOwedBack(r: Pick<IutReference, "amount" | "refunded" | "settles" | "confirmedAt">): number {
  if (!r.confirmedAt || r.settles) return 0;
  return Math.max(0, num(r.amount) - num(r.refunded));
}

/** what a confirmed payment is, as the applicant's fee panel heads it: the receipt of the fee; a payment after the fee was settled;
 *  or, on an application that was never settled (withdrawn before the payment arrived), the only payment, owed back all the same —
 *  and once the refund desk has given it back, in whole or in part, so (never "owed back" over money already returned) */
export function paymentTitle(r: Pick<IutReference, "reference"> & Partial<Pick<IutReference, "amount" | "refunded">>, v: Pick<IutView, "fee">): string {
  const settling = settlingReference(v);
  if (settling && r.reference === settling.reference) return "Application fee receipt";
  const what = settling ? "A second payment" : "A payment";
  const given = num(r.refunded);
  if (given > 0) {
    const owed = Math.max(0, num(r.amount) - given);
    return owed > 0 ? `${what}: ${naira(given)} refunded to you, ${naira(owed)} still owed back by the Bursary` : `${what}: refunded to you by the Bursary`;
  }
  return settling ? "A second payment: owed back to you by the Bursary" : "A payment owed back to you by the Bursary";
}

/** the fee as the Registry's desk reads it — of the applicant, never to them (feeWords is the applicant's own: "your documents are
 *  uploaded after it", "confirm it below") */
export function officeFeeWords(v: Partial<Pick<IutView, "fee" | "session" | "state">>): string {
  const f = v.fee ?? null;
  if (f?.settled) {
    if (f.basis === "NONE_DUE") return `No application fee was due${v.session ? ` for ${v.session}` : ""}.`;
    const r = settlingReference({ fee: f });
    return r ? `Paid ${naira(r.amount)}${r.confirmedAt ? ` on ${dayWords(r.confirmedAt)}` : ""}${r.receiptNo ? `, receipt ${r.receiptNo}` : ""}.` : "Paid.";
  }
  if (feeClosed(v)) return v.state === "WITHDRAWN" ? "None taken: withdrawn before the fee was paid." : "None taken: the application ended before the fee was paid.";
  if (zeroDue(v)) return "No fee is due; the applicant has not yet confirmed it on the portal.";
  if (f?.due != null && f.due !== "" && num(f.due) > 0) return `${naira(f.due)}, not yet paid.`;
  return "Not published yet: the Bursary publishes the session's fee.";
}
/** the pill beside it, following the same reading */
export function officeFeePill(v: Partial<Pick<IutView, "fee" | "state">>): [string, Pill] {
  const f = v.fee ?? null;
  if (f?.settled) return [f.basis === "NONE_DUE" ? "None due" : "Paid", "ok"];
  if (feeClosed(v)) return ["Not taken", "grey"];
  if (zeroDue(v)) return ["None due", "info"];
  return ["Not paid", "warn"];
}
/** a payment's standing on the Registry's fee table: the one that settles the fee; one owed back (what is still owed, once the refund
 *  desk has given part of it back); one given back whole; nothing for a reference not paid */
export function referencePill(r: Pick<IutReference, "amount" | "refunded" | "settles" | "confirmedAt">): [string, Pill] | null {
  if (!r.confirmedAt) return null;
  if (r.settles) return ["Settles the fee", "ok"];
  const owed = stillOwedBack(r);
  if (owed <= 0) return ["Refunded", "grey"];
  return num(r.refunded) > 0 ? [`${naira(owed)} still owed back`, "bad"] : ["Owed back", "bad"];
}

// ── the documents ─────────────────────────────────────────────────────────────────────────────────────────────────────

export type DocStatus = "MISSING" | "PENDING" | "ACCEPTED" | "REJECTED";
export interface ChecklistRow {
  code: string; label: string; hint: string | null; required: boolean; imagesAllowed: boolean;
  status: DocStatus; note: string | null; document: IutDocument | null; canUpload: boolean; canRemove: boolean; why: string | null;
}

/** what can be done with each document while the application is with the applicant: a document the Registry accepted is never
 *  replaced; returned for correction, only a rejected document (or a missing one) is uploaded again; documents come after the fee */
export function documentChecklist(kinds: DocumentKind[] | null | undefined, documents: IutDocument[] | null | undefined, state: string = "DRAFT", feeSettled = true,
  noneDue = false): ChecklistRow[] {
  const current = (documents ?? []).filter((d) => !d.supersededAt);
  const open = state === "DRAFT" || state === "CORRECTION_REQUIRED";
  const row = (k: DocumentKind, d: IutDocument | null): ChecklistRow => {
    const status: DocStatus = d ? (d.status === "ACCEPTED" || d.status === "REJECTED" ? d.status : "PENDING") : "MISSING";
    let why: string | null = null;
    if (!open) why = state === "WITHDRAWN" ? "The application is withdrawn" : state === "ADMITTED" || state === "REJECTED" ? "The application is decided"
      : "Your application is with the University";
    else if (!feeSettled) why = noneDue ? "Confirm that no application fee is due first; documents are uploaded after it" : "Pay the application fee first; documents are uploaded after it";
    else if (status === "ACCEPTED") why = "Accepted by the Registry: it is not replaced";
    else if (state === "CORRECTION_REQUIRED" && status === "PENDING") why = "Still being checked: only the documents marked are replaced";
    const canUpload = why === null;
    const canRemove = open && !!d && status !== "ACCEPTED";
    return {
      code: k.code, label: d?.label ?? k.label, hint: k.hint ?? null, required: !!k.required, imagesAllowed: k.imagesAllowed !== false,
      status, note: status === "REJECTED" ? d?.note ?? null : null, document: d, canUpload, canRemove, why,
    };
  };
  const rows = (kinds ?? []).filter((k) => k.active !== false).map((k) => row(k, current.find((d) => d.kind === k.code) ?? null));
  // a document of a kind no longer asked for is still shown, as it stands
  for (const d of current) {
    if (rows.some((r) => r.code === d.kind)) continue;
    const r = row({ code: d.kind, label: d.label ?? d.kind, required: false, imagesAllowed: true }, d);
    rows.push({ ...r, canUpload: false, why: r.why ?? "No longer asked for" });
  }
  return rows;
}

/** the MIME type of a chosen file: the browser's, else read from its name (a browser may give none) */
export function documentType(file: { type?: string | null; name?: string | null }): string {
  const t = (file.type ?? "").toLowerCase();
  if (t) return t === "image/jpg" || t === "image/pjpeg" ? "image/jpeg" : t;
  const ext = /\.([a-z0-9]+)$/i.exec(file.name ?? "")?.[1]?.toLowerCase() ?? "";
  return ext === "pdf" ? "application/pdf" : ext === "jpg" || ext === "jpeg" ? "image/jpeg" : ext === "png" ? "image/png" : "";
}

/** why a file cannot be sent for a kind, or null: the type (PDF, or an image where the kind takes one) and the size (D12). The server
 *  checks the first bytes besides. */
export function fileProblem(file: { type?: string | null; size: number; name?: string | null }, kind: Pick<DocumentKind, "imagesAllowed"> | null = null,
  maxBytes: number = MAX_DOCUMENT_BYTES): string | null {
  const type = documentType(file);
  const images = kind?.imagesAllowed !== false;
  if (!(DOCUMENT_TYPES as readonly string[]).includes(type)) return images ? "A PDF, JPEG or PNG file only." : "This document is taken as a PDF only.";
  if (type !== "application/pdf" && !images) return "This document is taken as a PDF only: scan it, or save the photograph as a PDF.";
  if (file.size <= 0) return "The file is empty.";
  if (file.size > maxBytes) return `At most ${sizeWords(maxBytes)} a file; this one is ${sizeWords(file.size)}.`;
  return null;
}

/** a data URL with the type the file is, whatever the browser wrote (some write none) */
export function typedDataUrl(dataUrl: string, type: string): string {
  return dataUrl.replace(/^data:[^;,]*/, `data:${type}`);
}

/** why the application cannot be submitted yet; none when it can */
export function canSubmit(v: Pick<IutView, "state" | "fee" | "kinds" | "documents">): string[] {
  if (v.state !== "DRAFT" && v.state !== "CORRECTION_REQUIRED") return ["Only an application not yet submitted, or returned to you, is submitted."];
  const out: string[] = [];
  const settled = !!v.fee?.settled;
  if (!settled) {
    out.push(zeroDue(v) ? "Confirm that no application fee is due first."
      : `Pay the application fee${v.fee?.due != null && num(v.fee.due) > 0 ? ` of ${naira(v.fee.due)}` : ""} first.`);
  }
  const rows = documentChecklist(v.kinds, v.documents, v.state, settled);
  const missing = rows.filter((r) => r.required && r.status === "MISSING").map((r) => r.label);
  if (missing.length) out.push(`Upload: ${list(missing)}.`);
  const rejected = rows.filter((r) => r.status === "REJECTED").map((r) => r.label);
  if (rejected.length) out.push(`Replace: ${list(rejected)}.`);
  return out;
}

/** the next thing to do on an application with the applicant */
export function nextStep(v: ApplicantContext): string {
  const reasons = canSubmit({ state: v.state ?? "DRAFT", fee: v.fee, kinds: v.kinds, documents: v.documents });
  const first = reasons[0];
  if (!first) return "submit";
  return first.charAt(0).toLowerCase() + first.slice(1).replace(/\.$/, "");
}

/** withdrawn by the applicant until the department has assessed it (iut_withdraw). With the Registry for a decision (WITH_REGISTRY: a
 *  recommendation, a decline or an approval) it is asked of the Registry, alike in all three (D11) */
export function mayWithdraw(state: string): boolean {
  return ["DRAFT", "SUBMITTED", "CORRECTION_REQUIRED", "WITH_HOD"].includes(state);
}
/** with the Registry for a decision: the applicant who would withdraw writes to the Registry */
export function withdrawFromRegistry(state: string): boolean {
  return WITH_THE_REGISTRY.includes(state);
}
/** the acknowledgement is printed once the application has been submitted */
export function hasAcknowledgement(v: Pick<IutView, "state" | "submittedAt">): boolean {
  return !!v.submittedAt && v.state !== "DRAFT" && v.state !== "WITHDRAWN";
}

// ── the form ──────────────────────────────────────────────────────────────────────────────────────────────────────────

/** the particulars the API takes, by its own names (iut_apply's keys) */
export const PARTICULARS = ["surname", "otherNames", "sex", "dateOfBirth", "jambRegNo", "universityCode", "universityNamed", "otherMatricNo", "otherProgramme",
  "otherLevel", "otherEntrySession", "otherCgpa", "otherCgpaScale", "reason"] as const;
export type ApiField = (typeof PARTICULARS)[number] | "email" | "phone" | "programme" | "level";

/** what may be changed at each state, as iut_update allows it: a draft everything (the programme and level only while the window is
 *  open, D5); returned for correction, every particular but the programme and level; until a decision, the e-mail and phone */
export function editableFields(state: string, windowOpen: boolean): ApiField[] {
  const contact: ApiField[] = ["email", "phone"];
  if (state === "DRAFT") return [...PARTICULARS, ...contact, ...(windowOpen ? (["programme", "level"] as ApiField[]) : [])];
  if (state === "CORRECTION_REQUIRED") return [...PARTICULARS, ...contact];
  if (["SUBMITTED", "WITH_HOD", ...WITH_THE_REGISTRY].includes(state)) return contact;
  return [];
}

/** the programmes an edit of a draft offers: those open, with the application's own programme and level kept among them when the
 *  Academic Office has stopped taking new applications on that line — an application made on it keeps it (SPEC §3.2), and an edit of
 *  the phone alone must not be refused for a choice the applicant is not changing */
export function programmesWithCurrent(open: PublicProgramme[] | null | undefined, applied: IutView["applied"] | null | undefined): PublicProgramme[] {
  const list = [...(open ?? [])];
  const code = applied?.programme ?? null;
  const level = applied?.level ?? null;
  if (!code || !level) return list;
  const at = list.findIndex((p) => p.code === code);
  if (at >= 0) {
    if (!list[at].levels.includes(level)) list[at] = { ...list[at], levels: [...list[at].levels, level].sort((a, b) => a - b) };
    return list;
  }
  return [...list, { code, name: applied?.programmeName ?? code, dept: applied?.dept ?? null, deptName: applied?.deptName ?? null,
    faculty: applied?.faculty ?? null, facultyName: applied?.facultyName ?? null, levels: [level] }];
}

/** the API the public verification page asks: the number in the query — its slashes encoded in a path (%2F) are refused by the
 *  API's request firewall, so the acknowledgement would never verify */
export function verifyApiPath(applicationNo: string, code: string): string {
  return `/api/v1/verify/transfer-application?no=${encodeURIComponent(applicationNo)}&t=${encodeURIComponent(code)}`;
}

export interface ApplyForm {
  surname: string; otherNames: string; sex: "" | "M" | "F"; dateOfBirth: string; email: string; phone: string; jambRegNo: string;
  universityCode: string; notListed: boolean; universityNamed: string; otherMatricNo: string; otherProgramme: string; otherLevel: string;
  otherEntrySession: string; otherCgpa: string; otherCgpaScale: "" | "4" | "5";
  programme: string; level: string; reason: string;
  password: string; password2: string; privacy: boolean; website2: string;
}
export type ApplyField = keyof ApplyForm;

export function emptyApplyForm(): ApplyForm {
  return { surname: "", otherNames: "", sex: "", dateOfBirth: "", email: "", phone: "", jambRegNo: "", universityCode: "", notListed: false, universityNamed: "",
    otherMatricNo: "", otherProgramme: "", otherLevel: "", otherEntrySession: "", otherCgpa: "", otherCgpaScale: "", programme: "", level: "", reason: "",
    password: "", password2: "", privacy: false, website2: "" };
}

/** the form filled from an application: to edit it, or to apply again in a later window */
export function formFromView(v: IutView, account?: IutMe["account"]): ApplyForm {
  const a = v.applicant ?? {}, p = v.previous ?? {}, ap = v.applied ?? {};
  const named = !p.universityCode && !!p.universityNamed;
  return {
    ...emptyApplyForm(),
    surname: a.surname ?? "", otherNames: a.otherNames ?? "", sex: a.sex === "M" || a.sex === "F" ? a.sex : "", dateOfBirth: (a.dateOfBirth ?? "").slice(0, 10),
    email: account?.email ?? a.email ?? "", phone: account?.phone ?? a.phone ?? "", jambRegNo: a.jambRegNo ?? "",
    universityCode: p.universityCode ?? "", notListed: named, universityNamed: p.universityNamed ?? "", otherMatricNo: p.matricNo ?? "", otherProgramme: p.programme ?? "",
    otherLevel: p.level != null ? String(p.level) : "", otherEntrySession: p.entrySession ?? "",
    otherCgpa: p.cgpa != null && p.cgpa !== "" ? num(p.cgpa).toFixed(2) : "", otherCgpaScale: p.cgpaScale === 4 || p.cgpaScale === 5 ? (String(p.cgpaScale) as "4" | "5") : "",
    programme: ap.programme ?? "", level: ap.level != null ? String(ap.level) : "", reason: v.reason ?? "",
  };
}

/** a phone number as people.contact_phone keeps it: 0 and ten digits; +234 and 234 read as 0, a dropped leading 0 put back */
export function normalPhone(p: string): string {
  const d = p.replace(/[^0-9]/g, "");
  if (/^234[0-9]{10}$/.test(d)) return `0${d.slice(3)}`;
  if (/^[789][0-9]{9}$/.test(d)) return `0${d}`;
  return d;
}
/** a number as the database reads one: no spaces, capitals */
export const numberOf = (s: string) => s.replace(/\s+/g, "").toUpperCase();

const NAME = /^[\p{L}][\p{L} '-]*$/u;
const EMAIL = /^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$/;
const JAMB = /^[0-9]{12}[A-Z]{2,3}$/;
const MATRIC = /^[A-Z0-9/._-]{1,40}$/;
const LEVEL = (s: string) => /^[1-9]00$/.test(s.trim());

/** the age in whole years on a day (both YYYY-MM-DD) */
export function ageOn(dob: string, today: string): number | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dob), t = /^(\d{4})-(\d{2})-(\d{2})$/.exec(today);
  if (!m || !t) return null;
  const d = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]));
  if (d.getUTCFullYear() !== +m[1] || d.getUTCMonth() !== +m[2] - 1 || d.getUTCDate() !== +m[3]) return null;
  let age = +t[1] - +m[1];
  if (+t[2] < +m[2] || (+t[2] === +m[2] && +t[3] < +m[3])) age--;
  return age;
}

export interface ApplyOptions {
  programmes?: PublicProgramme[] | null; universities?: PublicUniversity[] | null; session?: string | null;
  /** YYYY-MM-DD: the day the age is read on (Lagos today by default) */
  today?: string;
  /** applying again from a signed-in account: no e-mail, phone, password or privacy box */
  again?: boolean;
  /** only these fields are checked (an edit of what the state allows); every one by default */
  only?: ApiField[] | null;
}

/** what the form must give before it is sent, field by field in the page's order, so the first is the one to put right first. The
 *  database checks the same rules (iut_apply) and says them; these spare a round trip. */
export function applyErrors(f: ApplyForm, o: ApplyOptions = {}): Partial<Record<ApplyField, string>> {
  const e: Partial<Record<ApplyField, string>> = {};
  const asked = (k: ApiField) => !o.only || o.only.includes(k);
  const surname = f.surname.trim(), other = f.otherNames.trim();
  if (asked("surname") && !(surname.length >= 2 && surname.length <= 60 && NAME.test(surname))) e.surname = "Your surname: 2 to 60 letters (letters, spaces, ' and - only)";
  if (asked("otherNames") && !(other.length >= 2 && other.length <= 120 && NAME.test(other))) e.otherNames = "Your other names: 2 to 120 letters (letters, spaces, ' and - only)";
  if (asked("sex") && f.sex !== "M" && f.sex !== "F") e.sex = "Choose Male or Female";
  if (asked("dateOfBirth")) {
    const age = ageOn(f.dateOfBirth, o.today ?? lagosToday());
    if (age === null) e.dateOfBirth = "Give your date of birth";
    else if (age < 14 || age > 70) e.dateOfBirth = "An applicant is 14 to 70 years old";
  }
  if (!o.again) {
    if (asked("email") && !EMAIL.test(f.email.trim())) e.email = "An e-mail address you can read: you sign in with it, and the University writes to you there";
    if (asked("phone") && !/^0[0-9]{10}$/.test(normalPhone(f.phone))) e.phone = "A Nigerian phone number: 11 digits from 0 (or +234)";
  }
  const jamb = numberOf(f.jambRegNo);
  if (asked("jambRegNo") && !JAMB.test(jamb)) e.jambRegNo = "Your JAMB registration number: 12 digits and 2 or 3 letters";
  if (asked("universityCode") || asked("universityNamed")) {
    if (f.notListed) {
      const n = f.universityNamed.trim();
      if (n.length < 3 || n.length > 200) e.universityNamed = "Name your university: 3 to 200 characters";
    } else if (!f.universityCode || (o.universities && !o.universities.some((u) => u.code === f.universityCode))) {
      e.universityCode = "Choose your present university, or choose that it is not on the list";
    }
  }
  if (asked("otherMatricNo") && !MATRIC.test(numberOf(f.otherMatricNo))) e.otherMatricNo = "Your matriculation number there: letters, digits and / . _ - (at most 40)";
  const op = f.otherProgramme.trim();
  if (asked("otherProgramme") && (op.length < 3 || op.length > 200)) e.otherProgramme = "The programme you study there: 3 to 200 characters";
  if (asked("otherLevel") && !LEVEL(f.otherLevel)) e.otherLevel = "The level you have reached there";
  if (asked("otherEntrySession")) {
    const es = f.otherEntrySession.replace(/\s+/g, "");
    const m = /^(\d{4})\/(\d{4})$/.exec(es);
    if (!m || +m[2] !== +m[1] + 1) e.otherEntrySession = "The session you entered there, written 2023/2024";
    else if (o.session && es > o.session) e.otherEntrySession = `The session you entered there cannot be after ${o.session}`;
  }
  if (asked("otherCgpa") || asked("otherCgpaScale")) {
    const g = f.otherCgpa.trim();
    if (f.otherCgpaScale !== "4" && f.otherCgpaScale !== "5") e.otherCgpaScale = "Choose the scale: 4 or 5 points";
    else if (!/^\d(\.\d{1,2})?$/.test(g)) e.otherCgpa = "Your CGPA: a number with up to two decimals, such as 3.45";
    else if (Number(g) > Number(f.otherCgpaScale)) e.otherCgpa = `Above the ${f.otherCgpaScale}-point scale`;
  }
  if (asked("programme") || asked("level")) {
    const prog = (o.programmes ?? []).find((p) => p.code === f.programme) ?? null;
    if (!prog) e.programme = "Choose the programme you apply for, from those taking transfer students";
    else if (!prog.levels.includes(Number(f.level))) e.level = "Choose the level you apply for, from those open";
  }
  const reason = f.reason.trim();
  if (asked("reason") && (reason.length < 20 || reason.length > 2000)) e.reason = "Say why you are transferring: 20 to 2,000 characters";
  if (!o.again && !o.only) {
    if (f.password.length < 8 || f.password.length > 200) e.password = "At least 8 characters";
    else if (numberOf(f.password) === jamb && jamb) e.password = "Not your JAMB number";
    if (f.password2 !== f.password) e.password2 = "The two passwords do not match";
    if (!f.privacy) e.privacy = "Tick the box to say you have read the Privacy Policy";
  }
  return e;
}

/** the form as the API takes it (iut_apply's keys): the confirmation and the privacy box stay in the browser; the JAMB and matriculation
 *  numbers in capitals with no spaces; the phone as the database keeps it; a university on the list, or one named */
export function applyBody(f: ApplyForm, o: { again?: boolean } = {}): Record<string, unknown> {
  const body: Record<string, unknown> = {
    surname: f.surname.trim(), otherNames: f.otherNames.trim().replace(/\s+/g, " "), sex: f.sex, dateOfBirth: f.dateOfBirth,
    jambRegNo: numberOf(f.jambRegNo),
    universityCode: f.notListed ? null : f.universityCode || null, universityNamed: f.notListed ? f.universityNamed.trim() : null,
    otherMatricNo: numberOf(f.otherMatricNo), otherProgramme: f.otherProgramme.trim(), otherLevel: Number(f.otherLevel),
    otherEntrySession: f.otherEntrySession.replace(/\s+/g, ""), otherCgpa: f.otherCgpa.trim(), otherCgpaScale: Number(f.otherCgpaScale),
    programme: f.programme, level: Number(f.level), reason: f.reason.trim(),
  };
  if (!o.again) Object.assign(body, { email: f.email.trim().toLowerCase(), phone: normalPhone(f.phone), password: f.password, website2: f.website2 });
  return body;
}

/** an edit as PUT /me takes it: the fields changed, of those the state allows (any other is refused IUT_NOT_EDITABLE) */
export function updateBody(f: ApplyForm, was: ApplyForm, allowed: ApiField[]): Record<string, unknown> {
  const now = applyBody(f), before = applyBody(was);
  const contact = { email: f.email.trim().toLowerCase(), phone: normalPhone(f.phone) };
  const contactWas = { email: was.email.trim().toLowerCase(), phone: normalPhone(was.phone) };
  const out: Record<string, unknown> = {};
  for (const k of allowed) {
    const a = k === "email" || k === "phone" ? contact[k] : now[k];
    const b = k === "email" || k === "phone" ? contactWas[k] : before[k];
    if (JSON.stringify(a ?? null) !== JSON.stringify(b ?? null)) out[k] = a ?? null;
  }
  // a university is one of the two: a change of either sends both
  if (("universityCode" in out || "universityNamed" in out) && allowed.includes("universityCode") && allowed.includes("universityNamed")) {
    out.universityCode = now.universityCode ?? null;
    out.universityNamed = now.universityNamed ?? null;
  }
  return out;
}

/** the programmes the apply page offers, grouped as its select shows them: by faculty, then department */
export function programmeGroups(programmes: PublicProgramme[] | null | undefined): { label: string; programmes: PublicProgramme[] }[] {
  const out: { label: string; programmes: PublicProgramme[] }[] = [];
  const sorted = [...(programmes ?? [])].sort((a, b) => (a.facultyName ?? a.faculty ?? "").localeCompare(b.facultyName ?? b.faculty ?? "")
    || (a.deptName ?? a.dept ?? "").localeCompare(b.deptName ?? b.dept ?? "") || a.name.localeCompare(b.name));
  for (const p of sorted) {
    const label = [p.facultyName ?? p.faculty, p.deptName ?? p.dept].filter(Boolean).join(" · ") || "Programmes";
    const g = out.find((x) => x.label === label);
    if (g) g.programmes.push(p); else out.push({ label, programmes: [p] });
  }
  return out;
}

/** the documents asked, in a sentence: the required ones, then the optional */
export function documentsWords(kinds: DocumentKind[] | null | undefined): { required: string; optional: string } {
  const live = (kinds ?? []).filter((k) => k.active !== false);
  return { required: live.filter((k) => k.required).map((k) => k.label).join("; "), optional: live.filter((k) => !k.required).map((k) => k.label).join("; ") };
}

/** whether the public window is open: the API's word, else its status */
export function windowIsOpen(w: IutPublicWindow | null | undefined): boolean {
  if (!w) return false;
  return w.open != null ? w.open === true : w.status === "OPEN";
}

/** the window in the shape the closed page reads (components/ApplicationClosed), filled where the API left a key out; with no window
 *  ever opened the session is blank (the page then names none); null when there is no answer at all */
export function publicWindowOf(o: PublicOptions | null | undefined, origin = ""): {
  type: string; label: string; session: string; status: string; open: boolean; opensAt: string | null; closesAt: string | null; message: string | null;
  applicationPath: string; applicationUrl: string;
} | null {
  if (!o) return null;
  const w: IutPublicWindow = o.window ?? { status: "CLOSED" };
  const session = w.session ?? o.session ?? "";
  return {
    type: w.type ?? "INTER_UNIVERSITY_TRANSFER_APPLICATION", label: w.label ?? "Inter-university transfer application", session,
    status: w.status ?? "CLOSED", open: windowIsOpen(w),
    opensAt: w.opensAt ?? (w.opensOn ? `${w.opensOn}T00:00:00+01:00` : null), closesAt: w.closesAt ?? (w.closesOn ? `${w.closesOn}T23:59:59+01:00` : null),
    message: w.message ?? null, applicationPath: w.applicationPath ?? "/transfer/apply", applicationUrl: w.applicationUrl ?? `${origin}/transfer/apply`,
  };
}

// ── the desks: what they read ─────────────────────────────────────────────────────────────────────────────────────────

/** a programme and level taking transfer students in a session (admissions.iut_line, as iut_window_view gives it) */
export interface WindowLine {
  programme: string; programmeName?: string | null; dept?: string | null; deptName?: string | null; faculty?: string | null; facultyName?: string | null;
  level: number; places?: number | null; accepting: boolean; applications?: number | null; approved?: number | null; admitted?: number | null;
  /** the programme still takes transfer students (undergraduate, not archived); levelInUse: the level is still one of the programme's (a
   *  programme shortened since, ref.set_programme_length, has not); offered: accepting on such a programme and level, as the public lists it */
  programmeInUse?: boolean | null; levelInUse?: boolean | null; offered?: boolean | null;
}
/** GET /office/window: the session's window, its fee as the Bursary left it, its lines and the applications by state */
export interface WindowView {
  session: string; state?: "DRAFT" | "OPEN" | "CLOSED" | string | null; status?: string | null; opensOn?: string | null; closesOn?: string | null;
  message?: string | null; note?: string | null; setByName?: string | null; setOffice?: string | null; setAt?: string | null;
  fee?: { amount?: Money; state?: string | null; published?: boolean | null; draftAmount?: Money } | null;
  /** the lines the public is offered (accepting, on a programme in use) */
  offered?: number | null;
  lines?: WindowLine[]; counts?: Record<string, number>;
}
/** GET /office/programmes: the undergraduate programmes a line may name, each with its levels (names read whichever way the API writes them) */
export interface OfficeProgramme { code: string; name: string; dept: string; deptName: string; faculty: string; facultyName: string; levels: number[] }
export function officeProgramme(x: Record<string, unknown>): OfficeProgramme {
  const s = (...k: string[]) => { for (const key of k) { const v = x[key]; if (typeof v === "string" && v) return v; } return ""; };
  const levels = Array.isArray(x.levels) ? (x.levels as unknown[]).map(Number).filter((n) => Number.isFinite(n) && n > 0) : [];
  return { code: s("code", "programme", "programmeCode", "programme_code"), name: s("name", "programmeName", "programme_name"),
    dept: s("dept", "deptCode", "dept_code"), deptName: s("deptName", "dept_name", "department", "departmentName"),
    faculty: s("faculty", "facultyCode", "faculty_code"), facultyName: s("facultyName", "faculty_name", "facultyName"), levels };
}
/** a row of GET /office/applications (iut_applications) */
export interface ApplicationRow {
  id: string; applicationNo: string; session: string; state: string; surname?: string | null; otherNames?: string | null; jambRegNo?: string | null;
  universityCode?: string | null; universityName?: string | null; universityNamed?: string | null; programme?: string | null; programmeName?: string | null;
  dept?: string | null; deptName?: string | null; level?: number | null; hodLevel?: number | null; cgpa?: Money; cgpaScale?: number | null;
  submittedAt?: string | null; updatedAt?: string | null; feeSettled?: boolean | null; documents?: { pending?: number; accepted?: number; rejected?: number } | null;
}
export interface ApplicationList { total: number; counts?: Record<string, number>; rows: ApplicationRow[] }
/** the V763 check of the transfer the application would register (people.university_transfer_form_check), for the Registry */
export interface TransferCheck {
  status?: "VALID" | "WARNING" | "INVALID" | string; action?: string | null; matchedBy?: string | null; student?: string | null;
  problems?: { code: string; text?: string | null }[]; warnings?: { code: string; text?: string | null }[];
}
export type OfficeDetail = IutView & { transferCheck?: TransferCheck | null };

/** the desks' lists are paged fifty at a time */
export const PAGE_SIZE = 50;

/** the history's fee steps, which the department never reads */
const FEE_STEPS = new Set(["FEE_NONE_DUE", "FEE_PAID", "FEE_PAID_AGAIN"]);
/** the Registry's acts whose note is its own words (to the applicant: a return, a rejection; the approval's; the deciding officer's; the
 *  university set), which the department reads without the note; its notes to the department (sent to it, sent back) stay */
const REGISTRY_NOTES = new Set(["RETURNED", "REJECTED", "APPROVED", "TRANSFER_REJECTED", "UNIVERSITY_SET"]);

/** what the department's desk is given of an application: the HOD view as the API answers it (no contact, fee, transfer, Registry or
 *  notice, and a history without the fee's steps or the Registry's own words), those left out again here so nothing more reaches the
 *  page whatever the answer held — a rejected document's note (the Registry's words to the applicant) included: the history names the
 *  document alone, and a document rejected or replaced shows no note */
export function forDepartment(v: OfficeDetail): OfficeDetail {
  const { email: _e, phone: _p, ...applicant } = v.applicant ?? {};
  void _e; void _p;
  const labels = new Set((v.kinds ?? []).map((k) => k.label));
  const history = v.history?.filter((h) => !FEE_STEPS.has(h.action))
    .map((h) => ((REGISTRY_NOTES.has(h.action) || (h.action === "DOCUMENT_REJECTED" && !labels.has(h.note ?? ""))) && h.note != null ? { ...h, note: undefined } : h));
  const quiet = (d: IutDocument) => (d.status === "REJECTED" && d.note != null ? { ...d, note: undefined } : d);
  return { ...v, applicant, fee: undefined, transfer: undefined, registry: undefined, notice: undefined, transferCheck: undefined, history,
    documents: v.documents?.map(quiet), superseded: v.superseded?.map(quiet) };
}

/** the list's query string: the session (or every session), the state, the programme, the search and the page */
export function listQuery(f: { session?: string | null; state?: string | null; programme?: string | null; q?: string | null; page?: number | null; size?: number | null }): string {
  const p = new URLSearchParams();
  if (f.session) p.set("session", f.session);
  if (f.state) p.set("state", f.state);
  if (f.programme) p.set("programme", f.programme);
  if (f.q && f.q.trim()) p.set("q", f.q.trim());
  if (f.page) p.set("page", String(f.page));
  if (f.size) p.set("size", String(f.size));
  return p.toString();
}

/** a CGPA as the desks show it: "3.85 of 5" */
export function cgpaOf(cgpa: Money, scale: number | null | undefined): string {
  if (cgpa === null || cgpa === undefined || cgpa === "") return "—";
  return `${num(cgpa).toFixed(2)} of ${scale ?? 5}`;
}

// ── the desks ─────────────────────────────────────────────────────────────────────────────────────────────────────────

export type OfficeAction = "SEND_TO_HOD" | "RETURN" | "SEND_BACK_TO_HOD" | "APPROVE" | "REJECT";
export interface ActionButton {
  action: OfficeAction; label: string; enabled: boolean; why: string | null;
  /** the note the act asks: none, optional, or required (with its least length) */
  note: "none" | "optional" | "required"; noteMin: number; noteLabel: string;
  kind: "primary" | "secondary" | "ghost" | "go" | "urgent";
  /** what an enabled act costs the applicant, said before it is done (a paid draft ended loses its fee) */
  warning?: string | null;
}

/** what the documents say for the Registry: any still to check, any rejected, and — with required (the default: sending to the Head of
 *  Department) — any kind required now without an accepted one. The approval passes required false, as the API's does
 *  (admissions.iut_unchecked(app, false)): a kind made required after the department had the application never holds it, and nothing
 *  would let the applicant upload it by then */
export function documentsUnchecked(v: Pick<IutView, "kinds" | "documents">, required = true): string | null {
  const current = (v.documents ?? []).filter((d) => !d.supersededAt);
  const label = (d: IutDocument) => d.label ?? (v.kinds ?? []).find((k) => k.code === d.kind)?.label ?? d.kind;
  const pending = current.filter((d) => d.status !== "ACCEPTED" && d.status !== "REJECTED").map(label);
  if (pending.length) return `Accept or reject each document first: ${list(pending)}`;
  const rejected = current.filter((d) => d.status === "REJECTED").map(label);
  if (rejected.length) return `A document is rejected (${list(rejected)}): return the application to the applicant, or reject it`;
  if (!required) return null;
  const notAccepted = (v.kinds ?? []).filter((k) => k.active !== false && k.required && !current.some((d) => d.kind === k.code && d.status === "ACCEPTED")).map((k) => k.label);
  if (notAccepted.length) return `A required document is missing: ${list(notAccepted)}`;
  return null;
}

/** V763's check would record the transfer on a student already on the register (RECORD_ON_EXISTING, only a warning on its form): an
 *  online application is never approved so (IUT_STUDENT_EXISTS) — the applicant would be admitted onto that student's record */
export function studentHere(check: TransferCheck | null | undefined): boolean {
  return check?.action === "RECORD_ON_EXISTING";
}
export const STUDENT_HERE = "A student already on the register holds this JAMB number at this programme and level: an online application never admits onto that record. Reject it, or take the record up with the Registry's records";

/** what V763's check of the transfer refuses (INVALID: the programme archived, a transfer of the student pending, and the like): the
 *  approval runs the same check and is refused (UNIVERSITY_TRANSFER_FORM_INVALID), so Approve is closed with the check's own words */
export function checkRefusal(check: TransferCheck | null | undefined): string | null {
  if (check?.status !== "INVALID") return null;
  const said = (check.problems ?? []).map((p) => p.text || p.code).filter(Boolean);
  return `The transfer check refuses this transfer${said.length ? `: ${list(said)}` : ""}`;
}

/** a draft whose fee is paid, ended by the Registry: the fee is not refunded (D19), and the account cannot apply again in the window */
export const PAID_DRAFT_ENDED = "Its fee is paid: ended, the fee is not refunded and the account cannot apply again in this window";

/** the Head of Department's Accept when the window has no line of the programme at a level it still has (each line's level gone since
 *  the programme was shortened, or none added): nothing to recommend at until the Academic Office adds one */
export const NO_LEVEL_TO_RECOMMEND = "The window has no level of this programme to recommend at (a level the programme no longer has is not offered): "
  + "ask the Academic Office to add one, or decline with a reason";

/** the Registry's buttons for the state the application is in, each with why it is closed; none for a reader (Records) or once the
 *  Registry has approved (another officer decides on the Inter-University Transfer page) */
export function officeActions(v: Pick<IutView, "state" | "kinds" | "documents" | "previous"> & Partial<Pick<IutView, "fee">> & { transferCheck?: TransferCheck | null },
  office: string | null | undefined): ActionButton[] {
  if (!KEEPERS.includes(office ?? "")) return [];
  const b = (action: OfficeAction, label: string, why: string | null, note: ActionButton["note"], noteLabel: string, kind: ActionButton["kind"]): ActionButton =>
    ({ action, label, enabled: why === null, why, note, noteMin: note === "required" ? 10 : 0, noteLabel, kind });
  const reject = b("REJECT", "Reject", null, "required", "The reason, which the applicant reads (ten characters or more)", "urgent");
  const docs = documentsUnchecked(v);
  switch (v.state) {
    case "SUBMITTED": return [
      b("SEND_TO_HOD", "Send to the Head of Department", docs, "none", "", "primary"),
      b("RETURN", "Return to the applicant", null, "required", "What the applicant is to put right (ten characters or more)", "secondary"),
      reject,
    ];
    // a draft holds its JAMB number until it ends: the Registry ends one made under another person's number (never for lateness: a
    // started application has no deadline, D5); a paid one loses its fee so, which the button says
    case "DRAFT": return [{ ...b("REJECT", "Reject", null, "required", "The reason, which the account that made the draft reads (ten characters or more)", "urgent"),
      warning: v.fee?.settled && v.fee.basis === "PAID" ? PAID_DRAFT_ENDED : null }];
    case "CORRECTION_REQUIRED": case "WITH_HOD": return [reject];
    case "RECOMMENDED": return [
      // in the API's order: the documents, a student already here, the university on the list, then V763's own check
      b("APPROVE", "Approve", documentsUnchecked(v, false) ?? (studentHere(v.transferCheck) ? STUDENT_HERE : null) ?? (v.previous?.universityCode ? null
        : `Set the university from the list first${v.previous?.universityNamed ? `: ${v.previous.universityNamed} is not on it` : ""}`)
        ?? checkRefusal(v.transferCheck), "optional", "A note for the transfer (optional)", "go"),
      b("SEND_BACK_TO_HOD", "Send back to the Head of Department", null, "required", "What the Head of Department is to look at again (ten characters or more)", "secondary"),
      reject,
    ];
    case "NOT_RECOMMENDED": return [
      b("SEND_BACK_TO_HOD", "Send back to the Head of Department", null, "required", "What the Head of Department is to look at again (ten characters or more)", "secondary"),
      reject,
    ];
    default: return [];
  }
}

/** an applicant who asks to withdraw once the Registry has approved writes to the Registry (D11: the portal no longer withdraws it);
 *  the approved transfer is the deciding officer's, so the Registry has it rejected there first */
export const WITHDRAW_WHEN_APPROVED = "An applicant who asks to withdraw now writes to the Registry; the portal no longer withdraws it. To honour the request, ask the "
  + "deciding officer to reject the transfer on Inter-University Transfer (the application comes back here as recommended, and the applicant is not told), "
  + "then reject it here with the applicant's request as the reason";

/** what the Registry's desk says beside its buttons, for the states that need a word: a draft (the applicant's, ended only when it
 *  holds another person's number), a decline (approval needs the department's level) and an approval (a withdrawal asked for) */
export function officeGuidance(v: Pick<IutView, "state">): string | null {
  switch (v.state) {
    case "DRAFT": return "Not yet submitted: the applicant pays, uploads and submits it, with no deadline (a draft made before the window closed still "
      + "submits). Reject a draft only to end one made under another person's JAMB number (the number's owner is refused while it stands), never because "
      + "it is unfinished; the account that made it reads the reason, and a fee paid on it is not refunded";
    case "NOT_RECOMMENDED": return "The Head of Department declined: approval needs the department's recommendation and level, so the application is rejected (with "
      + "words the applicant reads) or sent back to the department";
    case "APPROVED": return WITHDRAW_WHEN_APPROVED;
    default: return null;
  }
}

/** whether the Recommend form is shown: with the department, to an office of the department desk */
export function hodMay(v: Pick<IutView, "state">, office?: string | null): boolean {
  return v.state === "WITH_HOD" && (office === undefined || DEPARTMENT.includes(office ?? ""));
}

/** a document's status in words, with its pill */
export const DOC_WORDS: Record<DocStatus, [string, Pill]> = {
  MISSING: ["Missing", "grey"], PENDING: ["Uploaded: being checked", "info"], ACCEPTED: ["Accepted", "ok"], REJECTED: ["Rejected", "bad"],
};
export function docWords(status: string): [string, Pill] {
  return DOC_WORDS[(status === "ACCEPTED" || status === "REJECTED" || status === "MISSING" ? status : "PENDING") as DocStatus];
}

/** the window's status in words (iut_window_status: OPEN, CLOSED, SCHEDULED, EXPIRED) */
export function windowWords(status: string | null | undefined, opensOn?: string | null, closesOn?: string | null): [string, Pill] {
  switch (status) {
    case "OPEN": return [`Open${closesOn ? ` until ${dayWords(closesOn)}` : ""}`, "ok"];
    case "SCHEDULED": return [`Opens on ${dayWords(opensOn) || "the date set"}`, "info"];
    case "EXPIRED": return [`The closing date${closesOn ? `, ${dayWords(closesOn)},` : ""} has passed`, "warn"];
    default: return ["Closed", "grey"];
  }
}

/** a line as the window's table reads it: a line whose programme was archived or merged away since it was added, or whose level the
 *  programme no longer has (shortened since), offers the public nothing, accepting or not */
export function lineWords(l: Pick<WindowLine, "accepting" | "programmeInUse" | "levelInUse">): [string, Pill] {
  if (l.programmeInUse === false) return ["Programme archived: not offered", "warn"];
  if (l.levelInUse === false) return ["No longer a level of the programme: not offered", "warn"];
  return l.accepting ? ["Accepting", "ok"] : ["Closed to new", "grey"];
}
/** whether a line offers nothing whatever its accepting box says (its programme archived, or its level gone) */
export function lineGone(l: Pick<WindowLine, "programmeInUse" | "levelInUse">): boolean {
  return l.programmeInUse === false || l.levelInUse === false;
}
/** the lines the public is offered */
export function offeredLines(lines: Pick<WindowLine, "accepting" | "programmeInUse" | "levelInUse" | "offered">[] | null | undefined): number {
  return (lines ?? []).filter((l) => (l.offered ?? (l.accepting && !lineGone(l)))).length;
}
/** a window set open that offers no programme and level in use (each line's programme archived, its level gone, or closed): the public,
 *  the sign-in page and the website read it closed (iut_window_status), and the Office is told why */
export function windowAlert(v: Pick<WindowView, "state" | "offered"> & { lines?: Pick<WindowLine, "accepting" | "programmeInUse" | "levelInUse" | "offered">[] | null }): string | null {
  if (v.state !== "OPEN" || (v.offered ?? offeredLines(v.lines)) > 0) return null;
  return "The window is set open, but no programme in use takes applications on it (a programme archived or merged away since its line was added, or a "
    + "level the programme no longer has, offers nothing), so the public, the sign-in page and the website read it as closed. Add a programme and level, "
    + "or close the window";
}

/** a line's places as the Academic Office types them: blank is no limit (null); a whole number of 1 or more is that number; anything
 *  else (5o, 0, 2.5) is not a number of places (undefined) and is never sent — the API reads a places left out as no limit */
export function placesOf(typed: string | null | undefined): number | null | undefined {
  const t = (typed ?? "").trim();
  if (!t) return null;
  if (!/^[0-9]+$/.test(t)) return undefined;
  const n = Number(t);
  return n >= 1 && Number.isSafeInteger(n) ? n : undefined;
}

/** a document kind as the Academic Office edits it: the code and label the database takes (IUT_KIND) */
export function kindProblem(k: { code: string; label: string; hint?: string | null }): string | null {
  if (!/^[A-Z][A-Z0-9_]{2,39}$/.test(k.code)) return "A code of capital letters, digits and _, starting with a letter (3 to 40)";
  const l = k.label.trim();
  if (l.length < 3 || l.length > 160) return "A label of 3 to 160 characters";
  if ((k.hint ?? "").length > 400) return "A hint of at most 400 characters";
  return null;
}

// ── the Bursary's payments report ─────────────────────────────────────────────────────────────────────────────────────

export interface IutPaymentRow {
  reference: string; amount: Money; generatedAt?: string | null; expiresAt?: string | null; confirmedAt?: string | null; channel?: string | null; receiptNo?: string | null;
  state: "PAID" | "PENDING" | "EXPIRED" | string; settles?: boolean | null;
  /** paid, settling nothing, and not yet all given back by the refund desk */
  owedBack?: boolean | null;
  /** given back by the refund desk: its refunds approved or paid against the reference */
  refunded?: Money;
  applicationId?: string | null; applicationNo?: string | null; name?: string | null; jambRegNo?: string | null; programme?: string | null; programmeName?: string | null;
  applicationState?: string | null;
}
export interface IutPayments {
  session?: string | null;
  /** owedBackAmount: what is still owed back (net of what the refund desk gave back); refunded and refundedAmount: the payments given back */
  totals?: { drawn?: number; paid?: number; paidAmount?: Money; pending?: number; expired?: number; owedBack?: number; owedBackAmount?: Money;
    refunded?: number; refundedAmount?: Money } | null;
  rows: IutPaymentRow[];
}
export const PAYMENT_STATES = ["PAID", "PENDING", "EXPIRED", "OWED_BACK"] as const;
export const PAYMENT_WORDS: Record<string, [string, Pill]> = {
  PAID: ["Paid", "ok"], PENDING: ["Waiting for payment", "info"], EXPIRED: ["Expired", "grey"], OWED_BACK: ["Owed back", "bad"],
};
/** a payment the refund desk gave back: in part (still owed back), or whole */
export function refundWords(r: Pick<IutPaymentRow, "amount" | "refunded" | "owedBack">): string | null {
  const given = num(r.refunded);
  if (given <= 0) return null;
  return r.owedBack ? `${naira(given)} refunded; ${naira(num(r.amount) - given)} still owed back` : `Refunded ${naira(given)}`;
}
export const PAYMENT_HEAD = ["S/N", "Reference", "Application", "Applicant", "JAMB number", "Programme", "Amount", "State", "Owed back", "Refunded", "Receipt", "Channel",
  "Confirmed", "Application state"];
export function paymentLine(r: IutPaymentRow, i: number): (string | number)[] {
  return [i + 1, r.reference, r.applicationNo ?? "", r.name ?? "", r.jambRegNo ?? "", r.programmeName ?? r.programme ?? "", num(r.amount),
    (PAYMENT_WORDS[r.state] ?? [r.state])[0], r.owedBack ? "Yes" : "", num(r.refunded) > 0 ? num(r.refunded) : "", r.receiptNo ?? "", r.channel ?? "",
    r.confirmedAt ? r.confirmedAt.slice(0, 10) : "", r.applicationState ? officeWords(r.applicationState)[0] : ""];
}
