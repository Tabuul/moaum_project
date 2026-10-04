import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { CbtExam } from "@/components/cbt/CbtExam";
import type { CbtExam as Exam } from "@/lib/cbt";

export const dynamic = "force-dynamic";

/** t/epscbt — one EPS CBT examination (V322) on the shared engine */
export default async function Page({ params, searchParams }: { params: Promise<{ id: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const { id } = await params;
  const q = await searchParams;
  const tab = typeof q.tab === "string" && ["setup", "paper", "candidates", "results"].includes(q.tab) ? (q.tab as "setup" | "paper" | "candidates" | "results") : undefined;
  const [me, exam] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Exam>(`/api/v1/cbt/exams/${encodeURIComponent(id)}`)]);
  const acting = me.ok ? me.data.activeOffice ?? "" : "";
  return (
    <Shell route="t/epscbt" me={me.ok ? me.data : null} sub={exam.ok ? exam.data.reference : undefined}>
      {exam.ok ? <CbtExam exam={exam.data} base="/eps" canManage={["eps", "super"].includes(acting)} stronger={["super", "registrar"].includes(acting)} initialTab={tab} /> : <ProblemNotice problem={exam.problem} />}
    </Shell>
  );
}
