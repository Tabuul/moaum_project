import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { PrelimRow } from "@/lib/preliminary";
import { PrelimDesk, type DeskFilters, type PrelimSummary } from "./PrelimDesk";

export const dynamic = "force-dynamic";

const KEYS = ["session", "view", "q", "target", "sittings", "eligibility", "remediation", "state", "paid", "sex", "origin", "lga", "from", "to", "sort", "size"] as const;

/** prelim/dashboard — the Preliminary Science desk (V446): the figures, each the filter of the list behind it; the applications,
 *  paged and filtered on the server; each opened for review. A Head of Department or a Dean reads their own targets only. */
export default async function PrelimDeskPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const filters = Object.fromEntries(KEYS.map((k) => [k, typeof sp[k] === "string" ? (sp[k] as string) : ""])) as unknown as DeskFilters;
  const page = typeof sp.page === "string" ? Math.max(1, Number(sp.page) || 1) : 1;
  const qs = new URLSearchParams();
  for (const k of KEYS) if (filters[k]) qs.set(k, filters[k]);
  qs.set("page", String(page - 1));
  if (!filters.size) qs.set("size", "50");
  const [me, summary, list] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<PrelimSummary>(`/api/v1/admissions/preliminary/summary${filters.session ? `?session=${encodeURIComponent(filters.session)}` : ""}`),
    api<{ session: string; total: number; page: number; size: number; rows: PrelimRow[] }>(`/api/v1/admissions/preliminary/applications?${qs.toString()}`),
  ]);
  return (
    <Shell route="prelim/dashboard" me={me.ok ? me.data : null}>
      {!summary.ok ? <ProblemNotice problem={summary.problem} /> : !list.ok ? <ProblemNotice problem={list.problem} /> : (
        <PrelimDesk summary={summary.data} list={list.data} filters={filters} page={page} generatedBy={me.ok ? me.data.name ?? null : null} />
      )}
    </Shell>
  );
}
