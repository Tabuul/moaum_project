import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import type { Desk, ProcessDetail, Workflows } from "@/lib/clearance";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { ClearanceDesk } from "./ClearanceDesk";

export const dynamic = "force-dynamic";

/** t/clearance — student clearance (V415): each office's desk on its own stage of fresh or final clearance, held on the server
 *  to the office's units and its faculty or department; the Registry sees every office. */
export default async function ClearancePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const s = (k: string) => (typeof params[k] === "string" ? (params[k] as string).trim() : "");
  const [me, wf, scoped] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Workflows>("/api/v1/clearance/workflows"), loadScope(params)]);
  if (!wf.ok) return <Shell route="t/clearance" me={me.ok ? me.data : null}><ProblemNotice problem={wf.problem} /></Shell>;
  const active = wf.data.workflows.filter((w) => w.active);
  // asked for by name, else the first in use with a stage of the office's own (the Alumni Office's is final clearance's)
  const ownStage = active.find((w) => w.stages.some((st) => st.active && wf.data.myUnits.includes(st.unit)));
  const workflow = (active.find((w) => w.code === s("wf").toUpperCase()) ?? (wf.data.myUnits.length && !["registrar", "dregistrar", "academic"].includes(me.ok ? me.data.activeOffice ?? "" : "") ? ownStage : undefined)
    ?? active[0] ?? wf.data.workflows[0]).code;
  const session = scoped.scope.session || wf.data.currentSession || wf.data.sessions[0] || "";
  const page = Math.max(0, Number(s("page")) || 0);
  const q = new URLSearchParams({ workflow, session, page: String(page), size: "50" });
  for (const [k, v] of [["unit", s("unit")], ["status", s("status")], ["fac", scoped.scope.fac], ["dept", scoped.scope.dept], ["prog", scoped.scope.prog],
    ["level", scoped.scope.level], ["sex", s("sex")], ["entry", s("entry")], ["q", s("q")]] as [string, string][]) if (v) q.set(k, v);
  const process = /^[0-9a-f-]{36}$/.test(s("process")) ? s("process") : "";
  const [desk, detail] = await Promise.all([
    session ? api<Desk>(`/api/v1/clearance/desk?${q.toString()}`) : null,
    process ? api<ProcessDetail>(`/api/v1/clearance/processes/${process}`) : null,
  ]);
  return (
    <Shell route="t/clearance" me={me.ok ? me.data : null}>
      {desk && !desk.ok ? <ProblemNotice problem={desk.problem} /> : null}
      {detail && !detail.ok ? <ProblemNotice problem={detail.problem} /> : null}
      <ClearanceDesk workflows={wf.data} workflow={workflow} session={session} desk={desk && desk.ok ? desk.data : null}
        detail={detail && detail.ok ? detail.data : null} scope={{ ...scoped.scope, session }} structure={scoped.structure} sessions={scoped.sessions}
        ceiling={scoped.ceiling} params={{ unit: s("unit"), status: s("status"), sex: s("sex"), entry: s("entry"), q: s("q"), page }}
        actingOffice={me.ok ? me.data.activeOffice : null} />
    </Shell>
  );
}
