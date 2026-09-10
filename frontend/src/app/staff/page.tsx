import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Establishment, type StaffRow } from "./Establishment";

export const dynamic = "force-dynamic";

/** t/staff — the establishment: who is on the roll, on what grade. */
export default async function StaffPage() {
  const [me, staff] = await Promise.all([api<Me>("/api/v1/iam/me"), api<StaffRow[]>("/api/v1/payroll/staff")]);
  return (
    <Shell route="t/staff" me={me.ok ? me.data : null}>
      {staff.ok ? <Establishment rows={staff.data} /> : <ProblemNotice problem={staff.problem} />}
    </Shell>
  );
}
