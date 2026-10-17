/**
 * V508: overload approval — a student's request for a higher maximum course load in one semester, and the Head of Department's
 * decision. The database decides every rule; this only says it.
 */

export type OverloadStatus = "REQUESTED" | "GRANTED" | "REFUSED" | "WITHDRAWN";

export interface OverloadRequest {
  id: string; status: OverloadStatus; requested_max: number; granted_max: number | null; reason: string;
  decision_reason: string | null; requested_at: string; decided_at: string | null;
}

/** the student's semester: the request (the live one first), the maximum, the ceiling a grant may reach, whether they may ask */
export interface OverloadState {
  session: string; semester: number; level: number; regular_max: number | null; ceiling: number | null; max_extra: number;
  may_ask: boolean; why_not: string | null; request: OverloadRequest | null;
}

export interface OverloadRow {
  id: string; student_id: string; full_name: string; matric_no: string | null; programme: string | null; dept_code: string | null;
  faculty_code: string | null; session: string; semester: number; level: number; regular_max: number; requested_max: number;
  granted_max: number | null; reason: string; status: OverloadStatus; decision_reason: string | null; requested_at: string;
  decided_at: string | null; decided_office: string | null; decided_by: string | null; units: number | null;
  /** V514: whether the student's department has a Head of Department on the portal to decide it */
  has_head?: boolean;
}

export interface OverloadRule { open: boolean; max_extra: number; reason: string; set_at: string | null; set_office: string | null; set_by: string | null }

export interface OverloadList {
  session: string; semester: number | null; current: string | null; sessions: string[]; dept: string | null; faculty: string | null;
  counts: Record<OverloadStatus, number>; total: number; page: number; size: number; rows: OverloadRow[]; rule: OverloadRule;
  /** V514: waiting requests whose department has no Head of Department on the portal */
  noHead?: number;
}

export const OVERLOAD_STATUSES: { status: OverloadStatus; label: string; who: string }[] = [
  { status: "REQUESTED", label: "Waiting", who: "The Head of Department grants or refuses" },
  { status: "GRANTED", label: "Granted", who: "The ceiling is the semester's maximum" },
  { status: "REFUSED", label: "Refused", who: "The student registers within the maximum" },
  { status: "WITHDRAWN", label: "Withdrawn", who: "By the student, while it waited" },
];

export function statusLabel(s: string): string {
  return OVERLOAD_STATUSES.find((x) => x.status === s)?.label ?? s;
}

/** the credit units a request may name: more than the maximum, at most the ceiling */
export function unitChoices(regularMax: number | null, ceiling: number | null): number[] {
  if (regularMax == null || ceiling == null || ceiling <= regularMax) return [];
  return Array.from({ length: ceiling - regularMax }, (_, i) => regularMax + i + 1);
}
