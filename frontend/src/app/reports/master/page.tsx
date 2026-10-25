import { Suspense } from "react";
import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Note } from "@/components/proto/ui";
import { masterQuery, readFilters, type HistoryRow, type MasterOptions, type MasterSummary, type Page, type StudentRow } from "@/lib/master-report";
import type { Scope } from "@/lib/scope";
import type { Ceiling, ScopeStructure } from "@/components/proto/ScopeBar";
import { MasterReport } from "./MasterReport";

export const dynamic = "force-dynamic";

/** t/masterreport — V650: the Master University Report. The bar and the filters at once; the figures (one pass over every student
 *  of the scope, a few seconds over the whole University) stream in when the server has them. ?list=1 opens the students behind a
 *  figure, the figure's own filter in the address. */
export default async function MasterReportPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const { scope, structure, sessions, ceiling } = await loadScope(params);
  const [me, options] = await Promise.all([api<Me>("/api/v1/iam/me"), api<MasterOptions>("/api/v1/reports/master/options")]);
  if (!options.ok) {
    return <Shell route="t/masterreport" me={me.ok ? me.data : null}><ProblemNotice problem={options.problem} /></Shell>;
  }
  const sc: Scope = { ...scope, session: scope.session || options.data.period.session, sem: scope.sem && scope.sem !== "0" ? scope.sem : String(options.data.period.semester) };
  const filters = readFilters(params);
  const list = params.list === "1";
  const page = typeof params.page === "string" && /^\d{1,4}$/.test(params.page) ? Number(params.page) : 1;
  const actor = me.ok ? me.data.name ?? null : null;
  return (
    <Shell route="t/masterreport" me={me.ok ? me.data : null}>
      <Suspense fallback={<Note kind="info" title="Preparing the report…">Reading every student of the scope once — the classification, school fees, registration, GST, EPS, the examination card and the permit — and the period&apos;s transactions. Over the whole University this takes a few seconds.</Note>}>
        <Figures scope={sc} structure={structure} sessions={sessions} ceiling={ceiling} options={options.data} filters={filters} list={list} page={page} actor={actor} />
      </Suspense>
    </Shell>
  );
}

async function Figures({ scope, structure, sessions, ceiling, options, filters, list, page, actor }: {
  scope: Scope; structure: ScopeStructure; sessions: string[]; ceiling: Ceiling; options: MasterOptions; filters: ReturnType<typeof readFilters>;
  list: boolean; page: number; actor: string | null;
}) {
  const q = masterQuery(scope, filters);
  const [summary, students, history] = await Promise.all([
    api<MasterSummary>(`/api/v1/reports/master/summary?${q}`),
    list ? api<Page<StudentRow>>(`/api/v1/reports/master/students?${q}&page=${page}&size=50&sort=name`) : Promise.resolve(null),
    api<HistoryRow[]>("/api/v1/reports/master/history"),
  ]);
  return (
    <MasterReport scope={scope} structure={structure} sessions={sessions} ceiling={ceiling} options={options} filters={filters} actor={actor}
      summary={summary.ok ? summary.data : null} problem={summary.ok ? null : summary.problem}
      students={students && students.ok ? students.data : null} history={history.ok ? history.data : []} />
  );
}
