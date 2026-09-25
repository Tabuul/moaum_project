import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { BedRow } from "@/lib/hostel";
import { hostelSession } from "../page";
import { Occupancy } from "./Occupancy";

export const dynamic = "force-dynamic";

export interface OccFilters { hall: string; block: string; status: string; fac: string; dept: string; prog: string; level: string; sex: string; q: string; view: string; page: string; room: string }
export interface OccList { session: string; total: number; page: number; size: number; rows: BedRow[]; halls: { code: string; name: string }[]; blocks: { hall_code: string; code: string }[]; options: { faculty_code: string; faculty: string; dept_code: string; department: string; programme_code: string; programme: string }[] }

/** t/hostel › occupancy — every bed with who holds it; every student with where they stay; a room opened bed by bed */
export default async function HostelOccupancyPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const g = (k: string) => (typeof p[k] === "string" ? (p[k] as string).slice(0, 80) : "");
  const { session } = await hostelSession(p);
  const filters: OccFilters = { hall: g("hall"), block: g("block"), status: g("status"), fac: g("fac"), dept: g("dept"), prog: g("prog"), level: g("level"), sex: g("sex"), q: g("q"), view: g("view"), page: g("page"), room: g("room") };
  const qs = new URLSearchParams(); for (const [k, v] of Object.entries(filters)) if (v && k !== "room") qs.set(k, v);
  qs.set("size", "500");
  const [me, view] = await Promise.all([api<Me>("/api/v1/iam/me"), api<OccList>(`/api/v1/hostel/sessions/${session}/occupancy?${qs}`)]);
  return (
    <Shell route="t/hostel" me={me.ok ? me.data : null}>
      {view.ok ? <Occupancy list={view.data} filters={filters} session={session} office={me.ok ? me.data.activeOffice ?? null : null} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
