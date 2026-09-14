import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { PaymentsHistory } from "./PaymentsHistory";

export const dynamic = "force-dynamic";

/** t/paymenthistory — load past students' payment history (V120). */
export default async function PaymentsHistoryPage() {
  const me = await api<Me>("/api/v1/iam/me");
  return (
    <Shell route="t/paymenthistory" me={me.ok ? me.data : null}>
      <PaymentsHistory actingOffice={me.ok ? me.data.activeOffice : null} />
    </Shell>
  );
}
