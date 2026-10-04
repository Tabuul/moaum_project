import { api } from "@/lib/api";
import { loadScope, scopeParams } from "@/lib/scope-data";
import type { PipelineView } from "@/lib/results";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Pipeline } from "./Pipeline";

export const dynamic = "force-dynamic";

const STAGES = new Set(["ENTRY", "VERIFICATION", "DEPT_BOARD", "FACULTY_SCRUTINY", "FACULTY_COMPILATION", "FACULTY_BOARD", "RECORDS", "SENATE", "PUBLISHED"]);

/** t/pipeline — the result pipeline monitor (V318): the nine stages with their real counts in scope, the coverage counted
 *  from the rolls, the courses whose results are not in, what needs a desk, the timeline, and every programme and level's
 *  live broadsheet. The office's bound applies: a Programme Examinations Officer reads their programme, a Head of
 *  Department their department, a faculty office its faculty, Exams & Records the University. */
export default async function PipelinePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const { scope, structure, sessions, ceiling } = await loadScope(params);
  const stage = typeof params.stage === "string" && STAGES.has(params.stage) ? params.stage : "";
  const [me, view] = await Promise.all([api<Me>("/api/v1/iam/me"), api<PipelineView>(`/api/v1/results/pipeline?${scopeParams(scope)}`)]);
  return (
    <Shell route="t/pipeline" me={me.ok ? me.data : null}>
      {view.ok
        ? <Pipeline scope={scope} structure={structure} sessions={sessions} ceiling={ceiling} view={view.data} stage={stage} office={me.ok ? me.data.activeOffice : null} />
        : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
