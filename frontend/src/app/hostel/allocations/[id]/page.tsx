import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Charge, ClearanceItem, HostelEvent, Inspection, Roommate, TransferReq } from "@/lib/hostel";
import { hostelSession } from "../../page";
import { Allocation } from "./Allocation";

export const dynamic = "force-dynamic";

export interface AllocationFull {
  id: string; reference_no: string; application_id: string; application_ref: string; session: string; state: string; basis: string; draw_position: number | null; allocated_at: string; held_until: string; reference: string | null; confirmed_at: string | null;
  lapsed_at: string | null; ended_at: string | null; ended_reason: string | null; start_on: string | null; end_on: string | null; accepted_at: string | null; rules_version: number | null; declined_at: string | null; decline_reason: string | null;
  checked_in_at: string | null; checkin_note: string | null; checkout_requested_at: string | null; checkout_on: string | null; checkout_reason: string | null; checked_out_at: string | null; moved_from: string | null; moved_from_ref: string | null;
  category: string; category_note: string | null; special_need: string | null; roommate_note: string | null; hall_code: string; hall_name: string; hall_sex: string | null; block: string; floor: number; room_no: string; room_type: string | null; bed: number; bed_label: string | null; room_id: string; bed_id: string | null;
  student_id: string; student_name: string; student_number: string; sex: string | null; level: number; student_status: string; programme: string | null; department: string | null; faculty: string | null;
  fee: number | null; rules: string | null; current_rules_version: number | null; clearance_id: string | null; clearance_ref: string | null; clearance_state: string | null; clearance_completed_at: string | null; passport_id: string | null;
  roommates: Roommate[]; inspections: Inspection[]; charges: Charge[]; clearanceItems: ClearanceItem[]; transfers: TransferReq[]; events: HostelEvent[]; assets: { id: string; tag: string; kind: string; condition: string }[];
}

/** t/hostel › allocation — one stay: the student, the placing, check-in, transfer, inspection, damage, clearance, the trail */
export default async function HostelAllocationPage({ params, searchParams }: { params: Promise<{ id: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const { id } = await params;
  const p = await searchParams;
  const { session } = await hostelSession(p);
  const [me, view] = await Promise.all([api<Me>("/api/v1/iam/me"), api<AllocationFull>(`/api/v1/hostel/allocations/${id}`)]);
  return (
    <Shell route="t/hostel" me={me.ok ? me.data : null}>
      {view.ok ? <Allocation a={view.data} session={session} office={me.ok ? me.data.activeOffice ?? null : null} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
