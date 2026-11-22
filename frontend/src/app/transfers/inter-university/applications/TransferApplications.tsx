"use client";

/** V766: the Registry's desk for the online inter-university transfer applications (t/iutapps) — the applications of a session by state,
 *  the Academic Office's window with its programmes and levels, and the documents asked. Each application opens on its own page, where
 *  the documents are checked, the application sent to the Head of Department, and approved into the V588/V763 transfer that another
 *  officer decides on the Inter-University Transfer page. */
import { useQueryNav } from "@/lib/query-nav";
import { LinkBtn, Note, Tabs } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Problem } from "@/lib/api";
import type { ApplicationList as List, DocumentKind, OfficeProgramme, WindowView } from "@/lib/transfer-application";
import { ApplicationList, type ListFilters } from "./ApplicationList";
import { WindowPanel } from "./WindowPanel";
import { KindsPanel } from "./KindsPanel";

export type Tab = "applications" | "window" | "documents";
const PATH = "/transfers/inter-university/applications";

export function TransferApplications({ tab, filters, list, listProblem, windowView, windowProblem, programmes, kinds, kindsProblem, sessions, office }: {
  tab: Tab; filters: ListFilters; list: List | null; listProblem: Problem | null; windowView: WindowView | null; windowProblem: Problem | null;
  programmes: OfficeProgramme[]; kinds: DocumentKind[] | null; kindsProblem: Problem | null; sessions: { name: string; state: string }[]; office: string | null;
}) {
  const go = useQueryNav();
  const session = filters.session ?? windowView?.session ?? null;
  const tabHref = (t: Tab) => `${PATH}?${new URLSearchParams({ tab: t, ...(session ? { session } : {}) })}`;
  const lineProgrammes = (windowView?.lines ?? []).reduce<{ code: string; name: string }[]>((out, l) => {
    if (!out.some((p) => p.code === l.programme)) out.push({ code: l.programme, name: l.programmeName ?? l.programme });
    return out;
  }, []);
  return (
    <>
      <Note kind="info" title="Students of other universities who apply online"
        action={<LinkBtn kind="ghost" href="/transfers/inter-university">Inter-University Transfer</LinkBtn>}>
        A student of another university applies at /transfer/apply while the window below is open, pays the application fee and uploads the documents asked. The
        Registry checks each document, then sends the application to the Head of Department of the programme, who recommends a level or declines with a reason.
        The Registry approves a recommended application into a transfer of one, which another officer of the Academic Office or the Registry decides on the
        Inter-University Transfer page; the applicant is admitted at that decision.
      </Note>
      <Tabs label="Transfer applications" value={tab} onChange={(t) => go(tabHref(t))} items={[
        { id: "applications", label: "Applications", count: list?.total },
        { id: "window", label: "Window and programmes", count: windowView?.lines?.length },
        { id: "documents", label: "Documents asked", count: kinds?.filter((k) => k.active !== false).length },
      ]} />
      {tab === "applications" ? (
        <ApplicationList data={list} problem={listProblem} filters={filters} sessions={sessions.map((s) => s.name)} programmes={lineProgrammes} path={PATH} />
      ) : tab === "window" ? (
        windowView ? <WindowPanel key={`${windowView.session}:${windowView.setAt ?? ""}`} view={windowView} programmes={programmes} sessions={sessions} office={office}
          onSession={(s) => go(`${PATH}?${new URLSearchParams({ tab: "window", session: s })}`)} />
          : windowProblem ? <ProblemNotice problem={windowProblem} /> : null
      ) : (
        kinds ? <KindsPanel kinds={kinds} office={office} /> : kindsProblem ? <ProblemNotice problem={kindsProblem} /> : null
      )}
    </>
  );
}
