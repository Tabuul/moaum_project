import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { hostelSession } from "../page";
import { Accountability, type AccountabilityData, type AccFilters } from "./Accountability";

export const dynamic = "force-dynamic";

/** t/hostel-accountability — who occupies every room of the session, paying or not; the room board beneath (V290) */
export default async function AccountabilityPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const { session, sessions } = await hostelSession(p);
  const str = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const filters: AccFilters = { hall: str("hall"), category: str("category"), feeStatus: str("feeStatus") };
  const q = new URLSearchParams();
  if (filters.hall) q.set("hall", filters.hall); if (filters.category) q.set("category", filters.category); if (filters.feeStatus) q.set("feeStatus", filters.feeStatus);
  const [me, data] = await Promise.all([api<Me>("/api/v1/iam/me"), api<AccountabilityData>(`/api/v1/hostel/sessions/${session}/accountability${q.size ? `?${q.toString()}` : ""}`)]);
  return (
    <Shell route="t/hostel-accountability" me={me.ok ? me.data : null}>
      {data.ok ? <Accountability data={data.data} filters={filters} session={session} sessions={sessions} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
