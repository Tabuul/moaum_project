import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import type { NelfundDesk, FundingReport } from "@/lib/wallet";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Nelfund } from "./Nelfund";

export const dynamic = "force-dynamic";

/** Sources of funding — the wallet fed from many sources, its remittances, suspense, the Fund's decisions,
 *  withdrawals to bank, the source settings and the report (V033, V079). */
export default async function NelfundPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const tab = typeof params.tab === "string" && ["match", "status", "withdrawals", "sources", "report"].includes(params.tab) ? params.tab : "batches";
  const { scope, sessions } = await loadScope(params);
  const [me, desk, report] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<NelfundDesk>(`/api/v1/nelfund/sessions/${scope.session}`),
    api<FundingReport>(`/api/v1/funding/sessions/${scope.session}/report`),
  ]);
  const route = tab === "match" ? "t/nelmatch" : tab === "status" ? "t/nelstatus" : "t/nelfund";
  return (
    <Shell route={route} me={me.ok ? me.data : null}>
      {desk.ok ? <Nelfund d={desk.data} report={report.ok ? report.data : null} tab={tab} sessions={sessions} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={desk.problem} />}
    </Shell>
  );
}
