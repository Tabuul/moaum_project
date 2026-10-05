"use client";
/** The funded population of a session, one row per student (V327): NELFUND credited, applied, available and refundable; other
 *  funding; the fees due, paid and outstanding; the shortfall and whether a top-up is allowed; the refund's state; what came from
 *  the old portal. Filtered by the Bursary's question, searched by name or number, exported branded. */
import { useState } from "react";
import { Btn, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, money } from "@/components/proto/blocks";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { notifyProblem } from "@/components/proto/Toast";
import { NELFUND_FILTERS, type NelfundStudentRow } from "@/lib/wallet";

const REASON: Record<string, string> = { ALLOWED: "Top-up allowed", NO_SHORTFALL: "Funding covers it", FEES_SETTLED: "Fees settled", NO_CHARGE_STATED: "No charge stated", WINDOW_CLOSED: "Window closed", STUDENT_INACTIVE: "Not in study" };
const REFUND: Record<string, [string, "ok" | "info" | "bad" | "grey" | "warn"]> = { REQUESTED: ["Refund requested", "warn"], APPROVED: ["Refund approved", "info"], PAID: ["Refund paid", "ok"], REJECTED: ["Refund rejected", "grey"] };
const HEAD = ["S/N", "Student", "Number", "Programme", "Level", "NELFUND credited", "NELFUND applied", "NELFUND available", "NELFUND refundable", "Grants", "Own top-ups", "Fees due", "Paid", "Outstanding", "Shortfall", "Top-up", "Refund", "Old portal"];

export function NelfundStudents({ rows, total, page, size, filter, q, session, onNav }: {
  rows: NelfundStudentRow[]; total: number; page: number; size: number; filter: string; q: string; session: string; onNav: (p: { filter?: string; q?: string; page?: number }) => void;
}) {
  const [search, setSearch] = useState(q);
  const [busy, setBusy] = useState(false);
  const pages = Math.max(1, Math.ceil(total / size));
  async function exportXlsx() {
    setBusy(true);
    try {
      const body = rows.map((r, i) => [i + 1, r.name, r.number, r.programme, r.level, Number(r.nelfund_credited), Number(r.nelfund_applied), Number(r.nelfund_available), Number(r.nelfund_refundable), Number(r.other_credited), Number(r.self_credited),
        Number(r.due), Number(r.paid), Number(r.outstanding), Number(r.shortfall), REASON[r.topup_reason] ?? r.topup_reason, r.refund_state ? `${(REFUND[r.refund_state] ?? [r.refund_state])[0]} ${money(Number(r.refund_amount))}` : "", Number(r.legacy_posted)]);
      const label = NELFUND_FILTERS.find((x) => x[0] === filter)?.[1] ?? filter;
      downloadBlob(await brandedXlsx("NELFUND funding statement by student", HEAD, body, { sheetName: "Students", serial: docSerial("NELSTU"), sub: `${session} · ${label} · ${rows.length} of ${total} student${total === 1 ? "" : "s"}` }), `nelfund-students-${session.replace("/", "-")}.xlsx`);
    } catch (e) { notifyProblem({ status: 500, title: "The export could not be built", detail: e instanceof Error ? e.message : String(e) }); }
    finally { setBusy(false); }
  }
  return (
    <>
      <Panel title="The funded population" right={<Btn kind="secondary" size="sm" disabled={busy || !rows.length} onClick={() => void exportXlsx()}>Excel</Btn>}>
        <PBody>
          <div className="grid grid--3">
            <Field id="ns-f" label="Who"><select id="ns-f" className="ctl" value={filter} onChange={(e) => onNav({ filter: e.target.value, page: 1 })}>{NELFUND_FILTERS.map(([k, w]) => <option key={k} value={k}>{w}</option>)}</select></Field>
            <Field id="ns-q" label="Name or number"><input id="ns-q" className="ctl" value={search} onChange={(e) => setSearch(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") onNav({ q: search, page: 1 }); }} placeholder="Type, then Enter" /></Field>
            <div className="row row--end"><Btn kind="primary" onClick={() => onNav({ q: search, page: 1 })}>Search</Btn></div>
          </div>
        </PBody>
      </Panel>
      <Panel title={`${total.toLocaleString()} student${total === 1 ? "" : "s"}`} right={pages > 1 ? <span className="row row--inline row--tight sub2"><Btn kind="ghost" size="sm" disabled={page <= 1} onClick={() => onNav({ page: page - 1 })}>Previous</Btn>Page {page} of {pages}<Btn kind="ghost" size="sm" disabled={page >= pages} onClick={() => onNav({ page: page + 1 })}>Next</Btn></span> : null}>
        {rows.length ? (
          <DTable noPrint cols={["S/N|num", "Student", "Programme", "NELFUND|num", "Applied|num", "Available|num", "Refundable|num", "Other|num", "Fees|num", "Paid|num", "Outstanding|num", "Shortfall|num", "Top-up|mid", "Refund|mid"]} rows={rows.map((r, i) => [
            <span key="n" className="tnum sub2">{(page - 1) * size + i + 1}</span>,
            <span key="s"><b>{r.name}</b><div className="sub2 tnum">{r.number}{r.legacy_posted ? " · old portal" : ""}{r.nelfund_after_settlement ? " · paid before the Fund" : ""}</div></span>,
            <span key="p" className="sub2">{r.programme_code} · {r.level}</span>,
            <span key="c" className="tnum">{money(Number(r.nelfund_credited))}</span>,
            <span key="a" className="tnum">{money(Number(r.nelfund_applied))}</span>,
            <span key="v" className="tnum">{money(Number(r.nelfund_available))}</span>,
            <span key="rf" className={`tnum${Number(r.nelfund_refundable) ? " ink-green" : ""}`}>{money(Number(r.nelfund_refundable))}</span>,
            <span key="o" className="tnum sub2">{money(Number(r.other_credited) + Number(r.self_credited))}</span>,
            <span key="d" className="tnum">{money(Number(r.due))}</span>,
            <span key="pd" className="tnum">{money(Number(r.paid))}</span>,
            <span key="ou" className={`tnum${Number(r.outstanding) ? " ink-red" : ""}`}>{money(Number(r.outstanding))}</span>,
            <span key="sh" className={`tnum${Number(r.shortfall) ? " ink-red b600" : ""}`}>{money(Number(r.shortfall))}</span>,
            <Pil key="t" kind={r.topup_allowed ? "warn" : "grey"}>{REASON[r.topup_reason] ?? r.topup_reason}</Pil>,
            r.refund_state ? <Pil key="r" kind={(REFUND[r.refund_state] ?? ["", "grey"])[1]}>{(REFUND[r.refund_state] ?? [r.refund_state])[0]}</Pil> : <span key="r" className="sub2">—</span>,
          ])} texts={rows.map((r) => `${r.name} ${r.number} ${r.programme_code}`)} />
        ) : <PBody><div className="sub2">Nobody for this question in {session}.</div></PBody>}
      </Panel>
    </>
  );
}
