import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { DisasterRecovery, type Drill } from "./DisasterRecovery";

export const dynamic = "force-dynamic";

/** t/dr — disaster recovery: objectives, the drill log, and the runbook. */
export default async function DrPage() {
  const [me, data] = await Promise.all([api<Me>("/api/v1/iam/me"), api<{ drills: Drill[] }>("/api/v1/governance/dr")]);
  return (
    <Shell route="t/dr" me={me.ok ? me.data : null}>
      {data.ok ? <DisasterRecovery drills={data.data.drills} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
