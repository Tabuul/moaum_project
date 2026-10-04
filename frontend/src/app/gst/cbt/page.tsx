import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { CbtExams } from "@/components/cbt/CbtExams";
import type { CbtExamList } from "@/lib/cbt";

export const dynamic = "force-dynamic";

/** t/gstcbt — the GST office's CBT examinations (V322) */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const q = await searchParams;
  const p = new URLSearchParams({ office: "GST" });
  if (typeof q.session === "string") p.set("session", q.session);
  if (typeof q.semester === "string" && q.semester) p.set("semester", q.semester);
  const [me, data] = await Promise.all([api<Me>("/api/v1/iam/me"), api<CbtExamList>(`/api/v1/cbt/exams?${p.toString()}`)]);
  const acting = me.ok ? me.data.activeOffice ?? "" : "";
  return (
    <Shell route="t/gstcbt" me={me.ok ? me.data : null}>
      {data.ok ? <CbtExams data={data.data} base="/gst" office="GST" canManage={["gst", "super"].includes(acting)} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
