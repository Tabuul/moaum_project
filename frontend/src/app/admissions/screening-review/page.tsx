import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { ReviewList } from "@/lib/screening";
import { ScreeningReview, type ReviewFilters } from "./ScreeningReview";

export const dynamic = "force-dynamic";

const SESSION_PATTERN = /^\d{4}\/\d{4}$/;

/** t/screeningreview — the screening officers' desk: the queue, the form in full, the decision */
export default async function ScreeningReviewPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string).slice(0, 80) : "");
  const requested = s("session") || "2026/2027";
  const session = SESSION_PATTERN.test(requested) ? requested : "2026/2027";
  const filters: ReviewFilters = { session, state: s("state").toUpperCase(), fac: s("fac").toUpperCase(), dept: s("dept").toUpperCase(), prog: s("prog").toUpperCase(), q: s("q"), from: s("from"), to: s("to"), open: s("open") };
  const qs = new URLSearchParams();
  for (const [k, v] of Object.entries(filters)) if (v && !["session", "open"].includes(k)) qs.set(k, v);
  const [me, list] = await Promise.all([api<Me>("/api/v1/iam/me"), api<ReviewList>(`/api/v1/admissions/sessions/${session}/screening-review?${qs}&size=500`)]);
  return (
    <Shell route="t/screeningreview" me={me.ok ? me.data : null}>
      {list.ok ? <ScreeningReview list={list.data} filters={filters} actingOffice={me.ok ? me.data.activeOffice ?? null : null} /> : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
