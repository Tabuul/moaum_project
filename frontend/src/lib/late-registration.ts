/**
 * V516: late registration by the Registry, on the student's behalf — the student's own courses for the semester, what the engine
 * says of each for a late registration (the window and add and drop set aside, every other rule holding), and the late
 * registrations made. The database decides it all.
 */

export interface LateMenuRow {
  offering_id: string; course_code: string; title: string; units: number; kind: string | null; basis: string | null;
  carryover: boolean; deferred: boolean; registered: boolean; blocked_by: string | null; window_set_aside: boolean;
}

export interface LateStudent {
  session: string; semester: number; sessions: string[];
  student: { id: string; name: string; matric_no: string | null; admission_no: string | null; status: string; current_level: number; entry_mode: string | null; programme: string | null; dept_code: string | null };
  registration: { id: string; status: string; level: number; submitted_at: string | null; approved_at: string | null; units: number } | null;
  load: { min_units: number; max_units: number; basis: string; curriculum: string | null } | null;
  /** the registration window's refusal for the student now, or null when it is open */
  window: string | null;
  feesCleared: boolean | null;
  menu: LateMenuRow[];
  history: { at: string; semester: number; units: number; status: string; reason: string; courses: number; by_name: string | null; by_office: string }[];
}

export interface LateRow {
  id: string; at: string; semester: number; units: number; status: string; reason: string; courses: number; by_office: string; by_name: string | null;
  student_id: string; name: string; number: string | null; programme: string | null; dept_code: string | null;
}
