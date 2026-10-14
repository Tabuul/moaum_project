import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { CourseList, Directory, DuplicatePair, ReviewSummary } from "@/lib/catalogue";
import { Review, type ReviewFilters } from "./Review";

export const dynamic = "force-dynamic";

const KEYS = ["q", "fac", "dept", "prog", "level", "semester", "kind", "state", "session", "review", "issue", "sort", "dir", "size"] as const;

/** t/coursereview — the ownership review of the course pool (V445): the dashboard, the filtered list with what the review flags,
 *  the review's word on each course, the owner corrected one by one or in bulk, the possible duplicates, the report. */
export default async function CourseReviewPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const filters = Object.fromEntries(KEYS.map((k) => [k, typeof sp[k] === "string" ? (sp[k] as string) : ""])) as ReviewFilters;
  const page = typeof sp.page === "string" ? Math.max(1, Number(sp.page) || 1) : 1;
  const qs = new URLSearchParams();
  for (const k of KEYS) if (filters[k]) qs.set(k, filters[k]);
  qs.set("page", String(page));
  if (!filters.size) qs.set("size", "50");
  if (!filters.sort) qs.set("sort", "dept");
  const [me, list, directory, summary, sessions, duplicates] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<CourseList>(`/api/v1/catalogue/courses/list?${qs.toString()}`),
    api<Directory>("/api/v1/catalogue/directory"),
    api<ReviewSummary>("/api/v1/catalogue/review/summary"),
    api<{ name: string; state: string }[]>("/api/v1/ref/sessions").then((r) => (r.ok ? r.data.map((s) => s.name) : [])).catch(() => [] as string[]),
    api<DuplicatePair[]>("/api/v1/catalogue/possible-duplicates").then((r) => (r.ok ? r.data : [])).catch(() => [] as DuplicatePair[]),
  ]);
  const acting = me.ok ? me.data.activeOffice : null;
  return (
    <Shell route="t/coursereview" me={me.ok ? me.data : null}>
      {!list.ok ? <ProblemNotice problem={list.problem} /> : (
        <Review list={list.data} directory={directory.ok ? directory.data : null} summary={summary.ok ? summary.data : null} sessions={sessions} filters={filters} page={page}
          duplicates={duplicates} actingOffice={acting} generatedBy={me.ok ? me.data.name ?? null : null} />
      )}
    </Shell>
  );
}
