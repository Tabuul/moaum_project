import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import type { Management } from "@/lib/graduation-batch";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { GraduationManage } from "./GraduationManage";
import { OutsideMaximum } from "./OutsideMaximum";
import type { Candidate, RecBatch, RecFigures, RecSetting } from "@/lib/graduation-reconciliation";

export const dynamic = "force-dynamic";

/** V602: Graduation Management — the figures, graduation batches on the Senate's minute, the graduated, the reports; V638: the students
 *  outside the maximum academic period, reconciled to graduated */
export default async function GraduationManagePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const { scope, structure, sessions } = await loadScope(params);
  const q = new URLSearchParams({ session: scope.session });
  if (scope.fac) q.set("fac", scope.fac);
  if (scope.dept) q.set("dept", scope.dept);
  if (scope.prog) q.set("prog", scope.prog);
  const r = new URLSearchParams();
  if (scope.fac) r.set("fac", scope.fac);
  if (scope.dept) r.set("dept", scope.dept);
  if (scope.prog) r.set("prog", scope.prog);
  const [me, view, figures, setting, batches] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Management>(`/api/v1/graduation/management?${q.toString()}`),
    api<RecFigures>(`/api/v1/graduation/reconciliation/figures?${r.toString()}`), api<RecSetting>("/api/v1/graduation/reconciliation/setting"),
    api<RecBatch[]>(`/api/v1/graduation/reconciliation/batches?${r.toString()}`)]);
  const gr = typeof params.gr === "string" && ["ALL", "HIGH", "MEDIUM", "LOW"].includes(params.gr) ? params.gr : null;
  // a card clicked: the list's first page read here, the rest on the screen
  const l = new URLSearchParams(r);
  l.set("page", "1");
  l.set("size", "50");
  if (gr && gr !== "ALL") l.set("confidence", gr);
  const first = gr ? await api<{ rows: Candidate[]; total: number }>(`/api/v1/graduation/reconciliation/candidates?${l.toString()}`) : null;
  const office = me.ok ? me.data.activeOffice : null;
  const recProblem = !figures.ok ? figures.problem : !setting.ok ? setting.problem : null;
  return (
    <Shell route="t/graduationmanage" me={me.ok ? me.data : null}>
      {view.ok ? (
        <GraduationManage scope={scope} structure={structure} sessions={sessions} view={view.data} actingOffice={office}>
          {figures.ok && setting.ok ? <OutsideMaximum key={gr ?? "none"} scope={scope} figures={figures.data} setting={setting.data} batches={batches.ok ? batches.data : []} actingOffice={office}
              focus={gr} initial={first && first.ok ? first.data : gr ? { rows: [], total: 0 } : null} />
            : recProblem ? <ProblemNotice problem={recProblem} /> : null}
        </GraduationManage>
      ) : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
