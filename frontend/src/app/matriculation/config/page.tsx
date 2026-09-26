import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { MatricConfig, type ConfigData } from "./MatricConfig";

export const dynamic = "force-dynamic";

/** t/matriculation-config — the matriculation number's rule: the format, the series, each faculty's and programme's segments, and the number each would give */
export default async function MatricConfigPage() {
  const [me, view] = await Promise.all([api<Me>("/api/v1/iam/me"), api<ConfigData>("/api/v1/matriculation/config")]);
  return (
    <Shell route="t/matriculation-config" me={me.ok ? me.data : null}>
      {view.ok ? <MatricConfig data={view.data} office={me.ok ? me.data.activeOffice ?? null : null} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
