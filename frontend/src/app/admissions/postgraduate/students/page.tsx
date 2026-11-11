import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { StudentsRegister, type View } from "./StudentsRegister";

export const dynamic = "force-dynamic";

const EDITORS = ["pgschool", "pgsecretary", "super"];
/** V721: who opens a postgraduate student's edit page from the register (V715: the School and ICT; V642: the Academic Office and the Registry) */
const RECORD_EDITORS = ["pgschool", "pgsecretary", "ict", "super", "academic", "registrar", "dregistrar"];

/** PG register (V211): every postgraduate with CGPA, standing and research stage. */
export default async function Page() {
  const [me, view] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<View>("/api/v1/pg/students"),
  ]);
  const office = me.ok ? me.data.activeOffice : null;
  return (
    <Shell route="t/pgstudents" me={me.ok ? me.data : null}>
      <StudentsRegister view={view.ok ? view.data : null} problem={view.ok ? null : view.problem} mayEdit={EDITORS.includes(office ?? "")} mayOpenEdit={RECORD_EDITORS.includes(office ?? "")} />
    </Shell>
  );
}
