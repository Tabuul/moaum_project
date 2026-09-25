import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { DashboardData } from "@/lib/hostel";
import { hostelSession } from "../page";
import { WindowScreen } from "./Window";

export const dynamic = "force-dynamic";

/** t/hostel › window — the fee, the dates, the allocation method, the eligibility rules and the hostel rules of a session */
export default async function HostelWindowPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const { session } = await hostelSession(p);
  const [me, view] = await Promise.all([api<Me>("/api/v1/iam/me"), api<DashboardData>(`/api/v1/hostel/sessions/${session}/dashboard`)]);
  return (
    <Shell route="t/hostel" me={me.ok ? me.data : null}>
      {view.ok ? <WindowScreen data={view.data} session={session} office={me.ok ? me.data.activeOffice ?? null : null} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
