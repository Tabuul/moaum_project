import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Queries, type QueryRow } from "./Queries";

export const dynamic = "force-dynamic";

/** the department's desk for result queries: one mark, one course, answered on the record */
export default async function QueriesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const state = params.state === "answered" ? "answered" : params.state === "all" ? "all" : "open";
  const dept = typeof params.dept === "string" ? params.dept : "";
  const [me, rows] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<QueryRow[]>(`/api/v1/results/queries?state=${state}${dept ? `&dept=${encodeURIComponent(dept)}` : ""}`),
  ]);
  return (
    <Shell route="t/queries" me={me.ok ? me.data : null}>
      {rows.ok ? <Queries rows={rows.data} state={state} dept={dept} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={rows.problem} />}
    </Shell>
  );
}
