"use client";

/** V545: refunds and wallet withdrawals approved and not yet paid, with the days each has waited — past the days the Bursary sets
 *  (7 by default) the Bursar and the Students Account Officer are told once a day. */
import { useEffect, useState } from "react";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Panel, PBody, Pil, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { money } from "@/components/proto/blocks";

interface Unpaid { kind: "REFUND" | "WALLET"; id: string; reference: string; payee: string; number: string | null; amount: number; approved_on: string; days_waiting: number; account_ready: boolean; overdue: boolean }

const day = (iso: string) => new Date(`${iso}T12:00:00`).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });

export function UnpaidPayouts({ may }: { may: boolean }) {
  const [data, setData] = useState<{ days: number; rows: Unpaid[] } | null>(null);
  const [days, setDays] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let live = true;
    fetch("/api/bff/api/v1/finance/refunds/unpaid", { cache: "no-store" })
      .then((r) => (r.ok ? r.json() : { days: 7, rows: [] }))
      .catch(() => ({ days: 7, rows: [] }))
      .then((j: { days: number; rows: Unpaid[] }) => { if (live) { setData(j); setDays(String(j.days)); } });
    return () => { live = false; };
  }, []);

  async function save() {
    setBusy(true);
    try {
      const r = await fetch("/api/bff/api/v1/finance/refunds/unpaid/days", { method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Unpaid payouts told after ${days} days`) }, body: JSON.stringify({ days: Number(days) }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      setData(j as { days: number; rows: Unpaid[] });
      notify(`Told after ${days} days`);
    } finally {
      setBusy(false);
    }
  }

  const overdue = (data?.rows ?? []).filter((u) => u.overdue);
  const daysOk = /^\d{1,3}$/.test(days) && Number(days) >= 1 && Number(days) <= 365;
  return (
    <Panel title="Approved, not yet paid" right={data ? <span className="sub2">{overdue.length ? `${overdue.length} past ${data.days} days` : `None past ${data.days} days`}</span> : undefined}>
      {data === null ? <PBody><div className="sub2">Looking…</div></PBody> : data.rows.length ? (
        <DTable pageSize={0} cols={["Payment", "Payee", "Amount|num", "Approved|mid", "Waiting|num", "Account|mid"]} rows={data.rows.map((u) => [
          <Two key="r" a={<span className="tnum">{u.reference}</span>} b={u.kind === "WALLET" ? "Wallet withdrawal" : "Refund"} />,
          <Two key="p" a={u.payee} b={u.number ?? ""} />,
          <b key="a" className="tnum">{money(Number(u.amount))}</b>,
          <span key="d" className="tnum">{day(u.approved_on)}</span>,
          <span key="w">{u.overdue ? <Pil kind="bad">{u.days_waiting} days</Pil> : <span className="tnum">{u.days_waiting} day{u.days_waiting === 1 ? "" : "s"}</span>}</span>,
          u.account_ready ? <Pil key="ac" kind="ok">Ready</Pil> : <Pil key="ac" kind="warn">No account</Pil>,
        ])} texts={data.rows.map((u) => `${u.reference} ${u.payee} ${u.number ?? ""}`)} />
      ) : <PBody><div className="sub2">Nothing approved is waiting to be paid.</div></PBody>}
      <PBody>
        <div className="row" style={{ flexWrap: "wrap", gap: 8, alignItems: "center" }}>
          <span className="sub2">The Bursar and the Students Account Officer are told once a day of any approved more than</span>
          {may ? <>
            <input aria-label="Days before the Bursary is told" className="ctl tnum" style={{ width: 80 }} inputMode="numeric" value={days} onChange={(e) => setDays(e.target.value.replace(/[^0-9]/g, ""))} />
            <span className="sub2">days ago and not yet paid.</span>
            <Btn kind="ghost" size="sm" disabled={busy || !daysOk || Number(days) === data?.days} onClick={() => void save()}>Save</Btn>
          </> : <span className="sub2">{data?.days ?? 7} days ago and not yet paid.</span>}
        </div>
      </PBody>
    </Panel>
  );
}
