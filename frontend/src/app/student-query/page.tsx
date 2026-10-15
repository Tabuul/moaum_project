import { redirect } from "next/navigation";
import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { queryString, readQueryFilters, type QueryOptions, type QueryPage, type QuerySummary } from "@/lib/student-query";
import { StudentQuery } from "./StudentQuery";

export const dynamic = "force-dynamic";

/** t/studentquery — the Student Query (V469): every learner in the office's scope, by student type first, from the one engine */
export default async function StudentQueryPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const filters = readQueryFilters(p);
  const page = typeof p.page === "string" && /^\d+$/.test(p.page) ? Number(p.page) : 0;
  const group = typeof p.group === "string" && ["faculty", "department", "programme"].includes(p.group) ? (p.group as "faculty" | "department" | "programme") : "";
  const [me, options, summary, list] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<QueryOptions>(`/api/v1/stats/students/query/options?${queryString({ type: filters.type })}`),
    api<QuerySummary>(`/api/v1/stats/students/query/summary?${queryString(filters)}`),
    api<QueryPage>(`/api/v1/stats/students/query?${queryString(filters, { page, size: 50 })}`),
  ]);
  // an office whose students are one programme type reads that type only (the server holds it whatever is asked); the
  // address is put right rather than showing another type's empty list
  const bound = options.ok ? options.data.scope.programmeType : null;
  if (bound && filters.type && filters.type !== bound) redirect(`/student-query?${queryString({ ...filters, type: bound })}`);
  return (
    <Shell route="t/studentquery" me={me.ok ? me.data : null}>
      {!options.ok ? <ProblemNotice problem={options.problem} />
        : !summary.ok ? <ProblemNotice problem={summary.problem} />
        : !list.ok ? <ProblemNotice problem={list.problem} />
        : <StudentQuery filters={filters} group={group} options={options.data} summary={summary.data} list={list.data} />}
    </Shell>
  );
}
