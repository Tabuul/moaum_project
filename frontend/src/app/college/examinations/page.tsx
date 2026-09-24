import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Examinations, type Candidates, type ExamCatalogue, type Reconciliation } from "./Examinations";

export const dynamic = "force-dynamic";

/** t/collegeexams — the Professional examination desk: each candidate's subjects by attempt, the pass judged
 *  by the rule, the progression decision, and the reconciliation the crossing to Senate needs */
export default async function ExaminationsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const [me, catalogue, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<ExamCatalogue>("/api/v1/college/exams"),
    api<{ name: string; state?: string }[]>("/api/v1/ref/sessions"),
  ]);
  const sessionList = sessions.ok ? sessions.data : [];
  const current = sessionList.find((s) => s.state === "CURRENT")?.name ?? sessionList[0]?.name ?? "";
  const session = typeof p.session === "string" && p.session ? p.session : current;
  // the MBBS Coordinator's desk opens at the level they hold, and stays there
  const mine = me.ok && me.data.activeOffice === "mbbscoordinator" ? await api<{ level: number }>("/api/v1/college/coordinator") : null;
  const myCode = mine && mine.ok && catalogue.ok ? catalogue.data.exams.find((e) => e.level === mine.data.level)?.code : undefined;
  const code = myCode ?? (typeof p.exam === "string" && p.exam ? p.exam : "PE1");
  const [candidates, reconciliation] = await Promise.all([
    session ? api<Candidates>(`/api/v1/college/exams/${encodeURIComponent(code)}/candidates?session=${encodeURIComponent(session)}`) : null,
    session ? api<Reconciliation>(`/api/v1/college/exams/${encodeURIComponent(code)}/reconciliation?session=${encodeURIComponent(session)}`) : null,
  ]);
  return (
    <Shell route="t/collegeexams" me={me.ok ? me.data : null}>
      {!catalogue.ok ? <ProblemNotice problem={catalogue.problem} /> : (
        <Examinations catalogue={catalogue.data} sessions={sessionList.map((s) => s.name)} session={session} code={code}
          data={candidates && candidates.ok ? candidates.data : null} reconciliation={reconciliation && reconciliation.ok ? reconciliation.data : null}
          problem={candidates && !candidates.ok ? candidates.problem : null} />
      )}
    </Shell>
  );
}
