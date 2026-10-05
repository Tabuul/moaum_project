import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { StaffList, type DeptStaff } from "./StaffList";
import type { OfficeScopeState } from "@/lib/office-scope";

export const dynamic = "force-dynamic";

/** t/deptstaff — the HOD's department staff. */
export default async function DeptStaffPage() {
  const [me, view, scope] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<DeptStaff>("/api/v1/hod/staff"),
    api<OfficeScopeState>("/api/v1/iam/me/scope"),
  ]);
  return (
    <Shell route="t/deptstaff" me={me.ok ? me.data : null}>
      {view.ok ? <StaffList data={view.data} scope={scope.ok ? scope.data : null} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
