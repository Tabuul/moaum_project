import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { CbtExams } from "@/components/cbt/CbtExams";
import type { CbtExamList } from "@/lib/cbt";

export const dynamic = "force-dynamic";

/** t/epscbt — the EPS office's CBT examinations (V322), on the same engine as GST */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const q = await searchParams;
  const p = new URLSearchParams({ office: "EPS" });
  if (typeof q.session === "string") p.set("session", q.session);
  if (typeof q.semester === "string" && q.semester) p.set("semester", q.semester);
  const [me, data] = await Promise.all([api<Me>("/api/v1/iam/me"), api<CbtExamList>(`/api/v1/cbt/exams?${p.toString()}`)]);
  const acting = me.ok ? me.data.activeOffice ?? "" : "";
  return (
    <Shell route="t/epscbt" me={me.ok ? me.data : null}>
      {data.ok ? <CbtExams data={data.data} base="/eps" office="EPS" canManage={["eps", "super"].includes(acting)} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
