import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { StudentsRegister, type View } from "./StudentsRegister";

export const dynamic = "force-dynamic";

const EDITORS = ["pgschool", "pgsecretary", "super"];

/** PG register (V211): every postgraduate with CGPA, standing and research stage. */
export default async function Page() {
  const [me, view] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<View>("/api/v1/pg/students"),
  ]);
  const office = me.ok ? me.data.activeOffice : null;
  return (
    <Shell route="t/pgstudents" me={me.ok ? me.data : null}>
      <StudentsRegister view={view.ok ? view.data : null} problem={view.ok ? null : view.problem} mayEdit={EDITORS.includes(office ?? "")} />
    </Shell>
  );
}
