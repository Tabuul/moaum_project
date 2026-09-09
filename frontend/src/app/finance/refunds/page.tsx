import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Refunds, type Refund } from "./Refunds";

export const dynamic = "force-dynamic";

/** t/refunds — refunds and credits, maker–checker controlled. */
export default async function RefundsPage() {
  const [me, list] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Refund[]>("/api/v1/finance/refunds")]);
  return (
    <Shell route="t/refunds" me={me.ok ? me.data : null}>
      {list.ok ? <Refunds refunds={list.data} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
