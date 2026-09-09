import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Vouchers, type Voucher } from "./Vouchers";

export const dynamic = "force-dynamic";

/** t/pv and t/prepayment — payment vouchers and the pre-payment gate. */
export default async function VouchersPage() {
  const [me, list] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Voucher[]>("/api/v1/expenditure/vouchers")]);
  return (
    <Shell route={me.ok && me.data.activeOffice === "bursar" ? "t/pv" : "t/prepayment"} me={me.ok ? me.data : null}>
      {list.ok ? <Vouchers vouchers={list.data} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
