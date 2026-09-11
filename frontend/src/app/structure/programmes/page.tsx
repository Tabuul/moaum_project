import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Programmes, type Programme, type FacultyOption } from "./Programmes";

export const dynamic = "force-dynamic";

/** t/programmeupload — create or upload programmes (V091). */
export default async function ProgrammesPage() {
  const [me, progs, facs] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Programme[]>("/api/v1/catalogue/programmes"),
    api<FacultyOption[]>("/api/v1/catalogue/faculties"),
  ]);
  return (
    <Shell route="t/programmeupload" me={me.ok ? me.data : null}>
      {progs.ok ? (
        <Programmes programmes={progs.data} faculties={facs.ok ? facs.data : []} actingOffice={me.ok ? me.data.activeOffice : null} />
      ) : <ProblemNotice problem={progs.problem} />}
    </Shell>
  );
}
