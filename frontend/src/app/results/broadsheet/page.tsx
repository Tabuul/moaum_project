import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import type { Broadsheet } from "@/lib/results";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { BroadsheetScreen } from "./BroadsheetScreen";

export const dynamic = "force-dynamic";

/** t/broadsheet — by programme and level, computed from the sheets, never typed */
export default async function BroadsheetPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const { scope, structure, sessions } = await loadScope(params);
  const me = await api<Me>("/api/v1/iam/me");
  const ready = !!scope.prog && !!scope.level;
  const sheet = ready
    ? await api<Broadsheet>(`/api/v1/results/broadsheet?prog=${encodeURIComponent(scope.prog)}&level=${scope.level}&session=${encodeURIComponent(scope.session)}&sem=${scope.sem || "1"}`)
    : null;
  return (
    <Shell route="t/broadsheet" me={me.ok ? me.data : null}>
      {sheet && !sheet.ok ? <ProblemNotice problem={sheet.problem} /> : null}
      <BroadsheetScreen scope={scope} structure={structure} sessions={sessions} sheet={sheet && sheet.ok ? sheet.data : null} />
    </Shell>
  );
}
