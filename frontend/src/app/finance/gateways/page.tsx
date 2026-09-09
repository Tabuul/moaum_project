import { api } from "@/lib/api";
import type { PaymentsDesk } from "@/lib/bursary";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Gateways } from "./Gateways";

export const dynamic = "force-dynamic";

/** t/gateways — what is wired, the webhook log, and a test checkout to watch an event arrive */
export default async function GatewaysPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const [me, d] = await Promise.all([api<Me>("/api/v1/iam/me"), api<PaymentsDesk>("/api/v1/payments/bursary")]);
  return (
    <Shell route="t/gateways" me={me.ok ? me.data : null}>
      {d.ok ? <Gateways d={d.data} paid={typeof params.paid === "string" ? params.paid : null} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={d.problem} />}
    </Shell>
  );
}
