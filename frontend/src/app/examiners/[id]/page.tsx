import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { ExaminerDetail, type ExaminerFull } from "./ExaminerDetail";

export const dynamic = "force-dynamic";

/** one external examiner: the record, the invitation, the appointments, the projects with them, the history */
export default async function ExaminerPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const [me, e, structure, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<ExaminerFull>(`/api/v1/examiners/${encodeURIComponent(id)}`),
    api<{ faculties: { code: string; name: string; departments: { code: string; name: string; programmes?: { code: string; name: string }[] }[] }[] }>("/api/v1/ref/structure"),
    api<{ name: string; state?: string }[]>("/api/v1/ref/sessions"),
  ]);
  return (
    <Shell route="t/extexaminers" me={me.ok ? me.data : null}>
      {e.ok ? <ExaminerDetail e={e.data} faculties={structure.ok ? structure.data.faculties : []} sessions={sessions.ok ? sessions.data.map((s) => s.name) : []} /> : <ProblemNotice problem={e.problem} />}
    </Shell>
  );
}
