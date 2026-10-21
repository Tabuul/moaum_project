import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import type { Management } from "@/lib/graduation-batch";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { GraduationManage } from "./GraduationManage";

export const dynamic = "force-dynamic";

/** V602: Graduation Management — the figures, graduation batches on the Senate's minute, the graduated, the reports */
export default async function GraduationManagePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const { scope, structure, sessions } = await loadScope(params);
  const q = new URLSearchParams({ session: scope.session });
  if (scope.fac) q.set("fac", scope.fac);
  if (scope.dept) q.set("dept", scope.dept);
  if (scope.prog) q.set("prog", scope.prog);
  const [me, view] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Management>(`/api/v1/graduation/management?${q.toString()}`)]);
  return (
    <Shell route="t/graduationmanage" me={me.ok ? me.data : null}>
      {view.ok ? <GraduationManage scope={scope} structure={structure} sessions={sessions} view={view.data} actingOffice={me.ok ? me.data.activeOffice : null} />
        : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
