import Link from "next/link";
import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { LinkBtn, Note, PageHead, Panel, PBody } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { SEM, StatePil, ReturnPil, dayOf, periodOf, returnOf, type Deferment } from "@/lib/deferments";

export const dynamic = "force-dynamic";

/** students due to return from deferment, within the office's bound; the return is confirmed on the request */
export default async function ReturnsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const status = typeof p.status === "string" && ["UPCOMING", "DUE", "OVERDUE"].includes(p.status) ? p.status : "";
  const [me, r] = await Promise.all([api<Me>("/api/v1/iam/me"), api<{ rows: Deferment[] }>(`/api/v1/deferments/returns${status ? `?status=${status}` : ""}`)]);
  const rows = r.ok ? r.data.rows : [];
  return (
    <Shell route="t/deferments" me={me.ok ? me.data : null}>
      <PageHead title="Students Due to Return" description="Every deferment in force within your bound, by its return date: upcoming, due, or overdue. Confirm a return on the request when the student presents themselves."
        actions={<>{["", "DUE", "OVERDUE", "UPCOMING"].map((s) => <LinkBtn key={s || "all"} kind={status === s ? "primary" : "ghost"} href={`/deferments/returns${s ? `?status=${s}` : ""}`}>{s ? s.charAt(0) + s.slice(1).toLowerCase() : "All"}</LinkBtn>)}<LinkBtn href="/deferments">Deferments Desk</LinkBtn></>} />
      {!r.ok ? <ProblemNotice problem={r.problem} /> : null}
      <Panel title="Deferments in force" right={`${rows.length} · by return date`}>
        {rows.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Student", "Programme", "Deferred", "Expected return", "Return date|mid", "Status|mid", "|num"]}
            rows={rows.map((d, i) => [
              <span key="sn" className="tnum sub2">{i + 1}</span>,
              <span key="s"><strong>{d.surname}, {d.other_names}</strong><div className="sub2 tnum">{d.number} · {d.reference}</div></span>,
              <span key="p">{d.programme}<div className="sub2">{d.department} · {d.faculty}</div></span>,
              <span key="d" className="tnum">{periodOf(d)}</span>,
              <span key="r" className="tnum">{returnOf(d)}{d.return_semester ? "" : ` · ${SEM(1)}`}</span>,
              <span key="on" className="tnum">{dayOf(d.return_on)}</span>,
              <span key="st"><ReturnPil status={d.return_status} /> <StatePil state={d.state} /></span>,
              <Link key="o" className="btn btn--primary btn--sm" href={`/deferments/${d.id}`}>Confirm Return</Link>,
            ])} texts={rows.map((d) => `${d.surname} ${d.other_names} ${d.number} ${d.reference} ${d.programme}`)} />
        ) : <PBody><Note kind="info" title="No student is due to return">No deferment is in force within your bound{status ? ` at that stage` : ""}.</Note></PBody>}
      </Panel>
    </Shell>
  );
}
