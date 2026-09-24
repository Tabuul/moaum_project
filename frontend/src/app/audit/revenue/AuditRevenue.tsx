"use client";

/** tAuditRevenue — the audit directorate reads collection against the register: what was
 *  billed, what came in, and where it is still owed. Every figure is the same one the
 *  Bursary and the Academic Office see; audit does not keep a second set of books. */
import { money } from "@/lib/format";
import { Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

export interface Bursary {
  session: string;
  tiles: { fees_collected: number; today: number; today_count: number; references_open: number; credits_open: number; credits_open_amount: number; gateway_exceptions: number; hanging: number };
  byFaculty: { faculty_name: string; students: number; paid_students: number; collected: number; due: number }[];
}
export interface Revenue { session: string; rows: { category: string; payments: number; amount: number }[]; totals: { payments: number; amount: number } }

export function AuditRevenue({ session, bursary, revenue }: { session: string; bursary: Bursary; revenue: Revenue | null }) {
  const t = bursary.tiles;
  const totalDue = bursary.byFaculty.reduce((n, f) => n + Number(f.due), 0);
  const totalCollected = bursary.byFaculty.reduce((n, f) => n + Number(f.collected), 0);

  return (
    <>
      <Note kind="info" title="One answer, from the transactions themselves">
        Audit reads the same figures the Academic Office and the Bursary act on — collection is counted only when the gateway or the bank has confirmed it. Where the two offices would disagree, this screen shows the exception rather than a reconciled guess.
      </Note>
      <Tiles items={[
        ["Fees collected", money(Number(t.fees_collected)), "var(--green-ink)", `School fees · ${session}`],
        ["Confirmed today", money(Number(t.today)), null, `${t.today_count} payment${t.today_count === 1 ? "" : "s"}`],
        ["Still owed", money(totalDue), totalDue ? "var(--red-ink)" : null, "Across the register"],
        ["Open exceptions", String(Number(t.gateway_exceptions) + Number(t.credits_open) + Number(t.hanging)), (Number(t.gateway_exceptions) + Number(t.credits_open) + Number(t.hanging)) ? "var(--red-ink)" : null, `${t.gateway_exceptions} gateway · ${t.credits_open} bank · ${t.hanging} hanging`],
      ]} />

      {revenue && revenue.rows.length ? (
        <Panel title="Revenue by category" right={`Confirmed for ${session}`}>
          <DTable cols={["Category", "Payments|num", "Amount|num"]} rows={[
            ...revenue.rows.map((r) => [
              <span key="c">{r.category}</span>,
              <span className="tnum sub2" key="p">{Number(r.payments).toLocaleString()}</span>,
              <b className="tnum" key="a">{money(Number(r.amount))}</b>,
            ]),
            [<b key="c">Total</b>, <b className="tnum" key="p">{Number(revenue.totals.payments).toLocaleString()}</b>, <b className="tnum" key="a">{money(Number(revenue.totals.amount))}</b>],
          ]} />
        </Panel>
      ) : null}

      <Panel title="Collection against the register, by faculty" right={`Collected ${money(totalCollected)} · owed ${money(totalDue)}`}>
        {bursary.byFaculty.length ? (
          <DTable cols={["Faculty", "Students|num", "Paid|num", "Collected|num", "Outstanding|num"]} rows={bursary.byFaculty.map((f) => [
            <span key="f">{f.faculty_name}</span>,
            <span className="tnum sub2" key="s">{Number(f.students).toLocaleString()}</span>,
            <span className="tnum sub2" key="p">{Number(f.paid_students).toLocaleString()}</span>,
            <span className="tnum" key="c">{money(Number(f.collected))}</span>,
            <b className={`tnum${Number(f.due) ? " ink-red" : ""}`} key="d">{money(Number(f.due))}</b>,
          ])} texts={bursary.byFaculty.map((f) => f.faculty_name)} />
        ) : <PBody><div className="sub2">No collection recorded for {session} yet.</div></PBody>}
      </Panel>
    </>
  );
}
