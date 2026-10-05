import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { CourseDetail as Detail, Directory } from "@/lib/catalogue";
import { CourseDetail } from "./CourseDetail";

export const dynamic = "force-dynamic";

/** One course: its record, every department and programme that offers it, the sessions it was taught, the proposals and the history (V332). */
export default async function CoursePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const code = typeof p.code === "string" ? p.code.trim() : "";
  const [me, detail, directory] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    code ? api<Detail>(`/api/v1/catalogue/courses/${encodeURIComponent(code)}/detail`) : Promise.resolve(null),
    api<Directory>("/api/v1/catalogue/directory"),
  ]);
  return (
    <Shell route="t/deptcourses" me={me.ok ? me.data : null}>
      {!code ? <ProblemNotice problem={{ status: 400, title: "No course named", detail: "Open a course from the department's catalogue or the list of all courses." }} />
        : !detail || !detail.ok ? <ProblemNotice problem={detail ? detail.problem : { status: 404, title: "Course not found" }} />
        : <CourseDetail data={detail.data} directory={directory.ok ? directory.data : null} />}
    </Shell>
  );
}
