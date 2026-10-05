import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import type { NelfundDesk, FundingReport, NelfundFigures, NelfundStudentRow, WalletPolicy } from "@/lib/wallet";
import type { NelfundLegacyPage } from "@/lib/legacy-nelfund";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Nelfund } from "./Nelfund";

export const dynamic = "force-dynamic";

/** Sources of funding — the wallet fed from many sources, its remittances, suspense, the Fund's decisions,
 *  withdrawals to bank, the source settings and the report (V033, V079). */
export default async function NelfundPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const tab = typeof params.tab === "string" && ["overview", "students", "legacy", "match", "status", "withdrawals", "sources", "report"].includes(params.tab) ? params.tab : "batches";
  const filter = typeof params.filter === "string" ? params.filter : "ALL";
  const q = typeof params.q === "string" ? params.q : "";
  const page = typeof params.page === "string" && Number(params.page) > 0 ? Number(params.page) : 1;
  const { scope, sessions } = await loadScope(params);
  const [me, desk, report, figures, students, legacy] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<NelfundDesk>(`/api/v1/nelfund/sessions/${scope.session}`),
    api<FundingReport>(`/api/v1/funding/sessions/${scope.session}/report`),
    /* V327: the figures over the funded population, the students a page at a time, the old portal's payments — each only on its tab */
    tab === "overview" ? api<{ figures: NelfundFigures; policy: WalletPolicy }>(`/api/v1/nelfund/figures?session=${encodeURIComponent(scope.session)}`) : null,
    tab === "students" ? api<{ rows: NelfundStudentRow[]; total: number; page: number; size: number; filter: string }>(`/api/v1/nelfund/students?session=${encodeURIComponent(scope.session)}&filter=${encodeURIComponent(filter)}&q=${encodeURIComponent(q)}&page=${page}&size=100`) : null,
    tab === "legacy" ? api<NelfundLegacyPage>(`/api/v1/nelfund/legacy/summary?session=${encodeURIComponent(scope.session)}`) : null,
  ]);
  const route = tab === "match" ? "t/nelmatch" : tab === "status" ? "t/nelstatus" : tab === "legacy" ? "t/nellegacy" : "t/nelfund";
  return (
    <Shell route={route} me={me.ok ? me.data : null}>
      {desk.ok ? <Nelfund d={desk.data} report={report.ok ? report.data : null} tab={tab} sessions={sessions} actingOffice={me.ok ? me.data.activeOffice : null}
        figures={figures && figures.ok ? figures.data : null} students={students && students.ok ? { ...students.data, q } : null} legacy={legacy && legacy.ok ? legacy.data : null} /> : <ProblemNotice problem={desk.problem} />}
    </Shell>
  );
}
