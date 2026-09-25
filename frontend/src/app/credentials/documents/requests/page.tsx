import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { RequestRow } from "@/lib/documents";
import { Requests } from "./Requests";

export const dynamic = "force-dynamic";

export interface ReqFilters { stage: string; kind: string; payment: string; delivery: string; fac: string; dept: string; prog: string; session: string; q: string; page: string }
export interface ReqList { total: number; page: number; size: number; rows: RequestRow[]; options: { faculty_code: string; faculty: string; dept_code: string; department: string; programme_code: string; programme: string }[] }

/** t/documents › requests — every document request, filtered and searched on the server, names A–Z, each a door to its processing */
export default async function DocumentRequestsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const g = (k: string) => (typeof p[k] === "string" ? (p[k] as string).slice(0, 80) : "");
  const filters: ReqFilters = { stage: g("stage"), kind: g("kind"), payment: g("payment"), delivery: g("delivery"), fac: g("fac"), dept: g("dept"), prog: g("prog"), session: g("session"), q: g("q"), page: g("page") };
  const qs = new URLSearchParams(); for (const [k, v] of Object.entries(filters)) if (v) qs.set(k, v);
  qs.set("size", "500");
  const [me, view] = await Promise.all([api<Me>("/api/v1/iam/me"), api<ReqList>(`/api/v1/documents/requests?${qs}`)]);
  return (
    <Shell route="t/documents" me={me.ok ? me.data : null}>
      {view.ok ? <Requests list={view.data} filters={filters} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
