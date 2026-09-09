"use client";

/** bRefunds — proto/part…: refunds and credits, maker–checker controlled. The officer who
 *  raises a refund cannot approve it; the database refuses the second click. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
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
}

const STATE: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  PROPOSED: ["warn", "Awaiting approval"], APPROVED: ["info", "Approved, to pay"], PAID: ["ok", "Paid"], REJECTED: ["grey", "Rejected"],
};

export function Refunds({ refunds, actingOffice }: { refunds: Refund[]; actingOffice: string | null }) {
  const router = useRouter();
  const may = ["bursar", "super"].includes(actingOffice ?? "");
  const [add, setAdd] = useState(false);
  const [f, setF] = useState({ payer: "", reason: "", amount: "", bank: "", accountName: "", accountLast4: "" });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  const open = refunds.filter((r) => r.state === "PROPOSED").length;
  const toPay = refunds.filter((r) => r.state === "APPROVED").length;

  async function send(path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/finance/refunds${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j ?? { status: r.status, title: r.statusText }); return null; }
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
            <span className="tnum" key="r">{r.reference}</span>,
            <Two key="p" a={r.payer} b={r.number ?? ""} />,
            <span className="sub2" key="rs">{r.reason}</span>,
            <b className="tnum" key="a">{money(Number(r.amount))}</b>,
            <span key="s"><Pil kind={STATE[r.state]?.[0] ?? "grey"}>{STATE[r.state]?.[1] ?? r.state}</Pil>{r.proposed_by_name ? <div className="sub2">Raised by {r.proposed_by_me ? "you" : r.proposed_by_name}</div> : null}{r.rejected_why ? <div className="sub2">{r.rejected_why}</div> : null}</span>,
            <span key="ac" style={{ display: "inline-flex", gap: 6, flexWrap: "wrap" }}>
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
        <div><button className="btn btn--primary" onClick={() => { setF({ payer: "", reason: "", amount: "", bank: "", accountName: "", accountLast4: "" }); setErr(null); setAdd(true); }}>+ Raise a refund</button></div>
      ) : null}

      <Note kind="bad" title="A refund account whose name does not match the payer is the commonest route money reaches the wrong person">
        The account is snapshotted when the refund is raised, so a later edit of a student&rsquo;s bank details cannot redirect money already approved. The University never asks for a BVN, a PIN or a card, and never collects by direct debit.
      </Note>

      {add ? (
        <Modal title="Raise a refund" sub="It goes to a second officer to approve" onClose={() => setAdd(false)}
          foot={<><Btn kind="ghost" onClick={() => setAdd(false)}>Cancel</Btn><span style={{ flexGrow: 1 }} />
            <Btn kind="primary" disabled={busy || !f.payer.trim() || !f.reason.trim() || !(Number(f.amount) > 0)} onClick={async () => { const j = await send("", { payer: f.payer, reason: f.reason, amount: Number(f.amount), bank: f.bank || null, accountName: f.accountName || null, accountLast4: f.accountLast4 || null }, `Raise refund for ${f.payer}`); if (j) { setSaid(`Refund ${j.reference} raised for ${f.payer}`); setAdd(false); } }}>Raise it</Btn></>}>
          {err ? <ProblemNotice problem={err} /> : null}
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
