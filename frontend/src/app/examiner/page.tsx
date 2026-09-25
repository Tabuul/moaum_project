import Link from "next/link";
import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { LinkBtn, Note, PageHead, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ExaminerPil, RecommendationPil, StatusPil, daysWords, dayOf, when, type Appointment, type ExaminerRow, type MyAssignment } from "@/lib/examiners";

export const dynamic = "force-dynamic";

interface Workspace extends ExaminerRow {
  appointments: Appointment[];
  counts: { assigned: number; not_started: number; in_review: number; pending: number; submitted: number; overdue: number };
  recent: MyAssignment[]; upcoming: MyAssignment[]; submitted_list?: MyAssignment[]; submitted: number;
}

/** x/dashboard — the external examiner's workspace: what is assigned, what is due, what has gone in */
export default async function ExaminerDashboardPage() {
  const [me, w] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Workspace & { submitted: MyAssignment[] | number }>("/api/v1/examiners/me")]);
  if (!w.ok) return <Shell route="x/dashboard" me={me.ok ? me.data : null}><ProblemNotice problem={w.problem} /></Shell>;
  const d = w.data;
  const c = d.counts;
  const n = (v: number | null | undefined) => Number(v ?? 0);
  const submittedList = Array.isArray(d.submitted) ? (d.submitted as MyAssignment[]) : [];
  const row = (a: MyAssignment) => [
    <span key="t"><Link className="lnk b600" href={`/examiner/projects/${a.id}`}>{a.title}</Link><div className="sub2">{a.student} · {a.number}</div></span>,
    <span key="p" className="sub2">{a.programme}<div>{a.department}</div></span>,
    <StatusPil key="s" status={a.status} />,
    <span key="d" className={`tnum${a.overdue ? " ink-red b600" : ""}`}>{dayOf(a.deadline)}<div className="sub2">{daysWords(a.days_left, a.status)}</div></span>,
    <LinkBtn key="o" href={`/examiner/projects/${a.id}`} kind={a.status === "ASSIGNED" ? "primary" : "ghost"} size="sm">{a.status === "ASSIGNED" ? "Start Review" : a.status === "IN_REVIEW" || a.status === "REOPENED" ? "Continue" : "View"}</LinkBtn>,
  ];
  return (
    <Shell route="x/dashboard" me={me.ok ? me.data : null}>
      <PageHead eyebrow="External Examiner" title={`Welcome, ${d.name}`} description={`${d.institution}${d.appointments.length ? ` · appointed for ${d.appointments.map((a) => `${a.department} (${a.session})`).join("; ")}` : ""}`}
        actions={<><LinkBtn kind="primary" href="/examiner/projects?filter=pending">Pending Reviews</LinkBtn><LinkBtn href="/examiner/profile">My Profile</LinkBtn></>} />
      <Tiles items={[
        ["Assigned projects", String(n(c.assigned)), null, "In your workspace", "/examiner/projects"],
        ["Pending reviews", String(n(c.pending)), n(c.pending) ? "var(--amber-ink)" : null, `${n(c.not_started)} not started · ${n(c.in_review)} in review`, "/examiner/projects?filter=pending"],
        ["Submitted", String(n(c.submitted)), null, "Read-only unless the University reopens one", "/examiner/projects?filter=submitted"],
        ["Overdue", String(n(c.overdue)), n(c.overdue) ? "var(--red-ink)" : null, n(c.overdue) ? "Past the review deadline" : "Nothing overdue"],
      ]} />
      {n(c.overdue) ? <Note kind="bad" title={`${n(c.overdue)} review${n(c.overdue) === 1 ? " is" : "s are"} past the deadline`} action={<LinkBtn kind="primary" href="/examiner/projects?filter=pending">Open Them</LinkBtn>}>Please submit as soon as you can, or write to the Academic Office if you need more time.</Note> : null}
      <Panel title="Upcoming deadlines" right="Pending reviews, the soonest first">
        {d.upcoming.length ? <DTable pageSize={0} cols={["Project", "Programme", "Status|mid", "Deadline|mid", "|num"]} rows={d.upcoming.map(row)} /> : <PBody><div className="sub2">Nothing pending. New assignments appear here as the University sends them.</div></PBody>}
      </Panel>
      <div className="grid grid--2">
        <Panel title="Recent assignments" right="The latest five">
          {d.recent.length ? <DTable pageSize={0} cols={["Project", "Programme", "Status|mid", "Deadline|mid", "|num"]} rows={d.recent.map(row)} /> : <PBody><div className="sub2">No project has been assigned to you yet.</div></PBody>}
        </Panel>
        <Panel title="Recently submitted" right="Your last five assessments">
          {submittedList.length ? (
            <DTable pageSize={0} cols={["Project", "Total|mid", "Recommendation|mid", "Submitted|mid"]} rows={submittedList.map((a) => [
              <span key="t"><Link className="lnk b600" href={`/examiner/projects/${a.id}`}>{a.title}</Link><div className="sub2">{a.student}</div></span>,
              <span key="n" className="tnum">{a.total != null ? `${a.total} / ${a.max_total}` : "—"}{a.grade ? <div className="sub2">{a.percentage}% · {a.grade}</div> : null}</span>,
              <RecommendationPil key="r" value={a.final_recommendation} />,
              <span key="s" className="tnum sub2">{when(a.submitted_at)}</span>,
            ])} />
          ) : <PBody><div className="sub2">Nothing submitted yet.</div></PBody>}
        </Panel>
      </div>
      <Panel title="Your appointment" right={<ExaminerPil status={d.status} />}>
        {d.appointments.length ? (
          <DTable pageSize={0} cols={["Session", "Department", "Programme", "From|mid", "To|mid"]} rows={d.appointments.map((a) => [
            <span key="s" className="tnum">{a.session}</span>, <span key="d">{a.department}<div className="sub2">{a.faculty}</div></span>, <span key="p" className="sub2">{a.programme ?? "Every programme of the department"}</span>,
            <span key="f" className="tnum">{dayOf(a.starts_on)}</span>, <span key="t" className="tnum">{dayOf(a.ends_on)}</span>,
          ])} />
        ) : <PBody><div className="sub2">No appointment period is on record yet; the University records it when it issues the letter.</div></PBody>}
      </Panel>
    </Shell>
  );
}
