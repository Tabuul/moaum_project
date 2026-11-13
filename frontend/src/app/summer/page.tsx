import { api } from "@/lib/api";
import { sessionRows } from "@/lib/sessions-server";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { sessionPath, type SummerPeriod } from "@/lib/summer";
import { SummerDesk, type SummerAuthorisationToReview, type SummerCourseRow, type SummerStudents } from "./SummerDesk";

/** V754: the desk's SETTERS (SummerDesk, the API's): only they read the authorisations to look at again */
const SETTERS = ["academic", "registrar", "dregistrar", "super"];

export const dynamic = "force-dynamic";

/** t/summer — V735: the Summer Semester desk. The Academic Office sets the period (its window, examination dates, who it is for),
 *  identifies the eligible, authorises a student, tells the students and opens the examinations; the Registry, the Heads of
 *  Department and Deans (their own unit), the Bursary, ICT and management read the students, the courses and the figures. */
export default async function SummerDeskPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const asked = typeof sp.session === "string" && /^\d{4}\/\d{4}$/.test(sp.session) ? sp.session : null;
  const [me, periods, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<SummerPeriod[]>("/api/v1/summer/periods"),
    sessionRows(),
  ]);
  if (!periods.ok) {
    return <Shell route="t/summer" me={me.ok ? me.data : null}><ProblemNotice problem={periods.problem} /></Shell>;
  }
  const session = asked ?? periods.data[0]?.session ?? null;
  const maySet = SETTERS.includes(me.ok ? me.data.activeOffice ?? "" : "");
  const [students, courses, toReview] = session && periods.data.some((p) => p.session === session)
    ? await Promise.all([
        api<SummerStudents>(`/api/v1/summer/${sessionPath(session)}/students`),
        api<SummerCourseRow[]>(`/api/v1/summer/${sessionPath(session)}/courses`),
        maySet ? api<SummerAuthorisationToReview[]>(`/api/v1/summer/${sessionPath(session)}/authorisations`) : Promise.resolve(null),
      ])
    : [null, null, null];
  return (
    <Shell route="t/summer" me={me.ok ? me.data : null}>
      {students && !students.ok ? <ProblemNotice problem={students.problem} /> : null}
      <SummerDesk periods={periods.data} session={session} sessions={sessions.map((s) => s.name)}
                  students={students && students.ok ? students.data : null} courses={courses && courses.ok ? courses.data : []}
                  actingOffice={me.ok ? me.data.activeOffice : null} toReview={toReview && toReview.ok ? toReview.data : []} />
    </Shell>
  );
}
