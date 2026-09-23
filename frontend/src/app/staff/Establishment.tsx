"use client";

/** tStaff — the establishment: the people on the roll and the grade each holds, which
 *  is what the payroll is built over. Read here; movements and appointments are HR's. */
import { Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { StaffOpen } from "@/components/StaffModal";
import { money } from "@/components/proto/blocks";

export interface StaffRow {
  id: string; person_id: string; staff_no: string; grade: string; step: number; category: string; status: string;
  appointment_date: string; name: string; bank_name: string | null; account_last4: string | null; gross: number | null;
}

const STATUS: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  ACTIVE: ["ok", "Active"], SUSPENDED: ["warn", "Suspended"], ENDED: ["grey", "Ended"],
};

export function Establishment({ rows }: { rows: StaffRow[] }) {
  const active = rows.filter((r) => r.status === "ACTIVE");
  const academic = active.filter((r) => r.category === "ACADEMIC").length;
  const monthly = active.reduce((n, r) => n + Number(r.gross ?? 0), 0);

  return (
    <>
      <Tiles items={[
        ["On the roll", String(rows.length), null, `${active.length} active`],
        ["Academic", String(academic), null, "Teaching staff"],
        ["Non-academic", String(active.length - academic), null, "Administrative and technical"],
        ["Monthly gross", money(monthly), null, "Active establishment, before deductions"],
      ]} />
      <Panel title="Establishment" right={`${rows.length} on the roll`}>
        {rows.length ? (
          <DTable cols={["Staff", "Grade|mid", "Category|mid", "Monthly gross|num", "Bank|mid", "Status|mid"]} rows={rows.map((r) => [
            <span key="p"><StaffOpen id={r.person_id} kind="link" label={r.name} /><div className="sub2 tnum">{r.staff_no}</div></span>,
            <span className="sub2" key="g">{r.grade} · {r.step}</span>,
            <span className="sub2" key="c">{r.category === "ACADEMIC" ? "Academic" : "Non-academic"}</span>,
            <span className="tnum" key="gr">{r.gross == null ? "—" : money(Number(r.gross))}</span>,
            <span className="sub2" key="b">{r.bank_name ? `${r.bank_name}${r.account_last4 ? ` ····${r.account_last4}` : ""}` : "—"}</span>,
            <Pil kind={STATUS[r.status]?.[0] ?? "grey"} key="s">{STATUS[r.status]?.[1] ?? r.status}</Pil>,
          ])} texts={rows.map((r) => `${r.name} ${r.staff_no} ${r.grade} ${r.category} ${r.status}`)} />
        ) : <PBody><div className="sub2">No staff on the establishment yet.</div></PBody>}
      </Panel>
      <Note kind="info" title="The payroll is built over this roll">
        A pay run pays everyone shown as active here, on the grade and step recorded against them. Appointments, promotions and endings are the Human Resource office&rsquo;s to record; the payroll reads what they set.
      </Note>
    </>
  );
}
