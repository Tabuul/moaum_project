import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Payroll, type PayRun, type RunDetail } from "./Payroll";

export const dynamic = "force-dynamic";

/** t/payroll — the monthly payroll run, maker–checker controlled. */
export default async function PayrollPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const runId = typeof params.run === "string" ? params.run : null;
  const [me, runs, detail] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<PayRun[]>("/api/v1/payroll/runs"),
    runId ? api<RunDetail>(`/api/v1/payroll/runs/${runId}`) : Promise.resolve(null),
  ]);
  return (
    <Shell route="t/payroll" me={me.ok ? me.data : null}>
      {runs.ok ? (
        <Payroll
          runs={runs.data}
          detail={detail && detail.ok ? detail.data : null}
          actingOffice={me.ok ? me.data.activeOffice : null}
        />
      ) : <ProblemNotice problem={runs.problem} />}
    </Shell>
  );
}
