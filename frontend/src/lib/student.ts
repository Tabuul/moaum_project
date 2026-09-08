/**
 * What the student module serves (`/api/v1/student`), as the screens read it.
 * The names are the API's names; nothing is computed here that the API can
 * compute, because the register is the authority and the screen is not.
 */

export type Tier = "open" | "locked" | "approval";

/** `GET /api/v1/ref/sessions` — the scope bar's session list. */
export interface RefSession {
  name: string;
  startsOn: string;
  endsOn: string;
  state: string;
  senateMinute: string | null;
  semesters: number;
}

/** `GET /api/v1/ref/courses` — the scope bar's course selector. */
export interface RefCourse {
  code: string;
  title: string;
  units: number;
  semester: number;
  level: number;
  deptCode: string;
  deptName: string;
  kind: string;
  state: string;
  endedOn: string | null;
}

export interface StudentRow {
  id: string;
  matricNo: string | null;
  admissionNo: string | null;
  jambRegNo: string | null;
  surname: string;
  otherNames: string;
  sex: string | null;
  dateOfBirth: string | null;
  entryMode: string;
  entrySession: string;
  entryLevel: number;
  programmeCode: string;
  programmeName: string;
  deptCode: string;
  deptName: string;
  facultyCode: string;
  facultyName: string;
  currentLevel: number;
  status: string;
}

export interface Register {
  rows: StudentRow[];
  /** the register entire — what the University has, whatever the scope shows */
  total: number;
}

export interface BiodataField {
  field: string;
  section: string;
  label: string;
  tier: Tier;
  hint: string | null;
  wide: boolean;
  ord: number;
  value: string | null;
}

export interface StudentDocument {
  id: string;
  kind: string;
  detail: string | null;
  source: string;
  receivedOn: string | null;
  status: string;
}

export interface StatusEntry {
  id: string;
  fromStatus: string;
  toStatus: string;
  instrument: string;
  effectiveOn: string;
  reason: string | null;
}

export interface EnrolmentRow {
  session: string;
  level: number;
  mode: string;
  feeCategory: string | null;
  enrolledAt: string;
}

export interface RegistrationRow {
  id: string;
  session: string;
  semester: number;
  level: number;
  status: string;
  units: number;
  submittedAt: string | null;
}

export interface ClearanceRow {
  unit: string;
  label: string;
  state: string;
  item: string | null;
  decidedAt: string | null;
  ord: number;
}

export interface PendingChange {
  id: string;
  field: string;
  label: string;
  fromValue: string | null;
  toValue: string;
  evidence: string | null;
  requestedAt: string;
  state: string;
}

export interface DecidedChange extends PendingChange {
  decision: string | null;
  decidedAt: string | null;
}

export interface StudentRecord {
  student: StudentRow;
  biodata: BiodataField[];
  documents: StudentDocument[];
  statusHistory: StatusEntry[];
  enrolments: EnrolmentRow[];
  registrations: RegistrationRow[];
  convocationClearance: ClearanceRow[];
  registrationClearance: ClearanceRow[];
  pendingChanges: PendingChange[];
  decidedChanges: DecidedChange[];
  approvedUnits: number;
}

export interface BiodataChange {
  id: string;
  studentId: string;
  surname: string;
  otherNames: string;
  matricNo: string | null;
  admissionNo: string | null;
  field: string;
  label: string;
  fromValue: string | null;
  toValue: string;
  evidence: string | null;
  requestedAt: string;
  state: string;
  decision: string | null;
  decidedAt: string | null;
}

export interface ChangeCounts {
  pending: number;
  oldestDays: number;
  approved: number;
  refused: number;
  selfService: number;
}

export interface ChangeQueue {
  rows: BiodataChange[];
  counts: ChangeCounts;
}

export interface SearchHit {
  kind: string;
  identifier: string;
  name: string;
  detail: string;
  status: string;
  id: string;
}

export interface SearchResult {
  q: string;
  kind: string;
  hits: SearchHit[];
  exact: SearchHit | null;
  total: number;
}

export interface RecordsResult {
  view: string;
  rows: Record<string, unknown>[];
  total: number;
  notServed: string | null;
}

/** "ADAMU, Grace Mwuese" — the register's own order. */
export function fullName(s: { surname: string; otherNames: string }): string {
  return `${s.surname}, ${s.otherNames}`;
}

/** A status as a person reads it: TRANSFERRED_OUT is "Transferred out". */
export function statusLabel(status: string): string {
  const words = status.replace(/_/g, " ").toLowerCase();
  return words.charAt(0).toUpperCase() + words.slice(1);
}

/** Which pill a status wears (proto/part5, part22). */
export function statusPill(status: string): "ok" | "bad" | "grey" | "info" {
  if (status === "ACTIVE" || status === "GRADUATED") return "ok";
  if (status === "ADMITTED") return "info";
  if (status === "WITHDRAWN" || status === "TRANSFERRED_OUT" || status === "DORMANT" || status === "DEFERRED") return "grey";
  return "bad";
}
