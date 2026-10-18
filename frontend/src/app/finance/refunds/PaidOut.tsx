"use client";

/** V540: the Paid-out report — every refund and NELFUND wallet withdrawal paid between two dates, by the day the money left: the
 *  payee, the account it went to, the amount, the bank transfer reference, who approved and who paid it, and when the same
 *  reference is on another payment — for Internal Audit to tick against the bank statement. Excel and PDF through the export engine
 *  (on the export log, V523). */
import { useEffect, useState } from "react";
import { Btn, Panel, PBody, Pil, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, money } from "@/components/proto/blocks";
import { notifyProblem } from "@/components/proto/Toast";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";

export interface PaidOutRow {
  kind: "REFUND" | "WALLET"; reference: string; payee: string; number: string | null; bank_name: string | null; account_number: string | null;
  account_name: string | null; amount: number; paid_on: string; transfer_reference: string | null; approved_by_name: string | null;
  paid_by_name: string | null; recorded_at: string | null; same_reference: number;
}

const lagosDay = (offset = 0) => {
  const d = new Date(Date.now() + offset * 86400000);
  return d.toLocaleDateString("en-CA", { timeZone: "Africa/Lagos" });
};
const day = (iso: string) => new Date(`${iso}T12:00:00`).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });
const KIND: Record<string, string> = { REFUND: "Refund", WALLET: "Wallet withdrawal" };

export function PaidOut() {
  const [range, setRange] = useState({ from: lagosDay(-30), to: lagosDay() });
  const [asked, setAsked] = useState(range);
  const [rows, setRows] = useState<PaidOutRow[] | null>(null);

  useEffect(() => {
    let live = true;
    fetch(`/api/bff/api/v1/finance/refunds/paid-out?from=${asked.from}&to=${asked.to}`, { cache: "no-store" })
      .then(async (r) => {
        const j = await r.json().catch(() => null);
        if (!live) return;
        if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); setRows([]); return; }
        setRows(j as PaidOutRow[]);
      })
      .catch(() => { if (live) setRows([]); });
    return () => { live = false; };
  }, [asked]);

  const total = (rows ?? []).reduce((n, r) => n + Number(r.amount), 0);
  const shared = (rows ?? []).filter((r) => r.same_reference > 0).length;
  const sub = `Paid ${day(asked.from)} to ${day(asked.to)} · ${rows?.length ?? 0} payment${rows?.length === 1 ? "" : "s"} · ${money(total)}`;
  const HEAD = ["Paid on", "Kind", "Reference", "Payee", "Number", "Bank", "Account number", "Account name", "Amount", "Transfer reference", "Same reference elsewhere", "Approved by", "Paid by"];
  const line = (r: PaidOutRow) => [day(r.paid_on), KIND[r.kind] ?? r.kind, r.reference, r.payee, r.number ?? "", r.bank_name ?? "", r.account_number ?? "", r.account_name ?? "",
    Number(r.amount), r.transfer_reference ?? "", r.same_reference > 0 ? r.same_reference : "", r.approved_by_name ?? "", r.paid_by_name ?? ""];
  const valid = /^\d{4}-\d{2}-\d{2}$/.test(range.from) && /^\d{4}-\d{2}-\d{2}$/.test(range.to) && range.from <= range.to;

  return (
    <Panel title="Paid out" right={<div className="row row--inline" style={{ gap: 6 }}>
      <Btn kind="ghost" size="sm" disabled={!rows?.length} busyLabel="Preparing Excel..." onClick={async () => {
        if (rows) downloadBlob(await brandedXlsx("Refunds and Withdrawals Paid Out", HEAD, rows.map(line), { sub, serial: docSerial("PDO") }), `paid-out-${asked.from}-to-${asked.to}.xlsx`);
      }}>Excel</Btn>
      <Btn kind="ghost" size="sm" disabled={!rows?.length} onClick={() => { if (rows) brandedPrint("Refunds and Withdrawals Paid Out", sub, HEAD, rows.map(line), docSerial("PDO"), { orientation: "landscape" }); }}>PDF</Btn>
    </div>}>
      <PBody>
        <div className="sub2">Every refund and NELFUND wallet withdrawal paid in the period, by the day the money left, with the account it went to and the bank transfer reference — to tick against the bank statement.</div>
        <form className="filterbar mt-1" onSubmit={(e) => { e.preventDefault(); if (valid) { setRows(null); setAsked(range); } }}>
          <Field id="po-from" label="Paid from"><input id="po-from" type="date" className="ctl" value={range.from} max={range.to} onChange={(e) => setRange({ ...range, from: e.target.value })} /></Field>
          <Field id="po-to" label="To"><input id="po-to" type="date" className="ctl" value={range.to} min={range.from} max={lagosDay()} onChange={(e) => setRange({ ...range, to: e.target.value })} /></Field>
          <button type="submit" className="btn btn--primary btn--sm" style={{ alignSelf: "flex-end" }} disabled={!valid}>Show</button>
        </form>
      </PBody>
      {rows === null ? <PBody><div className="sub2">Looking…</div></PBody> : rows.length ? (
        <>
          <DTable pageSize={0} cols={["Paid on|mid", "Payment", "Payee", "Paid into", "Amount|num", "Transfer reference", "Approved / paid by"]} rows={rows.map((r) => [
            <span key="d" className="tnum">{day(r.paid_on)}</span>,
            <Two key="k" a={<span className="tnum">{r.reference}</span>} b={KIND[r.kind] ?? r.kind} />,
            <Two key="p" a={r.payee} b={r.number ?? ""} />,
            <Two key="a" a={<span className="tnum">{`${r.bank_name ?? ""} · ${r.account_number ?? "—"}`}</span>} b={r.account_name ?? ""} />,
            <b key="m" className="tnum">{money(Number(r.amount))}</b>,
            <span key="t"><span className="tnum">{r.transfer_reference ?? "—"}</span>{r.same_reference > 0 ? <div><Pil kind="warn" title="The same bank transfer reference is on other payments">Also on {r.same_reference} other</Pil></div> : null}</span>,
            <Two key="w" a={r.approved_by_name ?? "—"} b={r.paid_by_name ?? ""} />,
          ])} texts={rows.map((r) => `${r.reference} ${r.payee} ${r.number ?? ""} ${r.transfer_reference ?? ""} ${r.account_number ?? ""}`)} />
          <PBody><div className="sub2">{rows.length} payment{rows.length === 1 ? "" : "s"}, {money(total)} in all{shared ? ` · ${shared} carry a transfer reference that is also on another payment` : ""}.</div></PBody>
        </>
      ) : <PBody><div className="sub2">Nothing was paid out in the period.</div></PBody>}
    </Panel>
  );
}
