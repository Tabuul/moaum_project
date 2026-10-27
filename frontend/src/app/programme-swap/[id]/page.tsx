import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Faculty } from "@/lib/programme-swap";
import { SwapStudent, type StudentView } from "./SwapStudent";

export const dynamic = "force-dynamic";

/** /programme-swap/{student} — one student's programme swap (V578): the record as it stands, the placement to move to, the check, the preview, the swap prepared;
 *  ?restore=1 (V669) opens on restoring a transfer approved on the old portal (from the transfer desk and the student edit page) */
export default async function SwapStudentPage({ params, searchParams }: { params: Promise<{ id: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const { id } = await params;
  const sp = await searchParams;
  const [me, student, structure] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<StudentView>(`/api/v1/programme-swaps/students/${encodeURIComponent(id)}`),
    api<{ faculties: Faculty[] }>("/api/v1/programme-swaps/structure"),
  ]);
  return (
    <Shell route="t/programmeswap" me={me.ok ? me.data : null}>
      {student.ok ? <SwapStudent view={student.data} faculties={structure.ok ? structure.data.faculties : []} actingOffice={me.ok ? me.data.activeOffice ?? null : null}
        restoreInitially={sp.restore === "1"} />
        : <ProblemNotice problem={student.problem} />}
    </Shell>
  );
}
