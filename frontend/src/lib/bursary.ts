/** The Bursary's desk, as the API states it (V037). */
export interface GatewayConfig { gateway: string; configured: boolean; has_hash: boolean; mode: string | null; last4: string | null; set_at: string | null; set_by_name: string | null }
export interface GatewayMerchant { scope: string; productId: string; merchantCode: string; payItemId: string; identity: string; name: string }
export interface GatewayRow { gateway: string; on: boolean; mode: string; webhook: string; return?: string; validate?: string; hash?: boolean; channels: string; merchants?: GatewayMerchant[] }
/** Pay on Quickteller (V299): the billers, Quickteller's reference checks, the collections report — the API leaves absent values out */
export interface PaydirectBiller { scope: string; biller_code: string; name: string; pay_link?: string | null; active: boolean; redirect: boolean; with_amount: boolean; updated_at?: string }
export interface PaydirectCollection { biller_code?: string | null; prn: string; amount?: number | null; paid_at?: string | null; channel?: string | null; rrn?: string | null; payer?: string | null; state: string; reference?: string | null; why?: string | null; imported_at: string }
export interface PaydirectValidation { id: string; reference?: string | null; merchant_reference?: string | null; amount?: number | null; outcome: string; received_at: string; why?: string | null }
/** V383: a test reference the Bursary issued for Interswitch's testers, payable for the days chosen */
export interface PaydirectCertification {
  validation_at: string | null; validation_outcome: string | null; believed_at: string | null; believed_outcome: string | null; believed_reference: string | null;
  discarded_since: number | null; discarded_at: string | null; reversal_at: string | null; reversal_reference: string | null;
}
export interface PaydirectTestReference {
  reference: string; amount: number; session: string; generated_at: string; expires_at: string; days: number; state: "OPEN" | "PAID" | "EXPIRED" | "WITHDRAWN";
  payer: string; number: string; confirmed_at?: string | null; receipt_no?: string | null; channel?: string | null; withdrawn_at?: string | null;
  issued_by_name?: string | null; issued_office: string; checks: number; last_check_at?: string | null; last_outcome?: string | null; link?: string;
}
/** V433: an address (or range) the PAYDirect door is kept to */
export interface PaydirectDoorAddress { address: string; label: string | null; added_at: string; added_by_name: string | null }
/** V433: an address that called the door, with how its calls fared */
export interface PaydirectSeenAddress { address: string; calls: number; refused: number; first_at: string; last_at: string; last_kind: string | null; listed: boolean }
/** V433: the PAYDirect door — its state against its own rhythm, who calls it, the addresses it is kept to, the silence watch */
export interface PaydirectDoor {
  restrict_addresses: boolean; watch_enabled: boolean; silence_hours: number; last_alert_at: string | null;
  last_validation_at: string | null; last_notification_at: string | null; last_call_at: string | null;
  calls_today: number; calls_7d: number; refused_7d: number; calls_14d: number;
  longest_gap_hours: number; quiet_hours: number; threshold_hours: number; state: "NEVER" | "OK" | "QUIET" | "SILENT";
  addresses: PaydirectDoorAddress[]; seen: PaydirectSeenAddress[];
}
export interface PaydirectDesk {
  billers: PaydirectBiller[]; collections: PaydirectCollection[]; validations: PaydirectValidation[]; credentials: boolean;
  /** Oct 2026: a username and password set, and a key in the notification address set */
  credentialsPair?: boolean; notificationKey?: boolean; keyedPath?: string;
  /** Oct 2026: the facts the Interswitch certification checklist is read from */
  certification?: PaydirectCertification;
  apiBase: string; validatePath: string; notifyPath: string; /** Oct 2026: the one address for both messages */ singlePath?: string;
  testReferences: PaydirectTestReference[];
  /** V433: the door watched, and kept to Interswitch */
  door?: PaydirectDoor;
  /** V474: the notified payments recorded before they are settled — waiting, failed (retried), settled in the last day */
  inbox?: PaydirectInbox;
}
export interface PaydirectInbox { waiting: number; failed: number; settled_today: number; oldest_open: string | null; last_error: string | null }
export interface GatewayEvent {
  id: string; gateway: string; source: string; event: string | null; reference: string | null; gateway_ref: string | null; amount: number | null; status: string | null;
  signature_ok: boolean; outcome: string; received_at: string; resolved_at: string | null; resolution: string | null; resolved_by_name: string | null;
  /** V413: the sweep's same answer for the reference, counted on this row */
  times?: number; last_at?: string | null;
}
export interface Hanging {
  id: string; reference: string; gateway: string; kind: string; opened_at: string; checked_at: string | null; checks: number; amount: number | null; expires_at: string | null; minutes: number; payer: string | null; number: string | null;
  /** V480: the receipt the payer reported for it */
  receipt_log_id?: string | null; receipt_paid_on?: string | null; receipt_amount?: number | null; receipt_channel?: string | null;
}
/** V480: a receipt a payer reported for a Pay on Quickteller payment (finance.paydirect_claims) */
export interface PaydirectClaimRow {
  reference: string; payer: string | null; number: string | null; due: number | null; payment_log_id: string; paid_on: string; amount: number | null;
  channel: string | null; note: string | null; claimed_at: string; claimed_office: string | null; confirmed_at: string | null;
}
export interface PaymentsDesk { gateways: GatewayRow[]; tiles: { today: number; settled: number; exceptions: number; bad_signatures: number; settled_today: number }; events: GatewayEvent[]; hanging: Hanging[]; claims?: PaydirectClaimRow[]; portalUrl: string }

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
  NOT_SUCCESSFUL: ["Not successful", "grey"], IGNORED: ["Ignored", "grey"], BAD_SIGNATURE: ["Bad signature — discarded", "bad"], GATEWAY_ERROR: ["Gateway gave no usable answer", "bad"],
  NO_CREDENTIALS: ["Not believed — no service credentials set", "bad"],
  REVERSED: ["Reversed by Interswitch — for the Bursary", "bad"], VALID: ["Reference valid", "ok"], INVALID: ["Reference refused", "grey"],
};
/** the events the Bursary resolves by hand, with a reason on the record */
export const EXCEPTIONS = ["UNKNOWN_REFERENCE", "SHORT_PAID", "BAD_SIGNATURE", "NO_CREDENTIALS", "GATEWAY_ERROR", "REVERSED"];
export function when(iso: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  return d.toLocaleDateString("en-GB", { day: "numeric", month: "short" }) + ", " + d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
}
