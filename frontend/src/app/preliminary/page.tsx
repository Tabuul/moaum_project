import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { PrelimDeskRoute, PrelimRow } from "@/lib/preliminary";
import { PrelimDesk, type DeskFilters, type PrelimSummary } from "./PrelimDesk";

export const dynamic = "force-dynamic";

const KEYS = ["route", "session", "view", "q", "target", "group", "sittings", "eligibility", "remediation", "state", "paid", "sex", "origin", "lga", "from", "to", "sort", "size"] as const;

/** prelim/dashboard — the preliminary and proficiency desk (V446; V701 every route: Preliminary Science, Preliminary Technology &
 *  Industrial Studies, the Adikpo Campus certificate courses, chosen with ?route=): the figures, each the filter of the list behind
 *  it; the applications, paged and filtered on the server; each opened for review. A Head of Department or a Dean reads their own
 *  targets only; a programme's own office reads its own programmes. */
export default async function PrelimDeskPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const filters = Object.fromEntries(KEYS.map((k) => [k, typeof sp[k] === "string" ? (sp[k] as string) : ""])) as unknown as DeskFilters;
  const page = typeof sp.page === "string" ? Math.max(1, Number(sp.page) || 1) : 1;
  const qs = new URLSearchParams();
  for (const k of KEYS) if (filters[k]) qs.set(k, filters[k]);
  qs.set("page", String(page - 1));
  if (!filters.size) qs.set("size", "50");
  const sq = new URLSearchParams();
  if (filters.session) sq.set("session", filters.session);
  if (filters.route) sq.set("route", filters.route);
  const [me, summary, list, routes] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<PrelimSummary>(`/api/v1/admissions/preliminary/summary?${sq.toString()}`),
    api<{ session: string; total: number; page: number; size: number; rows: PrelimRow[] }>(`/api/v1/admissions/preliminary/applications?${qs.toString()}`),
    api<PrelimDeskRoute[]>("/api/v1/admissions/preliminary/routes"),
  ]);
  return (
    <Shell route="prelim/dashboard" me={me.ok ? me.data : null}>
      {!summary.ok ? <ProblemNotice problem={summary.problem} /> : !list.ok ? <ProblemNotice problem={list.problem} /> : (
        <PrelimDesk summary={summary.data} list={list.data} filters={filters} page={page} generatedBy={me.ok ? me.data.name ?? null : null} routes={routes.ok ? routes.data : []} />
      )}
    </Shell>
  );
}
