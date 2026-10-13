import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Security, type Posture, type SessionMonitor, type PolicyChange } from "./Security";
import type { SessionPolicy } from "@/lib/idle";

export const dynamic = "force-dynamic";

/** t/security — security posture, read from the audit spine and the sign-in record. */
export default async function SecurityPage() {
  const [me, posture, policy, monitor, history] = await Promise.all([
    api<Me>("/api/v1/iam/me"), api<Posture>("/api/v1/governance/security"),
    // V437: the session timeout, the sessions open now, and the setting's history
    api<SessionPolicy>("/api/v1/auth/session-policy"), api<SessionMonitor>("/api/v1/auth/session-policy/monitor"), api<PolicyChange[]>("/api/v1/auth/session-policy/history"),
  ]);
  const office = me.ok ? me.data.activeOffice ?? "" : "";
  return (
    <Shell route="t/security" me={me.ok ? me.data : null}>
      {posture.ok ? <Security p={posture.data} policy={policy.ok ? policy.data : null} monitor={monitor.ok ? monitor.data : null} history={history.ok ? history.data : []}
        canSet={["ict", "admin", "super"].includes(office)} /> : <ProblemNotice problem={posture.problem} />}
    </Shell>
  );
}
