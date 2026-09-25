import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { ExaminerRow, ProjectRow, Rubric } from "@/lib/examiners";
import { Projects } from "./Projects";

export const dynamic = "force-dynamic";

/** t/extassignments — the projects registered for external examination, and a new one registered; assignment starts here */
export default async function ProjectsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const session = typeof p.session === "string" ? p.session : "";
  const assign = typeof p.assign === "string" ? p.assign : "";
  const [me, list, sessions, examiners, rubrics] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<ProjectRow[]>(`/api/v1/examiners/projects${session ? `?session=${encodeURIComponent(session)}` : ""}`),
    api<{ name: string; state?: string }[]>("/api/v1/ref/sessions"),
    api<ExaminerRow[]>("/api/v1/examiners/list?status=ACTIVE"),
    api<Rubric[]>("/api/v1/examiners/rubrics"),
  ]);
  const names = sessions.ok ? sessions.data.map((s) => s.name) : [];
  const current = sessions.ok ? sessions.data.find((s) => s.state === "CURRENT")?.name ?? names[0] ?? "" : "";
  return (
    <Shell route="t/extassignments" me={me.ok ? me.data : null}>
      {!list.ok ? <ProblemNotice problem={list.problem} /> : (
        <Projects rows={list.data} session={session} current={current} sessions={names} examiners={examiners.ok ? examiners.data : []} rubrics={rubrics.ok ? rubrics.data.filter((r) => r.active) : []} assignFor={assign} />
      )}
    </Shell>
  );
}
