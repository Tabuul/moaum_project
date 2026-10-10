import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { ManualAdmin } from "@/components/manual/ManualAdmin";
import type { ManualAdminView } from "@/lib/manual";

export const dynamic = "force-dynamic";

/** t/manualadmin — Manual Management (V387): Super Administrator, System Administrator, Director of ICT */
export default async function Page() {
  const [me, data] = await Promise.all([api<Me>("/api/v1/iam/me"), api<ManualAdminView>("/api/v1/manual/admin")]);
  return (
    <Shell route="t/manualadmin" me={me.ok ? me.data : null}>
      {data.ok ? <ManualAdmin data={data.data} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
