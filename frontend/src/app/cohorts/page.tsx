import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { CohortList, CohortSettings, CohortSummary } from "@/lib/cohorts";
import { Cohorts, type Filters } from "./Cohorts";

export const dynamic = "force-dynamic";

const TABS = ["overview", "current", "graduated", "spillover", "review", "all", "quality", "settings"];
/** what each list tab asks the server for */
const CLASS_OF: Record<string, string> = { current: "ACTIVE", graduated: "GRADUATED", spillover: "SPILLOVER,SPILLOVER_LIMIT_REACHED", review: "REVIEW", all: "" };

/** t/cohorts — where every student stands (V331): the figures, the current, graduated and spillover lists, the reconciliation review, the data
 *  quality report and the policy; every list filtered, paged and sorted on the server within the office's scope */
export default async function CohortsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const tab = TABS.includes(s("tab")) ? s("tab") : "overview";
  const filters: Filters = { q: s("q"), fac: s("fac"), dept: s("dept"), prog: s("prog"), cohort: s("cohort"), entry: s("entry"), jamb: s("jamb"), level: s("level"), duration: s("duration"), status: s("status"), grad: s("grad"), spill: s("spill"), conf: s("conf"), issue: s("issue"), sex: s("sex"), entryMode: s("entryMode"), sort: s("sort") || "name", dir: s("dir") || "asc", size: s("size") || "50" };
  const qs = new URLSearchParams();
  for (const [k, v] of Object.entries(filters)) if (v) qs.set(k, v);
  const listQs = new URLSearchParams(qs);
  if (CLASS_OF[tab] !== undefined && CLASS_OF[tab]) listQs.set("classification", CLASS_OF[tab]);
  listQs.set("page", s("page") || "1");
  const isList = CLASS_OF[tab] !== undefined;
  const [me, summary, list, settings, structure] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<CohortSummary>(`/api/v1/cohorts/summary?${qs.toString()}`),
    isList ? api<CohortList>(`/api/v1/cohorts/students?${listQs.toString()}`) : Promise.resolve(null),
    tab === "settings" || tab === "overview" ? api<CohortSettings>("/api/v1/cohorts/settings") : Promise.resolve(null),
    api<{ faculties: { code: string; name: string; departments: { code: string; name: string }[] }[] }>("/api/v1/ref/structure"),
  ]);
  const office = me.ok ? me.data.activeOffice : null;
  return (
    <Shell route="t/cohorts" me={me.ok ? me.data : null}>
      {!summary.ok ? <ProblemNotice problem={summary.problem} /> : (
        <Cohorts tab={tab} summary={summary.data} list={list && list.ok ? list.data : null} listProblem={list && !list.ok ? list.problem : null}
          settings={settings && settings.ok ? settings.data : null}
          structure={structure.ok ? structure.data.faculties : []} filters={filters} page={Number(s("page") || 1)}
          canDecide={["academic", "registrar", "dregistrar", "records"].includes(office ?? "")} canSet={["registrar", "dregistrar", "academic", "super"].includes(office ?? "")}
          generatedBy={me.ok ? me.data.name ?? null : null} />
      )}
    </Shell>
  );
}
