"use client";

/** tStaff — the establishment: the people on the roll and the grade each holds, which
 *  is what the payroll is built over. Read here; movements and appointments are HR's. */
import { Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { StaffOpen } from "@/components/StaffModal";
import { money } from "@/components/proto/blocks";

export interface StaffRow {
  /** V770: today's status (Lagos today) by the pay run's rule — ACTIVE while serving, an exit still to come included; the run itself
   *  reads its month's first day. ended_on the exit's effective date */
  id: string; person_id: string; staff_no: string; grade: string; step: number; category: string; status: string;
  appointment_date: string; ended_on?: string | null; name: string; bank_name: string | null; account_last4: string | null; gross: number | null;
}

const STATUS: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  ACTIVE: ["ok", "Active"], SUSPENDED: ["warn", "Suspended"], ENDED: ["grey", "Ended"],
};

const leaving = (d: string | null | undefined) => (d ? ` · leaving ${new Date(d).toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" })}` : "");

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
            <Pil kind={STATUS[r.status]?.[0] ?? "grey"} key="s">{STATUS[r.status]?.[1] ?? r.status}{r.status === "ACTIVE" ? leaving(r.ended_on) : ""}</Pil>,
          ])} texts={rows.map((r) => `${r.name} ${r.staff_no} ${r.grade} ${r.category} ${r.status}`)} />
        ) : <PBody><div className="sub2">No staff on the establishment yet.</div></PBody>}
      </Panel>
      <Note kind="info" title="The payroll is built over this roll">
        A pay run pays everyone serving on at least one day of its month, on their recorded grade and step: an exit taking effect after
        the month&apos;s first day is paid the whole month, even once its row here shows Ended; nobody is paid for a month before their
        appointment; a suspended employment is not paid. The status here is today&apos;s.
      </Note>
    </>
  );
}
