import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { Note } from "@/components/proto/ui";
import { PAGE_SIZE, listQuery, type ApplicationList as List } from "@/lib/transfer-application";
import type { SessionRow } from "@/lib/sessions";
import { ApplicationList } from "@/app/transfers/inter-university/applications/ApplicationList";

export const dynamic = "force-dynamic";

const SESSION = /^\d{4}\/\d{4}$/;
const one = (v: string | string[] | undefined) => (typeof v === "string" ? v : null);
/** what reaches the department: from the Registry's check onwards */
const DESK_STATES = ["WITH_HOD", "RECOMMENDED", "NOT_RECOMMENDED", "APPROVED", "ADMITTED", "REJECTED", "WITHDRAWN"];

/** t/iuthod — V766: the transfer applicants from other universities who have reached the department — the Head of Department's own
 *  department, or for a College Dean (V734) the departments of the College's faculty; the API scopes them. Those waiting for a
 *  recommendation first (?state=WITH_HOD, the default; ?state= every state). Every session unless one is asked. */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const asked = SESSION.test(one(sp.session) ?? "") ? one(sp.session) : null;
  const st = one(sp.state);
  // the waiting ones by default; "every state" is asked for with an empty state
  const state = st && DESK_STATES.includes(st) ? st : sp.state !== undefined ? null : "WITH_HOD";
  const filters = { session: asked, state, programme: one(sp.programme), q: one(sp.q), page: /^\d{1,5}$/.test(one(sp.page) ?? "") ? Number(one(sp.page)) : 0 };
  const [me, sessions, list] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<SessionRow[]>("/api/v1/ref/sessions"),
    api<List>(`/api/v1/transfer-applications/office/applications?${listQuery({ ...filters, size: PAGE_SIZE })}`),
  ]);
  const programmes = list.ok ? list.data.rows.reduce<{ code: string; name: string }[]>((out, r) => {
    if (r.programme && !out.some((p) => p.code === r.programme)) out.push({ code: r.programme, name: r.programmeName ?? r.programme });
    return out;
  }, []) : [];
  return (
    <Shell route="t/iuthod" me={me.ok ? me.data : null} sub={asked ?? "Every session"}>
      <Note kind="info" title="Students of other universities applying to your department">
        The Registry has checked each applicant&rsquo;s documents before the application reaches you. Open an application to read the transcript and the other
        documents, then recommend a level the window opens for the programme, or decline with a reason. The Registry decides after you; the applicant is not told
        your recommendation.
      </Note>
      <ApplicationList data={list.ok ? list.data : null} problem={list.ok ? null : list.problem} filters={filters} sessions={sessions.ok ? sessions.data.map((s) => s.name) : []}
        programmes={programmes} path="/hod/transfer-applications" states={DESK_STATES} />
    </Shell>
  );
}
