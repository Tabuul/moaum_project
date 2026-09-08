/** the shapes the clearance, credentials and graduation modules answer with */
export interface ClearanceUnit {
  code: string;
  label: string;
  clearsAgainst: string;
  holdsFor: string;
  typicalReason: string;
  officeCode: string | null;
  ord: number;
}

export interface ClearanceListing {
  purpose: string;
  totals: { candidates: number; fullyCleared: number; outstandingAtOne: number; outstandingAtTwoOrMore: number };
  units: { code: string; label: string; clearsAgainst: string; holdsFor: string; typicalReason: string; holding: number; progress: number }[];
  candidates: { id: string; number: string; surname: string; otherNames: string; programmeName: string; deptName: string; facultyCode: string; level: number; states: string[]; cleared: boolean }[];
  total: number;
}

export interface ClearancePosition {
  unit: string;
  label: string;
  state: string;
  item: string | null;
  officerId: string | null;
  officer: string | null;
  decidedAt: string | null;
  note: string | null;
  ord: number;
}

export interface TranscriptRow {
  id: string;
  ref: string;
  studentId: string;
  number: string;
  surname: string;
  otherNames: string;
  destination: string;
  destinationName: string | null;
  mode: string;
  express: boolean;
  copies: number;
  requestedAt: string;
  paidAt: string | null;
  stage: string;
  producedAt: string | null;
  releasedAt: string | null;
  unitsCleared: number;
  heldBy: string | null;
  heldReason: string | null;
}

export interface TranscriptQueue {
  tiles: { open: number; heldAtClearance: number; breachingSla: number; averageTurnaroundDays: number | null };
  requests: { row: TranscriptRow; slaDay: number | null; breaching: boolean; actionStage: string }[];
}

export interface Certificate {
  id: string;
  number: string;
  studentId: string;
  matricNo: string | null;
  surname: string;
  otherNames: string;
  award: string;
  classOfDegree: string;
  convocation: string;
  serial: number | null;
  batch: string | null;
  status: string;
  printedOn: string;
  collectedOn: string | null;
  collectedNote: string | null;
  heldReason: string | null;
  issuingName: string;
  duplicateOf: string | null;
}

export interface CertificateRegister {
  convocation: string | null;
  tiles: { graduands: number; printed: number; collected: number; stockLeft: number };
  certificates: Certificate[];
  batches: { id: string; batch: string; serialFrom: number; serialTo: number; receivedOn: string; issued: number; used: number; spoiled: number; returned: number }[];
  awaitingPrint: { studentId: string; matricNo: string | null; surname: string; otherNames: string; award: string; classOfDegree: string | null; session: string }[];
}

export interface GraduationView {
  session: string;
  tiles: { finalists: number; auditPassed: number; outstanding: number; awaitingClearance: number; approved: number };
  exceptions: { studentId: string; number: string; surname: string; otherNames: string; programmeName: string; unmet: string; cgpa: number | null }[];
  classification: { clazz: string; students: number; share: number; low: number; high: number }[];
}

export const DESTINATION: Record<string, string> = { SELF: "Myself", INSTITUTION: "Another institution", EMPLOYER: "Employer", EMBASSY: "Embassy" };
