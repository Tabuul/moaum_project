"use client";

/** bRefunds — proto/part…: refunds and credits, maker–checker controlled. The officer who
 *  raises a refund cannot approve it; the database refuses the second click. */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface Refund {
  id: string; reference: string; student_id: string | null; payer: string; reason: string; amount: number;
  bank_name: string | null; account_name: string | null; account_last4: string | null; state: string;
  proposed_at: string; approved_at: string | null; rejected_why: string | null; paid_at: string | null;
  number: string | null; proposed_by_name: string | null; approved_by_name: string | null; proposed_by_me: boolean;
  source_reference: string | null;
}

interface Txn { kind: string; amount: number; confirmed_at: string | null; channel: string | null; receipt_no: string | null; payer: string | null; number: string | null; student_id: string | null; purpose: string | null }

const STATE: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  PROPOSED: ["warn", "Awaiting approval"], APPROVED: ["info", "Approved, to pay"], PAID: ["ok", "Paid"], REJECTED: ["grey", "Rejected"],
};

export function Refunds({ refunds, actingOffice, initialRefund }: { refunds: Refund[]; actingOffice: string | null; initialRefund?: string | null }) {
  const router = useRouter();
  const may = ["bursar", "super"].includes(actingOffice ?? "");
  const [add, setAdd] = useState(!!(initialRefund && may));
  const [f, setF] = useState({ payer: "", reason: "", amount: "", bank: "", accountName: "", accountLast4: "" });
  const [source, setSource] = useState(initialRefund && may ? initialRefund.toUpperCase() : "");
  const [student, setStudent] = useState<string | null>(null);
  const [txn, setTxn] = useState<Txn | null>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  function openModal(fromReference?: string) {
    setF({ payer: "", reason: "", amount: "", bank: "", accountName: "", accountLast4: "" });
    setSource(fromReference ?? "");
    setStudent(null);
    setTxn(null);
    setErr(null);
    setAdd(true);
    if (fromReference) void fetchTxn(fromReference);
  }

  async function fetchTxn(ref: string) {
    const r = ref.trim();
    if (!r) return;
    setBusy(true);
    setErr(null);
    try {
      const res = await fetch(`/api/bff/api/v1/finance/refunds/transaction?reference=${encodeURIComponent(r)}`);
      const j = await res.json().catch(() => null);
      if (!res.ok) { setErr(j ?? { status: res.status, title: res.statusText }); setTxn(null); return; }
      const t = j as Txn;
      setTxn(t);
      setStudent(t.student_id ?? null);
      setSource(r.toUpperCase());
      setF((prev) => ({ ...prev, payer: t.payer ?? prev.payer, amount: t.amount != null ? String(t.amount) : prev.amount, reason: prev.reason || `Refund against ${r.toUpperCase()}${t.purpose ? ` — ${t.purpose}` : ""}` }));
    } finally {
      setBusy(false);
    }
  }

  const open = refunds.filter((r) => r.state === "PROPOSED").length;
  const toPay = refunds.filter((r) => r.state === "APPROVED").length;

  // launched from a transaction on the ledger: the modal opens pre-filled (above),
  // and this fetches that transaction to fill in the payer and amount
  useEffect(() => {
    if (!initialRefund || !may) return;
    let live = true;
    (async () => {
      const res = await fetch(`/api/bff/api/v1/finance/refunds/transaction?reference=${encodeURIComponent(initialRefund)}`);
      const j = await res.json().catch(() => null);
      if (!live) return;
      if (!res.ok) { setErr(j ?? { status: res.status, title: res.statusText }); return; }
      const t = j as Txn;
      setTxn(t);
      setStudent(t.student_id ?? null);
      setF((prev) => ({ ...prev, payer: t.payer ?? prev.payer, amount: t.amount != null ? String(t.amount) : prev.amount, reason: prev.reason || `Refund against ${initialRefund.toUpperCase()}${t.purpose ? ` — ${t.purpose}` : ""}` }));
    })();
    return () => { live = false; };
  }, [initialRefund, may]);

  async function send(path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/finance/refunds${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j ?? { status: r.status, title: r.statusText }); return null; }
      notify(reason);
      router.refresh();
      return j as Record<string, unknown>;
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Note kind="info" title="Maker and checker are always different people">
        The officer who raises a refund cannot approve it. The system refuses the second click rather than relying on anyone to remember the rule. A refund is paid only after a second officer has approved it, into the account snapshotted when it was raised.
      </Note>

      {said ? <Note kind="ok" title={said}>It waits for a second officer to approve it before any money leaves the University.</Note> : null}
      {err ? <ProblemNotice problem={err} /> : null}

      <Tiles items={[
        ["Awaiting approval", String(open), open ? "var(--red-ink)" : null, "A second officer must agree"],
        ["Approved, to pay", String(toPay), toPay ? "var(--chrome)" : null, "Ready to disburse"],
        ["Paid", String(refunds.filter((r) => r.state === "PAID").length), "var(--green-ink)", "On the record"],
        ["All", String(refunds.length), null, "Newest 300"],
      ]} />

      <Panel title="Refund requests" right={may ? undefined : "You are reading this queue"}>
        {refunds.length ? (
          <DTable cols={["Reference", "Payer", "Reason", "Amount|num", "Stage", "Action|num"]} rows={refunds.map((r) => [
            <span key="r"><span className="tnum">{r.reference}</span>{r.source_reference ? <div className="sub2">against <span className="tnum">{r.source_reference}</span></div> : null}</span>,
            <Two key="p" a={r.payer} b={r.number ?? ""} />,
            <span className="sub2" key="rs">{r.reason}</span>,
            <b className="tnum" key="a">{money(Number(r.amount))}</b>,
            <span key="s"><Pil kind={STATE[r.state]?.[0] ?? "grey"}>{STATE[r.state]?.[1] ?? r.state}</Pil>{r.proposed_by_name ? <div className="sub2">Raised by {r.proposed_by_me ? "you" : r.proposed_by_name}</div> : null}{r.rejected_why ? <div className="sub2">{r.rejected_why}</div> : null}</span>,
            <span key="ac" className="row row--inline row--tight">
              {may && r.state === "PROPOSED" && !r.proposed_by_me ? <Btn kind="go" disabled={busy} onClick={() => void send(`/${r.id}/approve`, {}, `Approve refund ${r.reference}`).then((j) => { if (j) setSaid(`${r.reference} approved`); })}>Approve</Btn> : null}
              {may && r.state === "PROPOSED" && r.proposed_by_me ? <Btn kind="ghost" disabled>Awaiting another approver</Btn> : null}
              {may && r.state === "PROPOSED" ? <Btn kind="ghost" disabled={busy} onClick={() => { const w = window.prompt("Why is this refund rejected? The reason is recorded."); if (w) void send(`/${r.id}/reject`, { why: w }, `Reject refund ${r.reference}`); }}>Reject</Btn> : null}
              {may && r.state === "APPROVED" ? <Btn kind="primary" disabled={busy} onClick={() => { if (window.confirm(`Mark ${r.reference} paid? Record this once the money has left, into ${r.account_name ?? "the account on file"}.`)) void send(`/${r.id}/pay`, {}, `Refund ${r.reference} paid`).then((j) => { if (j) setSaid(`${r.reference} recorded paid`); }); }}>Mark paid</Btn> : null}
              {!may || (r.state !== "PROPOSED" && r.state !== "APPROVED") ? <span className="sub2">{r.paid_at ? "Disbursed" : r.approved_by_name ? `Approved by ${r.approved_by_name}` : ""}</span> : null}
            </span>,
          ])} texts={refunds.map((r) => `${r.reference} ${r.payer} ${r.reason}`)} />
        ) : <PBody><div className="sub2">No refund has been raised. A refund appears here when an overpayment, a duplicate payment or a withdrawal is owed back.</div></PBody>}
      </Panel>

      {may ? (
        <div><button className="btn btn--primary" onClick={() => openModal()}>+ Raise a refund</button></div>
      ) : null}

      {add ? (
        <Modal title="Raise a refund" sub="It goes to a second officer to approve" onClose={() => setAdd(false)}
          foot={<><Btn kind="ghost" onClick={() => setAdd(false)}>Cancel</Btn><span className="grow" />
            <Btn kind="primary" disabled={busy || !f.payer.trim() || !f.reason.trim() || !(Number(f.amount) > 0)} onClick={async () => { const j = await send("", { student, payer: f.payer, reason: f.reason, amount: Number(f.amount), bank: f.bank || null, accountName: f.accountName || null, accountLast4: f.accountLast4 || null, source: source.trim() || null }, `Raise refund for ${f.payer}`); if (j) { setSaid(`Refund ${j.reference} raised for ${f.payer}`); setAdd(false); } }}>Raise it</Btn></>}>
          {err ? <ProblemNotice problem={err} /> : null}
          <Field id="rf-src" label="From a payment reference" hint="Optional — name the transaction being refunded and the payer and amount are filled in and checked against it.">
            <div style={{ display: "flex", gap: 8 }}>
              <input id="rf-src" className="ctl tnum" value={source} onChange={(e) => setSource(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); void fetchTxn(source); } }} placeholder="e.g. a receipt or reference" autoComplete="off" />
              <Btn kind="ghost" disabled={busy || !source.trim()} onClick={() => void fetchTxn(source)}>Fetch</Btn>
            </div>
          </Field>
          {txn ? (
            <Note kind={txn.confirmed_at ? "ok" : "bad"} title={txn.confirmed_at ? `Confirmed payment of ${money(Number(txn.amount))}` : "Not a confirmed payment"}>
              {txn.payer ?? "Payer not on record"}{txn.number ? ` · ${txn.number}` : ""}{txn.purpose ? ` · ${txn.purpose}` : ""}{txn.receipt_no ? ` · receipt ${txn.receipt_no}` : ""}. A refund cannot exceed what was paid on this transaction.
            </Note>
          ) : null}
          <Field id="rf-payer" label="Paid to" hint="The student or sponsor the money is owed to"><input id="rf-payer" className="ctl" value={f.payer} onChange={(e) => setF({ ...f, payer: e.target.value })} autoComplete="off" /></Field>
          <div className="grid grid--2">
            <Field id="rf-reason" label="Reason"><input id="rf-reason" className="ctl" value={f.reason} onChange={(e) => setF({ ...f, reason: e.target.value })} placeholder="Duplicate payment — timeout retry" autoComplete="off" /></Field>
            <Field id="rf-amount" label="Amount (₦)"><input id="rf-amount" className="ctl tnum" value={f.amount} inputMode="decimal" onChange={(e) => setF({ ...f, amount: e.target.value })} /></Field>
          </div>
          <div className="grid grid--3">
            <Field id="rf-bank" label="Bank" hint="Optional"><input id="rf-bank" className="ctl" value={f.bank} onChange={(e) => setF({ ...f, bank: e.target.value })} autoComplete="off" /></Field>
            <Field id="rf-an" label="Account name" hint="Must match the payer"><input id="rf-an" className="ctl" value={f.accountName} onChange={(e) => setF({ ...f, accountName: e.target.value })} autoComplete="off" /></Field>
            <Field id="rf-l4" label="Account (last 4)"><input id="rf-l4" className="ctl tnum" value={f.accountLast4} onChange={(e) => setF({ ...f, accountLast4: e.target.value })} autoComplete="off" /></Field>
          </div>
        </Modal>
      ) : null}
    </>
  );
}
