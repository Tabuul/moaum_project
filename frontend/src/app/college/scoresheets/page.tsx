import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { ScoreSheets } from "./ScoreSheets";
import type { Candidates, ExamCatalogue } from "../examinations/Examinations";

export const dynamic = "force-dynamic";

/** t/collegesheets — the level's score sheet (V250): downloaded for the cohort, filled, uploaded; the marked sheet back down */
export default async function ScoreSheetsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const [me, catalogue, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<ExamCatalogue>("/api/v1/college/exams"),
    api<{ name: string; state?: string }[]>("/api/v1/ref/sessions"),
  ]);
  const coordinator = me.ok && me.data.activeOffice === "mbbscoordinator";
  const mine = coordinator ? await api<{ level: number }>("/api/v1/college/coordinator") : null;
  const sessionList = sessions.ok ? sessions.data : [];
  const current = sessionList.find((s) => s.state === "CURRENT")?.name ?? sessionList[0]?.name ?? "";
  const session = typeof p.session === "string" && p.session ? p.session : current;
  const level = mine && mine.ok ? mine.data.level : typeof p.level === "string" && p.level ? Number(p.level) : 200;
  const exam = catalogue.ok ? catalogue.data.exams.find((e) => e.level === level) : null;
  const candidates = session && exam ? await api<Candidates>(`/api/v1/college/exams/${encodeURIComponent(exam.code)}/candidates?session=${encodeURIComponent(session)}`) : null;
  return (
    <Shell route="t/collegesheets" me={me.ok ? me.data : null}>
      {!catalogue.ok ? <ProblemNotice problem={catalogue.problem} /> : mine && !mine.ok ? <ProblemNotice problem={mine.problem} /> : (
        <ScoreSheets sessions={sessionList.map((s) => s.name)} session={session} level={level} exams={catalogue.data.exams} coordinator={coordinator}
          data={candidates && candidates.ok ? candidates.data : null} problem={candidates && !candidates.ok ? candidates.problem : null} />
      )}
    </Shell>
  );
}
