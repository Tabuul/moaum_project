/** Hostel and accommodation, as the API states it (V030, extended by the lifecycle of V261). */
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";

export interface Hall { code: string; name: string; sex: string | null; beds: number; rooms: number; out_of_service: number }
export interface HostelView {
  application_id: string | null; state: string | null; hall_code: string | null; hall_name: string | null; category: string | null; applied_at: string | null;
  allocation_id: string | null; room_id: string | null; block: string | null; room_no: string | null; bed: number | null; beds: number | null;
  basis: string | null; draw_position: number | null; held_until: string | null; confirmed_at: string | null; lapsed_at: string | null; reference: string | null;
  fee: number | null; hold_hours: number | null; drawn_at: string | null; seed: string | null; applications_close: string | null; open: boolean | null;
  application_ref: string | null; allocation_ref: string | null; allocation_state: string | null; floor: number | null; room_type: string | null; bed_label: string | null; hall_location: string | null; hall_campus: string | null;
  accepted_at: string | null; checked_in_at: string | null; checkout_requested_at: string | null; checkout_on: string | null; checked_out_at: string | null; start_on: string | null; end_on: string | null;
  review: string | null; review_note: string | null; room_type_pref: string | null; block_pref: string | null; special_need: string | null; roommate_id: string | null; roommate_note: string | null;
  rules: string | null; rules_version: number | null; rules_accepted: number | null; applications_open: string | null; requires_review: boolean | null; allocation_method: string | null; window_state: string | null;
  eligible: boolean | null; eligibility_why: string | null; clearance_id: string | null; clearance_ref: string | null; clearance_state: string | null; transfer_state: string | null;
  damage_due: number | null; withdrawn_reason: string | null;
}
export interface HostelHistory { session: string; state: string; hall_name: string | null; block: string | null; room_no: string | null; bed: number | null; basis: string | null; confirmed_at: string | null; lapsed_at: string | null; applied_at: string }
export interface Maintenance { id: string; issue: string; raised_at: string; state: string; note: string | null; decided_at: string | null; raised_by_name: string; hall_name?: string; block?: string; room_no?: string; number?: string; category?: string; priority?: string; assigned_to?: string | null }
export interface StudentHostel { session: string; view: Partial<HostelView>; halls: Hall[]; history: HostelHistory[]; maintenance: Maintenance[] }

export interface HostelSetting { session: string; fee: number; hold_hours: number; applications_close: string | null; seed: string | null; drawn_at: string | null; drawn_by: string | null }
export interface DrawRow {
  draw_position: number | null; state: string; category: string; number: string; name: string; hall_requested: string | null;
  hall_name: string | null; block: string | null; room_no: string | null; bed: number | null; basis: string | null; held_until: string | null; confirmed_at: string | null; lapsed_at: string | null;
}
export interface HostelDeskData {
  session: string; setting: HostelSetting | null; halls: Hall[];
  counts: { beds: number; out_of_service: number; applications: number; priority: number; allocated: number; confirmed: number; reserves: number; lapsed: number; free: number };
  draw: DrawRow[]; maintenance: Maintenance[];
}

export const CATEGORIES: [string, string][] = [
  ["NONE", "No priority — the ballot"],
  ["DISABILITY", "Disability"],
  ["MEDICAL", "Medical condition"],
  ["FRESHER", "First year"],
  ["FINALIST", "Final year"],
  ["SPORTS", "University sports"],
  ["OTHER", "Other (say what)"],
];

/* ── the lifecycle (V261) ── */

export interface HallFull { code: string; name: string; sex: string | null; kind: string; campus: string | null; location: string | null; description: string | null; state: string; state_reason: string | null; free?: number; beds?: number }
export interface HistoryRow {
  session: string; application_ref: string; application_state: string; allocation_ref: string | null; allocation_state: string | null; hall_name: string | null; block: string | null; room_no: string | null; bed: number | null; bed_label: string | null;
  basis: string | null; allocated_at: string | null; confirmed_at: string | null; checked_in_at: string | null; checked_out_at: string | null; ended_at: string | null; ended_reason: string | null; clearance_state: string | null; clearance_ref: string | null;
}
export interface Roommate { student_id: string; name: string; number: string; programme: string | null; bed: string | null; state: string }
export interface Charge { id: string; description: string; charge: number; reference: string | null; raised_at: string; settled_at: string | null; waived_at: string | null; waived_reason: string | null; asset_tag?: string | null; repair_cost?: number | null; replacement_cost?: number | null }
export interface ClearanceItem { id: string; requirement: string; label: string; state: string; decided_at: string | null; remarks: string | null; officer?: string | null }
export interface TransferReq { id: string; requested_hall: string | null; requested_type: string | null; reason: string; state: string; submitted_at: string; decided_at: string | null; decision_note: string | null; requested_hall_name?: string | null; requested_type_label?: string | null; student_name?: string; student_number?: string; sex?: string | null; hall_name?: string; block?: string; room_no?: string; bed_label?: string | null; allocation_id?: string; reference_no?: string }
export interface Inspection { kind: string; inspected_at: string; condition: string; cleanliness: string | null; damages: string | null; keys_returned: boolean | null; card_returned: boolean | null; remarks: string | null; officer?: string | null }
export interface HostelEvent { action: string; from_value: string | null; to_value: string | null; note: string | null; at: string; actor_office?: string | null; actor?: string | null }
export interface StudentHostelFull {
  session: string; sessions: string[]; view: Partial<HostelView>; halls: HallFull[]; roomTypes: { code: string; label: string; beds: number }[]; history: HistoryRow[];
  roommates: Roommate[]; transfers: TransferReq[]; charges: Charge[]; clearanceItems: ClearanceItem[]; inspections: Inspection[]; maintenance: Maintenance[]; events: HostelEvent[];
}

export interface Window {
  session: string; fee: number; hold_hours: number; applications_open: string | null; applications_close: string | null; seed: string | null; drawn_at: string | null; allocation_method: string; requires_review: boolean; waitlist: boolean;
  max_applications: number | null; eligible_statuses: string[]; eligible_levels: number[] | null; eligible_faculties: string[] | null; eligible_kinds: string[] | null; require_registration: boolean; refuse_hostel_debt: boolean;
  rules: string | null; rules_version: number; stay_from: string | null; stay_to: string | null; state: string;
}
export interface Totals {
  halls: number; halls_active: number; blocks: number; rooms: number; rooms_available: number; beds: number; occupied: number; reserved: number; available: number; maintenance: number; out_of_service: number; students_accommodated: number;
  applications: number; pending_review: number; approved: number; rejected: number; allocated: number; unallocated: number; waitlisted: number; lapsed: number; checked_in: number; checked_out: number; pending_clearance: number; cleared: number;
  transfers_pending: number; checkouts_pending: number; maintenance_open: number;
}
export interface Dash {
  session: string; setting: Window | null; totals: Totals;
  bedStatus: { status: string; n: number }[]; byHall: { code: string; hall: string; kind: string; sex: string | null; beds: number; occupied: number; reserved: number; available: number; maintenance: number }[];
  byBlock: { hall: string; block: string; block_id: string | null; beds: number; occupied: number; reserved: number; available: number; maintenance: number }[];
  byRoomType: { room_type: string; label: string; beds: number; occupied: number; available: number }[]; byFaculty: { faculty: string | null; faculty_code: string | null; accommodated: number }[];
  byDepartment: { department: string | null; dept_code: string | null; faculty: string | null; accommodated: number }[]; bySex: { sex: string | null; accommodated: number }[]; byLevel: { level: number | null; accommodated: number }[];
  applicationStatus: { status: string; n: number }[]; applicationsByHall: { hall: string; n: number }[]; applicationsByFaculty: { faculty: string; faculty_code: string | null; n: number }[]; applicationsByLevel: { level: number | null; n: number }[];
}
export interface Preview { eligible_applicants: number; approved: number; pending_review: number; free_beds: number; halls: number; rooms: number; will_seat: number; will_wait: number }
export interface DashboardData { dashboard: string; preview: Preview; sessions: string[]; halls: { code: string; name: string; sex: string | null; kind: string; state: string }[]; kinds: { code: string; label: string }[]; faculties: { code: string; name: string }[]; waiting: { reviews: number; transfers: number; checkouts: number; checkins: number; clearances: number; maintenance: number } }

export interface RoomRow {
  id: string; hall_code: string; hall_name: string; block: string; block_id: string | null; floor: number; room_no: string; room_type: string | null; room_type_label: string | null; beds: number; sex: string | null; state: string; state_reason: string | null; note: string | null;
  occupied: number; reserved: number; available: number; maintenance: number; out_of_service: number; facilities: string | null;
}
export interface Block { id: string; hall_code: string; code: string; name: string; floors: number; state: string; state_reason: string | null; note: string | null }
export interface Asset { id: string; tag: string; kind: string; hall_code: string; hall_name?: string; block_id: string | null; room_id: string | null; room_no?: string | null; block?: string | null; quantity: number; condition: string; acquired_on: string | null; value: number | null; state: string; note: string | null }
export interface InventoryData { session: string; kinds: { code: string; label: string; active: boolean }[]; roomTypes: { code: string; label: string; beds: number; active: boolean }[]; facilities: { code: string; label: string; active: boolean }[]; halls: HallFull[]; blocks: Block[]; rooms: RoomRow[]; assets: Asset[] }

export interface BedRow {
  hall_code: string; hall_name: string; hall_kind: string; hall_sex: string | null; hall_state: string; campus: string | null; block_id: string | null; block: string; block_state: string; floor: number;
  room_id: string; room_no: string; room_type: string | null; room_state: string; capacity: number; bed_id: string; bed_no: number; bed_label: string; bed_state: string;
  occupancy: string; allocation_id: string | null; allocation_state: string | null; student_id: string | null; student_name: string | null; student_number: string | null; sex: string | null; programme: string | null; programme_code: string | null;
  dept_code: string | null; department: string | null; faculty_code: string | null; faculty: string | null; level: number | null; checked_in_at: string | null; end_on: string | null;
}
export interface ApplicationRow {
  application_id: string; reference: string; state: string; review: string | null; review_note: string | null; category: string; category_note: string | null; applied_at: string; draw_position: number | null;
  student_id: string; student_name: string; student_number: string; sex: string | null; level: number; programme: string | null; programme_code: string | null; dept_code: string | null; department: string | null; faculty_code: string | null; faculty: string | null;
  hall_pref: string | null; hall_pref_name: string | null; room_type_pref: string | null; block_pref: string | null; special_need: string | null; roommate_name: string | null;
  eligible: boolean; eligibility_why: string; allocation_id: string | null; allocation_ref: string | null; allocation_state: string | null; hall_name: string | null; block: string | null; room_no: string | null; bed_label: string | null;
  fee_paid: boolean; held_until: string | null; reference_no: string | null;
}
export interface FreeBed { room_id: string; hall_code: string; hall_name: string; hall_sex: string | null; block: string; room_no: string; bed: number; bed_id: string; room_type: string | null; room_type_label: string | null; floor: number }
export interface ClearanceRow {
  id: string; reference: string; state: string; started_at: string; completed_at: string | null; allocation_id: string; reference_no: string; allocation_state: string; checkout_requested_at: string | null; checkout_on: string | null; checked_out_at: string | null;
  student_name: string; student_number: string; hall_name: string; block: string; room_no: string; bed_label: string | null; outstanding: number; outstanding_items: string | null; charges_due: number;
}

export type PilKind = "grey" | "info" | "ok" | "bad" | "warn";
export const APP_STATE: Record<string, [string, PilKind]> = {
  APPLIED: ["Submitted", "info"], ALLOCATED: ["Allocated — payment pending", "warn"], CONFIRMED: ["Confirmed", "ok"], LAPSED: ["Lapsed unpaid", "bad"], UNSUCCESSFUL: ["Waitlisted", "warn"], WITHDRAWN: ["Withdrawn", "grey"], REJECTED: ["Rejected", "bad"],
};
export const REVIEW: Record<string, [string, PilKind]> = { APPROVED: ["Approved", "ok"], REJECTED: ["Rejected", "bad"], WAITLISTED: ["Waitlisted", "warn"], CORRECTION: ["Correction asked", "warn"] };
export const ALLOC_STATE: Record<string, [string, PilKind]> = {
  HELD: ["Held — pay the fee", "warn"], CONFIRMED: ["Confirmed — accept", "info"], ACCEPTED: ["Accepted — check in", "info"], CHECKED_IN: ["Checked in", "ok"], CHECKED_OUT: ["Checked out", "grey"],
  DECLINED: ["Declined", "grey"], LAPSED: ["Lapsed", "bad"], CANCELLED: ["Cancelled", "bad"], TRANSFERRED: ["Transferred", "grey"],
};
export const OCCUPANCY: Record<string, [string, PilKind]> = { AVAILABLE: ["Available", "ok"], RESERVED: ["Reserved", "warn"], OCCUPIED: ["Occupied", "info"], MAINTENANCE: ["Maintenance", "bad"], OUT_OF_SERVICE: ["Out of service", "grey"] };
export const CLEAR_STATE: Record<string, [string, PilKind]> = { PENDING: ["Pending", "warn"], CLEARED: ["Cleared", "ok"], NOT_CLEARED: ["Not cleared", "bad"], WAIVED: ["Waived", "info"], NOT_APPLICABLE: ["Not applicable", "grey"] };
export const TRANSFER_STATE: Record<string, [string, PilKind]> = { SUBMITTED: ["Submitted", "info"], UNDER_REVIEW: ["Under review", "warn"], APPROVED: ["Approved", "ok"], REJECTED: ["Rejected", "bad"], COMPLETED: ["Completed", "ok"], CANCELLED: ["Cancelled", "grey"] };
export const WINDOW_STATE: Record<string, [string, PilKind]> = { DRAFT: ["Draft", "grey"], OPEN: ["Open", "ok"], CLOSED: ["Closed", "bad"], ALLOCATED: ["Allocated", "info"] };
export const METHODS: [string, string][] = [
  ["BALLOT", "Ballot from a published seed (priority categories first)"], ["FIRST_COME", "First come, first served"], ["LEVEL", "Level-based — higher levels first"],
  ["FACULTY", "Faculty-based — faculties kept together"], ["PROGRAMME", "Programme-based — programmes kept together"], ["SPECIAL_NEEDS", "Special needs first, then the ballot"], ["MANUAL", "Manual — every seat by hand"],
];
export const MAINT_CATS: [string, string][] = [["BED", "Broken bed"], ["FURNITURE", "Damaged furniture"], ["WATER", "Water"], ["ELECTRICITY", "Electricity"], ["PLUMBING", "Plumbing"], ["INTERNET", "Internet"], ["CLEANING", "Cleaning"], ["SECURITY", "Security"], ["OTHER", "Other"]];
export const CONDITIONS = ["NEW", "GOOD", "FAIR", "DAMAGED", "REPAIR_REQUIRED", "REPLACED", "DISPOSED"];

export const dayOf = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");
export const longDay = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long", year: "numeric" }) : "—");
export const whenAt = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }) : "—");
export const naira = (n: number | string | null | undefined) => (n === null || n === undefined ? "—" : `₦${Number(n).toLocaleString("en-NG", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`);
export const pct = (a: number, b: number) => (b ? Math.round((1000 * a) / b) / 10 : 0);
export function hostelVerifyPath(ref: string): string {
  return `/verify/hostel/${encodeURIComponent(ref)}`;
}

/** one call to the hostel doors from the browser: the problem returned, never thrown */
export async function callHostel<T>(method: "GET" | "POST" | "PUT", path: string, body: unknown, reason: string): Promise<{ ok: true; data: T } | { ok: false; problem: Problem }> {
  const r = await fetch(`/api/bff/api/v1${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: body === undefined ? undefined : JSON.stringify(body) });
  const j = await r.json().catch(() => null);
  if (!r.ok) return { ok: false, problem: (j as Problem) ?? { status: r.status, title: r.statusText } };
  return { ok: true, data: j as T };
}
