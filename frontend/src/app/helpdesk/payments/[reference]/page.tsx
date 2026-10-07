import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { PaymentDiagnosis } from "@/lib/support";
import { PaymentCase } from "./PaymentCase";

export const dynamic = "force-dynamic";

/** One payment in Payment Support (V346): the diagnosis — gateway, finance, entitlement, verification — and the acts allowed. */
export default async function PaymentCasePage({ params, searchParams }: { params: Promise<{ reference: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const { reference } = await params;
  const p = await searchParams;
  const ticket = typeof p.ticket === "string" ? p.ticket : "";
  const [me, d] = await Promise.all([api<Me>("/api/v1/iam/me"), api<PaymentDiagnosis>(`/api/v1/helpdesk/support/payments/${encodeURIComponent(reference)}`)]);
  return (
    <Shell route="t/supportpayments" me={me.ok ? me.data : null}>
      {!d.ok ? <ProblemNotice problem={d.problem} /> : <PaymentCase data={d.data} ticket={ticket} />}
    </Shell>
  );
}
