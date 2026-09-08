/** Hostel and accommodation, as the API states it (V030). */
export interface Hall { code: string; name: string; sex: string | null; beds: number; rooms: number; out_of_service: number }
export interface HostelView {
  application_id: string | null; state: string | null; hall_code: string | null; hall_name: string | null; category: string | null; applied_at: string | null;
  allocation_id: string | null; room_id: string | null; block: string | null; room_no: string | null; bed: number | null; beds: number | null;
  basis: string | null; draw_position: number | null; held_until: string | null; confirmed_at: string | null; lapsed_at: string | null; reference: string | null;
  fee: number | null; hold_hours: number | null; drawn_at: string | null; seed: string | null; applications_close: string | null; open: boolean | null;
}
export interface HostelHistory { session: string; state: string; hall_name: string | null; block: string | null; room_no: string | null; bed: number | null; basis: string | null; confirmed_at: string | null; lapsed_at: string | null; applied_at: string }
export interface Maintenance { id: string; issue: string; raised_at: string; state: string; note: string | null; decided_at: string | null; raised_by_name: string; hall_name?: string; block?: string; room_no?: string; number?: string }
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
