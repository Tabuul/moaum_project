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

export interface ComplianceSummary {
  total: number;
  complete: number;
  incomplete: number;
  percent: number;
  items: { item: string; missing: number }[];
  origin: { origin: "MIGRATED" | "PORTAL"; total: number; complete: number }[];
  faculties: { code: string | null; name: string; total: number; complete: number }[];
  departments: { code: string | null; name: string; faculty: string | null; total: number; complete: number }[];
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

/** GET /api/v1/biodata-compliance */
export interface ComplianceOverview {
  gate: GateSetting;
  summary: ComplianceSummary;
  requirements: Requirement[];
  canSet: boolean;
  /** the University's date (Africa/Lagos), for the exception form's limits */
  today: string;
  exceptions?: GateException[];
  history?: GateHistory[];
}

export interface ComplianceRow {
  id: string;
  name: string;
  matric_no?: string | null;
  jamb_reg_no?: string | null;
  admission_no?: string | null;
  faculty?: string | null;
  department?: string | null;
  programme?: string | null;
  level?: number | null;
  sex?: string | null;
  entry_session?: string | null;
  phone?: string | null;
  email?: string | null;
  required: number;
  completed: number;
  complete: boolean;
  missing?: string | null;
  last_updated?: string | null;
  migrated: boolean;
  excepted: boolean;
  status: "UP_TO_DATE" | "INCOMPLETE";
}

export interface ComplianceList {
  total: number;
  page: number;
  size: number;
  rows: ComplianceRow[];
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
