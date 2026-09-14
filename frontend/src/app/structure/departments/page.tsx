import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Departments, type Department } from "./Departments";

export const dynamic = "force-dynamic";

/** t/departmentupload — create or upload departments (V118). */
export default async function DepartmentsPage() {
  const [me, list] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Department[]>("/api/v1/catalogue/departments"),
  ]);
  return (
    <Shell route="t/departmentupload" me={me.ok ? me.data : null}>
      {list.ok ? <Departments departments={list.data} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
