"use client";

/**
 * Archive a payment (V670): the payment found on the server — by its reference, receipt, old-portal number, the gateway's or a
 * transaction reference, or the student's matriculation, JAMB, admission or application number or name — with whether it may be
 * archived and why not; the reason from the Bursary's list; the payment it repeats where the reason asks (found the same way); what
 * was found, in twenty characters or more; and the confirmation that it leaves the student's paid figures and income until it is
 * verified. The server decides everything.
 */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { Btn, Note, Pil } from "@/components/proto/ui";
import { Field, Modal, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { formatDocDateTime } from "@/lib/document/institution";
import { longEnough, refusalParts, type ArchiveDetail, type Catalogue, type FoundPayment } from "@/lib/payment-archive";
import { archiveGet, archivePost } from "./archive-call";

function PaymentPicker({ id, label, hint, onPick, exclude, pickedId, onlyEligible, initial }: {
  id: string; label: string; hint: string; onPick: (p: FoundPayment) => void; exclude?: string | null; pickedId?: string | null; onlyEligible: boolean; initial?: string;
}) {
  const [q, setQ] = useState(initial ?? "");
  const [rows, setRows] = useState<FoundPayment[] | null>(null);
  const [err, setErr] = useState<Problem | null>(null);
  async function find(t: string) {
    setErr(null);
    const r = await archiveGet<FoundPayment[]>(`/payments?q=${encodeURIComponent(t.trim())}`);
    if (!r.ok) { setErr(r.problem); setRows(null); return; }
    setRows(r.data.filter((p) => p.id !== exclude));
  }
  // a payment named already (from the possible duplicates) is looked up once, its answer set when it comes
  useEffect(() => {
    if (!initial) return;
    let live = true;
    void archiveGet<FoundPayment[]>(`/payments?q=${encodeURIComponent(initial.trim())}`).then((r) => {
      if (!live) return;
      if (r.ok) setRows(r.data.filter((p) => p.id !== exclude)); else setErr(r.problem);
    });
    return () => { live = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  return (
    <div>
      <div className="row" style={{ gap: 8, alignItems: "flex-end" }}>
        <Field id={id} label={label} hint={hint}>
          <input id={id} className="ctl" value={q} autoComplete="off" onChange={(e) => setQ(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter" && q.trim().length >= 3) void find(q); }} />
        </Field>
        <Btn kind="secondary" disabled={q.trim().length < 3} busyLabel="Searching..." onClick={() => find(q)}>Find</Btn>
      </div>
      {err ? <ProblemNotice problem={err} /> : null}
      {rows ? (
        rows.length ? (
          <table className="tbl tbl--data" style={{ marginTop: 6 }}>
            <tbody>
              {rows.map((p) => {
                const blocked = onlyEligible && !p.eligible;
                return (
                  <tr key={p.id} style={pickedId === p.id ? { outline: "2px solid var(--chrome)" } : undefined}>
                    <td className="tnum">{p.reference}<div className="sub2">{p.legacy_payref ? `old ${p.legacy_payref} · ` : ""}{p.channel ?? ""}{p.receipt_no ? ` · ${p.receipt_no}` : ""}</div></td>
                    <td>{p.name}<div className="sub2 tnum">{p.matric_no ?? p.admission_no ?? ""}</div></td>
                    <td>{p.purpose}<div className="sub2">{p.session} · paid {formatDocDateTime(p.confirmed_at)}</div></td>
                    <td className="num tnum"><b>{money(Number(p.amount))}</b></td>
                    <td>
                      {p.archived_at ? <Pil kind="warn">Archived</Pil> : null}
                      {blocked ? <div className="sub2">{p.refusals.map((r) => <div key={r}>{refusalParts(r).words}</div>)}</div>
                        : <Btn kind={pickedId === p.id ? "primary" : "ghost"} onClick={() => onPick(p)}>{pickedId === p.id ? "Chosen" : "Choose"}</Btn>}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        ) : <div className="sub2">No confirmed payment matches.</div>
      ) : null}
    </div>
  );
}

export function NewArchive({ catalogue, preset, onClose, onDone }: {
  catalogue: Catalogue; preset: { payment?: string; related?: string; reason?: string }; onClose: () => void; onDone: (d: ArchiveDetail) => void;
}) {
  const [payment, setPayment] = useState<FoundPayment | null>(null);
  const [related, setRelated] = useState<FoundPayment | null>(null);
  const [reason, setReason] = useState(preset.reason ?? "");
  const [note, setNote] = useState("");
  const [confirmed, setConfirmed] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const chosen = catalogue.reasons.find((r) => r.code === reason);

  async function submit() {
    if (!payment) return;
    setErr(null);
    const r = await archivePost<ArchiveDetail>("", { payment: payment.id, reason, related: related?.id ?? null, note: note.trim(), confirmed },
      `Archive payment ${payment.reference} for review: ${chosen?.label ?? reason}`);
    if (!r.ok) { setErr(r.problem); return; }
    onDone(r.data);
  }

  const ready = !!payment && !!reason && (!chosen?.needs_related || !!related) && longEnough(note, 20) && confirmed;

  return (
    <Modal wide title="Archive a payment for review" sub="Kept as it was received, and counted nowhere until the Bursary settles it" onClose={onClose}>
      {err ? <ProblemNotice problem={err} /> : null}
      <div className="eyebrow">1 · The payment</div>
      <PaymentPicker id="na-pay" label="Find the payment" hint="Payment reference, receipt, old-portal number, gateway or transaction reference, matriculation, JAMB or application number, or name"
        onPick={setPayment} pickedId={payment?.id} onlyEligible initial={preset.payment} />

      <div className="eyebrow" style={{ marginTop: 12 }}>2 · Why it is archived</div>
      <Field id="na-reason" label="Reason" required hint={chosen?.explanation ?? "From the Bursary's list"}>
        <select id="na-reason" className="ctl" value={reason} onChange={(e) => { setReason(e.target.value); if (!catalogue.reasons.find((r) => r.code === e.target.value)?.needs_related) setRelated(null); }}>
          <option value="">Choose…</option>
          {catalogue.reasons.map((r) => <option key={r.code} value={r.code}>{r.label}</option>)}
        </select>
      </Field>
      {chosen?.needs_related ? (
        <div style={{ marginTop: 8 }}>
          <PaymentPicker id="na-rel" label="The payment it repeats (kept and counted)" hint="The record that stays; found the same way"
            onPick={setRelated} pickedId={related?.id} exclude={payment?.id} onlyEligible={false} initial={preset.related} />
          <Note kind="info" title="A duplicate is confirmed later, on proof">
            The same amount, student, day or purpose is never proof. When the settlement is proposed, the two must share an identifier (the gateway&apos;s or a
            transaction reference, an old-portal payment number) or strong evidence must be recorded (a bank statement, the gateway&apos;s or the bank&apos;s reference).
          </Note>
        </div>
      ) : null}
      <Field id="na-note" label="What was found" required hint="Twenty characters or more; kept with the archive">
        <textarea id="na-note" className="ctl" rows={3} value={note} onChange={(e) => setNote(e.target.value)} />
      </Field>

      {payment ? (
        <div className="card" style={{ padding: 12, marginTop: 10 }}>
          <b>{money(Number(payment.amount))}</b> · {payment.reference} · {payment.purpose} ({payment.session}) on {payment.name}
          <div className="sub2">From the moment it is archived this payment is not counted in {payment.name}&apos;s verified payments or fees, grants nothing, and is not income
            (its ledger posting moves to Payments under review). The student is told it is under review; nothing of anyone else is said.</div>
          <label className="row row--inline" style={{ gap: 8, alignItems: "flex-start", marginTop: 8 }}>
            <input type="checkbox" checked={confirmed} onChange={(e) => setConfirmed(e.target.checked)} />
            <span>I confirm this payment is to be taken out of the student&apos;s paid figures and out of income until it is verified.</span>
          </label>
        </div>
      ) : null}
      <div className="row" style={{ marginTop: 12 }}>
        <span className="grow" />
        <Btn kind="ghost" onClick={onClose}>Cancel</Btn>
        <Btn kind="urgent" disabled={!ready} busyLabel="Archiving..." onClick={submit}>Archive for review</Btn>
      </div>
    </Modal>
  );
}
