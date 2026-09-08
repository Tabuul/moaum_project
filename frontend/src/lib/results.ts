/** the shapes the results and registration modules answer with */
export interface SheetListed {
  id: string;
  courseCode: string;
  courseTitle: string;
  units: number;
  deptName: string;
  facultyName: string;
  session: string;
  semester: number;
  stage: string;
  spineStage: number;
  dueOn: string | null;
  daysLate: number | null;
  returnedTimes: number;
  lecturer: string | null;
  candidates: number;
  failRate: number | null;
  mayAct: boolean;
  blockedForYou: boolean;
}

export interface SheetListing {
  tiles: { expected: number; senateApproved: number; inWorkflow: number; notSubmitted: number };
  sheets: SheetListed[];
  desk: string;
}

export interface Decision {
  id: string;
  fromStage: string;
  toStage: string;
  kind: "SUBMIT" | "ADVANCE" | "RETURN";
  actorId: string;
  actor: string | null;
  actorOffice: string;
  comment: string | null;
  decidedAt: string;
}

export interface Mark {
  studentId: string;
  number: string;
  surname: string;
  otherNames: string;
  ca: number | null;
  exam: number | null;
  total: number | null;
  grade: string | null;
  points: number | null;
  outcome: string;
  version: number;
  amended: boolean;
}

export interface SheetDetail {
  sheet: SheetListed;
  secondExaminer: string | null;
  senateMinute: string | null;
  publishedAt: string | null;
  engineVersion: string | null;
  chain: Decision[];
  marks: Mark[];
}

export interface ExamSession {
  id: string;
  session: string;
  semester: number;
  kind: string;
  examsFrom: string;
  examsTo: string;
  sheetsDue: string;
  state: string;
  openedAt: string | null;
  sheets: number;
  candidates: number;
  outstanding: number;
}

export interface Monitor {
  examSession: ExamSession;
  faculties: { facultyCode: string; facultyName: string; expected: number; submitted: number; verified: number; pastTheBoard: number; outstanding: number; progress: number }[];
  outstanding: { id: string; courseCode: string; deptName: string; facultyCode: string; lecturer: string | null; candidates: number; daysLate: number | null; escalatedTo: string }[];
}

export interface ClassList {
  offeringId: string;
  courseCode: string;
  courseTitle: string;
  units: number;
  session: string;
  semester: number;
  deptCode: string;
  deptName: string;
  lecturer: string | null;
  all: number;
  own: number;
  borrowed: number;
  fromProgrammes: string[];
  rows: { studentId: string; number: string; surname: string; otherNames: string; programmeCode: string; programmeName: string; deptCode: string; level: number; basis: string; cleared: boolean }[];
}

/** the desks, as the prototype names them (proto/part28 CHAIN) */
export const STAGE_LABEL: Record<string, [string, string]> = {
  ENTRY: ["Not submitted", "Course lecturer"],
  VERIFICATION: ["Submitted for verification", "Second examiner"],
  DEPT_BOARD: ["Verified", "Head of Department"],
  FACULTY_SCRUTINY: ["Departmental approved", "Faculty Examinations Officer"],
  FACULTY_COMPILATION: ["Faculty scrutiny done", "Faculty Officer"],
  FACULTY_BOARD: ["Compiled for the Board", "Dean, in the Board"],
  RECORDS: ["Faculty Board approved", "Exams & Records"],
  SENATE: ["Validated", "Senate, on the Registrar’s minute"],
  PUBLISHED: ["Senate approved — published", ""],
};

/** the six-stage spine a student sees (proto/part15 RS_STAGES) */
export const RS_STAGES: [string, string, string][] = [
  ["Draft", "Scores are being entered on the sheet", "Submit for verification"],
  ["Submitted for verification", "With the departmental examinations officer", "Verify the sheet"],
  ["Verified", "Arithmetic and completeness checked by a second academic", "Approve at Departmental Board"],
  ["Departmental Board approved", "With the Faculty Board", "Approve at Faculty Board"],
  ["Faculty Board approved", "With Senate", "Approve for Senate"],
  ["Senate approved — published", "Visible to students; the result is now final", ""],
];

export function csv(rows: (string | number | null | undefined)[][]): string {
  return rows.map((r) => r.map((c) => `"${String(c ?? "").replace(/"/g, '""')}"`).join(",")).join("\r\n");
}

export function download(name: string, text: string) {
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([text], { type: "text/csv;charset=utf-8" }));
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}
