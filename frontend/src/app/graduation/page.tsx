import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import type { GraduationView } from "@/lib/credentials";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Graduation } from "./Graduation";

export const dynamic = "force-dynamic";

export default async function GraduationPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const { scope, structure, sessions } = await loadScope(params);
  const q = new URLSearchParams();
  if (scope.fac) q.set("fac", scope.fac);
  if (scope.dept) q.set("dept", scope.dept);
  if (scope.prog) q.set("prog", scope.prog);
  const [me, view] = await Promise.all([api<Me>("/api/v1/iam/me"), api<GraduationView>(`/api/v1/graduation/sessions/${scope.session}?${q.toString()}`)]);
  return (
    <Shell route="t/graduation" me={me.ok ? me.data : null}>
      {view.ok ? <Graduation scope={scope} structure={structure} sessions={sessions} view={view.data} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
