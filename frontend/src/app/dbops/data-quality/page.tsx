import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { DataQuality, type DqFigures, type DqRows } from "./DataQuality";

export const dynamic = "force-dynamic";

const KINDS = ["INVALID_PROGRAMME", "MISSING_FACULTY_DEPARTMENT", "MISSING_ENTRY_SESSION", "INVALID_LEVEL", "LEVEL_INCONSISTENT", "MISSING_MATRIC",
  "DUPLICATE_MATRIC", "DUPLICATE_JAMB", "UNCLASSIFIED", "CONFLICTING_STATUS", "GRADUATED_STILL_ACTIVE", "BEYOND_MAXIMUM_PERIOD",
  "PAID_NOT_REGISTERED", "REGISTERED_NOT_PAID"];

/** V640: data quality — every fault the engines can see on the records of the scope, each figure opening its records */
export default async function DataQualityPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const { scope, structure, sessions, ceiling } = await loadScope(params);
  const kind = typeof params.kind === "string" && KINDS.includes(params.kind) ? params.kind : "";
  const q = new URLSearchParams();
  if (scope.fac) q.set("fac", scope.fac);
  if (scope.dept) q.set("dept", scope.dept);
  if (scope.prog) q.set("prog", scope.prog);
  if (scope.session) q.set("session", scope.session);
  if (scope.sem && scope.sem !== "0") q.set("semester", scope.sem);
  const rq = new URLSearchParams(q);
  rq.set("page", "1");
  rq.set("size", "50");
  const [me, figures, rows] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<DqFigures>(`/api/v1/dbops/data-quality?${q.toString()}`),
    kind ? api<DqRows>(`/api/v1/dbops/data-quality/${kind}?${rq.toString()}`) : Promise.resolve(null),
  ]);
  return (
    <Shell route="t/dataquality" me={me.ok ? me.data : null}>
      {figures.ok ? (
        <DataQuality key={`${q.toString()}|${kind}`} scope={scope} structure={structure} sessions={sessions} ceiling={ceiling} figures={figures.data}
          kind={kind} rows={rows && rows.ok ? rows.data : null} actorName={me.ok ? me.data.name ?? null : null} />
      ) : <ProblemNotice problem={figures.problem} />}
      {rows && !rows.ok ? <ProblemNotice problem={rows.problem} /> : null}
    </Shell>
  );
}
