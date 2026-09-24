import type { Me } from "@/components/proto/Shell";
import { LinkBtn, Note, Panel, PBody, Tiles, Two } from "@/components/proto/ui";
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

/** The faculty (or College) home, scoped to one unit: registration by department, the result pipeline,
 *  offerings without a lecturer, and the students at risk. Serves the Dean and Faculty Officer at faculty
 *  scope, and the Provost and College Secretary at College scope — same view, labelled by `role` and
 *  `scopeNoun`. When `scopeNoun` is "college", the `faculty`/`facultyName` fields carry the College. */
export function DeanDashboard({ me, home, role = "Dean", scopeNoun = "faculty" }: { me: Me | null; home: DeanHome | null; role?: string; scopeNoun?: string }) {
  const Scope = scopeNoun.charAt(0).toUpperCase() + scopeNoun.slice(1);
  if (!home || !home.resolved) {
    return (
      <Note kind="bad" title={`Your ${role} office is not tied to a ${scopeNoun} yet`}>
        This dashboard is scoped to your {scopeNoun}, and the portal cannot tell which one this office holds. Ask the
        Registry to set the {scopeNoun} on your {role} assignment, then this fills in.
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
        <Note kind="info" title={`${needLect} Course${needLect === 1 ? " has" : "s have"} no Lecturer across ${home.facultyName}`} action={<LinkBtn kind="primary" href="/allocate">Teaching allocation</LinkBtn>}>
          A score sheet opens only once a lecturer is allocated. The departments below carry the gaps; a Head of Department allocates within each.
        </Note>
      ) : (
        <Note kind="ok" title={`${home.facultyName} is staffed for ${home.session}`} action={<LinkBtn kind="ghost" href="/results/broadsheet">{Scope} broadsheet</LinkBtn>}>
          Every course has a lecturer. Registration and results progress by department below.
        </Note>
      )}

      <Tiles items={[
        [`Students in the ${scopeNoun}`, students.toLocaleString(), null, `${dept.length} department${dept.length === 1 ? "" : "s"}`],
        ["Registered this session", registered.toLocaleString(), null, students ? `${Math.round((100 * registered) / students)}% · ${home.session}` : String(home.session)],
        ["Courses without a Lecturer", String(needLect), needLect ? "var(--chrome)" : "var(--green-ink)", `${(home.offeringsTotal ?? 0) - needLect} of ${home.offeringsTotal ?? 0} allocated`],
        ["On probation", String(home.probation ?? 0), (home.probation ?? 0) ? "var(--red-ink)" : "var(--green-ink)", `Across the ${scopeNoun}`],
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

      <div className="grid grid--2">
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

        <Panel title={`${Scope} desks`} right={`Scoped to your ${scopeNoun}`}>
          <PBody>
            <div className="grid--fill">
              <LinkBtn kind="ghost" href="/results/broadsheet">Broadsheet</LinkBtn>
              <LinkBtn kind="ghost" href="/results/desk">Result desk</LinkBtn>
              <LinkBtn kind="ghost" href="/results/approvals">Approvals</LinkBtn>
              <LinkBtn kind="ghost" href="/allocate">Teaching allocation</LinkBtn>
              <LinkBtn kind="ghost" href="/students">Students</LinkBtn>
              <LinkBtn kind="ghost" href="/catalogue">Courses</LinkBtn>
            </div>
            <div className="sub2 mt-2">You are acting as {role} of {home.facultyName}.{me?.name ? ` Signed in as ${me.name}.` : ""}</div>
          </PBody>
        </Panel>
      </div>
    </>
  );
}
