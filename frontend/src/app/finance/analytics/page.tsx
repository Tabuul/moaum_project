import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { FinancialAnalytics } from "./FinancialAnalytics";
import { finQuery, readFinFilters, type FinSummary } from "@/lib/analytics";

export const dynamic = "force-dynamic";

/** t/finanalytics — the financial analytics of the acting office's scope: the filters, the figures, the charts, the tables, the drill-down */
export default async function AnalyticsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const filters = readFinFilters(await searchParams);
  const [me, data] = await Promise.all([api<Me>("/api/v1/iam/me"), api<FinSummary>(`/api/v1/analytics/finance/summary?${finQuery(filters, {}, true)}`)]);
  return (
    <Shell route="t/finanalytics" me={me.ok ? me.data : null}>
      {data.ok ? <FinancialAnalytics data={data.data} filters={filters} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
