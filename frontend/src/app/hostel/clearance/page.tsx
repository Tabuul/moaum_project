import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { BedRow, ClearanceRow, Maintenance, TransferReq } from "@/lib/hostel";
import { hostelSession } from "../page";
import { Clearances } from "./Clearances";

export const dynamic = "force-dynamic";

/** t/hostel › checkout & clearance — the clearances of the session, the checkouts requested, the transfer requests, the maintenance queue */
export default async function HostelClearancePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const g = (k: string) => (typeof p[k] === "string" ? (p[k] as string).slice(0, 40) : "");
  const { session } = await hostelSession(p);
  const state = g("state"), q = g("q"), tab = g("tab") || "clearances";
  const qs = new URLSearchParams(); if (state) qs.set("state", state); if (q) qs.set("q", q);
  const [me, clearances, checkouts, transfers, maintenance] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ rows: ClearanceRow[] }>(`/api/v1/hostel/sessions/${session}/clearances?${qs}`),
    api<{ rows: BedRow[] }>(`/api/v1/hostel/sessions/${session}/occupancy?view=checkouts&size=1000`),
    api<TransferReq[]>(`/api/v1/hostel/sessions/${session}/transfers`),
    api<Maintenance[]>("/api/v1/hostel/maintenance"),
  ]);
  return (
    <Shell route="t/hostel" me={me.ok ? me.data : null}>
      {clearances.ok ? <Clearances rows={clearances.data.rows} checkouts={checkouts.ok ? checkouts.data.rows : []} transfers={transfers.ok ? transfers.data : []} maintenance={maintenance.ok ? maintenance.data : []} session={session} state={state} q={q} tab={tab} office={me.ok ? me.data.activeOffice ?? null : null} /> : <ProblemNotice problem={clearances.problem} />}
    </Shell>
  );
}
