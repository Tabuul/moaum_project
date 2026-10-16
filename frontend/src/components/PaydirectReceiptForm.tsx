"use client";

/**
 * V480, V490: the receipt of a payment made on Quickteller or at a bank (PayDirect) — the Payment Log Id, the day paid, the
 * amount and where — reported against a reference Interswitch has not reported. A second report replaces the first and
 * reopens one the Bursary marked not found. It confirms nothing; the Bursary finds the payment by it. The payer sends it from
 * their pay screen; the ICT Support Desk records it from the caller's slip (the `send` each passes says where it goes).
 */
import { useState } from "react";
import { Btn } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { notify } from "@/components/proto/Toast";
import { reasonHeader } from "@/lib/reason";
import { CHANNEL_LABEL, claimBody, claimProblems, lagosToday, type Claim, type ClaimChannel, type ClaimForm } from "@/lib/paydirect-claim";

export type ReceiptBody = ReturnType<typeof claimBody>;

/** sends the receipt; the saved receipt, or the words of the refusal */
export type ReceiptSend = (body: ReceiptBody) => Promise<{ ok: true; claim: Claim } | { ok: false; message: string }>;

/** POSTs the body to an API path through the BFF, with the reason the audit spine records */
export function receiptSender(path: string, reason: string, extra: Record<string, unknown> = {}): ReceiptSend {
  return async (body) => {
    try {
      const r = await fetch(`/api/bff${path}`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) },
        body: JSON.stringify({ ...body, ...extra }),
      });
      const j = (await r.json().catch(() => null)) as (Record<string, unknown> & { detail?: string; title?: string }) | null;
      if (!r.ok || !j) return { ok: false, message: j?.detail ?? j?.title ?? "The receipt could not be sent just now. Try again in a moment." };
      const claim = (j.receipt ?? j) as Claim;
      return { ok: true, claim };
    } catch {
      return { ok: false, message: "The portal could not be reached just now. Try again in a moment." };
    }
  };
}

export function PaydirectReceiptForm({ reference, claim, onClose, onSaved, send, desk }: {
  reference: string;
  claim: Claim | null;
  onClose: () => void;
  onSaved: (c: Claim) => void;
  send: ReceiptSend;
  /** recorded by the ICT Support Desk from the caller's receipt, not by the payer */
  desk?: boolean;
}) {
  const today = lagosToday();
  const [f, setF] = useState<ClaimForm>({
    paymentLogId: claim?.payment_log_id ?? "",
    paidOn: claim?.paid_on?.slice(0, 10) ?? today,
    amount: claim?.amount != null ? String(claim.amount) : "",
    channel: claim?.channel ?? "",
    note: claim?.note ?? "",
  });
  const [tried, setTried] = useState(false);
  const [busy, setBusy] = useState(false);
  const [refused, setRefused] = useState<string | null>(null);
  const problems = claimProblems(f, today);
  const shown = tried ? problems : {};
  async function go() {
    setTried(true);
    setRefused(null);
    if (Object.keys(problems).length > 0) return;
    setBusy(true);
    try {
      const out = await send(claimBody(reference, f));
      if (!out.ok) { setRefused(out.message); return; }
      notify(`Receipt ${desk ? "recorded" : "reported"}: the Bursary will look for ${out.claim.payment_log_id}.`);
      onSaved(out.claim);
    } finally {
      setBusy(false);
    }
  }
  return (
    <Modal title={desk ? "Record the caller's receipt" : claim ? "Correct the receipt" : "Report the receipt"} sub={<>For <b className="tnum">{reference}</b></>} onClose={onClose}
      foot={<><Btn kind="ghost" onClick={onClose} disabled={busy}>Cancel</Btn><Btn kind="primary" onClick={() => void go()} disabled={busy}>{busy ? "Sending…" : desk ? "Record the receipt" : "Send the receipt"}</Btn></>}>
      <p>
        The Payment Log Id on Quickteller&rsquo;s receipt (or the bank&rsquo;s PayDirect slip) is what finds the payment.
        {desk ? " Read it from the caller's receipt. " : " "}
        This does not confirm it: the payment counts when Interswitch reports it, and the Bursary uses the receipt to ask for it.
      </p>
      <div className="grid grid--2">
        <Field id="rc-log" label="Payment Log Id" required error={shown.paymentLogId}>
          <input id="rc-log" className="ctl" autoComplete="off" maxLength={40} value={f.paymentLogId} onChange={(e) => setF({ ...f, paymentLogId: e.target.value })} required />
        </Field>
        <Field id="rc-on" label="Day paid" required error={shown.paidOn}>
          <input id="rc-on" type="date" className="ctl" max={today} value={f.paidOn} onChange={(e) => setF({ ...f, paidOn: e.target.value })} required />
        </Field>
        <Field id="rc-amount" label="Amount paid (₦)" hint="As the receipt shows" error={shown.amount}>
          <input id="rc-amount" className="ctl tnum" inputMode="decimal" value={f.amount} onChange={(e) => setF({ ...f, amount: e.target.value })} />
        </Field>
        <Field id="rc-where" label={desk ? "Where they paid" : "Where you paid"}>
          <select id="rc-where" className="ctl" value={f.channel} onChange={(e) => setF({ ...f, channel: e.target.value as ClaimChannel | "" })}>
            <option value="">Choose…</option>
            {(Object.keys(CHANNEL_LABEL) as ClaimChannel[]).map((k) => <option key={k} value={k}>{CHANNEL_LABEL[k]}</option>)}
          </select>
        </Field>
        <Field id="rc-note" label="Anything else" hint="The bank, or what the receipt says" full error={shown.note}>
          <textarea id="rc-note" className="ctl" rows={2} maxLength={500} value={f.note} onChange={(e) => setF({ ...f, note: e.target.value })} />
        </Field>
      </div>
      {refused ? <p className="mt-2" role="alert"><b>{refused}</b></p> : null}
    </Modal>
  );
}
