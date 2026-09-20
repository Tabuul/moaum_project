import Link from "next/link";
import type { Me } from "@/components/proto/Shell";
import { Note, Panel, PBody, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Bar } from "@/components/proto/blocks";

export interface DeanHome {
  resolved: boolean;
  faculty?: string; facultyName?: string; session?: string; students?: number;
  byDept?: { code: string; name: string; students: number; registered: number }[];
  pipeline?: { entry: number; workflow: number; senate: number; published: number };
  offeringsTotal?: number; offeringsNeedLecturer?: number; probation?: number;
  atRisk?: { name: string; number: string; programme: string; level: number }[];
}

/** The faculty home, scoped to one faculty: registration by department, the result pipeline, offerings
 *  without a lecturer, and the students at risk. Serves the Dean (academic head) and the Faculty Officer
 *  (administrative head) — same faculty view, labelled by `role`. */
export function DeanDashboard({ me, home, role = "Dean" }: { me: Me | null; home: DeanHome | null; role?: string }) {
  if (!home || !home.resolved) {
    return (
      <Note kind="bad" title={`Your ${role} office is not tied to a faculty yet`}>
        This dashboard is scoped to your faculty, and the portal cannot tell which one this office holds. Ask the
        Registry to set the faculty on your {role} assignment, then this fills in.
      </Note>
    );
  }
  const dept = home.byDept ?? [];
  const pipe = home.pipeline ?? { entry: 0, workflow: 0, senate: 0, published: 0 };
  const atRisk = home.atRisk ?? [];
  const students = home.students ?? 0;
  const registered = dept.reduce((n, d) => n + d.registered, 0);
  const needLect = home.offeringsNeedLecturer ?? 0;
  return (
    <>
      {needLect ? (
        <Note kind="info" title={`${needLect} offering${needLect === 1 ? " has" : "s have"} no lecturer across ${home.facultyName}`} action={<Link href="/allocate" className="btn btn--primary btn--sm">Teaching allocation</Link>}>
          A score sheet opens only once a lecturer is allocated. The departments below carry the gaps; a Head of Department allocates within each.
        </Note>
      ) : (
        <Note kind="ok" title={`${home.facultyName} is staffed for ${home.session}`} action={<Link href="/results/broadsheet" className="btn btn--ghost btn--sm">Faculty broadsheet</Link>}>
          Every offering has a lecturer. Registration and results progress by department below.
        </Note>
      )}

      <Tiles items={[
        ["Students in the faculty", students.toLocaleString(), null, `${dept.length} department${dept.length === 1 ? "" : "s"}`],
        ["Registered this session", registered.toLocaleString(), null, students ? `${Math.round((100 * registered) / students)}% · ${home.session}` : String(home.session)],
        ["Offerings without a lecturer", String(needLect), needLect ? "var(--chrome)" : "var(--green-ink)", `${(home.offeringsTotal ?? 0) - needLect} of ${home.offeringsTotal ?? 0} allocated`],
        ["On probation", String(home.probation ?? 0), (home.probation ?? 0) ? "var(--red-ink)" : "var(--green-ink)", "Across the faculty"],
      ]} />

      <Panel title="Registration, by department" right={String(home.session)}>
        {dept.length ? (
          <DTable cols={["Department", "Students|mid", "Registered|mid", "Progress|num"]}
            rows={dept.map((d) => [
              <span key="d">{d.name}</span>,
              <span className="tnum" key="s">{d.students.toLocaleString()}</span>,
              <span className="tnum" key="r">{d.registered.toLocaleString()}</span>,
              <Bar key="p" pct={d.students ? Math.round((100 * d.registered) / d.students) : 0} colour={d.students && d.registered / d.students < 0.75 ? "var(--red)" : "var(--green)"} />,
            ])} />
        ) : <PBody><div className="sub2">No student is on the register in {home.facultyName} yet.</div></PBody>}
      </Panel>

      <Panel title="Result pipeline" right={`${home.facultyName} · ${home.session}`}>
        <Tiles cls="grid--4" items={[
          ["With lecturers", String(pipe.entry), pipe.entry ? "var(--red-ink)" : "var(--green-ink)", "Marks not submitted"],
          ["In the approval chain", String(pipe.workflow), pipe.workflow ? "var(--chrome)" : null, "Dept → Faculty → Records"],
          ["Awaiting Senate", String(pipe.senate), pipe.senate ? "var(--chrome)" : null, "Ready for the minute"],
          ["Published", String(pipe.published), "var(--green-ink)", "Released to students"],
        ]} />
      </Panel>

      <div className="grid--2" style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(320px,1fr))", gap: 14 }}>
        <Panel title="At-risk students" right={`${home.probation ?? 0} on probation`}>
          {atRisk.length ? (
            <DTable cols={["Student", "Programme", "Level|num"]}
              rows={atRisk.map((a) => [
                <Two key="s" a={a.name} b={a.number} />,
                <span className="sub2" key="p">{a.programme}</span>,
                <span className="tnum" key="l">{a.level}</span>,
              ])} />
          ) : <PBody><div className="sub2">No student in {home.facultyName} is on probation.</div></PBody>}
        </Panel>

        <Panel title="Faculty desks" right="Scoped to your faculty">
          <PBody>
            <div style={{ display: "grid", gap: 8, gridTemplateColumns: "repeat(auto-fill, minmax(200px, 1fr))" }}>
              <Link href="/results/broadsheet" className="btn btn--ghost btn--sm">Broadsheet</Link>
              <Link href="/results/desk" className="btn btn--ghost btn--sm">Result desk</Link>
              <Link href="/results/approvals" className="btn btn--ghost btn--sm">Approvals</Link>
              <Link href="/allocate" className="btn btn--ghost btn--sm">Teaching allocation</Link>
              <Link href="/students" className="btn btn--ghost btn--sm">Students</Link>
              <Link href="/catalogue" className="btn btn--ghost btn--sm">Courses</Link>
            </div>
            <div className="sub2" style={{ marginTop: 8 }}>You are acting as {role} of {home.facultyName}.{me?.name ? ` Signed in as ${me.name}.` : ""}</div>
          </PBody>
        </Panel>
      </div>
    </>
  );
}
