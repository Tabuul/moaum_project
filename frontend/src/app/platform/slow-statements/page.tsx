import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { SlowStatements, type SlowData } from "./SlowStatements";

export const dynamic = "force-dynamic";

/** t/slowstatements — V546: the live database's own slowest statements, with the screens that issue them. */
export default async function SlowStatementsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const order = typeof p.order === "string" && ["MEAN", "MAX", "TOTAL", "CALLS"].includes(p.order) ? p.order : "MEAN";
  const minCalls = typeof p.minCalls === "string" && Number(p.minCalls) > 0 ? Math.floor(Number(p.minCalls)) : 5;
  const [me, data] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<SlowData>(`/api/v1/platform/slow-statements?order=${order}&minCalls=${minCalls}&limit=200`),
  ]);
  const office = me.ok ? me.data.activeOffice : null;
  return (
    <Shell route="t/slowstatements" me={me.ok ? me.data : null}>
      {data.ok ? <SlowStatements d={data.data} order={order} minCalls={minCalls} may={office === "ict" || office === "super"} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
