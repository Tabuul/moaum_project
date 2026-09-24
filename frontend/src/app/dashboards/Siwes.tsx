import type { Me } from "@/components/proto/Shell";
import { LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

export interface SiwesOffering { id: string; course_code: string; title: string; dept_name: string; students: number; assigned: number; sheet_stage: string | null }

/** The SIWES Coordinator's home, scoped to their department: the industrial-training offerings, the
 *  students on them, and how many still need a supervisor to be assessed (V156). */
export function SiwesDashboard({ me, offerings, semester }: { me: Me | null; offerings: SiwesOffering[]; semester: number }) {
  const students = offerings.reduce((n, o) => n + Number(o.students), 0);
  const supervised = offerings.reduce((n, o) => n + Math.min(Number(o.students), Number(o.assigned)), 0);
  const unsupervised = Math.max(0, students - supervised);
  const semLabel = `${semester === 1 ? "First" : semester === 3 ? "Third" : "Second"} semester`;
  return (
    <>
      {!offerings.length ? (
        <Note kind="info" title={`No SIWES course in your department this semester`} action={<LinkBtn kind="primary" href="/siwes">SIWES desk</LinkBtn>}>
          Industrial-training courses appear here once they are offered for the semester. This dashboard shows the second-semester sitting.
        </Note>
      ) : unsupervised ? (
        <Note kind="bad" title={`${unsupervised} SIWES student${unsupervised === 1 ? " has" : "s have"} no supervisor`} action={<LinkBtn kind="urgent" href="/siwes">Assign supervisors</LinkBtn>}>
          A student is assessed by their assigned supervisor; until one is assigned they cannot be scored. Assign the remaining supervisors on the SIWES desk.
        </Note>
      ) : (
        <Note kind="ok" title="Every SIWES student has a supervisor" action={<LinkBtn kind="ghost" href="/siwes">SIWES desk</LinkBtn>}>
          All industrial-training students are assigned. The supervisors&rsquo; and the visit marks combine into the result.
        </Note>
      )}

      <Tiles items={[
        ["SIWES courses", String(offerings.length), null, semLabel],
        ["Students", String(students), null, "On industrial training"],
        ["With a supervisor", String(supervised), "var(--green-ink)", "Assigned"],
        ["Without a supervisor", String(unsupervised), unsupervised ? "var(--red-ink)" : "var(--green-ink)", "To assign", "/siwes"],
      ]} />

      <Panel title="Industrial-training offerings" right={offerings.length ? `${offerings.length} course${offerings.length === 1 ? "" : "s"}` : "None"}>
        {offerings.length ? (
          <DTable cols={["Course", "Department", "Students|mid", "Supervised|num"]}
            rows={offerings.map((o) => {
              const gap = Number(o.students) - Number(o.assigned);
              return [
                <span key="c"><strong className="tnum">{o.course_code}</strong><div className="sub2">{o.title}</div></span>,
                <span className="sub2" key="d">{o.dept_name}</span>,
                <span className="tnum" key="s">{o.students}</span>,
                gap > 0 ? <Pil kind="bad" key="a">{o.assigned} of {o.students}</Pil> : <Pil kind="ok" key="a">{o.assigned} of {o.students}</Pil>,
              ];
            })} texts={offerings.map((o) => `${o.course_code} ${o.title} ${o.dept_name}`)} />
        ) : <PBody><div className="sub2">No industrial-training course this semester.</div></PBody>}
      </Panel>

      <Panel title="SIWES desks" right={me?.name ? `Signed in as ${me.name}` : "SIWES"}>
        <PBody>
          <div className="grid--fill">
            <LinkBtn kind="ghost" href="/siwes">SIWES supervision</LinkBtn>
            <LinkBtn kind="ghost" href="/results/desk">Result desk</LinkBtn>
            <LinkBtn kind="ghost" href="/students">Students</LinkBtn>
          </div>
        </PBody>
      </Panel>
    </>
  );
}
