import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { ExaminerRow, Rubric } from "@/lib/examiners";
import { ProjectDetail, type ProjectFull } from "./ProjectDetail";

export const dynamic = "force-dynamic";

/** one project on the desk: the record, the documents released, the examiners it is with, the history */
export default async function ProjectPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const [me, p, examiners, rubrics] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<ProjectFull>(`/api/v1/examiners/projects/${encodeURIComponent(id)}`),
    api<ExaminerRow[]>("/api/v1/examiners/list?status=ACTIVE"),
    api<Rubric[]>("/api/v1/examiners/rubrics"),
  ]);
  return (
    <Shell route="t/extassignments" me={me.ok ? me.data : null}>
      {p.ok ? <ProjectDetail p={p.data} examiners={examiners.ok ? examiners.data : []} rubrics={rubrics.ok ? rubrics.data.filter((r) => r.active) : []} /> : <ProblemNotice problem={p.problem} />}
    </Shell>
  );
}
