/** the shapes the admissions cycle, candidate data and matriculation endpoints answer with */
export interface AdmissionCycle {
  session: string;
  applications: number;
  screened: number;
  offers: number;
  accepted: number;
  onTheRegister: number;
  notYetOnRegister: number;
  capacity: number | null;
  settingsInForce: boolean;
  programmes: { code: string; name: string; facultyCode: string; facultyName: string; applied: number; quota: number | null; offered: number; accepted: number; cutoff: number | null; stage: string }[];
  reconciliation: { finding: string; n: number; owner: string; whatItMeans: string }[];
}

export interface MatriculationOverview {
  session: string;
  totals: { registered: number; confirmed: number; pending: number; queried: number };
  faculties: { code: string; name: string; officer: string | null; registered: number; confirmed: number; queried: number; state: string; confirmedAt: string | null }[];
  heldBack: { studentId: string; admissionNo: string; surname: string; otherNames: string; facultyName: string; reason: string; office: string }[];
  runs: { id: string; ref: string; session: string; runAt: string; issued: number }[];
  sample: { admissionNo: string; matricNo: string; surname: string; otherNames: string; deptName: string }[];
  minUnits: number | null;
}

export interface FacultyList {
  session: string;
  code: string;
  name: string;
  state: string;
  confirmedAt: string | null;
  minUnits: number | null;
  rows: { studentId: string; admissionNo: string; surname: string; otherNames: string; deptCode: string; deptName: string; units: number; registrationStatus: string; queryReason: string | null; queryOffice: string | null }[];
}

export interface AttachmentState {
  session: string;
  findings: { finding: string; n: number; owner: string; whatItMeans: string }[];
  attachments: { id: string; kind: string; sourceName: string; jambKey: string | null; readAs: string; matched: boolean; payload: Record<string, unknown>; bytes: number | null; widthPx: number | null; heightPx: number | null; arrivedAt: string }[];
  candidates: { id: string; jambKey: string; surname: string; otherNames: string; programme: string; entryMode: string; hasPassport: boolean; hasDob: boolean; hasOlevel: boolean; committed: boolean }[];
}
