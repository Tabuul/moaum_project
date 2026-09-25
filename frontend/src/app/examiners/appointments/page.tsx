import Link from "next/link";
import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { LinkBtn, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ExaminerPil, dayOf, type Appointment } from "@/lib/examiners";

export const dynamic = "force-dynamic";

/** t/extappointments — every examiner appointment: the session, the unit, the period, what it carries */
export default async function AppointmentsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const session = typeof p.session === "string" ? p.session : "";
  const [me, list, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Appointment[]>(`/api/v1/examiners/appointments${session ? `?session=${encodeURIComponent(session)}` : ""}`),
    api<{ name: string }[]>("/api/v1/ref/sessions"),
  ]);
  const rows = list.ok ? list.data : [];
  return (
    <Shell route="t/extappointments" me={me.ok ? me.data : null}>
      <PageHead title="Examiner Appointments" description="Each external examiner's engagement for a session and a unit, as the letter names it; an examiner is appointed from their own record."
        actions={<><LinkBtn kind="primary" href="/examiners">The Register</LinkBtn><LinkBtn href="/examiners/assignments">Project Assignments</LinkBtn></>} />
      {!list.ok ? <ProblemNotice problem={list.problem} /> : null}
      <div className="row mb-3">
        <LinkBtn kind={!session ? "primary" : "ghost"} size="sm" href="/examiners/appointments">Every session</LinkBtn>
        {(sessions.ok ? sessions.data : []).slice(0, 6).map((s) => <LinkBtn key={s.name} kind={session === s.name ? "primary" : "ghost"} size="sm" href={`/examiners/appointments?session=${encodeURIComponent(s.name)}`}>{s.name}</LinkBtn>)}
      </div>
      <Panel title="Appointments" right={`${rows.length} appointment${rows.length === 1 ? "" : "s"}`}>
        {rows.length ? (
          <DTable cols={["Examiner", "Session", "Unit", "Programme", "From|mid", "To|mid", "Projects|mid", "Status|mid", "|num"]} rows={rows.map((a) => [
            <span key="e"><Link className="lnk b600" href={`/examiners/${a.examiner_id}`}>{a.examiner}</Link><div className="sub2">{a.institution}</div><div className="mt-1"><ExaminerPil status={a.examiner_status ?? ""} /></div></span>,
            <span key="s" className="tnum">{a.session}{a.semester ? <div className="sub2">semester {a.semester}</div> : null}</span>,
            <span key="u">{a.department}<div className="sub2">{a.faculty}</div></span>,
            <span key="p" className="sub2">{a.programme ?? "Every programme"}{a.period ? <div>{a.period}</div> : null}</span>,
            <span key="f" className="tnum">{dayOf(a.starts_on)}</span>, <span key="t" className="tnum">{dayOf(a.ends_on)}</span>,
            <span key="n" className="tnum">{Number(a.assignments ?? 0)}</span>,
            <Pil key="st" kind={a.status === "ACTIVE" ? "ok" : "grey"}>{a.status === "ACTIVE" ? "Active" : a.status === "ENDED" ? "Ended" : "Suspended"}</Pil>,
            <LinkBtn key="o" href={`/examiners/${a.examiner_id}`} size="sm">Open</LinkBtn>,
          ])} texts={rows.map((a) => `${a.examiner} ${a.institution ?? ""} ${a.session} ${a.department} ${a.programme ?? ""}`)} />
        ) : <PBody><div className="sub2">No appointment recorded{session ? ` for ${session}` : ""}. Open an examiner on the register and record one.</div></PBody>}
      </Panel>
    </Shell>
  );
}
