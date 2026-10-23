import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { QSource } from "@/lib/dbops";
import type { Options } from "@/lib/exam-readiness";
import { QueryBuilder, type HistoryPage, type ReportsPage, type SavedQuery } from "./QueryBuilder";

export const dynamic = "force-dynamic";

/** V640: the Database Operations query builder — a source, conditions, columns, a sort or a grouping; run, exported with S/N first,
 *  saved and shared; the query log and the register of official reports. Never SQL: the server validates and binds everything. */
export default async function QueryPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const s = (k: string) => (typeof params[k] === "string" ? (params[k] as string) : "");
  const { structure, sessions } = await loadScope(params);
  const [me, sources, options, saved, offices, history, reports] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ sources: QSource[]; operators: string[]; period: { session: string; semester: number } }>("/api/v1/dbops/query/sources"),
    api<Options>("/api/v1/reports/exam-readiness/options"),
    api<SavedQuery[]>("/api/v1/dbops/saved?kind=QUERY"),
    api<{ code: string; label: string }[]>("/api/v1/dbops/offices"),
    api<HistoryPage>("/api/v1/dbops/history?page=1&size=50"),
    api<ReportsPage>("/api/v1/dbops/reports?page=1&size=50"),
  ]);
  return (
    <Shell route="t/dbquery" me={me.ok ? me.data : null}>
      {sources.ok ? (
        <QueryBuilder sources={sources.data.sources} period={sources.data.period} structure={structure} sessions={sessions}
          types={options.ok ? options.data.types : []} saved={saved.ok ? saved.data : []} offices={offices.ok ? offices.data : []}
          history={history.ok ? history.data : null} reports={reports.ok ? reports.data : null}
          preset={s("preset")} open={s("open")} tab={s("tab")} actorName={me.ok ? me.data.name ?? null : null} office={me.ok ? me.data.activeOffice : null} />
      ) : <ProblemNotice problem={sources.problem} />}
    </Shell>
  );
}
