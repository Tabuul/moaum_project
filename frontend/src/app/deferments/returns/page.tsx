import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Deferment } from "@/lib/deferments";
import { Returns, type ReturnFilters } from "./Returns";

export const dynamic = "force-dynamic";

export interface ReturnsList { scope: { kind: string }; rows: (Deferment & { deferred_due: number })[]; options: { sessions: string[]; programmes: { faculty_code: string; faculty: string; dept_code: string; department: string; programme_code: string; programme: string }[] } }

/** students due to resume from deferment, within the office's bound, searched and filtered on the server; the return is confirmed on the application */
export default async function ReturnsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string).slice(0, 60) : "");
  const filters: ReturnFilters = { status: ["UPCOMING", "DUE", "OVERDUE"].includes(s("status")) ? s("status") : "", q: s("q"), fac: s("fac"), dept: s("dept"), prog: s("prog"), session: s("session"), kind: s("kind"), returnSession: s("returnSession"), returnSemester: s("returnSemester") };
  const qs = new URLSearchParams(); for (const [k, v] of Object.entries(filters)) if (v) qs.set(k, v);
  const [me, r] = await Promise.all([api<Me>("/api/v1/iam/me"), api<ReturnsList>(`/api/v1/deferments/returns?${qs}`)]);
  return (
    <Shell route="t/deferments" me={me.ok ? me.data : null}>
      {r.ok ? <Returns list={r.data} filters={filters} /> : <ProblemNotice problem={r.problem} />}
    </Shell>
  );
}
