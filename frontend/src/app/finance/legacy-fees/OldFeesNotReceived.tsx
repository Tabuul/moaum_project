"use client";

/** V561: old-portal payment records the bank shows never arrived — raised for withdrawal on evidence (from a bank check of a
 *  possible double charge, or for a reference on its own) by one Bursary officer and approved by another. Approved, the record is
 *  withdrawn: its ledger posting reversed, the record kept on the withdrawn list, its payment number remembered so the export
 *  loaded again never brings it back, and the student told. Rejected with a note, or cancelled by the officer who raised it. */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, money } from "@/components/proto/blocks";
import { PNR_STATE, pnrPath, type NotReceived, type NotReceivedList, type PnrState } from "@/lib/double-charges";

interface Deciding { w: NotReceived; approve: boolean; note: string }

export function OldFeesNotReceived({ may, tick = 0, onChanged }: { may: boolean; tick?: number; onChanged?: () => void }) {
  const [state, setState] = useState<"" | PnrState>("");
  const [data, setData] = useState<NotReceivedList | null>(null);
  const [answered, setAnswered] = useState<string | null>(null);
  const [own, setOwn] = useState(0);
  const [raising, setRaising] = useState<{ reference: string; evidence: string; reason: string } | null>(null);
  const [deciding, setDeciding] = useState<Deciding | null>(null);

  const listUrl = `/api/bff/api/v1/finance/payments-not-received${state ? `?state=${state}` : ""}`;
  const asked = `${listUrl}#${tick}#${own}`;
  const loading = answered !== asked;

  useEffect(() => {
    let alive = true;
    void (async () => {
      const r = await fetch(listUrl, { cache: "no-store" }).catch(() => null);
      const j = r ? await r.json().catch(() => null) : null;
      if (!alive) return;
      setAnswered(asked);
      if (!r || !r.ok) { notifyProblem((j ?? { status: r?.status ?? 0, title: r?.statusText || "The portal could not be reached" }) as Problem); return; }
      setData(j as NotReceivedList);
    })();
    return () => { alive = false; };
  }, [listUrl, asked]);

  async function post(path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    const r = await fetch(`/api/bff/api/v1/finance/payments-not-received${path}`, {
      method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}),
    });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem((j ?? { status: r.status, title: r.statusText }) as Problem); return null; }
    setOwn((x) => x + 1);
    onChanged?.();
    return j as Record<string, unknown>;
  }

  async function raise() {
    if (!raising) return;
    const j = await post("", { reference: raising.reference.trim().toUpperCase(), evidence: raising.evidence.trim(), reason: raising.reason.trim() },
      `Payment ${raising.reference.trim()} raised for withdrawal: the bank never received it — ${raising.evidence.trim()}`);
    if (j) { notify(`Withdrawal ${String(j.requestRef)} raised for another Bursary officer to approve`); setRaising(null); }
  }

  async function decide() {
    if (!deciding) return;
    const path = pnrPath(deciding.w.request_ref);
    if (!path) return;
    const j = await post(`/${path}/decide`, { approve: deciding.approve, note: deciding.note.trim() || null },
      `Withdrawal ${deciding.w.request_ref} ${deciding.approve ? "approved" : "rejected"}${deciding.note.trim() ? `: ${deciding.note.trim()}` : ""}`);
    if (j) { notify(deciding.approve ? `${deciding.w.reference} withdrawn; the student is told` : `${deciding.w.request_ref} rejected`); setDeciding(null); }
  }

  async function cancel(w: NotReceived) {
    const path = pnrPath(w.request_ref);
    if (!path) return;
    const j = await post(`/${path}/cancel`, {}, `Withdrawal ${w.request_ref} cancelled`);
    if (j) notify(`${w.request_ref} cancelled`);
  }

  const c = data?.counts ?? {};
  return (
    <Panel title="Payments the bank never received" right="Old-portal payment records withdrawn on evidence: raised by one Bursary officer, approved by another">
      <PBody>
        <Tiles items={[
          ["Waiting for approval", String(c.PROPOSED ?? 0), c.PROPOSED ? "var(--amber-ink)" : null, "Another Bursary officer approves or rejects each"],
          ["Withdrawn", String(c.APPROVED ?? 0), null, `${money(Number(data?.withdrawn ?? 0))} taken off students' accounts`],
          ["Rejected or cancelled", String((c.REJECTED ?? 0) + (c.CANCELLED ?? 0)), null, "The record stands"],
        ]} cls="grid--3" />
        <div className="row mt-2" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
          <Field id="pnr-state" label="Show" style={{ flex: "0 1 200px" }}>
            <select id="pnr-state" className="ctl" value={state} onChange={(e) => setState(e.target.value as "" | PnrState)} disabled={loading}>
              <option value="">Every withdrawal</option>
              {(Object.keys(PNR_STATE) as PnrState[]).map((s) => <option key={s} value={s}>{PNR_STATE[s][0]}</option>)}
            </select>
          </Field>
          {may ? <Btn kind="ghost" onClick={() => setRaising({ reference: "", evidence: "", reason: "" })}>Raise for a payment reference…</Btn> : null}
          {loading && data ? <span className="sub2" role="status">Looking…</span> : null}
        </div>
      </PBody>
      {data && data.rows.length ? (
        <DTable pageSize={0} cols={["Withdrawal", "Student", "Payment", "Amount|num", "Evidence and reason", "State", ""]} rows={data.rows.map((w) => [
          <span key="r" className="tnum">{w.request_ref}<div className="sub2">{w.from_check ? "From a bank check" : "Raised on its own"}</div></span>,
          <Two key="s" a={w.name} b={w.number} />,
          <span key="p" className="sub2 tnum">{w.reference}<div>{w.purpose} · {w.paid_on ?? "—"}{w.payref ? ` · ${w.payref}` : ""}</div>
            {w.kept_reference ? <div>Stands: {w.kept_reference}</div> : null}</span>,
          <span key="a" className="tnum">{money(Number(w.amount))}</span>,
          <span key="e" className="sub2">{w.evidence}<div>{w.reason}</div></span>,
          <span key="t"><Pil kind={PNR_STATE[w.state][1]}>{PNR_STATE[w.state][0]}</Pil>
            <div className="sub2">Raised by {w.raised_by ?? "—"}{w.decided_by ? ` · ${w.state === "CANCELLED" ? "cancelled" : "decided"} by ${w.decided_by}` : ""}</div>
            {w.decision_note ? <div className="sub2">{w.decision_note}</div> : null}</span>,
          may && w.state === "PROPOSED" ? (
            <span key="b" className="row" style={{ gap: "var(--s-2)" }}>
              {w.mine ? <Btn kind="ghost" size="sm" busyLabel="Cancelling…" onClick={() => cancel(w)}>Cancel</Btn> : <>
                <Btn kind="primary" size="sm" onClick={() => setDeciding({ w, approve: true, note: "" })}>Approve…</Btn>
                <Btn kind="ghost" size="sm" onClick={() => setDeciding({ w, approve: false, note: "" })}>Reject…</Btn>
              </>}
            </span>
          ) : <span key="b" />,
        ])} />
      ) : data ? <PBody><div className="sub2">No withdrawal{state ? ` ${PNR_STATE[state][0].toLowerCase()}` : ""}.</div></PBody> : <PBody><div className="sub2">Looking…</div></PBody>}

      {raising ? (
        <Modal title="Raise the withdrawal of a payment the bank never received" sub="Another Bursary officer approves it" onClose={() => setRaising(null)}
          foot={<><Btn kind="ghost" onClick={() => setRaising(null)}>Cancel</Btn>
            <Btn kind="primary" disabled={!raising.reference.trim() || raising.evidence.trim().length < 5 || raising.reason.trim().length < 10} busyLabel="Raising…"
              onClick={() => raise()}>Raise</Btn></>}>
          <Note kind="info" title="Only an old-portal payment record">
            A record imported from the old portal (MOAUM-LEG-…) that the University&rsquo;s bank statement shows never arrived. A record holding several payments, one a refund
            or deferment fee points at, one in a payment swap, or one whose session&rsquo;s overpayment was already carried or refunded is refused.
          </Note>
          <Field id="pnr-ref" label="Payment reference" required>
            <input id="pnr-ref" className="ctl tnum" maxLength={120} value={raising.reference} onChange={(e) => setRaising({ ...raising, reference: e.target.value })}
              placeholder="MOAUM-LEG-…" />
          </Field>
          <Field id="pnr-evidence" label="Evidence" required hint="The statement or report, its date and the line read">
            <input id="pnr-evidence" className="ctl" maxLength={500} value={raising.evidence} onChange={(e) => setRaising({ ...raising, evidence: e.target.value })} />
          </Field>
          <Field id="pnr-reason" label="Reason" required hint="At least ten characters">
            <textarea id="pnr-reason" className="ctl" rows={2} maxLength={500} value={raising.reason} onChange={(e) => setRaising({ ...raising, reason: e.target.value })} />
          </Field>
        </Modal>
      ) : null}

      {deciding ? (
        <Modal title={`${deciding.approve ? "Approve" : "Reject"} ${deciding.w.request_ref}`} sub={`${deciding.w.name} · ${deciding.w.reference} · ${money(Number(deciding.w.amount))}`}
          onClose={() => setDeciding(null)}
          foot={<><Btn kind="ghost" onClick={() => setDeciding(null)}>Cancel</Btn>
            <Btn kind="primary" disabled={!deciding.approve && deciding.note.trim().length < 5} busyLabel={deciding.approve ? "Withdrawing…" : "Rejecting…"}
              onClick={() => decide()}>{deciding.approve ? "Withdraw the record" : "Reject"}</Btn></>}>
          {deciding.approve ? (
            <Note kind="bad" title="The record comes off the student's account">
              The payment of {money(Number(deciding.w.amount))} recorded on {deciding.w.paid_on ?? "—"} is withdrawn: its ledger posting is reversed, the record is kept on the
              withdrawn list, its payment number is remembered so the export loaded again does not bring it back, and the student is told by e-mail, text and on the portal.
              Evidence: {deciding.w.evidence}.
            </Note>
          ) : null}
          <Field id="pnr-note" label={deciding.approve ? "Note (optional)" : "Why it is rejected"} required={!deciding.approve}>
            <input id="pnr-note" className="ctl" maxLength={500} value={deciding.note} onChange={(e) => setDeciding({ ...deciding, note: e.target.value })} />
          </Field>
        </Modal>
      ) : null}
    </Panel>
  );
}
