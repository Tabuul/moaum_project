/**
 * The GST & EPS examination permit card (V492): what the API says about a student's permit, and the words and groups the
 * screens and the PDF show. The courses are the API's — the GST and EPS courses on the student's submitted registration,
 * chosen by the database; nothing here decides which courses belong on a permit, it only lays them out. V589: the permit is
 * issued on the examination card's own terms (courses registered, school fees paid) and the GST fee, nothing more.
 */

/** one GST or EPS course on the permit, with its examination's slot where one is set */
export interface PermitCourse {
  course_code: string;
  title: string;
  units: number;
  course_type: "GST" | "EPS";
  entry_type?: string;
  /** CBT or WRITTEN, once a slot is set */
  mode?: string | null;
  held_on?: string | null;
  starts_at?: string | null;
  ends_at?: string | null;
  venue?: string | null;
  seat_no?: number | null;
  /** V381: attendance below the Centre's minimum, where it bars the paper */
  bar?: string | null;
}

export interface PermitRecord {
  reference: string;
  status: "GENERATED" | "DOWNLOADED" | "PRINTED" | "REVOKED";
  generatedAt: string;
  lastIssuedAt: string;
  viewed: number;
  downloaded: number;
  printed: number;
  revokedAt?: string | null;
  revokedOffice?: string | null;
  revokedReason?: string | null;
}

export interface PermitStudent {
  name: string;
  matricNo?: string | null;
  number?: string | null;
  jambNo?: string | null;
  faculty?: string | null;
  department?: string | null;
  programme?: string | null;
  level?: number | null;
  status?: string;
}

/** GET /api/v1/me/gst-eps-permit, and the issue's answer (with the check code) */
export interface PermitState {
  available: boolean;
  code?: string | null;
  reason?: string | null;
  session: string;
  semester: number;
  openSemester?: number;
  student: PermitStudent;
  registration?: { status: string; level: number; approvedAt?: string | null; approvalMode?: string | null } | null;
  courses: PermitCourse[];
  gstCount: number;
  epsCount: number;
  units: number;
  cleared?: boolean | null;
  permit?: PermitRecord | null;
  checkCode?: string;
}

/** the permit's sections: GST COURSES then EPS COURSES, each only when the student registered one */
export function permitSections(courses: PermitCourse[]): { type: "GST" | "EPS"; title: string; courses: PermitCourse[] }[] {
  const out: { type: "GST" | "EPS"; title: string; courses: PermitCourse[] }[] = [];
  for (const type of ["GST", "EPS"] as const) {
    const these = courses.filter((c) => c.course_type === type);
    if (these.length) out.push({ type, title: `${type} COURSES`, courses: these });
  }
  return out;
}

export const TO_BE_SCHEDULED = "TO BE SCHEDULED";

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** the examination's date, as the timetable or the CBT engine states it ("Mon 16 Nov 2026"); never invented */
export function slotDate(c: PermitCourse): string {
  if (!c.held_on) return TO_BE_SCHEDULED;
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(c.held_on);
  if (!m) return c.held_on;
  const d = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])));
  return `${["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d.getUTCDay()]} ${Number(m[3])} ${MONTHS[Number(m[2]) - 1]} ${m[1]}`;
}

/** the examination's time ("09:00–11:00", or the start alone where the end is not set) */
export function slotTime(c: PermitCourse, dash = "–"): string {
  if (!c.held_on || !c.starts_at) return TO_BE_SCHEDULED;
  const hm = (t: string) => t.slice(0, 5);
  return c.ends_at ? `${hm(c.starts_at)}${dash}${hm(c.ends_at)}` : hm(c.starts_at);
}

/** the venue (with the seat on a CBT sitting), or TO BE SCHEDULED */
export function slotVenue(c: PermitCourse): string {
  if (!c.venue) return TO_BE_SCHEDULED;
  return c.seat_no ? `${c.venue}, seat ${c.seat_no}` : c.venue;
}

/** whether the examination has a date yet */
export const scheduled = (c: PermitCourse) => !!c.held_on;

/** the permit's state in a word, as the screens show it */
export function permitStatusLabel(s: PermitState): string {
  if (s.permit?.status === "REVOKED") return "Withdrawn";
  if (!s.available) return "Not available";
  if (!s.permit) return "Available";
  return s.permit.status === "PRINTED" ? "Printed" : s.permit.status === "DOWNLOADED" ? "Downloaded" : "Available";
}

/** the refusals a course registration puts right: the screen offers the way back to it */
export function registrationRemedy(code: string | null | undefined): boolean {
  return code === "GST_EPS_PERMIT_NO_REGISTRATION" || code === "GST_EPS_PERMIT_NOT_SUBMITTED" || code === "GST_EPS_PERMIT_NO_COURSES";
}

/** the refusals a payment puts right: the GST fee, or the school fees (V589: as the examination card asks them) */
export function paymentRemedy(code: string | null | undefined): "GST" | "FEES" | null {
  return code === "GST_EPS_PERMIT_GST_PAYMENT" ? "GST" : code === "GST_EPS_PERMIT_NOT_PAID" ? "FEES" : null;
}

/** the public path the permit's QR opens */
export function permitVerifyPath(reference: string, code: string): string {
  return `/verify/gst-eps-permit?r=${encodeURIComponent(reference)}&c=${encodeURIComponent(code)}`;
}

/** the summary under the table: "3 papers · 6 credit units · GST 2 · EPS 1" */
export function permitSummary(s: Pick<PermitState, "courses" | "units" | "gstCount" | "epsCount">, dot = "·"): string {
  const n = s.courses.length;
  const parts = [`${n} paper${n === 1 ? "" : "s"}`, `${s.units} credit unit${s.units === 1 ? "" : "s"}`];
  if (s.gstCount) parts.push(`GST ${s.gstCount}`);
  if (s.epsCount) parts.push(`EPS ${s.epsCount}`);
  return parts.join(` ${dot} `);
}

/** the office desk's permit states, as the filter names them */
export const ROSTER_STATUSES = [
  ["ALL", "All students"],
  ["NOT_GENERATED", "Not generated"],
  ["GENERATED", "Generated"],
  ["DOWNLOADED", "Downloaded"],
  ["PRINTED", "Printed"],
  ["REVOKED", "Withdrawn"],
] as const;

export function rosterStatusLabel(status: string | null | undefined): string {
  return ROSTER_STATUSES.find(([k]) => k === (status ?? "NOT_GENERATED"))?.[1] ?? String(status);
}

/** the office desk's row */
export interface RosterRow {
  student_id: string;
  number: string;
  name: string;
  programme_code?: string | null;
  programme?: string | null;
  dept_code?: string | null;
  faculty_code?: string | null;
  level?: number | null;
  reg_status: string;
  courses: string;
  course_count: number;
  units: number;
  permit_id?: string | null;
  reference?: string | null;
  permit_status?: string | null;
  generated_at?: string | null;
  last_issued_at?: string | null;
  viewed: number;
  downloaded: number;
  printed: number;
  revoked_at?: string | null;
}

export interface RosterCourse {
  course_code: string;
  title: string;
  units: number;
  course_type: string;
  stream?: string;
  registered: number;
  held_on?: string | null;
  starts_at?: string | null;
  ends_at?: string | null;
  venue?: string | null;
  cbt_reference?: string | null;
  cbt_state?: string | null;
  cbt_starts_at?: string | null;
  cbt_ends_at?: string | null;
  cbt_venue?: string | null;
  cbt_sittings?: number | null;
}

export interface RosterPage {
  office: "GST" | "EPS";
  session: string;
  semester: number;
  figures: { students: number; generated: number; not_generated: number; downloaded: number; printed: number; revoked: number };
  courses: RosterCourse[];
  total: number;
  page: number;
  size: number;
  rows: RosterRow[];
}

/** an office course's examination in words: the timetable's slot, the CBT examination's window, or TO BE SCHEDULED */
export function courseSchedule(c: RosterCourse): string {
  if (c.held_on) {
    const slot: PermitCourse = { course_code: c.course_code, title: c.title, units: c.units, course_type: "GST", held_on: c.held_on, starts_at: c.starts_at, ends_at: c.ends_at, venue: c.venue };
    return `${slotDate(slot)} · ${slotTime(slot)} · ${slotVenue(slot)}`;
  }
  if (c.cbt_reference) {
    const when = c.cbt_starts_at ? new Date(c.cbt_starts_at).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" }) : "time not set";
    return `CBT ${c.cbt_reference} (${(c.cbt_state ?? "").toLowerCase()}) · ${when}${c.cbt_sittings ? ` · ${c.cbt_sittings} sitting${c.cbt_sittings === 1 ? "" : "s"}` : ""}`;
  }
  return TO_BE_SCHEDULED;
}
