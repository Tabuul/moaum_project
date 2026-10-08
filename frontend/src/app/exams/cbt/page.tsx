import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { CbtExams } from "@/components/cbt/CbtExams";
import type { CbtExamList } from "@/lib/cbt";

export const dynamic = "force-dynamic";

/** t/unicbt — the University's own CBT examinations (V364): the CBT-enabled courses within the examinations officer's scope, on the one engine */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const q = await searchParams;
  const p = new URLSearchParams({ office: "EXAMS" });
  if (typeof q.session === "string") p.set("session", q.session);
  if (typeof q.semester === "string" && q.semester) p.set("semester", q.semester);
  if (q.archived === "true") p.set("archived", "true");
  const [me, data] = await Promise.all([api<Me>("/api/v1/iam/me"), api<CbtExamList>(`/api/v1/cbt/exams?${p.toString()}`)]);
  const acting = me.ok ? me.data.activeOffice ?? "" : "";
  return (
    <Shell route="t/unicbt" me={me.ok ? me.data : null}>
      {data.ok ? <CbtExams data={data.data} base="/exams" office="EXAMS" canManage={["exams", "facultyexams", "records", "super"].includes(acting)} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
