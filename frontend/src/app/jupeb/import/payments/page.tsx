import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { JupebOldPayments } from "./JupebOldPayments";

export const dynamic = "force-dynamic";

/** /jupeb/import/payments — the payments made on the old JUPEB portal, put on each student's record once (V347); the API decides who reads and who writes */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice : null;
  const canWrite = office === "jupeb" || office === "super";
  return (
    <Shell route="jupeb/oldpayments" me={me.ok ? me.data : null}>
      <JupebOldPayments canWrite={canWrite} />
    </Shell>
  );
}
