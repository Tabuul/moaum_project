/** The Bursary's desk, as the API states it (V037). */
export interface GatewayRow { gateway: string; on: boolean; mode: string; webhook: string; hash?: boolean; channels: string }
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
};
export function when(iso: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  return d.toLocaleDateString("en-GB", { day: "numeric", month: "short" }) + ", " + d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
}
