import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "../load";

export const dynamic = "force-dynamic";
import type { Docket } from "@/lib/student-portal";
import { semesterName } from "@/lib/student-portal";
import { Exams } from "../Screens5";

/** s/exams — the papers the approved registration carries, when the scheme releases them */
export default async function Page() {
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/exams" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  const d = await api<Docket>("/api/v1/me/docket");
  // a live subtitle for the header — the exam sitting the docket actually shows, not a fixed month
  let sub: string | undefined;
  if (d.ok) {
    const sits = d.data.examSessions;
    const shown = sits.find((x) => x.papers.length) ?? sits[0];
    sub = shown
      ? `${shown.session} · ${semesterName(shown.semester)} semester · ${shown.kind === "MAIN" ? "main" : shown.kind.toLowerCase()} examinations`
      : `${d.data.session} · no open sitting`;
  }
  return (
    <Shell route="s/exams" me={loaded.me} sub={sub}>
      {d.ok ? <Exams d={d.data} s={loaded.student} /> : <ProblemNotice problem={d.problem} />}
    </Shell>
  );
}
