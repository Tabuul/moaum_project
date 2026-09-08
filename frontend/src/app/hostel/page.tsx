import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import type { HostelDeskData } from "@/lib/hostel";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { HostelDesk } from "./HostelDesk";

export const dynamic = "force-dynamic";

/** t/hostel — priority by rule, the rest by a ballot anyone can re-run */
export default async function HostelPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const { scope, sessions } = await loadScope(params);
  const [me, desk] = await Promise.all([api<Me>("/api/v1/iam/me"), api<HostelDeskData>(`/api/v1/hostel/sessions/${scope.session}`)]);
  return (
    <Shell route="t/hostel" me={me.ok ? me.data : null}>
      {desk.ok ? <HostelDesk d={desk.data} sessions={sessions} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={desk.problem} />}
    </Shell>
  );
}
