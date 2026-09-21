import Link from "next/link";
import type { Me } from "@/components/proto/Shell";
import { Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

export interface PgHome {
  session: string;
  counts: { total: number; submitted: number; recommended: number; offered: number; accepted: number; admitted: number };
  pgStudents: number;
  byProgramme: { programme_name: string; pg_award: string | null; applications: number; in_progress: number; offered: number; taken: number }[];
  recent?: {
    application_no: string; session: string; state: string; entry_level: number;
    surname: string; other_names: string; email: string; phone: string | null;
    programme_name: string; pg_award: string | null; submitted_at: string | null; fee_confirmed_at: string | null;
  }[];
}

const STATE_LABEL: Record<string, string> = {
  DRAFT: "Draft", SUBMITTED: "Submitted", DEPT_RECOMMENDED: "Recommended", DEPT_DECLINED: "Declined by dept",
  OFFERED: "Offered", NOT_OFFERED: "Not offered", ACCEPTED: "Accepted", ADMITTED: "Admitted",
};

function shortDate(v: string | null): string {
  if (!v) return "—";
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? "—" : d.toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" });
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
  const recent = home.recent ?? [];
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

      <Panel title="Latest applications" right={<Link href="/admissions/postgraduate" className="btn btn--ghost btn--sm">Open admissions desk</Link>}>
        {recent.length ? (
          <DTable cols={["Applicant", "Programme", "Session|mid", "Fee|mid", "Status|mid", "Applied|num"]}
            rows={recent.map((a) => [
              <span key="n"><span>{a.surname}, {a.other_names}</span><div className="sub2">{a.application_no} · {a.email}</div></span>,
              <span key="p"><span>{a.programme_name}</span><div className="sub2">{a.pg_award ?? ""}</div></span>,
              <span key="s" className="tnum">{a.session}</span>,
              <span key="f">{a.fee_confirmed_at ? <span style={{ color: "var(--green-ink)" }}>Paid</span> : <span className="sub2">Unpaid</span>}</span>,
              <span key="st">{STATE_LABEL[a.state] ?? a.state}</span>,
              <span key="d" className="tnum">{shortDate(a.submitted_at)}</span>,
            ])}
            texts={recent.map((a) => `${a.surname} ${a.other_names} ${a.application_no} ${a.email} ${a.programme_name}`)} />
        ) : <PBody><div className="sub2">No postgraduate application has been submitted yet.</div></PBody>}
      </Panel>

      <Panel title="Postgraduate desks" right={me?.name ? `Signed in as ${me.name}` : role}>
        <PBody>
          {DESK_GROUPS.map((g) => (
            <div key={g.name} style={{ marginBottom: 12 }}>
              <div className="sub2" style={{ textTransform: "uppercase", letterSpacing: ".5px", fontSize: 11, fontWeight: 600, marginBottom: 6 }}>{g.name}</div>
              <div style={{ display: "grid", gap: 8, gridTemplateColumns: "repeat(auto-fill, minmax(210px, 1fr))" }}>
                {g.items.map((it) => (
                  <Link key={it.href} href={it.href} className="btn btn--ghost btn--sm" style={{ justifyContent: "flex-start", textAlign: "left" }}>{it.label}</Link>
                ))}
              </div>
            </div>
          ))}
          <div className="sub2" style={{ marginTop: 2 }}>You are acting for the {role}.{me?.name ? ` Signed in as ${me.name}.` : ""}</div>
        </PBody>
      </Panel>
    </>
  );
}

const DESK_GROUPS: { name: string; items: { href: string; label: string }[] }[] = [
  { name: "Admissions & register", items: [
    { href: "/admissions/postgraduate", label: "Postgraduate admissions" },
    { href: "/admissions/postgraduate/students", label: "PG register" },
    { href: "/matriculation", label: "Matriculation" },
  ]},
  { name: "Coursework", items: [
    { href: "/admissions/postgraduate/courses", label: "Course catalogue" },
    { href: "/admissions/postgraduate/results", label: "Registrations & results" },
  ]},
  { name: "Research & examination", items: [
    { href: "/admissions/postgraduate/research", label: "Research & thesis desk" },
    { href: "/admissions/postgraduate/examiners", label: "External examiners" },
  ]},
  { name: "Awards", items: [
    { href: "/admissions/postgraduate/board", label: "School Board & awards" },
    { href: "/graduation", label: "Graduation list" },
    { href: "/results/broadsheet", label: "Results broadsheet" },
  ]},
  { name: "Fees", items: [
    { href: "/finance/fees", label: "Fee schedule" },
  ]},
];
