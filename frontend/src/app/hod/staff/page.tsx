import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { StaffList, type DeptStaff } from "./StaffList";

export const dynamic = "force-dynamic";

/** t/deptstaff — the HOD's department staff. */
export default async function DeptStaffPage() {
  const [me, view] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<DeptStaff>("/api/v1/hod/staff"),
  ]);
  return (
    <Shell route="t/deptstaff" me={me.ok ? me.data : null}>
      {view.ok ? <StaffList data={view.data} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
