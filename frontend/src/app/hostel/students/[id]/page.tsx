import Link from "next/link";
import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { LinkBtn, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ALLOC_STATE, APP_STATE, CLEAR_STATE, dayOf, naira, whenAt, type Charge, type HistoryRow, type HostelEvent } from "@/lib/hostel";
import { hostelSession } from "../../page";

export const dynamic = "force-dynamic";

interface History { student: { id: string; name: string; number: string; sex: string | null; current_level: number; status: string; programme: string | null }; history: HistoryRow[]; events: HostelEvent[]; charges: (Charge & { reference_no: string; session: string })[] }

/** t/hostel › student — where a student has stayed, session by session, with every charge and every step on the trail */
export default async function HostelStudentPage({ params, searchParams }: { params: Promise<{ id: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const { id } = await params;
  const p = await searchParams;
  const { session } = await hostelSession(p);
  const [me, view] = await Promise.all([api<Me>("/api/v1/iam/me"), api<History>(`/api/v1/hostel/students/${id}/history`)]);
  const q = `?session=${encodeURIComponent(session)}`;
  return (
    <Shell route="t/hostel" me={me.ok ? me.data : null}>
      {view.ok ? (
        <>
          <div className="row row--tight sub2" style={{ gap: 6 }}><Link className="lnk" href={`/hostel${q}`}>Accommodation</Link><span>›</span><strong>{view.data.student.name}</strong></div>
          <PageHead title={view.data.student.name} description={`${view.data.student.number} · ${view.data.student.programme ?? "—"} · ${view.data.student.current_level} Level · ${view.data.student.status.toLowerCase()}. Accommodation history: every session, hostel, room and bed, with the outcome.`}
            actions={<LinkBtn kind="ghost" href={`/students/${view.data.student.id}`}>Student record</LinkBtn>} />
          <Panel title="Accommodation history" right={`${view.data.history.length} record(s)`}>
            {view.data.history.length ? <DTable cols={["Session|mid", "Application|mid", "Hostel", "Room|mid", "Bed|mid", "Allocated|mid", "Checked in|mid", "Checked out|mid", "Status|mid", "Clearance|mid", "|num"]} rows={view.data.history.map((h, i) => [
              <span key="s" className="tnum">{h.session}</span>, <span key="a" className="tnum sub2">{h.application_ref}</span>, <span key="h">{h.hall_name ?? "—"}</span>, <span key="r" className="tnum">{h.block && h.room_no ? `${h.block}-${h.room_no}` : "—"}</span>, <span key="b" className="tnum">{h.bed_label ?? "—"}</span>,
              <span key="al" className="tnum sub2">{h.allocated_at ? dayOf(h.allocated_at) : "—"}</span>, <span key="ci" className="tnum sub2">{h.checked_in_at ? dayOf(h.checked_in_at) : "—"}</span>, <span key="co" className="tnum sub2">{h.checked_out_at ? dayOf(h.checked_out_at) : "—"}</span>,
              h.allocation_state ? <Pil key={`st${i}`} kind={ALLOC_STATE[h.allocation_state]?.[1] ?? "grey"}>{ALLOC_STATE[h.allocation_state]?.[0] ?? h.allocation_state}</Pil> : <Pil key={`st${i}`} kind={APP_STATE[h.application_state]?.[1] ?? "grey"}>{APP_STATE[h.application_state]?.[0] ?? h.application_state}</Pil>,
              h.clearance_state ? <Pil key="cl" kind={CLEAR_STATE[h.clearance_state]?.[1] ?? "grey"}>{CLEAR_STATE[h.clearance_state]?.[0] ?? h.clearance_state}</Pil> : <span key="cl" className="sub2">—</span>,
              <span key="o" className="tnum sub2">{h.allocation_ref ?? ""}</span>,
            ])} /> : <PBody><div className="sub2">No accommodation on this student&rsquo;s record.</div></PBody>}
          </Panel>
          {view.data.charges.length ? (
            <Panel title="Damage charges">
              <DTable cols={["Session|mid", "Allocation|mid", "Damage", "Charge|num", "Reference|mid", "Status|mid"]} rows={view.data.charges.map((c) => [<span key="s" className="tnum">{c.session}</span>, <span key="a" className="tnum sub2">{c.reference_no}</span>, c.description, <span key="c" className="tnum">{naira(c.charge)}</span>, <span key="r" className="tnum sub2">{c.reference ?? "—"}</span>, <Pil key="st" kind={c.waived_at ? "info" : c.settled_at ? "ok" : "bad"}>{c.waived_at ? "Waived" : c.settled_at ? "Settled" : "Outstanding"}</Pil>])} />
            </Panel>
          ) : null}
          <Panel title="Trail" right={`${view.data.events.length} event(s)`}>
            {view.data.events.length ? <DTable cols={["When|mid", "What", "Note", "By"]} rows={view.data.events.map((e) => [<span key="w" className="tnum sub2">{whenAt(e.at)}</span>, <span key="a">{e.action.replace(/_/g, " ").toLowerCase()}{e.to_value ? <span className="sub2"> · {e.to_value}</span> : null}</span>, <span key="n" className="sub2">{e.note ?? ""}</span>, <span key="b" className="sub2">{e.actor_office ?? "portal"}</span>])} pageSize={20} /> : <PBody><div className="sub2">Nothing on the trail.</div></PBody>}
          </Panel>
        </>
      ) : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
