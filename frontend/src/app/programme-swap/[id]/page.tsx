import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Faculty } from "@/lib/programme-swap";
import { SwapStudent, type StudentView } from "./SwapStudent";

export const dynamic = "force-dynamic";

/** /programme-swap/{student} — one student's programme swap (V578): the record as it stands, the placement to move to, the check, the preview, the swap prepared */
export default async function SwapStudentPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const [me, student, structure] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<StudentView>(`/api/v1/programme-swaps/students/${encodeURIComponent(id)}`),
    api<{ faculties: Faculty[] }>("/api/v1/programme-swaps/structure"),
  ]);
  return (
    <Shell route="t/programmeswap" me={me.ok ? me.data : null}>
      {student.ok ? <SwapStudent view={student.data} faculties={structure.ok ? structure.data.faculties : []} actingOffice={me.ok ? me.data.activeOffice ?? null : null} />
        : <ProblemNotice problem={student.problem} />}
    </Shell>
  );
}
