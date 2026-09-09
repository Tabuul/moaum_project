import { api } from "@/lib/api";
import type { PaymentsDesk } from "@/lib/bursary";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Hanging } from "./Hanging";

export const dynamic = "force-dynamic";

/** t/hanging — successful at the gateway, pending here: asked about, not argued about */
export default async function HangingPage() {
  const [me, d] = await Promise.all([api<Me>("/api/v1/iam/me"), api<PaymentsDesk>("/api/v1/payments/bursary")]);
  return (
    <Shell route="t/hanging" me={me.ok ? me.data : null}>
      {d.ok ? <Hanging d={d.data} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={d.problem} />}
    </Shell>
  );
}
