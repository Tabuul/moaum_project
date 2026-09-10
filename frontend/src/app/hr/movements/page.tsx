import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Movements, type MovementRow, type Grade } from "./Movements";

export const dynamic = "force-dynamic";

/** t/movement — staff movements: request, approve, and issue the instrument that makes it real. */
export default async function MovementsPage() {
  const [me, data] = await Promise.all([api<Me>("/api/v1/iam/me"), api<{ rows: MovementRow[]; grades: Grade[] }>("/api/v1/hr/movements")]);
  return (
    <Shell route="t/movement" me={me.ok ? me.data : null}>
      {data.ok ? <Movements rows={data.data.rows} grades={data.data.grades} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
