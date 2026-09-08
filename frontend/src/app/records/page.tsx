import { cookies } from "next/headers";
import { api } from "@/lib/api";
import { readScope, scopeQuery, SCOPE_COOKIE } from "@/lib/scope";
import type { RecordsResult, RefCourse, RefSession } from "@/lib/student";
import { Shell, type Me } from "@/components/proto/Shell";
import type { ScopeStructure } from "@/components/proto/ScopeBar";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Records, RECORD_VIEWS } from "./Records";

export const dynamic = "force-dynamic";

export default async function RecordsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const scope = readScope(params, (await cookies()).get(SCOPE_COOKIE)?.value);
  const asked = typeof params.view === "string" ? params.view : "students";
  const view = RECORD_VIEWS.some((v) => v[0] === asked) ? asked : "students";

  const courseQuery = new URLSearchParams();
  if (scope.dept) courseQuery.set("dept", scope.dept);
  if (scope.sem) courseQuery.set("semester", scope.sem);
  if (scope.level) courseQuery.set("level", scope.level);

  const [me, result, structure, sessions, courses] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<RecordsResult>(`/api/v1/student/records/${view}?${scopeQuery(scope)}`),
    api<ScopeStructure>("/api/v1/ref/structure"),
    api<RefSession[]>("/api/v1/ref/sessions"),
    scope.dept ? api<RefCourse[]>(`/api/v1/ref/courses?${courseQuery.toString()}`) : Promise.resolve(null),
  ]);

  return (
    <Shell route="t/records" me={me.ok ? me.data : null}>
      {!result.ok ? (
        <ProblemNotice problem={result.problem} />
      ) : (
        <Records
          view={view}
          scope={scope}
          result={result.data}
          structure={structure.ok ? structure.data : { faculties: [] }}
          sessions={sessions.ok ? sessions.data.map((s) => s.name) : [scope.session]}
          courses={courses && courses.ok ? courses.data : []}
        />
      )}
    </Shell>
  );
}
