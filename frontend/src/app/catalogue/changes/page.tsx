import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { CourseChangeList } from "@/lib/course-correction";
import { Changes, type ChangeFilters } from "./Changes";

export const dynamic = "force-dynamic";

const KEYS = ["q", "field", "source", "from", "to"] as const;

/** t/coursechanges — every change of a course's code and title (V713): by a correction with its reason, the department's desk,
 *  an upload or a migration, and those the audit spine held before; searchable by code, title, Course ID, ticket or department. */
export default async function CourseChangesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const filters = Object.fromEntries(KEYS.map((k) => [k, typeof sp[k] === "string" ? (sp[k] as string) : ""])) as ChangeFilters;
  const page = typeof sp.page === "string" ? Math.max(1, Number(sp.page) || 1) : 1;
  const qs = new URLSearchParams();
  for (const k of KEYS) if (filters[k]) qs.set(k, filters[k]);
  qs.set("page", String(page));
  qs.set("size", "50");
  const [me, list] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<CourseChangeList>(`/api/v1/catalogue/course-changes?${qs.toString()}`),
  ]);
  return (
    <Shell route="t/coursechanges" me={me.ok ? me.data : null}>
      {!list.ok ? <ProblemNotice problem={list.problem} /> : <Changes list={list.data} filters={filters} page={page} generatedBy={me.ok ? me.data.name ?? null : null} />}
    </Shell>
  );
}
