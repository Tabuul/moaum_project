import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Eligibility, type Dept, type CourseRow, type EligibilityView } from "./Eligibility";

export const dynamic = "force-dynamic";

/** t/eligibility — who may register a course: the eligible programme-and-level set. */
export default async function EligibilityPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const [me, depts] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Dept[]>("/api/v1/allocation/departments"),
  ]);
  const deptList = depts.ok ? depts.data : [];
  const dept = typeof p.dept === "string" ? p.dept : deptList[0]?.code ?? "";
  const courses = dept ? await api<CourseRow[]>(`/api/v1/catalogue/courses?dept=${encodeURIComponent(dept)}`) : null;
  const courseList = courses && courses.ok ? courses.data : [];
  const code = typeof p.course === "string" ? p.course : courseList[0]?.code ?? "";
  const view = code ? await api<EligibilityView>(`/api/v1/catalogue/courses/${encodeURIComponent(code)}/eligibility`) : null;
  return (
    <Shell route="t/eligibility" me={me.ok ? me.data : null}>
      {!depts.ok ? (
        <ProblemNotice problem={depts.problem} />
      ) : (
        <Eligibility depts={deptList} dept={dept} courses={courseList} code={code} view={view && view.ok ? view.data : null} problem={view && !view.ok ? view.problem : null} />
      )}
    </Shell>
  );
}
