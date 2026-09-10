"use client";

/** tAuditStaff — the audit directorate reads the establishment and the payroll that runs
 *  over it: the headcount, the monthly cost, and each month's run with its two-officer
 *  approval. A change in the payroll total should be explained by a change in the roll. */
import { money } from "@/lib/format";
import { Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

export interface StaffRow { staff_no: string; grade: string; step: number; category: string; status: string; name: string; gross: number | null }
export interface Run { id: string; period: string; state: string; staff_count: number; gross_total: number; deduction_total: number; net_total: number; approved_by_name: string | null; built_by_name: string | null }

const RUNSTATE: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  DRAFT: ["warn", "Draft"], APPROVED: ["info", "Approved"], PAID: ["ok", "Paid"], CANCELLED: ["grey", "Cancelled"],
};
function monthLabel(period: string): string { return new Date(period).toLocaleDateString("en-GB", { month: "long", year: "numeric" }); }

export function AuditStaff({ staff, runs }: { staff: StaffRow[]; runs: Run[] }) {
  const active = staff.filter((s) => s.status === "ACTIVE");
  const academic = active.filter((s) => s.category === "ACADEMIC").length;
  const monthly = active.reduce((n, s) => n + Number(s.gross ?? 0), 0);
  const lastPaid = runs.find((r) => r.state === "PAID") ?? null;

  return (
    <>
      <Note kind="info" title="The roll and the payroll, read together">
        Audit reads the establishment and the pay runs from the same records the Human Resource office and the Bursary act on. Each run is built by one officer and approved by another; a run whose total moves without a matching change on the roll is the thing to ask about.
      </Note>
      <Tiles items={[
        ["On the establishment", String(active.length), null, `${staff.length} on the roll`],
        ["Academic", String(academic), null, `${active.length - academic} non-academic`],
        ["Monthly gross", money(monthly), null, "Active establishment, before deductions"],
        ["Last payroll paid", lastPaid ? money(Number(lastPaid.net_total)) : "—", "var(--green-ink)", lastPaid ? `${monthLabel(lastPaid.period)} · net` : "None yet"],
      ]} />

      <Panel title="Pay runs" right="Each built by one officer, approved by another">
        {runs.length ? (
          <DTable cols={["Month|mid", "Staff|num", "Gross|num", "Deductions|num", "Net|num", "Stage", "Approved by"]} rows={runs.map((r) => [
            <span className="tnum" key="m">{monthLabel(r.period)}</span>,
            <span className="tnum sub2" key="c">{r.staff_count}</span>,
            <span className="tnum" key="g">{money(Number(r.gross_total))}</span>,
            <span className="tnum sub2" key="d">{money(Number(r.deduction_total))}</span>,
            <b className="tnum" key="n">{money(Number(r.net_total))}</b>,
            <Pil kind={RUNSTATE[r.state]?.[0] ?? "grey"} key="s">{RUNSTATE[r.state]?.[1] ?? r.state}</Pil>,
            <span className="sub2" key="a">{r.approved_by_name ?? (r.state === "DRAFT" ? "Awaiting" : "—")}</span>,
          ])} texts={runs.map((r) => `${monthLabel(r.period)} ${r.state}`)} />
        ) : <PBody><div className="sub2">No pay run has been built yet.</div></PBody>}
      </Panel>

      <Panel title="Establishment" right={`${active.length} active`}>
        {staff.length ? (
          <DTable cols={["Staff", "Grade|mid", "Category|mid", "Monthly gross|num", "Status|mid"]} rows={staff.map((s) => [
            <Two key="p" a={s.name} b={s.staff_no} />,
            <span className="sub2" key="g">{s.grade} · {s.step}</span>,
            <span className="sub2" key="c">{s.category === "ACADEMIC" ? "Academic" : "Non-academic"}</span>,
            <span className="tnum" key="gr">{s.gross == null ? "—" : money(Number(s.gross))}</span>,
            <Pil kind={s.status === "ACTIVE" ? "ok" : "grey"} key="st">{s.status === "ACTIVE" ? "Active" : s.status.charAt(0) + s.status.slice(1).toLowerCase()}</Pil>,
          ])} texts={staff.map((s) => `${s.name} ${s.staff_no} ${s.grade} ${s.status}`)} />
        ) : <PBody><div className="sub2">No staff are on the establishment yet.</div></PBody>}
      </Panel>
    </>
  );
}
