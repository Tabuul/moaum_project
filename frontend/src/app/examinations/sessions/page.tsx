import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import type { ExamSession, Monitor } from "@/lib/results";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { ExamSessions } from "./ExamSessions";

export const dynamic = "force-dynamic";

export default async function ExamSessionsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const { scope, sessions } = await loadScope(params);
  const [me, list] = await Promise.all([api<Me>("/api/v1/iam/me"), api<ExamSession[]>("/api/v1/results/exam-sessions")]);
  const all = list.ok ? list.data : [];
  const open = all.filter((e) => e.state === "OPEN");
  const chosen = typeof params.exam === "string" ? all.find((e) => e.id === params.exam) : open[0];
  const monitor = chosen ? await api<Monitor>(`/api/v1/results/exam-sessions/${chosen.id}/monitor`) : null;
  return (
    <Shell route="t/examsession" me={me.ok ? me.data : null}>
      {list.ok ? (
        <ExamSessions sessions={sessions} scope={scope} list={list.data} monitor={monitor && monitor.ok ? monitor.data : null} />
      ) : (
        <ProblemNotice problem={list.problem} />
      )}
    </Shell>
  );
}
