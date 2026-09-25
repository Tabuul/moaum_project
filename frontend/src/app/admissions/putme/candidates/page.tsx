import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { intakeSession, type SessionRow } from "@/lib/sessions";
import type { Batch, CandidateList } from "@/lib/putme";
import { Candidates } from "./Candidates";

export const dynamic = "force-dynamic";

export interface CandFilters { status: string; fac: string; dept: string; prog: string; batch: string; centre: string; q: string; page: string }

/** t/putme-cbt › candidates — every applicant of the session with where they stand, filtered, searched, exported; moved, unscheduled, confirmed */
export default async function PutmeCandidatesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const g = (k: string) => (typeof p[k] === "string" ? (p[k] as string).slice(0, 80) : "");
  const [me, sessions] = await Promise.all([api<Me>("/api/v1/iam/me"), api<SessionRow[]>("/api/v1/ref/sessions")]);
  const list = sessions.ok ? sessions.data : [];
  const session = /^\d{4}\/\d{4}$/.test(g("session")) ? g("session") : intakeSession(list);
  const filters: CandFilters = { status: g("status"), fac: g("fac"), dept: g("dept"), prog: g("prog"), batch: g("batch"), centre: g("centre"), q: g("q"), page: g("page") };
  const qs = new URLSearchParams(); for (const [k, v] of Object.entries(filters)) if (v) qs.set(k, v);
  qs.set("size", "500");
  const [view, batches] = await Promise.all([
    api<CandidateList>(`/api/v1/admissions/sessions/${session}/putme/candidates?${qs}`),
    api<Batch[]>(`/api/v1/admissions/sessions/${session}/putme/batches`),
  ]);
  return (
    <Shell route="t/putme-cbt" me={me.ok ? me.data : null}>
      {view.ok ? <Candidates view={view.data} batches={batches.ok ? batches.data : []} filters={filters} office={me.ok ? me.data.activeOffice ?? null : null} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
