import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { ExaminerRow } from "@/lib/examiners";
import { ExaminersDesk, type Dashboard } from "./ExaminersDesk";

export const dynamic = "force-dynamic";

/** t/extexaminers — the register of external examiners, the figures, and a new examiner invited */
export default async function ExaminersPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const session = typeof p.session === "string" ? p.session : "";
  const [me, dash, list, structure] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Dashboard>(`/api/v1/examiners/dashboard${session ? `?session=${encodeURIComponent(session)}` : ""}`),
    api<ExaminerRow[]>("/api/v1/examiners/list"),
    api<{ faculties: { code: string; name: string; departments: { code: string; name: string }[] }[] }>("/api/v1/ref/structure"),
  ]);
  return (
    <Shell route="t/extexaminers" me={me.ok ? me.data : null}>
      {!dash.ok ? <ProblemNotice problem={dash.problem} /> : (
        <ExaminersDesk dash={dash.data} session={session} examiners={list.ok ? list.data : []} faculties={structure.ok ? structure.data.faculties : []} />
      )}
    </Shell>
  );
}
