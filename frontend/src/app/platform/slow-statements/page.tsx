import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { SlowStatements, type SlowData } from "./SlowStatements";
import { DatabaseLimits, type DatabaseLimitsData } from "./DatabaseLimits";

export const dynamic = "force-dynamic";

/** t/slowstatements — V546: the live database's own slowest statements, with the screens that issue them. */
export default async function SlowStatementsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const order = typeof p.order === "string" && ["MEAN", "MAX", "TOTAL", "CALLS"].includes(p.order) ? p.order : "MEAN";
  const minCalls = typeof p.minCalls === "string" && Number(p.minCalls) > 0 ? Math.floor(Number(p.minCalls)) : 5;
  // V555: over the last days by the daily snapshots, or since the statistics were reset
  const days = typeof p.days === "string" && [1, 7, 30].includes(Number(p.days)) ? Number(p.days) : 0;
  const [me, data, limits] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<SlowData>(`/api/v1/platform/slow-statements?order=${order}&minCalls=${minCalls}&limit=200${days ? `&days=${days}` : ""}`),
    // 11 Nov 2026: the database's time limits on the portal's statements, and what it stopped since the API started
    api<DatabaseLimitsData>("/api/v1/platform/database-limits"),
  ]);
  const office = me.ok ? me.data.activeOffice : null;
  return (
    <Shell route="t/slowstatements" me={me.ok ? me.data : null}>
      {/* the slow-statements refusal is shown once below; an API not yet carrying the read-out (404) shows no panel */}
      {limits.ok ? <DatabaseLimits d={limits.data} /> : data.ok && limits.problem.status !== 404 ? <ProblemNotice problem={limits.problem} /> : null}
      {data.ok ?<SlowStatements d={data.data} order={order} minCalls={minCalls} days={days} may={office === "ict" || office === "super"} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
