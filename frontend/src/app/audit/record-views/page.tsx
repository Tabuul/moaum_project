import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { RecordViews, type RecordViewsData } from "./RecordViews";

export const dynamic = "force-dynamic";

const KEYS = ["from", "to", "office", "q", "student", "page"] as const;

/** t/recordviews — V530: who opened a student's record, for Internal Audit. */
export default async function RecordViewsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const filters: Record<string, string> = {};
  for (const k of KEYS) {
    const v = p[k];
    if (typeof v === "string" && v.trim()) filters[k] = v.trim();
  }
  const q = new URLSearchParams(filters);
  const [me, data] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<RecordViewsData>(`/api/v1/audit/record-views${q.toString() ? `?${q.toString()}` : ""}`),
  ]);
  return (
    <Shell route="t/recordviews" me={me.ok ? me.data : null}>
      {data.ok ? <RecordViews d={data.data} filters={filters} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
