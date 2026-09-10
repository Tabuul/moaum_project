import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Security, type Posture } from "./Security";

export const dynamic = "force-dynamic";

/** t/security — security posture, read from the audit spine and the sign-in record. */
export default async function SecurityPage() {
  const [me, posture] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Posture>("/api/v1/governance/security")]);
  return (
    <Shell route="t/security" me={me.ok ? me.data : null}>
      {posture.ok ? <Security p={posture.data} /> : <ProblemNotice problem={posture.problem} />}
    </Shell>
  );
}
