import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { Self, type StaffMe, type Payslip } from "./Self";
import type { MyLeave } from "./LeaveSelf";

export const dynamic = "force-dynamic";

export default async function MePage() {
  const [me, staff, payslips, leave] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<StaffMe>("/api/v1/staff/me"),
    api<Payslip[]>("/api/v1/me/payslips"),
    api<MyLeave>("/api/v1/me/leave"),
  ]);

  return (
    <Shell route="r/self" me={me.ok ? me.data : null}>
      <Self
        staff={staff.ok ? staff.data : null}
        payslips={payslips.ok ? payslips.data : []}
        leave={leave.ok ? leave.data : null}
        problem={staff.ok ? null : staff.problem}
        actingOffice={me.ok ? me.data.activeOffice : null}
      />
    </Shell>
  );
}
