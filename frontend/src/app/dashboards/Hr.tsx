import Link from "next/link";
import type { Me } from "@/components/proto/Shell";
import { Note, Panel, PBody, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { money } from "@/lib/format";

const d0 = (iso: string | null | undefined) => { if (!iso) return "—"; try { return new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short" }); } catch { return "—"; } };

export interface HrHome {
  cycle: string; staffActive: number; leavePending: number; onLeaveToday: number;
  movementsAwaiting: number; vacanciesOpen: number; shortlisted: number; payDraft: number; appraisals: number;
  latestRun: { period: string; state: string; staff_count: number; net_total: number } | null;
  leave: { name: string; staff_no: string; type_name: string; days: number; from_date: string }[];
  movements: { name: string; staff_no: string; what_changes: string; effective_date: string }[];
}

/** The Director of HR's home: the establishment and what is waiting on the directorate — from the HR module. */
export function HrDashboard({ me, home }: { me: Me | null; home: HrHome | null }) {
  if (!home) {
    return <Note kind="bad" title="The HR figures could not be read">The directorate&rsquo;s dashboard reads the HR module; it did not answer. Try again, or open a desk from the menu.</Note>;
  }
  const leave = home.leave ?? [];
  const movements = home.movements ?? [];
  return (
    <>
      {home.leavePending ? (
        <Note kind="bad" title={`${home.leavePending} leave request${home.leavePending === 1 ? "" : "s"} awaiting a decision`} action={<Link href="/hr/leave" className="btn btn--urgent btn--sm">Open leave</Link>}>
          A request draws down the staff member&rsquo;s annual balance on approval; a second officer decides it, on the record.
        </Note>
      ) : home.movementsAwaiting ? (
        <Note kind="info" title={`${home.movementsAwaiting} movement${home.movementsAwaiting === 1 ? " is" : "s are"} approved, awaiting an instrument`} action={<Link href="/hr/movements" className="btn btn--primary btn--sm">Issue instruments</Link>}>
          A promotion or transfer changes the record only when the instrument is issued. Issue the outstanding ones so the change takes effect from its date.
        </Note>
      ) : (
        <Note kind="ok" title="Nothing is waiting on the directorate" action={<Link href="/hr/movements" className="btn btn--ghost btn--sm">Movements</Link>}>
          No leave to decide and no instrument to issue. The establishment is up to date.
        </Note>
      )}

      <Tiles items={[
        ["Staff on the establishment", String(home.staffActive), null, `${home.onLeaveToday} on leave today`],
        ["Leave to decide", String(home.leavePending), home.leavePending ? "var(--red-ink)" : "var(--green-ink)", "Awaiting a decision", "/hr/leave"],
        ["Instruments to issue", String(home.movementsAwaiting), home.movementsAwaiting ? "var(--chrome)" : "var(--green-ink)", "Approved movements", "/hr/movements"],
        ["Open vacancies", String(home.vacanciesOpen), null, `${home.shortlisted} shortlisted`, "/hr/recruitment"],
      ]} />

      <div className="grid--2" style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(320px,1fr))", gap: 14 }}>
        <Panel title="Leave to decide" right={leave.length ? `${leave.length} waiting` : "None"}>
          {leave.length ? (
            <DTable cols={["Staff", "Type", "Days|mid", "From|mid"]}
              rows={leave.map((l) => [
                <Two key="s" a={l.name} b={l.staff_no} />,
                <span className="sub2" key="t">{l.type_name}</span>,
                <span className="tnum" key="d">{l.days}</span>,
                <span className="tnum sub2" key="f">{d0(l.from_date)}</span>,
              ])} />
          ) : <PBody><div className="sub2">No leave request is waiting. Staff apply from their own page; the request appears here to decide.</div></PBody>}
        </Panel>

        <Panel title="Movements awaiting an instrument" right={movements.length ? `${movements.length} to issue` : "None"}>
          {movements.length ? (
            <DTable cols={["Staff", "Change", "Effective|mid"]}
              rows={movements.map((m) => [
                <Two key="s" a={m.name} b={m.staff_no} />,
                <span className="sub2" key="w">{m.what_changes}</span>,
                <span className="tnum sub2" key="e">{d0(m.effective_date)}</span>,
              ])} />
          ) : <PBody><div className="sub2">No approved movement is waiting for its instrument.</div></PBody>}
        </Panel>
      </div>

      <Panel title="HR desks" right={`Appraisal cycle ${home.cycle} · ${home.appraisals} recorded`}>
        <PBody>
          <div style={{ display: "grid", gap: 8, gridTemplateColumns: "repeat(auto-fill, minmax(200px, 1fr))" }}>
            <Link href="/hr/leave" className="btn btn--ghost btn--sm">Leave</Link>
            <Link href="/hr/movements" className="btn btn--ghost btn--sm">Movements &amp; instruments</Link>
            <Link href="/hr/appraisal" className="btn btn--ghost btn--sm">Appraisal &amp; promotion</Link>
            <Link href="/hr/recruitment" className="btn btn--ghost btn--sm">Recruitment</Link>
            <Link href="/payroll" className="btn btn--ghost btn--sm">Payroll{home.payDraft ? ` (${home.payDraft} draft)` : ""}</Link>
            <Link href="/people/lecturers" className="btn btn--ghost btn--sm">Staff records</Link>
          </div>
          <div className="sub2" style={{ marginTop: 8 }}>
            {home.latestRun ? `Latest pay run ${home.latestRun.period} — ${home.latestRun.state.toLowerCase()}, ${home.latestRun.staff_count} staff, ${money(Number(home.latestRun.net_total))} net.` : "No pay run recorded yet."}
            {me?.name ? ` Signed in as ${me.name}.` : ""}
          </div>
        </PBody>
      </Panel>
    </>
  );
}
