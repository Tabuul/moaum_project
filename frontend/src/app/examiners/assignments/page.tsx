import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { AssignmentRow, ExaminerRow } from "@/lib/examiners";
import { Assignments } from "./Assignments";

export const dynamic = "force-dynamic";

/** t/extassessments — every live assignment: reassigned, extended, withdrawn; the assessments opened */
export default async function AssignmentsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const qs = new URLSearchParams();
  for (const k of ["session", "status", "examiner", "dept", "q"]) if (s(k)) qs.set(k, s(k));
  if (s("overdue")) qs.set("overdue", "true");
  const [me, list, examiners, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<AssignmentRow[]>(`/api/v1/examiners/assignments?${qs.toString()}`),
    api<ExaminerRow[]>("/api/v1/examiners/list"),
    api<{ name: string }[]>("/api/v1/ref/sessions"),
  ]);
  return (
    <Shell route="t/extassessments" me={me.ok ? me.data : null}>
      {!list.ok ? <ProblemNotice problem={list.problem} /> : (
        <Assignments rows={list.data} examiners={examiners.ok ? examiners.data : []} sessions={sessions.ok ? sessions.data.map((x) => x.name) : []}
          filters={{ session: s("session"), status: s("status"), examiner: s("examiner"), dept: s("dept"), q: s("q"), overdue: !!s("overdue") }} />
      )}
    </Shell>
  );
}
