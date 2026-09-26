import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Batch, Deferment } from "@/lib/deferments";
import { Desk, type DefermentDashboard } from "./Desk";

export const dynamic = "force-dynamic";

export interface DeskFilters { session: string; semester: string; state: string; fac: string; dept: string; prog: string; kind: string; q: string; batch: string; from: string; to: string }
export interface DeskList {
  scope: { kind: string; office: string; stage: string }; rows: Deferment[]; page: number; size: number;
  options: { sessions: string[]; programmes: { faculty_code: string; faculty: string; dept_code: string; department: string; programme_code: string; programme: string }[]; states: string[]; batches: { id: string; reference: string; forwarded_at: string; count: number }[] };
}

/** t/deferments — the deferments desk: the figures for this office's stage, every application within its bound, searched on the server, the doors to each */
export default async function DefermentsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string).slice(0, 60) : "");
  const filters: DeskFilters = { session: s("session"), semester: s("semester"), state: s("state"), fac: s("fac"), dept: s("dept"), prog: s("prog"), kind: s("kind"), q: s("q"), batch: s("batch"), from: s("from"), to: s("to") };
  const qs = new URLSearchParams(); for (const [k, v] of Object.entries(filters)) if (v) qs.set(k, v);
  const [me, list, dash, batches] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<DeskList>(`/api/v1/deferments?${qs}&size=500`),
    api<DefermentDashboard>(`/api/v1/deferments/dashboard${filters.session ? `?session=${encodeURIComponent(filters.session)}` : ""}`),
    api<Batch[]>("/api/v1/deferments/batches"),
  ]);
  return (
    <Shell route="t/deferments" me={me.ok ? me.data : null}>
      {list.ok ? <Desk list={list.data} dash={dash.ok ? dash.data : null} filters={filters} batches={batches.ok ? batches.data : []} /> : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
