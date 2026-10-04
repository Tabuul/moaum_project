import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { gstQuery, readGstFilters, type GstDashboardData } from "@/lib/gst";
import { GstDashboard } from "@/app/gst/GstDashboard";
import type { CbtSummary } from "@/lib/cbt";

export const dynamic = "force-dynamic";

/** r/gst — the GST office's dashboard (V314, CBT figures V322): the figures, the charts, the quick questions, the courses, the results and the CBT examinations, every one counted in the database */
export default async function GSTDashboardPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const filters = readGstFilters(await searchParams);
  const [me, data] = await Promise.all([api<Me>("/api/v1/iam/me"), api<GstDashboardData>(`/api/v1/gst/GST/dashboard?${gstQuery(filters)}`)]);
  const cbt = data.ok ? await api<CbtSummary>(`/api/v1/cbt/summary?office=GST&session=${encodeURIComponent(data.data.session)}`) : null;
  return (
    <Shell route="r/gst" me={me.ok ? me.data : null}>
      {data.ok ? <GstDashboard data={data.data} filters={filters} base="/gst" actingOffice={me.ok ? me.data.activeOffice : null} cbt={cbt && cbt.ok ? cbt.data : null} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
