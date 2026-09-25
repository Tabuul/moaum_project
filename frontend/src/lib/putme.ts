/** The Post-UTME CBT examination (V260): the shapes the desk screens read, the words for each state, and the small helpers. */
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";

export interface PutmeExam {
  id: string; session: string; name: string; kind: string; starts_on: string | null; ends_on: string | null; checkin_minutes: number; duration_minutes: number; buffer_minutes: number;
  registration_deadline: string | null; state: string; strategy: string; keep_programme: boolean; instructions: string | null; venue_instructions: string | null; contact: string | null; published_at: string | null;
}
export interface Room { id: string; centre_id: string; code: string; name: string; capacity: number; workstations: number; state: string; operational_workstations: number }
export interface Centre { id: string; code: string; name: string; location: string | null; address: string | null; contact_person: string | null; contact_info: string | null; state: string; rooms: Room[] }
export interface Slot { id: string; code: string; starts_at: string; ends_at: string; ord: number; active: boolean }
export interface Capacity { held_on: string; slot_id: string; slot: string; starts_at: string; ends_at: string; centre_id: string; centre: string; room_id: string; room: string; capacity: number; assigned: number; batch_id: string | null }
export interface Finding { severity: "ERROR" | "WARNING"; code: string; message: string; n: number }
export interface Batch {
  id: string; label: string; ordinal: number | null; held_on: string; starts_at: string; ends_at: string; venue: string; capacity: number; state: string; note: string | null; exam_id: string | null;
  centre: string | null; room: string | null; slot: string | null; assigned: number; checked_in: number; absent: number;
}
export interface Candidate {
  application_id: string; application_no: string; surname: string; other_names: string; jamb_reg_no: string; utme: number | null; entry_mode: string;
  programme_code: string | null; programme: string; dept_code: string | null; department: string | null; faculty_code: string | null; faculty: string | null;
  fee_confirmed_at: string | null; submitted_at: string | null; status: string; why: string; schedule_review: boolean; putme_token: string;
  batch_id: string | null; batch: string | null; held_on: string | null; starts_at: string | null; ends_at: string | null; centre: string | null; room: string | null; seat: string | null; workstation: string | null;
  attendance: string; exam_status: string; checked_in_at: string | null; screening_score: number | null; score_released_at: string | null; passport_id?: string | null;
}
export interface Overview {
  session: string; exam: PutmeExam | null; statuses: { status: string; n: number }[]; examProgrammes: { programme_code: string; name: string }[]; centres: Centre[];
  preview?: { eligible: number; ready: number; scheduled: number; unscheduled: number; capacity: number; used: number; places: number; required_batches: number; centres: number; rooms: number; days: number; slots: number };
  findings?: Finding[]; slots?: Slot[]; days?: { held_on: string; active: boolean }[]; examCentres?: string[]; capacity?: Capacity[]; batches?: Batch[];
  byDate?: { held_on: string; candidates: number; capacity: number }[]; byCentre?: { centre_id: string; centre: string; rooms: number; batches: number; capacity: number; assigned: number }[];
  byFaculty?: { faculty: string | null; candidates: number; scheduled: number }[]; byProgramme?: { programme_code: string; programme: string; faculty: string | null; candidates: number; scheduled: number }[];
}
export interface CandidateList { session: string; total: number; page: number; size: number; rows: Candidate[]; options: { faculty_code: string; faculty: string; dept_code: string; department: string; programme_code: string; programme: string }[] }

export type PilKind = "grey" | "info" | "ok" | "bad" | "warn";
export const EXAM_STATE: Record<string, [string, PilKind]> = {
  DRAFT: ["Draft", "grey"], CONFIGURING: ["Configuring", "info"], OPEN_FOR_SCHEDULING: ["Open for scheduling", "info"], SCHEDULING_IN_PROGRESS: ["Scheduling in progress", "warn"],
  SCHEDULED: ["Scheduled", "ok"], ONGOING: ["Ongoing", "ok"], COMPLETED: ["Completed", "grey"], CANCELLED: ["Cancelled", "bad"],
};
export const STATUS: Record<string, [string, PilKind]> = {
  NOT_ELIGIBLE: ["Not eligible", "grey"], DOCUMENT_PENDING: ["Form not submitted", "warn"], PAYMENT_PENDING: ["Fee not confirmed", "warn"], READY_FOR_SCHEDULING: ["Ready for scheduling", "info"],
  RESCHEDULE_REQUIRED: ["Reschedule required", "bad"], SCHEDULED: ["Scheduled", "ok"], RESCHEDULED: ["Rescheduled", "ok"], ABSENT: ["Absent", "bad"], EXAM_COMPLETED: ["Examination sat", "ok"], DISQUALIFIED: ["Disqualified", "bad"],
};
export const BATCH_STATE: Record<string, [string, PilKind]> = { DRAFT: ["Draft", "grey"], PUBLISHED: ["Published", "ok"], POSTPONED: ["Postponed", "warn"], CANCELLED: ["Cancelled", "bad"] };
export const ATTENDANCE: Record<string, [string, PilKind]> = { NOT_CHECKED_IN: ["Not checked in", "grey"], CHECKED_IN: ["Checked in", "info"], PRESENT: ["Present", "ok"], ABSENT: ["Absent", "bad"], DISQUALIFIED: ["Disqualified", "bad"] };
export const EXAM_STATUS: Record<string, [string, PilKind]> = { NOT_STARTED: ["Not started", "grey"], IN_PROGRESS: ["In progress", "info"], COMPLETED: ["Completed", "ok"], ABSENT: ["Absent", "bad"], DISQUALIFIED: ["Disqualified", "bad"] };
export const STRATEGY: Record<string, string> = {
  PROGRAMME: "By programme — a programme's candidates sit together, names A–Z", DEPARTMENT: "By department — a department's programmes together", FACULTY: "By faculty — a faculty's departments together",
  ALPHABETICAL: "Alphabetical — surnames A–Z across every programme", APPLICATION_NO: "By application number — in the order they applied", BALANCED: "Balanced — every batch a mix of programmes",
};

export const dayOf = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");
export const longDay = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long", year: "numeric" }) : "—");
export const clock = (t: string | null | undefined) => (t ? String(t).slice(0, 5) : "—");
export const whenAt = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }) : "—");
export const base = (session: string) => `/api/bff/api/v1/admissions/sessions/${session}/putme`;

/** one call to the desk's door from the browser: the problem returned, never thrown */
export async function callPutme<T>(session: string, method: "GET" | "POST" | "PUT", path: string, body: unknown, reason: string): Promise<{ ok: true; data: T } | { ok: false; problem: Problem }> {
  const r = await fetch(`${base(session)}${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: body === undefined ? undefined : JSON.stringify(body) });
  const j = await r.json().catch(() => null);
  if (!r.ok) return { ok: false, problem: (j as Problem) ?? { status: r.status, title: r.statusText } };
  return { ok: true, data: j as T };
}
