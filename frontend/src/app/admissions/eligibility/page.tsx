import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { ChangeRequest, ListRow, Stats } from "@/lib/eligibility";
import { EligibilityDesk, type DeskFilters } from "./Eligibility";

export const dynamic = "force-dynamic";

const SESSION_PATTERN = /^\d{4}\/\d{4}$/;

export interface EligibilityList {
  session: string; rows: ListRow[]; page: number; size: number; stats: Stats;
  options: { faculty_code: string; faculty: string; dept_code: string | null; department: string | null; programme_code: string; programme: string }[];
  recommendable: { programme_code: string; programme: string }[];
}

/** t/admeligibility — the eligibility register: every submitted applicant against the session's admission settings, the failed requirements, the suggested programmes, the change requests */
export default async function EligibilityPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string).slice(0, 60) : "");
  const requested = s("session") || "2026/2027";
  const session = SESSION_PATTERN.test(requested) ? requested : "2026/2027";
  const filters: DeskFilters = { session, q: s("q"), fac: s("fac"), dept: s("dept"), prog: s("prog"), status: s("status"), recommended: s("recommended"), mode: s("mode") };
  const qs = new URLSearchParams(); for (const [k, v] of Object.entries(filters)) if (v && k !== "session") qs.set(k, v);
  const [me, list, changes] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<EligibilityList>(`/api/v1/admissions/sessions/${session}/eligibility?${qs}&size=500`),
    api<ChangeRequest[]>(`/api/v1/admissions/sessions/${session}/eligibility/changes`),
  ]);
  return (
    <Shell route="t/admeligibility" me={me.ok ? me.data : null}>
      {list.ok ? <EligibilityDesk list={list.data} changes={changes.ok ? changes.data : []} filters={filters} actingOffice={me.ok ? me.data.activeOffice ?? null : null} /> : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
