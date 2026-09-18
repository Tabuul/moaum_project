import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { DeptCourses, type Course, type Dept, type Duplicate, type Programme } from "./DeptCourses";

export const dynamic = "force-dynamic";

/** t/deptcourses — the courses a department owns, and creates. */
export default async function CataloguePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const [me, depts] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Dept[]>("/api/v1/allocation/departments"),
  ]);
  const deptList = depts.ok ? depts.data : [];
  const dept = typeof p.dept === "string" ? p.dept : deptList[0]?.code ?? "";
  const [courses, duplicates, programmes] = dept
    ? await Promise.all([
        api<Course[]>(`/api/v1/catalogue/courses?dept=${encodeURIComponent(dept)}`),
        api<Duplicate[]>(`/api/v1/catalogue/duplicates?dept=${encodeURIComponent(dept)}`),
        api<Programme[]>("/api/v1/catalogue/programmes"),
      ])
    : [null, null, null];
  return (
    <Shell route="t/deptcourses" me={me.ok ? me.data : null}>
      {!depts.ok ? (
        <ProblemNotice problem={depts.problem} />
      ) : (
        <DeptCourses depts={deptList} dept={dept} courses={courses && courses.ok ? courses.data : []} duplicates={duplicates && duplicates.ok ? duplicates.data : []} programmes={programmes && programmes.ok ? programmes.data : []} problem={courses && !courses.ok ? courses.problem : null} />
      )}
    </Shell>
  );
}
