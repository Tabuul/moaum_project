import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Overview, type OverviewData } from "./Overview";

export const dynamic = "force-dynamic";

/** t/overview — the session so far, in figures. */
export default async function OverviewPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const semester = typeof p.sem === "string" ? Number(p.sem) || 1 : 1;
  const [me, data] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<OverviewData>(`/api/v1/reporting/overview?semester=${semester}`),
  ]);
  return (
    <Shell route="t/overview" me={me.ok ? me.data : null}>
      {data.ok ? <Overview d={data.data} semester={semester} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
