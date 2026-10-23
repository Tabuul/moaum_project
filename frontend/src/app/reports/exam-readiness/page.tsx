import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { CourseRow, Options, StudentPage, Summary } from "@/lib/exam-readiness";
import { ExamReadiness, type SavedReport, type View } from "./ExamReadiness";

export const dynamic = "force-dynamic";

/** V640: Examination Readiness — paid and registered, paid not registered, not paid, by faculty, department, programme, level,
 *  programme type and academic status, for a course, each course of a department; every figure opens its students; the package of
 *  six reports under one DBO/EXAM reference. ICT's Reports, the Database Operations office's, and the offices that read them. */
export default async function ExamReadinessPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const s = (k: string) => (typeof params[k] === "string" ? (params[k] as string) : "");
  const { scope, structure, sessions, ceiling } = await loadScope(params);
  const [me, options] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Options>("/api/v1/reports/exam-readiness/options")]);
  if (!options.ok) {
    return (
      <Shell route="t/examreadiness" me={me.ok ? me.data : null}>
        <ProblemNotice problem={options.problem} />
      </Shell>
    );
  }
  const session = scope.session || options.data.period.session;
  const semester = scope.sem && scope.sem !== "0" ? scope.sem : String(options.data.period.semester);
  const view: View = {
    by: ["faculty", "department", "programme", "level", "type", "status"].includes(s("by")) ? s("by") : "faculty",
    rule: s("rule") === "FULL" ? "FULL" : "CARD",
    type: s("type"), course: s("course"), cat: s("cat"), astatus: s("astatus"), mode: s("view"),
    cfac: s("cfac"), cdept: s("cdept"), cby: s("cby") === "faculty" ? "faculty" : "department",
  };
  const q = new URLSearchParams({ session, semester, rule: view.rule });
  if (scope.fac) q.set("fac", scope.fac);
  if (scope.dept) q.set("dept", scope.dept);
  if (scope.prog) q.set("prog", scope.prog);
  if (scope.level) q.set("level", scope.level);
  if (view.type) q.set("type", view.type);
  if (view.course) q.set("course", view.course);
  const lq = new URLSearchParams(q);
  lq.set("category", view.cat || "ALL");
  if (view.astatus) lq.set("astatus", view.astatus);
  lq.set("page", "1");
  lq.set("size", "50");
  const cq = new URLSearchParams(q);
  cq.delete("course");
  cq.delete("type");
  const courseOwner = view.cby === "faculty" ? (view.cfac || scope.fac) : (view.cdept || scope.dept);
  if (courseOwner) cq.set(view.cby === "faculty" ? "cfac" : "cdept", courseOwner);
  const courseDept = view.cdept || scope.dept;
  const oq = new URLSearchParams({ session, semester });
  if (courseDept) oq.set("cdept", courseDept);
  const [summary, students, courses, courseOptions, saved, offices] = await Promise.all([
    api<Summary>(`/api/v1/reports/exam-readiness/summary?${q.toString()}&by=${view.by}`),
    view.cat ? api<StudentPage>(`/api/v1/reports/exam-readiness/students?${lq.toString()}`) : Promise.resolve(null),
    view.mode === "courses" && courseOwner ? api<{ rows: CourseRow[]; at: string }>(`/api/v1/reports/exam-readiness/courses?${cq.toString()}`) : Promise.resolve(null),
    courseDept ? api<{ code: string; title: string; dept_code: string }[]>(`/api/v1/reports/exam-readiness/courses/options?${oq.toString()}`) : Promise.resolve(null),
    api<SavedReport[]>("/api/v1/dbops/saved?kind=EXAM_READINESS"),
    api<{ code: string; label: string }[]>("/api/v1/dbops/offices"),
  ]);
  return (
    <Shell route="t/examreadiness" me={me.ok ? me.data : null} sub={`${session} · ${semester === "1" ? "First" : semester === "2" ? "Second" : "Third"} Semester`}>
      <ExamReadiness key={`${q.toString()}|${view.by}|${view.cat}|${view.astatus}|${view.mode}|${courseOwner}`}
        scope={scope} structure={structure} sessions={sessions} ceiling={ceiling} options={options.data} view={view} session={session} semester={Number(semester)}
        summary={summary} students={students} courses={courses} courseOwner={courseOwner}
        courseOptions={courseOptions && courseOptions.ok ? courseOptions.data : []} saved={saved.ok ? saved.data : null} offices={offices.ok ? offices.data : []}
        actorName={me.ok ? me.data.name ?? null : null} />
    </Shell>
  );
}
