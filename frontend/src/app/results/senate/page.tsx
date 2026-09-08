import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import type { Senate } from "@/lib/results";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { SenateScreen } from "./SenateScreen";

export const dynamic = "force-dynamic";

/** t/senate — nothing is published without a minute */
export default async function SenatePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const { scope, structure, sessions } = await loadScope(params);
  const [me, senate] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Senate>(`/api/v1/results/senate?session=${encodeURIComponent(scope.session)}&sem=${scope.sem || "1"}`)]);
  return (
    <Shell route="t/senate" me={me.ok ? me.data : null}>
      {senate.ok ? <SenateScreen scope={scope} structure={structure} sessions={sessions} senate={senate.data} actingOffice={me.ok ? me.data.activeOffice : null} publish={false} /> : <ProblemNotice problem={senate.problem} />}
    </Shell>
  );
}
