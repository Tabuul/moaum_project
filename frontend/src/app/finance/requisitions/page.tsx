import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Requisitions, type Req } from "./Requisitions";

export const dynamic = "force-dynamic";

/** t/requisitions — procurement requisitions; the method is set by value. */
export default async function RequisitionsPage() {
  const [me, list] = await Promise.all([api<Me>("/api/v1/iam/me"), api<{ rows: Req[] }>("/api/v1/expenditure/requisitions")]);
  return (
    <Shell route="t/requisitions" me={me.ok ? me.data : null}>
      {list.ok ? <Requisitions rows={list.data.rows} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
