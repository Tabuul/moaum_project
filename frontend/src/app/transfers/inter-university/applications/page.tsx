import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { currentSession, type SessionRow } from "@/lib/sessions";
import { PAGE_SIZE, listQuery, officeProgramme, type ApplicationList, type DocumentKind, type WindowView } from "@/lib/transfer-application";
import { TransferApplications, type Tab } from "./TransferApplications";

export const dynamic = "force-dynamic";

const OFFICE = "/api/v1/transfer-applications/office";
const SESSION = /^\d{4}\/\d{4}$/;
const one = (v: string | string[] | undefined) => (typeof v === "string" ? v : null);

/** t/iutapps — V766: the Registry's desk for the online inter-university transfer applications: ?tab= applications (the default),
 *  window (the Academic Office's window and its programmes) or documents (the documents asked); ?session= the session (by default the
 *  one the API's window answers for: the open window's, else the latest session with applications on the desks' hands — a closed
 *  window keeps its desk work, a window being prepared for the next session does not take the desks off it — else the latest set
 *  open, else the University's current session; ?all=1 every session), ?state=, ?programme=, ?q= and ?page= the list's filters. */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const tab: Tab = one(sp.tab) === "window" ? "window" : one(sp.tab) === "documents" ? "documents" : "applications";
  const asked = SESSION.test(one(sp.session) ?? "") ? one(sp.session) : null;
  const [me, sessionsRes, windowRes] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<SessionRow[]>("/api/v1/ref/sessions"),
    api<WindowView>(`${OFFICE}/window${asked ? `?session=${encodeURIComponent(asked)}` : ""}`),
  ]);
  const sessions = sessionsRes.ok ? sessionsRes.data : [];
  const session = asked ?? (one(sp.all) === "1" ? null : windowRes.ok ? windowRes.data.session : currentSession(sessions));
  const state = one(sp.state);
  const filters = { session, state: state && /^[A-Z_]{4,30}$/.test(state) ? state : null, programme: one(sp.programme), q: one(sp.q),
    page: /^\d{1,5}$/.test(one(sp.page) ?? "") ? Number(one(sp.page)) : 0 };
  const [list, programmes, kinds] = await Promise.all([
    tab === "applications" ? api<ApplicationList>(`${OFFICE}/applications?${listQuery({ ...filters, size: PAGE_SIZE })}`) : null,
    tab === "window" ? api<Record<string, unknown>[]>(`${OFFICE}/programmes`) : null,
    tab === "documents" ? api<DocumentKind[]>(`${OFFICE}/document-kinds`) : null,
  ]);
  return (
    <Shell route="t/iutapps" me={me.ok ? me.data : null} sub={session ?? "Every session"}>
      <TransferApplications tab={tab} filters={filters}
        list={list && list.ok ? list.data : null} listProblem={list && !list.ok ? list.problem : null}
        windowView={windowRes.ok ? windowRes.data : null} windowProblem={windowRes.ok ? null : windowRes.problem}
        programmes={programmes && programmes.ok && Array.isArray(programmes.data) ? programmes.data.map(officeProgramme).filter((p) => p.code) : []}
        kinds={kinds && kinds.ok ? kinds.data : null} kindsProblem={kinds && !kinds.ok ? kinds.problem : null}
        sessions={sessions} office={me.ok ? me.data.activeOffice : null} />
    </Shell>
  );
}
