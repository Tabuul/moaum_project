/** One course offered to many programmes across departments (V332): the shapes the catalogue desks share. */

export interface Directory {
  faculties: { code: string; name: string }[];
  departments: { code: string; name: string; faculty_code: string }[];
  programmes: { code: string; name: string; dept_code: string | null; faculty_code: string | null; category: string | null }[];
  tracks: { code: string; name: string }[];
  actingDept: string | null;
  central: boolean;
}

export interface CourseHead {
  id: string; code: string; title: string; units: number; semester: number; level: number; kind: string; state: string;
  dept_code: string | null; dept_name: string | null; faculty_name?: string | null; programmes?: number;
}

export interface Offer {
  programme_code: string; programme: string; dept_code: string | null; dept: string | null; faculty_code: string | null; faculty: string | null;
  level: number; basis: string; track: string | null; added_at: string | null; added_by: string | null; source: string | null;
  registered_now: number; registered_ever: number; may_remove: boolean;
}

export interface Proposal {
  id: string; course_code?: string; course_title?: string; units?: number; course_dept?: string; course_dept_name?: string | null;
  programme_code: string; programme: string; dept_code: string | null; dept: string | null; level: number; basis: string; track: string | null;
  reason: string | null; state: string; proposed_by: string | null; proposed_office: string | null; proposed_dept: string | null; proposed_at: string;
  decided_by: string | null; decided_office?: string | null; decided_at: string | null; decision_note: string | null; may_decide?: boolean; may_cancel?: boolean;
}

export interface CourseDetail {
  course: CourseHead & { ended_on: string | null; curriculum: string | null; ca_max: number | null; general_office: string | null; lecture_hours: number | null; practical_hours: number | null; industrial_training: boolean | null; faculty_code: string | null;
    /** V338: the owner programme, the description, and the reset that archived the course */
    owner_programme?: string | null; owner_programme_name?: string | null; description?: string | null; reset_ref?: string | null };
  offers: Offer[];
  departments: { code: string; name: string; faculty: string | null; programmes: number; owner: boolean }[];
  sessions: { id: string; session: string; semester: number; allocated_on: string | null; lecturer: string | null; second_examiner: string | null; co_lecturers: { name: string; programme_code: string | null; programme: string | null }[]; registered: number; sheet_stage: string | null }[];
  proposals: Proposal[];
  history: { programme_code: string; programme: string; dept: string | null; level: number; basis: string | null; track: string | null; added_at: string | null; source: string | null; ended_at: string; ended_by: string | null; ended_office: string | null; reason: string | null; registrations_carried: number }[];
  usage: Usage;
  /** V338: what the course requires first, and every change of its owner */
  prerequisites?: { code: string; title: string }[];
  ownerHistory?: { from_dept: string | null; from_dept_name: string | null; to_dept: string | null; to_dept_name: string | null; from_programme: string | null; to_programme: string | null; to_programme_name: string | null; source: string | null; reason: string | null; changed_at: string; changed_office: string | null; changed_by: string | null }[];
  may: { edit: boolean; offer: boolean; central: boolean; actingDept: string; changeOwner?: boolean };
}

export interface Usage { registrations: number; scores: number; offerings: number; cbt_exams: number; questions: number; deferred: number; legacy: number }

export interface CourseListRow {
  id: string; code: string; title: string; units: number; level: number; semester: number; kind: string; state: string; ended_on: string | null; curriculum: string | null; general_office: string | null;
  dept_code: string | null; dept_name: string | null; faculty_name: string | null; programme_count: number; owner_programme?: string | null; owner_programme_name?: string | null;
  programmes: { code: string; name: string; dept: string | null; deptName?: string | null; faculty?: string | null; level: number; basis: string }[]; last_session: string | null; pending: number;
}
export interface CourseList { total: number; page: number; size: number; rows: CourseListRow[]; scope: { dept: string; fac: string } }

export interface Exists { byCode: CourseHead | null; byTitle: CourseHead[] }

export const STATE: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  LIVE: ["ok", "Live"], BOARD: ["warn", "Not yet live"], SENATE: ["warn", "Not yet live"], ENDED: ["grey", "Ended"],
};
export const KINDS = ["Core", "Required", "Elective", "GST"];
export const BASES = ["Core", "Elective", "Borrowed", "GST"];
export const LEVELS = [100, 200, 300, 400, 500, 600, 700, 800, 900];
export const semName = (n: number | null | undefined) => (n === 1 ? "First" : n === 2 ? "Second" : n === 3 ? "Third" : "—");
export const PROPOSAL_STATE: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  PENDING: ["warn", "Awaiting the department"], APPROVED: ["ok", "Approved"], REJECTED: ["bad", "Rejected"], CANCELLED: ["grey", "Withdrawn"],
};
export const SOURCE: Record<string, string> = { COURSE: "from the course's desk", STRUCTURE: "from the programme's structure", IMPORT: "by structure upload", PROPOSAL: "by the department's approval", GST: "by the GST/EPS office" };

/** how much hangs on the course, in words, for an edit's warning; empty when nothing does */
export function usageWords(u: Usage | null | undefined): string {
  if (!u) return "";
  const parts = [
    [Number(u.registrations), "registration"], [Number(u.scores), "score"], [Number(u.offerings), "session offering"],
    [Number(u.cbt_exams), "CBT examination"], [Number(u.questions), "question"], [Number(u.deferred), "deferred course"], [Number(u.legacy), "old-portal result"],
  ] as [number, string][];
  return parts.filter(([n]) => n > 0).map(([n, w]) => `${n.toLocaleString()} ${w}${n === 1 ? "" : "s"}`).join(", ");
}
