import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import type { ComplianceList, Requirement } from "@/lib/biodata-gate";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { ComplianceFilters } from "../ComplianceFilterBar";
import { BiodataStudents } from "./BiodataStudents";

export const dynamic = "force-dynamic";

/** t/biodatastudents — the students behind the Biodata compliance figures (V423): who, what is missing, when it last
 *  changed — filtered, searched and paged on the server, within the office's scope, and exported as it stands. */
export default async function BiodataStudentsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const s = (k: string) => (typeof params[k] === "string" ? (params[k] as string).trim() : "");
  const scoped = await loadScope({});
  const f: ComplianceFilters = {
    fac: scoped.ceiling.fac ?? s("fac"), dept: scoped.ceiling.dept ?? s("dept"), prog: scoped.ceiling.prog ?? s("prog"),
    level: s("level"), session: s("session"), sex: s("sex"),
  };
  const extra = { status: s("status").toUpperCase(), missing: s("missing"), q: s("q") };
  const page = Math.max(0, Number(s("page")) || 0);
  const q = new URLSearchParams({ page: String(page), size: "50" });
  for (const [k, v] of Object.entries({ ...f, ...extra })) if (v) q.set(k, v);
  const [me, rows, ov] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<ComplianceList>(`/api/v1/biodata-compliance/students?${q.toString()}`),
    api<Requirement[]>("/api/v1/biodata-compliance/requirements"),
  ]);
  return (
    <Shell route="t/biodatastudents" me={me.ok ? me.data : null}>
      {rows.ok ? <BiodataStudents list={rows.data} filters={f} extra={extra} page={page} requirements={ov.ok ? ov.data.filter((r) => r.required) : []}
        structure={scoped.structure} sessions={scoped.sessions} ceiling={scoped.ceiling} /> : <ProblemNotice problem={rows.problem} />}
    </Shell>
  );
}
