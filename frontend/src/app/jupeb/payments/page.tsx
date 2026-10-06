import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { JupebPayments } from "../JupebOffice";

export const dynamic = "force-dynamic";

/** /jupeb/payments — the JUPEB payments of a session, read by the JUPEB Office and the Bursary (V339) */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice : null;
  const canConfirm = office === "bursar" || office === "super";
  return (
    <Shell route="jupeb/payments" me={me.ok ? me.data : null}>
      <JupebPayments canConfirm={canConfirm} />
    </Shell>
  );
}
