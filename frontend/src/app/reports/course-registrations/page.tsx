import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { readFilters, regQuery, semWord, type CourseRow, type RegPage, type ReportScope, type SummaryRow } from "@/lib/course-registration-report";
import { CourseRegistrations, type View } from "./CourseRegistrations";

export const dynamic = "force-dynamic";

/** t/courseregreport — V652: the Course Registration Report. One row a student and course for the scope chosen, counted by every
 *  dimension; each course with its registered students, card or permit held and attendance; the attendance sheets issued from it.
 *  Every office reads within its own scope: the API holds a Head of Department to the department, the GST and EPS offices to
 *  their own courses. */
export default async function CourseRegistrationReportPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const s = (k: string) => (typeof params[k] === "string" ? (params[k] as string) : "");
  const { scope, structure, sessions, ceiling } = await loadScope(params);
  const filters = readFilters(params);
  const view: View = (["courses", "rows", "summary"] as const).find((v) => v === s("view")) ?? "courses";
  const page = /^\d{1,5}$/.test(s("page")) ? Math.max(1, Number(s("page"))) : 1;
  const q = regQuery(scope, filters).toString();
  const [me, summary, rows, courses] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ session: string; semester: number | null; scope: ReportScope; rows: SummaryRow[] }>(`/api/v1/reports/course-registrations/summary?${q}`),
    view === "rows" ? api<RegPage>(`/api/v1/reports/course-registrations?${q}&page=${page}&size=50`) : Promise.resolve(null),
    view === "courses" ? api<{ rows: CourseRow[] }>(`/api/v1/reports/course-registrations/courses?${q}`) : Promise.resolve(null),
  ]);
  if (!summary.ok) {
    return <Shell route="t/courseregreport" me={me.ok ? me.data : null}><ProblemNotice problem={summary.problem} /></Shell>;
  }
  const session = summary.data.session;
  const semester = summary.data.semester;
  return (
    <Shell route="t/courseregreport" me={me.ok ? me.data : null} sub={`${session} · ${semester ? `${semWord(semester)} Semester` : "Every semester"}`}>
      <CourseRegistrations key={`${q}|${view}|${page}`} scope={{ ...scope, session: scope.session || session }} structure={structure} sessions={sessions} ceiling={ceiling}
        filters={filters} view={view} session={session} semester={semester} summary={summary.data.rows} reportScope={summary.data.scope}
        rows={rows} courses={courses} office={me.ok ? me.data.activeOffice ?? "" : ""} actorName={me.ok ? me.data.name ?? null : null} />
    </Shell>
  );
}
