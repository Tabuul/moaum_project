"use client";

/**
 * Oct 2026: a reference Quickteller has already been told may be paid ("Reference valid" on the Bursary's log) with no
 * payment reported for it — the payer pressed Continue on Quickteller's page or at a bank. That is not a payment: it counts
 * only when Interswitch reports it. So the pay block leads with "I've paid — check now", keeps paying as the second choice
 * with a warning never to pay the same reference twice, and after a day points to the office that can trace the payment.
 * Also the one line every pay block carries: only this reference pays it (Quickteller refuses any other number, and its
 * refusal carries no words of ours).
 */
import { useEffect, useState } from "react";
import { Btn } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { CHANNEL_LABEL, claimBody, claimProblems, lagosToday, paidDay, type Claim, type ClaimChannel, type ClaimForm } from "@/lib/paydirect-claim";

const DAY_MS = 24 * 60 * 60 * 1000;

export interface ReferenceState {
  confirmed: boolean;
  /** when Quickteller was last told the reference may be paid, while no payment is reported */
  startedAt: string | null;
  /** a day or more since then */
  longAgo: boolean;
  /** V480: the receipt the payer reported for it, while it waits */
  claim: Claim | null;
}

async function readState(reference: string): Promise<ReferenceState | null> {
  const r = await fetch(`/api/bff/api/v1/payments/state?reference=${encodeURIComponent(reference)}`, { cache: "no-store" });
  if (!r.ok) return null;
  const j = (await r.json().catch(() => null)) as { confirmed?: boolean; startedAt?: string | null; claim?: Claim | null } | null;
  if (!j) return null;
  const startedAt = j.startedAt ?? null;
  return { confirmed: !!j.confirmed, startedAt, longAgo: !!startedAt && Date.now() - Date.parse(startedAt) >= DAY_MS, claim: j.claim ?? null };
}

/** the reference as the University's record has it, read once when the pay block opens */
export function useReferenceState(reference: string): ReferenceState | null {
  const [state, setState] = useState<ReferenceState | null>(null);
  useEffect(() => {
    let alive = true;
    readState(reference).then((s) => { if (alive) setState(s); }).catch(() => undefined);
    return () => { alive = false; };
  }, [reference]);
  return state;
}

function at(iso: string): string {
  const d = new Date(iso);
  return `${d.toLocaleDateString("en-GB", { day: "numeric", month: "short" })} at ${d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" })}`;
}

/** a payment begun on Quickteller and not yet reported: check first, pay again only when nothing was paid */
export function PaymentStarted({ reference, state, onPay, report }: {
  reference: string;
  state: ReferenceState;
  /** the payer did not complete it: the ordinary pay controls */
  onPay: () => void;
  /** where a payment still unconfirmed after a day is reported */
  report: { href: string; label: string };
}) {
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);
  const [claim, setClaim] = useState<Claim | null>(state.claim);
  const [reporting, setReporting] = useState(false);
  async function check() {
    setBusy(true);
    setSaid(null);
    try {
      const s = await readState(reference);
      if (s?.confirmed) {
        window.location.reload();
        return;
      }
      setSaid(s ? "Not confirmed yet. Interswitch usually reports a payment within minutes; wait a little and check again. Do not pay the same reference twice."
        : "The portal could not be reached just now. Wait a moment and check again.");
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="notice notice--info mt-2" style={{ flexBasis: "100%" }}>
      <div style={{ minWidth: 0 }}>
        <div className="notice__t">You started paying on Quickteller on {at(state.startedAt ?? "")}</div>
        <p>
          The payment of <b className="tnum">{reference}</b> counts only when Interswitch reports it to the University, usually within minutes.
          If money has left your account for it, do not pay again: check here instead.
        </p>
        <div className="row mt-2">
          <Btn kind="primary" size="md" disabled={busy} onClick={() => void check()}>{busy ? "Checking…" : "I've paid — check now"}</Btn>
          <Btn kind="ghost" size="md" disabled={busy} onClick={onPay}>I did not complete the payment — pay now</Btn>
        </div>
        {claim ? (
          <p className="sub2 mt-2">
            You reported receipt <b className="tnum">{claim.payment_log_id}</b>, paid on {paidDay(claim.paid_on)}{claim.amount != null ? <>, <span className="tnum">{nairaOf(claim.amount)}</span></> : null}.
            The Bursary looks for it in Interswitch&rsquo;s report and asks Interswitch to re-send it; it is confirmed here when it arrives.{" "}
            <button type="button" className="lnk" onClick={() => setReporting(true)}>Correct the receipt</button>
          </p>
        ) : (
          <p className="sub2 mt-2">
            Paid and holding the receipt? <button type="button" className="lnk" onClick={() => setReporting(true)}>Report the receipt</button>: its Payment Log Id lets the Bursary find the payment.
          </p>
        )}
        {state.longAgo && !claim ? (
          <p className="sub2 mt-2">Paid, and still not confirmed a day later? <a className="lnk" href={report.href}>{report.label}</a> with this reference and your bank&rsquo;s debit details, so the payment can be traced.</p>
        ) : null}
        {said ? <p className="sub2 mt-2"><b>{said}</b></p> : null}
      </div>
      {reporting ? <ReceiptForm reference={reference} claim={claim} onClose={() => setReporting(false)} onSaved={(c) => { setClaim(c); setReporting(false); }} /> : null}
    </div>
  );
}

function nairaOf(v: number | string): string {
  const n = Number(v);
  return Number.isFinite(n) ? `₦${n.toLocaleString("en-NG", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}` : String(v);
}

/**
 * V480: the receipt of a payment made on Quickteller or at a bank, reported against this reference: the Payment Log Id, the
 * day paid, the amount and where. A second report replaces the first. It confirms nothing; the Bursary finds the payment by it.
 */
function ReceiptForm({ reference, claim, onClose, onSaved }: {
  reference: string;
  claim: Claim | null;
  onClose: () => void;
  onSaved: (c: Claim) => void;
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
  async function send() {
    setTried(true);
    setRefused(null);
    if (Object.keys(problems).length > 0) return;
    setBusy(true);
    try {
      const r = await fetch("/api/bff/api/v1/payments/claims", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Receipt reported for ${reference}`) },
        body: JSON.stringify(claimBody(reference, f)),
      });
      const j = (await r.json().catch(() => null)) as (Claim & { detail?: string; title?: string }) | null;
      if (!r.ok || !j) {
        setRefused(j?.detail ?? j?.title ?? "The receipt could not be sent just now. Try again in a moment.");
        return;
      }
      notify(`Receipt reported: the Bursary will look for ${j.payment_log_id}.`);
      onSaved(j);
    } catch {
      setRefused("The portal could not be reached just now. Try again in a moment.");
    } finally {
      setBusy(false);
    }
  }
  return (
    <Modal title="Report the receipt" sub={<>For <b className="tnum">{reference}</b></>} onClose={onClose}
      foot={<><Btn kind="ghost" onClick={onClose} disabled={busy}>Cancel</Btn><Btn kind="primary" onClick={() => void send()} disabled={busy}>{busy ? "Sending…" : "Send the receipt"}</Btn></>}>
      <p>
        The Payment Log Id on Quickteller&rsquo;s receipt (or the bank&rsquo;s PayDirect slip) is what finds the payment.
        This does not confirm it: the payment counts when Interswitch reports it, and the Bursary uses your receipt to ask for it.
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
        <Field id="rc-where" label="Where you paid">
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

/** the line under every pay button: only this reference pays it */
export function OnlyThisReference({ reference, again }: { reference: string; again?: boolean }) {
  return (
    <div className="sub2 mt-1" style={{ flexBasis: "100%" }}>
      {again ? <><b>Pay only if no money left your account for this reference: the same reference is never paid twice.</b> </> : null}
      On Quickteller or at a bank, enter exactly <b className="tnum">{reference}</b>. Any other number, such as one starting with PR, is refused and pays nothing.
    </div>
  );
}
