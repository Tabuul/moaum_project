import { api } from "@/lib/api";
import type { BankCredit, PaymentsDesk } from "@/lib/bursary";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Exceptions } from "./Exceptions";

export const dynamic = "force-dynamic";

/** t/exception and t/cashdesk — money that arrived with no reference: recorded, proposed by one, approved by another, posted */
export default async function ExceptionsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const state = typeof params.state === "string" && ["open", "posted", "all"].includes(params.state) ? params.state : "open";
  const [me, credits, gw] = await Promise.all([api<Me>("/api/v1/iam/me"), api<BankCredit[]>(`/api/v1/finance/bank-credits?state=${state}`), api<PaymentsDesk>("/api/v1/payments/bursary")]);
  return (
    <Shell route="t/exception" me={me.ok ? me.data : null}>
      {credits.ok ? <Exceptions credits={credits.data} state={state} gatewayExceptions={gw.ok ? gw.data.events.filter((e) => ["UNKNOWN_REFERENCE", "SHORT_PAID", "GATEWAY_ERROR"].includes(e.outcome) && !e.resolved_at).length : 0} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={credits.problem} />}
    </Shell>
  );
}
