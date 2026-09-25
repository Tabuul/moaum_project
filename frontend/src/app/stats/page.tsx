import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { StudentStats } from "@/components/stats/StudentStats";
import { readStatFilters, statQuery, type StatSummary } from "@/lib/stats";

export const dynamic = "force-dynamic";

/** t/studentstats — the student statistics of the acting office's scope: figures, charts, tables, drill-down */
export default async function StatsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const filters = readStatFilters(await searchParams);
  const [me, data] = await Promise.all([api<Me>("/api/v1/iam/me"), api<StatSummary>(`/api/v1/stats/students/summary?${statQuery(filters)}`)]);
  return (
    <Shell route="t/studentstats" me={me.ok ? me.data : null}>
      {data.ok ? <StudentStats data={data.data} filters={filters} basePath="/stats" /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
