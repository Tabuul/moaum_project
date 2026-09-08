import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import type { MySheet } from "@/lib/results";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { SheetsList } from "./SheetsList";

export const dynamic = "force-dynamic";

/** t/scores — the lecturer's own sheets; every sheet in the session for the offices that read them all */
export default async function SheetsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const { scope, sessions } = await loadScope(params);
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice : null;
  const all = office !== "lecturer";
  const sheets = await api<MySheet[]>(`/api/v1/results/mine?session=${encodeURIComponent(scope.session)}${scope.sem ? `&sem=${scope.sem}` : ""}${all ? "&all=true" : ""}`);
  return (
    <Shell route="t/scores" me={me.ok ? me.data : null}>
      {sheets.ok ? <SheetsList sheets={sheets.data} session={scope.session} sessions={sessions} sem={scope.sem} all={all} /> : <ProblemNotice problem={sheets.problem} />}
    </Shell>
  );
}
