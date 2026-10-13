/** V423 — the student biodata completion gate: what the API answers, and the few words every screen shares. */

/** OFF (the switch is off) · EXCEPTION (a live exception lets the student through) · COMPLETE · REQUIRED (biodata first) */
export type GateState = "OFF" | "EXCEPTION" | "COMPLETE" | "REQUIRED";

export interface Completion {
  required: number;
  completed: number;
  complete: boolean;
  percent: number;
  lastUpdated?: string | null;
  missing: { item: string; label: string }[];
}

/** GET /api/v1/me/biodata/completion */
export interface StudentGate {
  gate: GateState;
  enabled: boolean;
  completion: Completion;
  /** every item required now, in the form's order */
  requiredItems?: string[];
  exception?: { id: string; starts_at: string; expires_at: string } | null;
}

export interface GateSetting {
  enabled: boolean;
  changed_at?: string | null;
  changed_office?: string | null;
  changed_by?: string | null;
  reason?: string | null;
}

export interface Requirement {
  item: string;
  label: string;
  section: string;
  ord: number;
  required: boolean;
  /** why the item cannot be required (a JAMB field, a health field), when it cannot */
  refused?: string | null;
}

export interface GateException {
  id: string;
  student_id: string;
  name: string;
  number: string | null;
  reason: string;
  starts_at: string;
  expires_at: string;
  revoked_at?: string | null;
  revoke_reason?: string | null;
  granted_office: string;
  granted_by: string;
  live: boolean;
}

export interface GateHistory {
  occurred_at: string;
  subject_type: string;
  actor_office?: string | null;
  reason?: string | null;
  source_ip?: string | null;
  actor: string;
  was_enabled?: string | null;
  now_enabled?: string | null;
  item?: string | null;
  was_required?: string | null;
  now_required?: string | null;
}

/** GET /api/v1/biodata-compliance — the switch's half of the one compliance screen (V434: the counts are the reading's) */
export interface ComplianceOverview {
  gate: GateSetting;
  requirements: Requirement[];
  canSet: boolean;
  /** the University's date (Africa/Lagos), for the exception form's limits */
  today: string;
  exceptions?: GateException[];
  history?: GateHistory[];
}

/** the sections of the biodata, as the form names them — and the photograph, which is not a field */
export const SECTION_LABEL: Record<string, string> = {
  photo: "Photograph",
  personal: "Personal details",
  contact: "Contact",
  origin: "Origin & sponsorship",
  family: "Parents or guardian",
  kin: "Next of kin & guarantor",
  health: "Health",
  bank: "Bank account",
};

/** the student pages a gated student may still open: the biodata itself, a request for help, the notices */
export const GATE_OPEN_PAGES = ["/student/biodata", "/student/support", "/student/notifications"];

export function gateOpenPage(pathname: string): boolean {
  return GATE_OPEN_PAGES.some((p) => pathname === p || pathname.startsWith(p + "/"));
}

/** a percentage to one decimal, never more than 100 */
export function pct(part: number, whole: number): string {
  if (!whole) return "—";
  return `${Math.min(100, (100 * part) / whole).toFixed(1)}%`;
}
