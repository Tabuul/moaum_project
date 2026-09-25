import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { ExaminerRow } from "@/lib/examiners";
import { Reports, type Report } from "./Reports";

export const dynamic = "force-dynamic";

/** t/extreports — the reports: examiners, assessments, workload, department, programme, pending, overdue, submitted; filtered; downloadable */
export default async function ExaminerReportsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const kind = s("kind") || "assessments";
  const qs = new URLSearchParams({ kind });
  for (const k of ["session", "faculty", "dept", "programme", "examiner", "status", "from", "to"]) if (s(k)) qs.set(k, s(k));
  const [me, report, examiners, sessions, structure] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Report>(`/api/v1/examiners/reports?${qs.toString()}`),
    api<ExaminerRow[]>("/api/v1/examiners/list"),
    api<{ name: string }[]>("/api/v1/ref/sessions"),
    api<{ faculties: { code: string; name: string; departments: { code: string; name: string; programmes?: { code: string; name: string }[] }[] }[] }>("/api/v1/ref/structure"),
  ]);
  return (
    <Shell route="t/extreports" me={me.ok ? me.data : null}>
      {!report.ok ? <ProblemNotice problem={report.problem} /> : (
        <Reports report={report.data} examiners={examiners.ok ? examiners.data : []} sessions={sessions.ok ? sessions.data.map((x) => x.name) : []} faculties={structure.ok ? structure.data.faculties : []}
          filters={{ kind, session: s("session"), faculty: s("faculty"), dept: s("dept"), programme: s("programme"), examiner: s("examiner"), status: s("status"), from: s("from"), to: s("to") }} />
      )}
    </Shell>
  );
}
