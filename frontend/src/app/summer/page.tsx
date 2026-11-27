import { api, type Problem } from "@/lib/api";
import { sessionRows } from "@/lib/sessions-server";
import { Shell, type Me } from "@/components/proto/Shell";
import type { ScopeStructure } from "@/components/proto/ScopeBar";
import { ProblemNotice } from "@/components/ProblemNotice";
import {
  QUEUE_PARAMS, REPORT_PARAMS, ROSTER_PARAMS, defaultQueueState, deskReads, deskView, maySetSummer, pageOf, pickFilters, queryString, sessionPath,
  type SummerPeriod, type SummerReportView, type SummerRosterView, type SummerSelectionsView,
} from "@/lib/summer";
import { SummerDesk, type DeskData } from "./SummerDesk";
import { orgFromStructure } from "@/lib/summer-org";
import type { SummerAuthorisationToReview } from "./SummerPeriodActs";
import type { SummerCourseRow } from "./SummerCourses";

export const dynamic = "force-dynamic";

/** the rows a page of the queue and of the students holds */
const PAGE_SIZE = 50;

/** t/summer — V735, V779: the Summer Semester desk. The Academic Office sets the period (its window, examination dates, who it is for),
 *  identifies the eligible, authorises a student, tells the students, verifies what they selected and opens the examinations; the
 *  Registry, the Heads of Department and Deans (their own unit), the Bursary, ICT and management read the queue, the students, the
 *  courses and the figures. The view is in the address (?view=review|students|reports|courses|period) and this page reads only the
 *  view that is shown. */
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
  const office = me.ok ? me.data.activeOffice : null;
  const maySet = maySetSummer(office);
  const view = deskView(sp.view, maySet);
  const known = !!session && periods.data.some((p) => p.session === session);
  const base = session ? `/api/v1/summer/${sessionPath(session)}` : null;
  const reads = deskReads(view, known, maySet);

  let desk: DeskData | null = null;
  let problem: Problem | null = null;
  if (base && reads === "new-period") {
    // a session with no Summer yet: the Period and acts tab carries the form that sets it; there is no period, no student and no paid
    // course to read, only the authorisations to look at again (V754), which do not wait for a period
    const toReview = await api<SummerAuthorisationToReview[]>(`${base}/authorisations`);
    desk = { view: "period", period: null, issues: [], toReview: toReview.ok ? toReview.data : [] };
  } else if (base && reads === "view") {
    const page = pageOf(sp.page);
    if (view === "review") {
      const filters = pickFilters(sp, QUEUE_PARAMS);
      filters.state = filters.state ?? defaultQueueState(maySet);
      const r = await api<SummerSelectionsView>(`${base}/selections?${queryString({ ...filters, page: page - 1, size: PAGE_SIZE })}`);
      if (r.ok) desk = { view, filters, page, data: r.data }; else problem = r.problem;
    } else if (view === "students") {
      const filters = pickFilters(sp, ROSTER_PARAMS);
      const [r, structure] = await Promise.all([
        api<SummerRosterView>(`${base}/students?${queryString({ ...filters, page: page - 1, size: PAGE_SIZE })}`),
        api<ScopeStructure>("/api/v1/ref/structure"),
      ]);
      if (r.ok) desk = { view, filters, page, org: orgFromStructure(structure.ok ? structure.data : null), data: r.data }; else problem = r.problem;
    } else if (view === "reports") {
      const filters = pickFilters(sp, REPORT_PARAMS);
      const [r, structure] = await Promise.all([
        api<SummerReportView>(`${base}/report?${queryString(filters)}`),
        api<ScopeStructure>("/api/v1/ref/structure"),
      ]);
      if (r.ok) desk = { view, filters, org: orgFromStructure(structure.ok ? structure.data : null), data: r.data }; else problem = r.problem;
    } else if (view === "courses") {
      const r = await api<SummerCourseRow[]>(`${base}/courses`);
      if (r.ok) desk = { view, data: r.data }; else problem = r.problem;
    } else {
      // the period's own answer (with the unverified count, read live, and the overrides), the paid courses the registration could not
      // take, and the authorisations to look at again
      const [p, r, toReview] = await Promise.all([
        api<SummerPeriod>(`${base}/period`),
        api<SummerRosterView>(`${base}/students?${queryString({ page: 0, size: 1 })}`),
        maySet ? api<SummerAuthorisationToReview[]>(`${base}/authorisations`) : Promise.resolve(null),
      ]);
      if (!p.ok) problem = p.problem; else if (!r.ok) problem = r.problem;
      desk = {
        view: "period", period: p.ok ? p.data : r.ok ? r.data.period : null, issues: r.ok ? r.data.issues ?? [] : [],
        toReview: toReview && toReview.ok ? toReview.data : [],
      };
    }
  }
  return (
    <Shell route="t/summer" me={me.ok ? me.data : null}>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <SummerDesk periods={periods.data} session={session} sessions={sessions.map((s) => s.name)} view={view} maySet={maySet} actingOffice={office} desk={desk} />
    </Shell>
  );
}
