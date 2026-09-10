import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { PayRun } from "../Payroll";
import { Variance, type VarianceRow } from "./Variance";

export const dynamic = "force-dynamic";

/** t/auditpayroll — payroll variance: a month against the one before it. */
export default async function VariancePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const [me, runsRes] = await Promise.all([api<Me>("/api/v1/iam/me"), api<PayRun[]>("/api/v1/payroll/runs")]);
  const runs = runsRes.ok ? runsRes.data.filter((r) => r.state !== "CANCELLED") : [];
  const asked = typeof params.period === "string" ? params.period : null;
  const period = asked ?? (runs.length ? runs[0].period.slice(0, 7) : null);
  const v = period ? await api<{ period: string; rows: VarianceRow[] }>(`/api/v1/payroll/variance?period=${period}`) : null;
  return (
    <Shell route="t/auditpayroll" me={me.ok ? me.data : null}>
      {runsRes.ok ? (
        <Variance
          runs={runs}
          period={period}
          rows={v && v.ok ? v.data.rows : []}
          problem={v && !v.ok ? v.problem : null}
        />
      ) : <ProblemNotice problem={runsRes.problem} />}
    </Shell>
  );
}
