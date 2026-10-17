import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { ApiKeys, type Call, type Consumer, type Scope } from "./ApiKeys";

export const dynamic = "force-dynamic";

/** t/api — API consumers and their keys; V511: the scopes they may hold and the calls on the integration door. */
export default async function ApiKeysPage() {
  const [me, consumers, scopes, calls] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Consumer[]>("/api/v1/apimgmt/consumers"),
    api<Scope[]>("/api/v1/apimgmt/scopes"), api<Call[]>("/api/v1/apimgmt/calls")]);
  return (
    <Shell route="t/api" me={me.ok ? me.data : null}>
      {consumers.ok ? <ApiKeys consumers={consumers.data} scopes={scopes.ok ? scopes.data : []} calls={calls.ok ? calls.data : []} /> : <ProblemNotice problem={consumers.problem} />}
    </Shell>
  );
}
