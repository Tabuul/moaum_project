import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { AllocatableBed } from "@/lib/hostel";
import { hostelSession } from "../page";
import { Special, type SpecialData } from "./Special";

export const dynamic = "force-dynamic";

/** t/hostel-special — the special, Student Union and Security allocations of a session, and the Dean's allocation of one (V290) */
export default async function SpecialPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const { session, sessions } = await hostelSession(p);
  const [me, data, beds] = await Promise.all([api<Me>("/api/v1/iam/me"), api<SpecialData>(`/api/v1/hostel/sessions/${session}/special`), api<{ beds: AllocatableBed[] }>(`/api/v1/hostel/sessions/${session}/allocatable-beds`)]);
  return (
    <Shell route="t/hostel-special" me={me.ok ? me.data : null}>
      {data.ok ? <Special data={data.data} session={session} sessions={sessions} office={me.ok ? me.data.activeOffice ?? null : null} beds={beds.ok ? beds.data.beds : []} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
