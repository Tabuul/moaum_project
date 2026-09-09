import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { ApiKeys, type Consumer } from "./ApiKeys";

export const dynamic = "force-dynamic";

/** t/api — API consumers and their keys. */
export default async function ApiKeysPage() {
  const [me, consumers] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Consumer[]>("/api/v1/apimgmt/consumers")]);
  return (
    <Shell route="t/api" me={me.ok ? me.data : null}>
      {consumers.ok ? <ApiKeys consumers={consumers.data} /> : <ProblemNotice problem={consumers.problem} />}
    </Shell>
  );
}
