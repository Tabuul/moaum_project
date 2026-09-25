import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { AllocationRow } from "@/app/dashboards/AllocationHistory";
import { CourseHistory } from "./CourseHistory";

export const dynamic = "force-dynamic";

/** t/coursehistory — every course ever allocated to the lecturer, by session, with the class each one had */
export default async function CourseHistoryPage() {
  const [me, history, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<AllocationRow[]>("/api/v1/allocation/history?scope=me"),
    api<{ name: string; state: string }[]>("/api/v1/ref/sessions"),
  ]);
  const current = sessions.ok ? sessions.data.find((s) => s.state === "CURRENT")?.name ?? null : null;
  return (
    <Shell route="t/coursehistory" me={me.ok ? me.data : null}>
      {history.ok ? <CourseHistory rows={history.data} current={current} /> : <ProblemNotice problem={history.problem} />}
    </Shell>
  );
}
