"use client";

/** V498: every old-portal payment on record twice — what the retired Payment History Upload recorded again, a whole-session
 *  record repeating the semester record of its key, an earlier upload's record repeating a numbered payment (the same student,
 *  session, amount within a naira and day) — listed, taken as Excel, and withdrawn by the Bursary with a reason: each one's
 *  ledger posting reversed, the record kept on the register, then removed. */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, money } from "@/components/proto/blocks";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { DOUBLE_HEADERS, DOUBLE_KIND, LINKED_WORD, doubleRow, withdrawDone, type DoubleKind, type DoubleRow } from "@/lib/old-fees";

interface Doubles { count: number; amount: number | string; linked: number; students: number; withdrawn: number; kinds: Partial<Record<DoubleKind, number>>; rows: DoubleRow[] }

/** tick: a change made elsewhere on the page (the list reads again); onChanged: told when this list changes the records */
export function OldFeesDoubles({ may, tick: changed = 0, onChanged }: { may: boolean; tick?: number; onChanged?: () => void }) {
  const [data, setData] = useState<Doubles | null>(null);
  const [busy, setBusy] = useState<string | null>("load");
  const [tick, setTick] = useState(0);
  const [asking, setAsking] = useState(false);
  const [reason, setReason] = useState("");
  const [progress, setProgress] = useState<string | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  // the list, read again after a withdrawal
  useEffect(() => {
    let alive = true;
    void (async () => {
      const r = await fetch("/api/bff/api/v1/finance/legacy-fees/doubles?limit=200", { cache: "no-store" }).catch(() => null);
      const j = r ? await r.json().catch(() => null) : null;
      if (!alive) return;
      setBusy(null);
      if (!r || !r.ok) { notifyProblem((j ?? { status: r?.status ?? 0, title: r?.statusText || "The portal could not be reached" }) as Problem); return; }
      setData(j as Doubles);
    })();
    return () => { alive = false; };
  }, [tick, changed]);

  async function excel() {
    setBusy("excel");
    try {
      const r = await fetch("/api/bff/api/v1/finance/legacy-fees/doubles?limit=100000", { cache: "no-store" });
      const j = (await r.json().catch(() => null)) as Doubles | null;
      if (!r.ok || !j) { notifyProblem((j ?? { status: r.status, title: r.statusText }) as unknown as Problem); return; }
      const blob = await brandedXlsx("Old payments recorded twice", DOUBLE_HEADERS, j.rows.map(doubleRow), {
        sheetName: "Recorded twice", serial: docSerial("OPD"),
        sub: `The same student, session, amount and day · ${j.count.toLocaleString()} payment${j.count === 1 ? "" : "s"}`,
      });
      downloadBlob(blob, "old-payments-recorded-twice.xlsx");
    } finally {
      setBusy(null);
    }
  }

  async function withdraw() {
    setBusy("withdraw");
    setSaid(null);
    let total = 0;
    let reversed = 0;
    try {
      for (;;) {
        const r = await fetch("/api/bff/api/v1/finance/legacy-fees/doubles/withdraw", {
          method: "POST",
          headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Old payments recorded twice withdrawn: ${reason.trim()}`) },
          body: JSON.stringify({ reason: reason.trim(), limit: 5000 }),
        });
        const j = await r.json().catch(() => null);
        if (!r.ok) { notifyProblem((j ?? { status: r.status, title: r.statusText }) as Problem); break; }
        const w = j as { withdrawn: number; ledger_reversed: number; left_linked: number; remaining: number };
        total += Number(w.withdrawn); reversed += Number(w.ledger_reversed);
        setProgress(`${total.toLocaleString()} withdrawn${Number(w.remaining) ? `, ${Number(w.remaining).toLocaleString()} to go` : ""}…`);
        if (withdrawDone(w)) {
          setSaid(`${total.toLocaleString()} payment${total === 1 ? "" : "s"} recorded twice withdrawn${reversed ? `, ${reversed.toLocaleString()} ledger posting${reversed === 1 ? "" : "s"} reversed` : ""}.${Number(w.left_linked) ? ` ${Number(w.left_linked).toLocaleString()} left because something uses them.` : ""}`);
          break;
        }
      }
      notify(`${total.toLocaleString()} withdrawn`);
      setAsking(false);
      setReason("");
    } finally {
      setProgress(null);
      setBusy("load");
      setTick((t) => t + 1);
      onChanged?.();
    }
  }

  const free = data ? data.count - data.linked : 0;
  return (
    <Panel title="Recorded twice" right="The same student, session, amount and day on record twice: by the retired Payment History Upload, or left by earlier uploads">
      {said ? <PBody><Note kind="ok" title="Withdrawn">{said} Each one is kept on the register with its reason; the record it repeated stays.</Note></PBody> : null}
      {!data ? <PBody><div className="sub2">{busy === "load" ? "Looking…" : ""}</div></PBody>
        : !data.count ? (
          <PBody><div className="sub2">No old-portal payment is on record twice.{data.withdrawn ? ` ${Number(data.withdrawn).toLocaleString()} withdrawn so far are on the register.` : ""}</div></PBody>
        ) : (
          <>
            <PBody>
              <Tiles items={[
                ["Recorded twice", data.count.toLocaleString(), "var(--red-ink)", `${data.students.toLocaleString()} student${data.students === 1 ? "" : "s"}${(Object.keys(data.kinds ?? {}) as DoubleKind[]).map((k) => ` · ${(data.kinds[k] ?? 0).toLocaleString()} ${k === "PAYMENT_HISTORY" ? "by Payment History Upload" : k === "WHOLE_SESSION" ? "whole-session" : "earlier uploads"}`).join("")}`],
                ["Amount counted twice", money(Number(data.amount)), "var(--red-ink)", "Paid once, counted twice"],
                ["Kept, something uses them", data.linked.toLocaleString(), data.linked ? "var(--red-ink)" : null, "A deferment fee, a refund or the GST reconciliation"],
                ["Withdrawn so far", Number(data.withdrawn).toLocaleString(), null, "On the register"],
              ]} />
              <div className="row mt-2">
                <Btn kind="ghost" disabled={!!busy} onClick={() => void excel()}>{busy === "excel" ? "Preparing…" : "Excel"}</Btn>
                {may && free > 0 ? <Btn kind="primary" disabled={!!busy} onClick={() => setAsking(true)}>{`Withdraw ${free.toLocaleString()} recorded twice`}</Btn> : null}
              </div>
            </PBody>
            <DTable cols={["Student", "Session|mid", "Day paid|mid", "Amount|num", "Recorded twice as", "Kept", ""]}
              rows={data.rows.map((d) => [
                <Two key="s" a={d.name} b={d.number} />,
                <span key="se" className="tnum sub2">{d.session}</span>,
                <span key="d" className="tnum sub2">{d.paid_on}</span>,
                <b key="a" className="tnum">{money(Number(d.amount))}</b>,
                <span key="o" className="sub2"><span className="tnum">{d.double_reference}</span><div>{DOUBLE_KIND[d.double_kind] ?? d.double_kind}</div></span>,
                <span key="k" className="sub2"><span className="tnum">{d.kept_reference}</span><div>{d.kept_purpose}</div></span>,
                d.linked ? <Pil key="l" kind="warn">{LINKED_WORD[d.linked] ?? d.linked}</Pil> : <span key="l" />,
              ])} />
            {data.count > data.rows.length ? <PBody><div className="sub2">The first {data.rows.length.toLocaleString()} of {data.count.toLocaleString()}; the Excel list has them all.</div></PBody> : null}
          </>
        )}
      {asking ? (
        <Modal title={`Withdraw ${free.toLocaleString()} payments recorded twice`} onClose={() => { if (!busy) setAsking(false); }}
          foot={<><Btn kind="ghost" disabled={!!busy} onClick={() => setAsking(false)}>Cancel</Btn>
            <Btn kind="primary" disabled={!!busy || reason.trim().length < 10} onClick={() => void withdraw()}>{busy === "withdraw" ? (progress ?? "Withdrawing…") : "Withdraw"}</Btn></>}>
          <p>
            Each payment on record twice is withdrawn: its ledger posting reversed, the record kept on the register with your reason, then removed.
            The record it repeats stays (a whole-session record&rsquo;s payment number moves to the semester record that stands for it), so every
            student keeps the payment once. Those something uses are left. Load the old portal&rsquo;s export on this screen first, so every payment
            carries its number.
          </p>
          <Field id="opd-reason" label="Why" required hint="At least ten characters; kept with each record">
            <textarea id="opd-reason" className="ctl" rows={2} maxLength={500} value={reason} onChange={(e) => setReason(e.target.value)}
              placeholder="e.g. old-portal payments loaded twice by the earlier uploads" />
          </Field>
        </Modal>
      ) : null}
    </Panel>
  );
}
