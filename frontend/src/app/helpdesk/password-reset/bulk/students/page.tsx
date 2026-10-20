import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { BulkHistory, DeskSummary } from "@/lib/bulk-reset";
import { BulkReset, type Candidates, type Filters } from "../BulkReset";

export const dynamic = "force-dynamic";

/** t/supportpwbulk — Bulk Password Reset of students without a ticket (V559): the students the agent may reset found and chosen,
 *  many at once, each reset to the default student credential by the one reset service. V594: Bulk Password Reset itself lists the
 *  Login Issues tickets; this finder is reached from it */
export default async function BulkResetStudentsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const str = (k: string) => (typeof p[k] === "string" ? (p[k] as string).trim() : "");
  const f: Filters = {
    q: str("q").slice(0, 80), fac: str("fac"), dept: str("dept"), prog: str("prog"),
    level: /^\d{3}$/.test(str("level")) ? str("level") : "", status: str("status"), account: str("account"),
    login: str("login") === "1", page: /^\d{1,4}$/.test(str("page")) ? Math.max(1, Number(str("page"))) : 1,
  };
  const qs = new URLSearchParams({ page: String(f.page), size: "50" });
  for (const k of ["q", "fac", "dept", "prog", "level", "status", "account"] as const) if (f[k]) qs.set(k, String(f[k]));
  if (f.login) qs.set("login", "true");
  const base = "/api/v1/helpdesk/support/password-reset/bulk";
  const [me, summary, list, history] = await Promise.all([
    api<Me>("/api/v1/iam/me"), api<DeskSummary>(`${base}/summary`), api<Candidates>(`${base}/candidates?${qs.toString()}`), api<BulkHistory>(`${base}?size=10`),
  ]);
  return (
    <Shell route="t/supportpwbulk" me={me.ok ? me.data : null}>
      {list.ok
        ? <BulkReset f={f} list={list.data} summary={summary.ok ? summary.data : null} history={history.ok ? history.data : null} />
        : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
