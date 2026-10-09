import { api } from "@/lib/api";
import type { GatewayConfig, PaydirectDesk, PaymentsDesk } from "@/lib/bursary";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Gateways } from "./Gateways";

export const dynamic = "force-dynamic";

/** t/gateways — what is wired, the webhook log, a test checkout, and Pay on Quickteller (V299) */
export default async function GatewaysPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const [me, d, cfg, qt] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<PaymentsDesk>("/api/v1/payments/bursary"),
    api<GatewayConfig[]>("/api/v1/payments/gateway-config"),
    api<PaydirectDesk>("/api/v1/payments/paydirect"),
  ]);
  const quickteller = qt.ok ? { ...qt.data, billers: qt.data.billers ?? [], collections: qt.data.collections ?? [], validations: qt.data.validations ?? [], testReferences: qt.data.testReferences ?? [], credentials: qt.data.credentials === true } : null;
  return (
    <Shell route="t/gateways" me={me.ok ? me.data : null}>
      {d.ok ? <Gateways d={d.data} config={cfg.ok ? cfg.data : []} quickteller={quickteller} paid={typeof params.paid === "string" ? params.paid : null} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={d.problem} />}
    </Shell>
  );
}
