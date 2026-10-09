/** rHod — the Head of Department's home, scoped to their own department: what waits on them
 *  (registrations to approve, offerings without a lecturer) and the size of the department. */
import Link from "next/link";
import { ScopeNotice } from "@/components/ScopeNotice";
import type { OfficeScopeState } from "@/lib/office-scope";
import type { Me } from "@/components/proto/Shell";
import type { Problem } from "@/lib/api";
import { ProblemNotice } from "@/components/ProblemNotice";
import { LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { StatsPanel } from "@/components/stats/StatsPanel";
import { DTable } from "@/components/proto/DTable";
import { FeeCount } from "./HodFeeDownloads";
import { AllocationHistory, type AllocationRow } from "./AllocationHistory";
import { semesterName } from "@/lib/student-portal";
import type { PipelineView } from "@/lib/results";
import { PipelinePanel } from "@/components/results/PipelinePanel";

export interface HodHome {
  resolved: boolean;
  dept?: string;
  deptName?: string;
  session?: string;
  approvals?: number;
  /** V380: the department's CCE students register in the CCE session; their submitted registrations wait here too */
  cceApprovals?: { session: string | null; count: number } | null;
  openQueries?: number;
  offeringsNeedLecturer?: number;
  offeringsTotal?: number;
  /** the department's students by curriculum track, with each track's expected end (V235) */
  tracks?: { code: string; label: string; framework: string; expected_end_session: string | null; students: number }[];
  deptStudents?: number;
  deptCourses?: number;
  sheetsPending?: number;
  siwesUnsupervised?: number;
  needLecturer?: { code: string; title: string; level: number; semester: number }[];
  pipeline?: { entry: number; workflow: number; senate: number; published: number };
  atRisk?: { name: string; number: string; level: number; status: string }[];
  probation?: number;
  carryoverStudents?: number;
  lecturers?: { name: string; courses: number; candidates: number }[];
  feesCleared?: number | null;
  feesOwing?: number | null;
  /** the figures that could not be read, with the database's reason; the rest of the dashboard stands */
  unavailable?: Record<string, string>;
}

const FIGURE: Record<string, string> = {
  approvals: "registrations to approve", openQueries: "result queries", offeringsNeedLecturer: "courses without a lecturer", offeringsTotal: "courses offered",
  deptStudents: "students", deptCourses: "courses in the catalogue", sheetsPending: "result sheets in progress", siwesUnsupervised: "SIWES supervision",
  needLecturer: "the courses still needing a lecturer", pipeline: "the result pipeline", atRisk: "at-risk students", probation: "students on probation",
  carryoverStudents: "students carrying a course", lecturers: "lecturers and teaching load", feesCleared: "fees cleared and owing", tracks: "students by curriculum track",
};

export function HodDashboard({ me, home, homeProblem = null, requestsOpen, history = [], pipeline = null, scope = null }: { me: Me | null; home: HodHome | null; homeProblem?: Problem | null; requestsOpen: number | null; history?: AllocationRow[]; pipeline?: PipelineView | null; scope?: OfficeScopeState | null }) {
  /* the scope is the cause only when the scope says so, or the server says the office resolved to no department */
  if (scope && !scope.resolved) return <ScopeNotice scope={scope} />;
  if (home && !home.resolved) {
    return (
      <Note kind="bad" title="Your Head-of-Department office is not tied to a department yet">
        The dashboard is scoped to your department, and the portal cannot tell which one this office holds. Ask the
        Registry to set the department on your Head-of-Department assignment, then this fills in.
      </Note>
    );
  }
  if (!home) {
    /* the department is known; the dashboard's figures could not be read — say what went wrong, and keep the desks open */
    return (
      <>
        <Note kind="bad" title="The department's figures could not be read just now">
          Your office is tied to {scope?.name ?? scope?.code ?? "your department"} and every department desk works as usual; only this
          dashboard&rsquo;s summary did not load. Reload the page; if it persists, send the reference below to the Directorate of ICT.
        </Note>
        {homeProblem ? <ProblemNotice problem={homeProblem} /> : null}
        <Panel title="Your department desks" right="Everything scoped to your department">
          <PBody><div className="row">
            <LinkBtn kind="ghost" href="/results/approvals">Registration approvals</LinkBtn>
            <LinkBtn kind="ghost" href="/allocate">Teaching allocation</LinkBtn>
            <LinkBtn kind="ghost" href="/results/desk">Result desk</LinkBtn>
            <LinkBtn kind="ghost" href="/results/broadsheet">Broadsheet</LinkBtn>
            <LinkBtn kind="ghost" href="/catalogue">Department courses</LinkBtn>
            <LinkBtn kind="ghost" href="/siwes">SIWES supervision</LinkBtn>
            <LinkBtn kind="ghost" href="/students">Students</LinkBtn>
            <LinkBtn kind="ghost" href="/clearance">Clearance</LinkBtn>
          </div></PBody>
        </Panel>
      </>
    );
  }
  const missing = Object.entries(home.unavailable ?? {});
  const approvals = home.approvals ?? 0;
  const needLect = home.offeringsNeedLecturer ?? 0;
  const allocated = (home.offeringsTotal ?? 0) - needLect;
  const siwesGap = home.siwesUnsupervised ?? 0;
  const sheets = home.sheetsPending ?? 0;
  const pipe = home.pipeline ?? { entry: 0, workflow: 0, senate: 0, published: 0 };
  const atRisk = home.atRisk ?? [];
  const lecturers = home.lecturers ?? [];
  const feesKnown = home.feesCleared != null && home.feesOwing != null;
  const feesCleared = home.feesCleared ?? 0;
  const feesOwing = home.feesOwing ?? 0;
  const carryovers = home.carryoverStudents ?? 0;
  return (
    <>
      <ScopeNotice scope={scope} />
      {missing.length ? (
        <Note kind="info" title={`${missing.length === 1 ? "One figure" : `${missing.length} figures`} could not be read`}>
          {missing.map(([k, why]) => <div key={k}><b>{FIGURE[k] ?? k}</b>: {why}</div>)}
          <div className="mt-1">The rest of the dashboard is current. A figure that depends on the clearance scheme reads once the Bursary has a scheme in force for the session.</div>
        </Note>
      ) : null}
      <StatsPanel session={home.session} title={`Student statistics · ${home.deptName}`} />
      {home.cceApprovals && home.cceApprovals.count > 0 && home.cceApprovals.session ? (
        <Note kind="bad" title={`${home.cceApprovals.count} CCE course registration${home.cceApprovals.count === 1 ? "" : "s"} waiting for your approval`}
          action={<LinkBtn kind="urgent" href={`/results/approvals?session=${encodeURIComponent(home.cceApprovals.session)}`}>Open the CCE session&rsquo;s approvals</LinkBtn>}>
          Part-time students of the Centre for Continuing Education in {home.deptName}&rsquo;s programmes register in the CCE session, {home.cceApprovals.session}, on the Centre&rsquo;s classes. You approve them as any other registration.
        </Note>
      ) : null}
      {approvals ? (
        <Note kind="bad" title={`${approvals} course registration${approvals === 1 ? "" : "s"} waiting for your approval`}
          action={<LinkBtn kind="urgent" href="/results/approvals">Open approvals</LinkBtn>}>
          Students in {home.deptName} have submitted registrations for {home.session}. They cannot appear on a class list,
          an attendance register or a score sheet until you approve them.
        </Note>
      ) : needLect ? (
        <Note kind="info" title={`${needLect} Course${needLect === 1 ? " has" : "s have"} no Lecturer allocated`}
          action={<LinkBtn kind="primary" href="/allocate">Allocate teaching</LinkBtn>}>
          A score sheet opens only once a lecturer is allocated. Allocate the remaining {home.session} courses so teaching
          and assessment can begin.
        </Note>
      ) : siwesGap ? (
        <Note kind="info" title={`${siwesGap} SIWES student${siwesGap === 1 ? " has" : "s have"} no supervisor assigned`}
          action={<LinkBtn kind="primary" href="/siwes">Assign supervisors</LinkBtn>}>
          The industrial-training students on your register need a supervisor each to be assessed. Assign the remaining
          supervisors on the SIWES supervision desk.
        </Note>
      ) : (
        <Note kind="ok" title={`${home.deptName} is set up for ${home.session}`}
          action={<LinkBtn kind="ghost" href="/allocate">Teaching allocation</LinkBtn>}>
          No registrations are waiting and every course has a lecturer. Nothing is blocking your department right now.
        </Note>
      )}

      <Tiles items={[
        ["Registrations to approve", String(approvals), approvals ? "var(--red-ink)" : "var(--green-ink)", `${home.deptName} · ${home.session}`, "/results/approvals"],
        ["Courses without a Lecturer", String(needLect), needLect ? "var(--chrome)" : "var(--green-ink)", `${allocated} of ${home.offeringsTotal ?? 0} allocated`],
        ["SIWES without a supervisor", String(siwesGap), siwesGap ? "var(--red-ink)" : "var(--green-ink)", "Industrial-training students"],
        ["Result sheets in progress", String(sheets), null, "Not yet published"],
        ["Students", String(home.deptStudents ?? 0), null, "Active in the department"],
        ["Cleared for registration",
          !feesKnown ? "—" : <FeeCount key="c" which="cleared" count={feesCleared} session={home.session ?? ""} deptName={home.deptName ?? ""} />,
          feesOwing ? "var(--chrome)" : "var(--green-ink)",
          !feesKnown ? <span key="o" className="sub2">Not read: {home.unavailable?.feesCleared ?? "the clearance scheme did not answer"}</span> : <span key="o" style={{ display: "block" }}>
            <FeeCount which="owing" count={feesOwing} session={home.session ?? ""} deptName={home.deptName ?? ""} size={22} colour={feesOwing ? "var(--red-ink)" : "var(--green-ink)"} />
            <span style={{ display: "block", marginTop: 2 }}>still owing for {home.session} · press either figure to download its list</span>
          </span>],
        ["Courses", String(home.deptCourses ?? 0), null, "In the department catalogue"],
        ...((home.tracks ?? []).filter((t) => t.code === "BMAS").map((t) => [
          "BMAS students remaining", String(Number(t.students)), Number(t.students) ? "var(--chrome)" : "var(--green-ink)",
          Number(t.students) ? `BMAS courses stay offered until the last has gone · expected end ${t.expected_end_session ?? "—"}` : "BMAS has run its course in this department",
        ] as [string, string, string, string])),
        ...(home.openQueries ? [["Result queries", String(home.openQueries), "var(--chrome)", "Awaiting your department", "/results/queries"] as [string, string, string, string, string]] : []),
        ...(requestsOpen ? [["Student requests", String(requestsOpen), "var(--chrome)", "Open, to your office"] as [string, string, string, string]] : []),
      ]} />

      <div className="grid grid--2">
        <Panel title="Courses still needing a Lecturer" right={needLect ? `${needLect} to allocate` : "All allocated"}>
          {home.needLecturer && home.needLecturer.length ? (
            <DTable
              cols={["Course|mid", "Title", "Level|num", "Semester|mid"]}
              rows={home.needLecturer.map((o) => [
                <span className="tnum" key="c">{o.code}</span>,
                <span className="sub2" key="t">{o.title}</span>,
                <span className="tnum" key="l">{o.level}</span>,
                <span key="s">{semesterName(o.semester)}</span>,
              ])}
            />
          ) : <PBody><div className="sub2">Every course this session has a lecturer. There is nothing to allocate.</div></PBody>}
        </Panel>

        <Panel title="Your department desks" right="Everything scoped to your department">
          <PBody>
            <div className="row">
              <LinkBtn kind="ghost" href="/results/approvals">Registration approvals{approvals ? ` (${approvals})` : ""}</LinkBtn>
              <LinkBtn kind="ghost" href="/allocate">Teaching allocation</LinkBtn>
              <LinkBtn kind="ghost" href="/results/desk">Result desk</LinkBtn>
              <LinkBtn kind="ghost" href="/results/broadsheet">Broadsheet</LinkBtn>
              <LinkBtn kind="ghost" href="/catalogue">Department courses</LinkBtn>
              <LinkBtn kind="ghost" href="/siwes">SIWES supervision</LinkBtn>
              <LinkBtn kind="ghost" href="/students">Students</LinkBtn>
              <LinkBtn kind="ghost" href="/clearance">Clearance</LinkBtn>
              {requestsOpen ? <LinkBtn kind="ghost" href="/support">Student requests ({requestsOpen})</LinkBtn> : null}
            </div>
            <div className="sub2 mt-3">You are acting as Head of {home.deptName}. Every screen above shows only your department.</div>
          </PBody>
        </Panel>
      </div>

      <AllocationHistory rows={history} mode="department" session={home.session ?? ""} />

      {pipeline ? (
        /* V318: the department's result pipeline as the monitor reads it — every stage a real count and a link, the coverage
           counted from the rolls, what waits at the Departmental Board, and every programme and level's live broadsheet */
        <PipelinePanel view={pipeline} title={`Result pipeline · ${home.deptName} · ${home.session}`} />
      ) : (
        <Panel title="Result pipeline" right={`${sheets} sheet${sheets === 1 ? "" : "s"} not yet published`}>
          <Tiles cls="grid--4" items={[
            ["With lecturers (Entry)", String(pipe.entry), pipe.entry ? "var(--red-ink)" : "var(--green-ink)", "Marks not yet submitted", "/results/desk"],
            ["In the approval chain", String(pipe.workflow), pipe.workflow ? "var(--chrome)" : null, "Dept → Faculty → Records", "/results/desk"],
            ["Awaiting Senate", String(pipe.senate), pipe.senate ? "var(--chrome)" : null, "Ready for the minute"],
            ["Published", String(pipe.published), "var(--green-ink)", "Released to students"],
          ]} />
        </Panel>
      )}

      <div className="grid grid--2">
        <Panel title="At-risk students" right={`${home.probation ?? 0} on probation · ${carryovers} carrying a course`}>
          {atRisk.length ? (
            <DTable cols={["Student", "Number|mid", "Level|num", "Standing|mid"]}
              rows={atRisk.map((a) => [
                <span key="n">{a.name}</span>,
                <span className="tnum" key="m">{a.number}</span>,
                <span className="tnum" key="l">{a.level}</span>,
                <Pil kind="bad" key="s">Probation</Pil>,
              ])} />
          ) : (
            <PBody><div className="sub2">No student in {home.deptName} is on probation.{carryovers ? ` ${carryovers} student${carryovers === 1 ? "" : "s"} carry a failed course into ${home.session}.` : ""}</div></PBody>
          )}
          {atRisk.length && carryovers ? <PBody><div className="sub2">Also {carryovers} student{carryovers === 1 ? "" : "s"} carrying a failed course. <Link href="/results/broadsheet">See the broadsheet</Link>.</div></PBody> : null}
        </Panel>

        <Panel title="Lecturers & teaching load" right={lecturers.length ? `${lecturers.length} teaching this session` : "None allocated yet"}>
          {lecturers.length ? (
            <DTable cols={["Lecturer", "Courses|num", "Candidates|num"]}
              rows={lecturers.map((l) => [
                <span key="n">{l.name}</span>,
                <span className="tnum" key="c">{l.courses}</span>,
                <span className="tnum" key="s">{l.candidates}</span>,
              ])} />
          ) : (
            <PBody><div className="sub2">No lecturer is allocated a {home.session} course yet. Allocate teaching so load appears here.</div></PBody>
          )}
        </Panel>
      </div>
    </>
  );
}
