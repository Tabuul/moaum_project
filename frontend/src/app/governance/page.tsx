import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Governance, type Activity, type DsrRow } from "./Governance";

export const dynamic = "force-dynamic";

/** t/governance — data governance under the Nigeria Data Protection Act 2023. */
export default async function GovernancePage() {
  const [me, reg, dsr] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ rows: Activity[] }>("/api/v1/governance/register"),
    api<{ rows: DsrRow[] }>("/api/v1/governance/dsr"),
  ]);
  return (
    <Shell route="t/governance" me={me.ok ? me.data : null}>
      {reg.ok ? (
        <Governance register={reg.data.rows} dsr={dsr.ok ? dsr.data.rows : []} actingOffice={me.ok ? me.data.activeOffice : null} />
      ) : <ProblemNotice problem={reg.problem} />}
    </Shell>
  );
}
