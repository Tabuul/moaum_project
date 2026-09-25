import Link from "next/link";
import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { LinkBtn, PageHead, Panel, PBody } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { RecommendationPil, StatusPil, daysWords, dayOf, type MyAssignment } from "@/lib/examiners";

export const dynamic = "force-dynamic";

/** x/projects — the examiner's assigned projects: all, pending, or submitted */
export default async function MyProjectsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const filter = typeof p.filter === "string" && ["pending", "submitted"].includes(p.filter) ? p.filter : "";
  const [me, list] = await Promise.all([api<Me>("/api/v1/iam/me"), api<MyAssignment[]>(`/api/v1/examiners/me/projects${filter ? `?filter=${filter}` : ""}`)]);
  const route = filter === "pending" ? "x/pending" : filter === "submitted" ? "x/submitted" : "x/projects";
  const title = filter === "pending" ? "Pending Reviews" : filter === "submitted" ? "Submitted Reviews" : "My Assigned Projects";
  return (
    <Shell route={route} me={me.ok ? me.data : null}>
      <PageHead eyebrow="External Examiner" title={title} description={filter === "pending" ? "Assessments not yet submitted, the soonest deadline first." : filter === "submitted" ? "Assessments you have submitted; read-only unless the University reopens one." : "Every project the University has sent you, with where each review stands."}
        actions={<>
          <LinkBtn kind={!filter ? "primary" : "ghost"} href="/examiner/projects">All</LinkBtn>
          <LinkBtn kind={filter === "pending" ? "primary" : "ghost"} href="/examiner/projects?filter=pending">Pending</LinkBtn>
          <LinkBtn kind={filter === "submitted" ? "primary" : "ghost"} href="/examiner/projects?filter=submitted">Submitted</LinkBtn>
        </>} />
      {!list.ok ? <ProblemNotice problem={list.problem} /> : (
        <Panel title={title} right={`${list.data.length} project${list.data.length === 1 ? "" : "s"}`}>
          {list.data.length ? (
            <DTable cols={["Candidate", "Project title", "Programme", "Supervisor", "Session|mid", "Submitted|mid", "Deadline|mid", "Status|mid", "|num"]} rows={list.data.map((a) => [
              <span key="c"><strong>{a.student}</strong><div className="sub2 tnum">{a.number}</div></span>,
              <span key="t"><Link className="lnk" href={`/examiner/projects/${a.id}`}>{a.title}</Link>{a.documents ? <div className="sub2">{a.documents} document{a.documents === 1 ? "" : "s"}</div> : <div className="sub2 ink-red">No documents released yet</div>}</span>,
              <span key="p" className="sub2">{a.programme}<div>{a.department}</div></span>,
              <span key="sv" className="sub2">{a.supervisor ?? "—"}</span>,
              <span key="s" className="tnum">{a.session}</span>,
              <span key="sub" className="tnum sub2">{dayOf(a.submitted_on)}</span>,
              <span key="d" className={`tnum${a.overdue ? " ink-red b600" : ""}`}>{dayOf(a.deadline)}<div className="sub2">{daysWords(a.days_left, a.status)}</div></span>,
              <span key="st"><StatusPil status={a.status} />{a.final_recommendation ? <div className="mt-1"><RecommendationPil value={a.final_recommendation} /></div> : null}</span>,
              <LinkBtn key="o" href={`/examiner/projects/${a.id}`} kind={a.status === "ASSIGNED" ? "primary" : "ghost"} size="sm">{a.status === "ASSIGNED" ? "Start Review" : a.status === "IN_REVIEW" || a.status === "REOPENED" ? "Continue Review" : "View Assessment"}</LinkBtn>,
            ])} texts={list.data.map((a) => `${a.student} ${a.number} ${a.title} ${a.programme} ${a.status}`)} />
          ) : <PBody><div className="sub2">{filter === "pending" ? "Nothing pending." : filter === "submitted" ? "Nothing submitted yet." : "No project has been assigned to you yet."}</div></PBody>}
        </Panel>
      )}
    </Shell>
  );
}
