"use client";

/**
 * The refund claims of withdrawn JUPEB candidates (V350), in the Bursary's own refund queue. A withdrawal that takes effect
 * opens a claim with every fee the candidate paid on the portal; the candidate gives the account. The Bursary decides under its
 * own rules: it raises a refund against one of the payments — which then waits in the refunds below for a second officer's
 * approval, exactly like any other refund, never more than was paid on that payment — or declines the claim with a reason the
 * candidate reads.
 */
import { useEffect, useState } from "react";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { FEE_KIND, day, jcall, naira, type RefundClaim } from "@/lib/jupeb";

interface Claim extends RefundClaim {
  application_id: string; application_no: string; name: string; session: string; email: string; phone: string | null; declined_by_name: string | null;
  refunds: (RefundClaim["refunds"][number] & { id: string; rejectedWhy: string | null })[];
}
const STATUS: Record<string, [string, "ok" | "info" | "bad" | "grey" | "warn"]> = {
  AWAITING_DETAILS: ["Waiting for the candidate's account", "grey"], WITH_BURSARY: ["To decide", "warn"], REFUND_PROPOSED: ["Refund awaiting approval", "info"],
  REFUND_APPROVED: ["Refund approved, to pay", "info"], REFUND_PAID: ["Refund paid", "ok"], DECLINED: ["Declined", "bad"],
};

export function JupebClaims({ may, onChanged }: { may: boolean; onChanged: () => void }) {
  const [claims, setClaims] = useState<Claim[] | null>(null);
  const [tick, setTick] = useState(0);
  const [raise, setRaise] = useState<{ claim: Claim; reference: string; amount: string; reason: string } | null>(null);
  const [decline, setDecline] = useState<{ claim: Claim; reason: string } | null>(null);
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let live = true;
    void jcall<Claim[]>("/api/v1/jupeb/fees/refund-claims").then((r) => { if (live) { if (r.ok) setClaims(r.data); else setClaims([]); } });
    return () => { live = false; };
  }, [tick]);
  if (!claims || !claims.length) return null;
  /** what is left to refund on a payment: what was paid, less refunds raised on it and not rejected */
  const left = (c: Claim, reference: string) => {
    const paid = Number(c.payments.find((p) => p.reference === reference)?.amount ?? 0);
    return paid - c.refunds.filter((r) => r.source === reference && r.state !== "REJECTED").reduce((a, r) => a + Number(r.amount), 0);
  };
  function openRaise(c: Claim) {
    const first = c.payments.find((p) => left(c, p.reference) > 0);
    if (!first) { notifyProblem({ status: 422, title: "Every payment on this claim is already refunded in full." }); return; }
    setRaise({ claim: c, reference: first.reference, amount: String(left(c, first.reference)), reason: `JUPEB withdrawal refund — ${c.application_no}` });
  }
  async function doRaise() {
    if (!raise) return;
    setBusy(true);
    try {
      const r = await jcall<{ reference: string }>(`/api/v1/jupeb/fees/refund-claims/${raise.claim.id}/refunds`, "POST",
        { reference: raise.reference, amount: Number(raise.amount), reason: raise.reason.trim() }, `JUPEB refund raised for ${raise.claim.name}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(`Refund ${r.data.reference} raised; a second officer approves it below.`);
      setRaise(null); setTick((t) => t + 1); onChanged();
    } finally { setBusy(false); }
  }
  async function doDecline() {
    if (!decline) return;
    setBusy(true);
    try {
      const r = await jcall(`/api/v1/jupeb/fees/refund-claims/${decline.claim.id}/decline`, "POST", { reason: decline.reason.trim() }, `JUPEB refund claim declined for ${decline.claim.name}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify("The claim is declined; the candidate is told the reason.");
      setDecline(null); setTick((t) => t + 1);
    } finally { setBusy(false); }
  }
  const open = claims.filter((c) => c.state.status === "WITH_BURSARY").length;
  const max = raise ? left(raise.claim, raise.reference) : 0;
  return (
    <Panel title={`JUPEB withdrawal refund claims${open ? ` — ${open} to decide` : ""}`}>
      <PBody>
        <p className="sub2">Raise a refund against a payment (a second officer approves it) or decline the claim with your reason.</p>
        <DTable pageSize={10} cols={["Candidate", "Opened", "Paid|num", "Account", "Refunds", "Stage", ...(may ? [""] : [])]}
          texts={claims.map((c) => `${c.name} ${c.application_no}`)}
          rows={claims.map((c) => [
            <span key="n"><b>{c.name}</b><div className="sub2 tnum">{c.application_no} · {c.session}</div></span>, day(c.opened_at),
            <span key="p">{naira(c.paid_total)}<div className="sub2">{c.payments.map((p) => FEE_KIND[p.kind] ?? p.kind).join(", ")}</div></span>,
            c.account_number ? <span key="a">{c.bank_name}<div className="sub2">{c.account_name} · <span className="tnum">{c.account_number}</span></div></span> : <span key="a" className="sub2">Not given yet</span>,
            c.refunds.length ? <span key="r">{c.refunds.map((r) => <div key={r.id} className="sub2"><span className="tnum">{r.reference}</span> · {naira(r.amount)} · {r.state.toLowerCase()}</div>)}</span> : "—",
            <span key="s"><Pil kind={(STATUS[c.state.status] ?? [c.state.status, "grey"])[1]}>{(STATUS[c.state.status] ?? [c.state.status])[0]}</Pil>{c.declined_reason ? <div className="sub2">{c.declined_reason}</div> : null}</span>,
            ...(may ? [c.declined_at ? "" : <span key="x" className="row row--inline row--tight">
              <Btn kind="secondary" disabled={!c.account_number || busy} onClick={() => openRaise(c)}>Raise a refund</Btn>
              {!["REFUND_PROPOSED", "REFUND_APPROVED", "REFUND_PAID"].includes(c.state.status) ? <Btn kind="ghost" disabled={busy} onClick={() => setDecline({ claim: c, reason: "" })}>Decline</Btn> : null}
            </span>] : []),
          ])} />
      </PBody>
      {raise ? (
        <Modal title={`Raise a refund — ${raise.claim.name}`} onClose={() => setRaise(null)}
          foot={<><Btn kind="ghost" onClick={() => setRaise(null)}>Cancel</Btn>
            <Btn kind="primary" disabled={busy || !(Number(raise.amount) > 0) || Number(raise.amount) > max || raise.reason.trim().length < 5} onClick={() => void doRaise()}>Raise the refund</Btn></>}>
          <Field id="jc-ref" label="Against the payment"><select id="jc-ref" className="ctl" value={raise.reference}
            onChange={(e) => setRaise({ ...raise, reference: e.target.value, amount: String(left(raise.claim, e.target.value)) })}>
            {raise.claim.payments.map((p) => <option key={p.reference} value={p.reference} disabled={left(raise.claim, p.reference) <= 0}>
              {`${FEE_KIND[p.kind] ?? p.kind} · ${p.reference} · ${naira(p.amount)}${left(raise.claim, p.reference) < Number(p.amount) ? ` (${naira(left(raise.claim, p.reference))} left)` : ""}`}</option>)}</select></Field>
          <Field id="jc-amt" label="Amount (₦)" required hint={`At most ${naira(max)} on this payment`} error={Number(raise.amount) > max ? "More than is left on the payment" : undefined}>
            <input id="jc-amt" className="ctl" type="number" min={0.01} step="0.01" value={raise.amount} onChange={(e) => setRaise({ ...raise, amount: e.target.value })} /></Field>
          <Field id="jc-why" label="Reason" required><input id="jc-why" className="ctl" maxLength={400} value={raise.reason} onChange={(e) => setRaise({ ...raise, reason: e.target.value })} /></Field>
          <Note kind="info" title="Paid into the account the candidate gave">{`${raise.claim.bank_name} · ${raise.claim.account_name} · ${raise.claim.account_number}. The refund is paid only after another officer approves it.`}</Note>
        </Modal>
      ) : null}
      {decline ? (
        <Modal title={`Decline the claim — ${decline.claim.name}`} onClose={() => setDecline(null)}
          foot={<><Btn kind="ghost" onClick={() => setDecline(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || decline.reason.trim().length < 5} onClick={() => void doDecline()}>Decline</Btn></>}>
          <Field id="jc-dr" label="Why no refund is made" required hint="The candidate reads this"><textarea id="jc-dr" className="ctl" rows={3} maxLength={1000} value={decline.reason} onChange={(e) => setDecline({ ...decline, reason: e.target.value })} /></Field>
        </Modal>
      ) : null}
    </Panel>
  );
}
