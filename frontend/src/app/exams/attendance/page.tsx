import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { regQuery, NO_FILTERS, semWord, type CourseRow } from "@/lib/course-registration-report";
import type { Marking, PendingRow, Reconciliation, SheetRow } from "@/lib/exam-attendance";
import { Attendance, ClassList, type Tab } from "./Attendance";

export const dynamic = "force-dynamic";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** t/examattendance — V652: Examination Attendance. Without a class: the courses of the scope with their sheets and attendance, each
 *  opening its class. With one (?offering=): the list marked after the paper, the handwritten rows entered, those not identified
 *  verified, the reconciliation and the sheet's versions — all within the office's own scope. */
export default async function ExamAttendancePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const s = (k: string) => (typeof params[k] === "string" ? (params[k] as string) : "");
  const me = await api<Me>("/api/v1/iam/me");
  const meData = me.ok ? me.data : null;
  const offering = UUID.test(s("offering")) ? s("offering").toLowerCase() : "";
  if (!offering) {
    const { scope, structure, sessions, ceiling } = await loadScope(params);
    const q = regQuery(scope, { ...NO_FILTERS, course: /^[A-Za-z][A-Za-z0-9 /-]{1,23}$/.test(s("course")) ? s("course").toUpperCase() : "" }).toString();
    const courses = await api<{ session: string; semester: number | null; rows: CourseRow[] }>(`/api/v1/reports/course-registrations/courses?${q}`);
    return (
      <Shell route="t/examattendance" me={meData}>
        {courses.ok ? (
          <ClassList scope={{ ...scope, session: scope.session || courses.data.session }} structure={structure} sessions={sessions} ceiling={ceiling}
            session={courses.data.session} semester={courses.data.semester} rows={courses.data.rows} />
        ) : <ProblemNotice problem={courses.problem} />}
      </Shell>
    );
  }
  const tab: Tab = (["mark", "manual", "pending", "reconcile", "sheets"] as const).find((t) => t === s("tab")) ?? "mark";
  const [marking, recon, pending, sheets] = await Promise.all([
    api<Marking>(`/api/v1/exams/attendance/${offering}`),
    api<Reconciliation>(`/api/v1/exams/attendance/${offering}/reconciliation`),
    api<{ rows: PendingRow[] }>(`/api/v1/exams/attendance/${offering}/pending?state=ALL`),
    api<{ sheets: SheetRow[] }>(`/api/v1/exams/attendance/sheets?offering=${offering}`),
  ]);
  if (!marking.ok) return <Shell route="t/examattendance" me={meData}><ProblemNotice problem={marking.problem} /></Shell>;
  const o = marking.data.offering;
  return (
    <Shell route="t/examattendance" me={meData} sub={`${o.shown_code} · ${o.session} · ${semWord(o.semester)} Semester`}>
      <Attendance key={`${offering}|${tab}`} tab={tab} marking={marking.data} recon={recon.ok ? recon.data : null} reconProblem={recon.ok ? null : recon.problem}
        pending={pending.ok ? pending.data.rows : []} sheets={sheets.ok ? sheets.data.sheets : []} actorName={meData?.name ?? null} />
    </Shell>
  );
}
