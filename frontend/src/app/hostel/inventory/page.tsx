import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { InventoryData } from "@/lib/hostel";
import { hostelSession } from "../page";
import { Inventory } from "./Inventory";

export const dynamic = "force-dynamic";

/** t/hostel › inventory — hostels, blocks, floors, rooms, beds, facilities and assets, with capacity, occupancy and closures */
export default async function HostelInventoryPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const { session } = await hostelSession(p);
  const [me, view] = await Promise.all([api<Me>("/api/v1/iam/me"), api<InventoryData>(`/api/v1/hostel/inventory?session=${encodeURIComponent(session)}`)]);
  return (
    <Shell route="t/hostel" me={me.ok ? me.data : null}>
      {view.ok ? <Inventory data={view.data} session={session} office={me.ok ? me.data.activeOffice ?? null : null} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
