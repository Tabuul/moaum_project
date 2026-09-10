import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { AuditStaff, type StaffRow, type Run } from "./AuditStaff";

export const dynamic = "force-dynamic";

/** t/auditstaff — the audit directorate's read of the establishment and what the payroll pays it. */
export default async function AuditStaffPage() {
  const [me, staff, runs] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<StaffRow[]>("/api/v1/payroll/staff"),
    api<Run[]>("/api/v1/payroll/runs"),
  ]);
  return (
    <Shell route="t/auditstaff" me={me.ok ? me.data : null}>
      {staff.ok ? <AuditStaff staff={staff.data} runs={runs.ok ? runs.data : []} /> : <ProblemNotice problem={staff.problem} />}
    </Shell>
  );
}
