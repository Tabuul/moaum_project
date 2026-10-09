/** The Bursary's desk, as the API states it (V037). */
export interface GatewayConfig { gateway: string; configured: boolean; has_hash: boolean; mode: string | null; last4: string | null; set_at: string | null; set_by_name: string | null }
export interface GatewayMerchant { scope: string; productId: string; merchantCode: string; payItemId: string; identity: string; name: string }
export interface GatewayRow { gateway: string; on: boolean; mode: string; webhook: string; return?: string; validate?: string; hash?: boolean; channels: string; merchants?: GatewayMerchant[] }
/** Pay on Quickteller (V299): the billers, Quickteller's reference checks, the collections report — the API leaves absent values out */
export interface PaydirectBiller { scope: string; biller_code: string; name: string; pay_link?: string | null; active: boolean; redirect: boolean; with_amount: boolean; updated_at?: string }
export interface PaydirectCollection { biller_code?: string | null; prn: string; amount?: number | null; paid_at?: string | null; channel?: string | null; rrn?: string | null; payer?: string | null; state: string; reference?: string | null; why?: string | null; imported_at: string }
export interface PaydirectValidation { id: string; reference?: string | null; merchant_reference?: string | null; amount?: number | null; outcome: string; received_at: string; why?: string | null }
/** V383: a test reference the Bursary issued for Interswitch's testers, payable for the days chosen */
export interface PaydirectTestReference {
  reference: string; amount: number; session: string; generated_at: string; expires_at: string; days: number; state: "OPEN" | "PAID" | "EXPIRED" | "WITHDRAWN";
  payer: string; number: string; confirmed_at?: string | null; receipt_no?: string | null; channel?: string | null; withdrawn_at?: string | null;
  issued_by_name?: string | null; issued_office: string; checks: number; last_check_at?: string | null; last_outcome?: string | null; link?: string;
}
export interface PaydirectDesk {
  billers: PaydirectBiller[]; collections: PaydirectCollection[]; validations: PaydirectValidation[]; credentials: boolean;
  apiBase: string; validatePath: string; notifyPath: string; /** Oct 2026: the one address for both messages */ singlePath?: string;
  testReferences: PaydirectTestReference[];
}
export interface GatewayEvent {
  id: string; gateway: string; source: string; event: string | null; reference: string | null; gateway_ref: string | null; amount: number | null; status: string | null;
  signature_ok: boolean; outcome: string; received_at: string; resolved_at: string | null; resolution: string | null; resolved_by_name: string | null;
}
export interface Hanging { id: string; reference: string; gateway: string; kind: string; opened_at: string; checked_at: string | null; checks: number; amount: number | null; expires_at: string | null; minutes: number; payer: string | null; number: string | null }
export interface PaymentsDesk { gateways: GatewayRow[]; tiles: { today: number; settled: number; exceptions: number; bad_signatures: number; settled_today: number }; events: GatewayEvent[]; hanging: Hanging[]; portalUrl: string }

export interface DayBookRow { reference: string; confirmed_at: string; payer: string; number: string; purpose: string; amount: number; channel: string; receipt_no: string | null; note: string | null; session: string }
export interface BursaryView {
  session: string;
  tiles: { fees_collected: number; today: number; today_count: number; references_open: number; credits_open: number; credits_open_amount: number; gateway_exceptions: number; hanging: number; scheme_in_force: boolean; schedule_items: number };
  byFaculty: { faculty_code: string; faculty_name: string; students: number; paid_students: number; collected: number; due: number }[];
  recent: DayBookRow[];
}
export interface BankCredit {
  id: string; received_on: string; bank: string; instrument: string; amount: number; payer: string | null; note: string | null; recorded_at: string; state: string;
  proposed_reference: string | null; proposed_why: string | null; proposed_at: string | null; approved_at: string | null; posted_reference: string | null; rejected_why: string | null;
  proposed_by_name: string | null; approved_by_name: string | null; recorded_by_name: string | null; proposed_by_me: boolean | null; reference_amount: number | null; reference_confirmed_at: string | null;
}
export const OUTCOME: Record<string, [string, "ok" | "info" | "bad" | "grey"]> = {
  SETTLED: ["Settled", "ok"], ALREADY_SETTLED: ["Already settled — no-op", "ok"], UNKNOWN_REFERENCE: ["Unknown reference", "bad"], SHORT_PAID: ["Short paid", "bad"],
  NOT_SUCCESSFUL: ["Not successful", "grey"], IGNORED: ["Ignored", "grey"], BAD_SIGNATURE: ["Bad signature — discarded", "bad"], GATEWAY_ERROR: ["Gateway did not answer", "bad"],
  REVERSED: ["Reversed by Interswitch — for the Bursary", "bad"], VALID: ["Reference valid", "ok"], INVALID: ["Reference refused", "grey"],
};
/** the events the Bursary resolves by hand, with a reason on the record */
export const EXCEPTIONS = ["UNKNOWN_REFERENCE", "SHORT_PAID", "BAD_SIGNATURE", "GATEWAY_ERROR", "REVERSED"];
export function when(iso: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  return d.toLocaleDateString("en-GB", { day: "numeric", month: "short" }) + ", " + d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
}
