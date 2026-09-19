/** rHod — the Head of Department's home, scoped to their own department: what waits on them
 *  (registrations to approve, offerings without a lecturer) and the size of the department. */
import Link from "next/link";
import type { Me } from "@/components/proto/Shell";
import { Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { semesterName } from "@/lib/student-portal";

export interface HodHome {
  resolved: boolean;
  dept?: string;
  deptName?: string;
  session?: string;
  approvals?: number;
  openQueries?: number;
  offeringsNeedLecturer?: number;
  offeringsTotal?: number;
  deptStudents?: number;
  deptCourses?: number;
  sheetsPending?: number;
  siwesUnsupervised?: number;
  needLecturer?: { code: string; title: string; level: number; semester: number }[];
}

export function HodDashboard({ me, home, requestsOpen }: { me: Me | null; home: HodHome | null; requestsOpen: number | null }) {
  if (!home || !home.resolved) {
    return (
      <Note kind="bad" title="Your Head-of-Department office is not tied to a department yet">
        The dashboard is scoped to your department, and the portal cannot tell which one this office holds. Ask the
        Registry to set the department on your Head-of-Department assignment, then this fills in.
      </Note>
    );
  }
  const approvals = home.approvals ?? 0;
  const needLect = home.offeringsNeedLecturer ?? 0;
  const allocated = (home.offeringsTotal ?? 0) - needLect;
  const siwesGap = home.siwesUnsupervised ?? 0;
  const sheets = home.sheetsPending ?? 0;
  return (
    <>
      {approvals ? (
        <Note kind="bad" title={`${approvals} course registration${approvals === 1 ? "" : "s"} waiting for your approval`}
          action={<Link href="/results/approvals" className="btn btn--urgent btn--sm">Open approvals</Link>}>
          Students in {home.deptName} have submitted registrations for {home.session}. They cannot appear on a class list,
          an attendance register or a score sheet until you approve them.
        </Note>
      ) : needLect ? (
        <Note kind="info" title={`${needLect} offering${needLect === 1 ? " has" : "s have"} no lecturer allocated`}
          action={<Link href="/allocate" className="btn btn--primary btn--sm">Allocate teaching</Link>}>
          A score sheet opens only once a lecturer is allocated. Allocate the remaining {home.session} offerings so teaching
          and assessment can begin.
        </Note>
      ) : siwesGap ? (
        <Note kind="info" title={`${siwesGap} SIWES student${siwesGap === 1 ? " has" : "s have"} no supervisor assigned`}
          action={<Link href="/siwes" className="btn btn--primary btn--sm">Assign supervisors</Link>}>
          The industrial-training students on your register need a supervisor each to be assessed. Assign the remaining
          supervisors on the SIWES supervision desk.
        </Note>
      ) : (
        <Note kind="ok" title={`${home.deptName} is set up for ${home.session}`}
          action={<Link href="/allocate" className="btn btn--ghost btn--sm">Teaching allocation</Link>}>
          No registrations are waiting and every offering has a lecturer. Nothing is blocking your department right now.
        </Note>
      )}

      <Tiles items={[
        ["Registrations to approve", String(approvals), approvals ? "var(--red-ink)" : "var(--green-ink)", `${home.deptName} · ${home.session}`],
        ["Offerings without a lecturer", String(needLect), needLect ? "var(--chrome)" : "var(--green-ink)", `${allocated} of ${home.offeringsTotal ?? 0} allocated`],
        ["SIWES without a supervisor", String(siwesGap), siwesGap ? "var(--red-ink)" : "var(--green-ink)", "Industrial-training students"],
        ["Result sheets in progress", String(sheets), null, "Not yet published"],
        ["Students", String(home.deptStudents ?? 0), null, "Active in the department"],
        ["Courses", String(home.deptCourses ?? 0), null, "In the department catalogue"],
        ...(home.openQueries ? [["Result queries", String(home.openQueries), "var(--chrome)", "Awaiting your department", "/results/queries"] as [string, string, string, string, string]] : []),
        ...(requestsOpen ? [["Student requests", String(requestsOpen), "var(--chrome)", "Open, to your office"] as [string, string, string, string]] : []),
      ]} />

      <div className="grid--2" style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(320px,1fr))", gap: 14 }}>
        <Panel title="Offerings still needing a lecturer" right={needLect ? `${needLect} to allocate` : "All allocated"}>
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
          ) : <PBody><div className="sub2">Every offering this session has a lecturer. There is nothing to allocate.</div></PBody>}
        </Panel>

        <Panel title="Your department desks" right="Everything scoped to your department">
          <PBody>
            <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
              <Link href="/results/approvals" className="btn btn--ghost btn--sm">Registration approvals{approvals ? ` (${approvals})` : ""}</Link>
              <Link href="/allocate" className="btn btn--ghost btn--sm">Teaching allocation</Link>
              <Link href="/results/desk" className="btn btn--ghost btn--sm">Result desk</Link>
              <Link href="/results/broadsheet" className="btn btn--ghost btn--sm">Broadsheet</Link>
              <Link href="/catalogue" className="btn btn--ghost btn--sm">Department courses</Link>
              <Link href="/siwes" className="btn btn--ghost btn--sm">SIWES supervision</Link>
              <Link href="/students" className="btn btn--ghost btn--sm">Students</Link>
              <Link href="/clearance" className="btn btn--ghost btn--sm">Clearance</Link>
              {requestsOpen ? <Link href="/support" className="btn btn--ghost btn--sm">Student requests ({requestsOpen})</Link> : null}
            </div>
            <div className="sub2" style={{ marginTop: 10 }}>You are acting as Head of {home.deptName}. Every screen above shows only your department.</div>
          </PBody>
        </Panel>
      </div>
    </>
  );
}
