import Link from "next/link";
import type { Me } from "@/components/proto/Shell";
import { Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

export interface PgHome {
  session: string;
  counts: { total: number; submitted: number; recommended: number; offered: number; accepted: number; admitted: number };
  pgStudents: number;
  byProgramme: { programme_name: string; pg_award: string | null; applications: number; in_progress: number; offered: number; taken: number }[];
}

/** The School of Postgraduate Studies' home (V202): what waits on the School, the postgraduate register,
 *  and the pipeline by programme. Its own desk — separate from the Academic Office. */
export function PgSchoolDashboard({ me, home, role = "School of Postgraduate Studies" }: { me: Me | null; home: PgHome | null; role?: string }) {
  if (!home) {
    return <Note kind="bad" title="The postgraduate figures could not be read">This dashboard reads the postgraduate admissions register; it did not answer.</Note>;
  }
  const c = home.counts;
  const recommended = Number(c.recommended);
  const toAdmit = Number(c.accepted);
  const progs = home.byProgramme ?? [];
  return (
    <>
      {recommended ? (
        <Note kind="info" title={`${recommended} application${recommended === 1 ? "" : "s"} recommended by a department, awaiting the School`} action={<Link href="/admissions/postgraduate" className="btn btn--primary btn--sm">Decide them</Link>}>
          A department&rsquo;s postgraduate committee has recommended these; the School offers or refuses each.
        </Note>
      ) : toAdmit ? (
        <Note kind="ok" title={`${toAdmit} applicant${toAdmit === 1 ? " has" : "s have"} accepted an offer, ready to admit`} action={<Link href="/admissions/postgraduate" className="btn btn--primary btn--sm">Admit them</Link>}>
          Admitting puts each on the register as a postgraduate student, to matriculate on fees and registration.
        </Note>
      ) : (
        <Note kind="ok" title={`Nothing waits on the School for ${home.session}`} action={<Link href="/admissions/postgraduate" className="btn btn--ghost btn--sm">Postgraduate admissions</Link>}>
          New recommendations from the departments and fresh acceptances appear here to be acted on.
        </Note>
      )}

      <Tiles items={[
        ["Applications", String(c.total), null, home.session],
        ["Awaiting the School", String(recommended), recommended ? "var(--chrome)" : null, "Recommended by a department"],
        ["Offered", String(c.offered), Number(c.offered) ? "var(--green-ink)" : null, "Awaiting acceptance"],
        ["To admit", String(toAdmit), toAdmit ? "var(--chrome)" : null, "Accepted, not yet on the register", "/admissions/postgraduate"],
        ["PG students", String(home.pgStudents), null, "On the register"],
      ]} />

      <Panel title="By programme" right={home.session}>
        {progs.length ? (
          <DTable cols={["Programme", "Applications|mid", "In progress|mid", "Offered|mid", "Accepted / admitted|num"]}
            rows={progs.map((p) => [
              <span key="p"><span>{p.programme_name}</span><div className="sub2">{p.pg_award ?? ""}</div></span>,
              <span className="tnum" key="a">{p.applications}</span>,
              <span className="tnum" key="i">{p.in_progress}</span>,
              <span className="tnum" key="o">{p.offered}</span>,
              <span className="tnum" key="t">{p.taken}</span>,
            ])} texts={progs.map((p) => p.programme_name)} />
        ) : <PBody><div className="sub2">No postgraduate application has been submitted for {home.session} yet.</div></PBody>}
      </Panel>

      <Panel title="Postgraduate desks" right={me?.name ? `Signed in as ${me.name}` : role}>
        <PBody>
          <div style={{ display: "grid", gap: 8, gridTemplateColumns: "repeat(auto-fill, minmax(200px, 1fr))" }}>
            <Link href="/admissions/postgraduate" className="btn btn--ghost btn--sm">Postgraduate admissions</Link>
            <Link href="/students" className="btn btn--ghost btn--sm">Students</Link>
            <Link href="/results/broadsheet" className="btn btn--ghost btn--sm">Broadsheet</Link>
          </div>
          <div className="sub2" style={{ marginTop: 8 }}>You are acting for the {role}.{me?.name ? ` Signed in as ${me.name}.` : ""}</div>
        </PBody>
      </Panel>
    </>
  );
}
