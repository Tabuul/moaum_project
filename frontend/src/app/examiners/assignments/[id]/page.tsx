import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { AssignmentDetail, type AssignmentFull } from "./AssignmentDetail";

export const dynamic = "force-dynamic";

/** one assignment on the desk: the assessment in full, locked or reopened; the documents; the history */
export default async function AssignmentPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const [me, a] = await Promise.all([api<Me>("/api/v1/iam/me"), api<AssignmentFull>(`/api/v1/examiners/assignments/${encodeURIComponent(id)}`)]);
  return (
    <Shell route="t/extassessments" me={me.ok ? me.data : null}>
      {a.ok ? <AssignmentDetail a={a.data} /> : <ProblemNotice problem={a.problem} />}
    </Shell>
  );
}
