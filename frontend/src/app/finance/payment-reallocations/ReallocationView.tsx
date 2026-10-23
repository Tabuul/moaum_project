"use client";

/**
 * One payment correction (V649): the payment as it was and as it is now, the student and where they sit, the original against the
 * destination (purpose, session, semester, level) with the fee, what was paid towards it, the amount moved and the balance or
 * surplus, the accounts before and after once executed, the reason, the evidence, the timeline and the payment's own history; and
 * what the officer may do — a Bursar officer other than the initiator approves (with the confirmation; it is executed at once),
 * returns it for correction or rejects it (with a reason), the initiator or the Bursar changes and sends again one returned or
 * cancels one open, the Bursar reverses one completed (another Bursar officer decides the reversal). The server refuses whatever
 * the officer may not do; these buttons only follow it.
 */
import { useState } from "react";
import type { Problem } from "@/lib/api";
import { Btn, Note, Pil } from "@/components/proto/ui";
import { Field, Modal, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { formatDocDateTime } from "@/lib/document/institution";
import {
  EVENT_WORDS, FLAG_WORDS, REASON_WORDS, STATUS_WORDS, evidenceRefusal, periodWords, reasonOk, refusalParts,
  type Account, type Destination, type Period, type ReallocCheck, type ReallocDetail,
} from "@/lib/payment-reallocations";
import { Calculation, NewReallocation } from "./NewReallocation";
import { REALLOCS, fileAsDataUrl, reallocGet, reallocPost } from "./realloc-call";

function paidOf(a?: Account | null): string {
  return a ? money(Number(a.paid)) : "—";
}

export function ReallocationView({ detail, office, destinations, onClose, onChanged }: {
  detail: ReallocDetail; office: string | null; destinations: Destination[]; onClose: () => void; onChanged: (d: ReallocDetail | null) => void;
}) {
  const x = detail.reallocation;
  const [act, setAct] = useState<"" | "approve" | "return" | "reject" | "cancel" | "reverse">("");
  const [note, setNote] = useState("");
  const [confirmed, setConfirmed] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<{ kind: "ok" | "bad" | "info"; title: string; body?: string } | null>(null);
  const [file, setFile] = useState<File | null>(null);
  const [editing, setEditing] = useState<{ base: ReallocCheck; periods: Period[] } | null>(null);
  const bursar = office === "bursar";
  const initiator = office === "bursar" || office === "studentaccounts";
  const pending = x.status === "PENDING_APPROVAL";
  const returned = x.status === "RETURNED";
  const flags = Array.isArray(x.flags) ? x.flags : typeof x.flags === "string" ? x.flags.replace(/[{}]/g, "").split(",").filter(Boolean) : [];

  async function send(path: string, body: unknown, reason: string): Promise<ReallocDetail | null> {
    setErr(null);
    const r = await reallocPost<ReallocDetail>(path, body, reason);
    if (!r.ok) { setErr(r.problem); notifyProblem(r.problem); return null; }
    return r.data;
  }

  async function decide(decision: "APPROVE" | "RETURN" | "REJECT") {
    const d = await send(`/${x.id}/decide`, { decision, note: note.trim() || null, confirmed: decision === "APPROVE" ? confirmed : false },
      `${decision === "APPROVE" ? "Approve" : decision === "RETURN" ? "Return" : "Reject"} payment correction ${x.realloc_ref}${note.trim() ? `: ${note.trim()}` : ""}`);
    if (!d) return;
    const status = d.result?.status ?? d.reallocation.status;
    if (status === "COMPLETED") {
      const bal = d.result?.balance;
      setSaid({ kind: "ok", title: "Payment reallocated successfully.",
        body: `${money(Number(x.amount))} now counts as ${x.to_purpose} (${x.to_session})${bal != null && Number(bal) > 0 ? `; ${money(Number(bal))} is left for the student to pay` : ""}. The student has been told.` });
      notify("Payment reallocated successfully.");
    } else if (status === "FAILED") {
      setSaid({ kind: "bad", title: "Payment correction failed — nothing was changed.", body: refusalParts(d.result?.failure ?? d.reallocation.failure ?? "").words });
    } else if (status === "RETURNED") {
      notify("Returned for correction.");
    } else if (status === "REJECTED") {
      notify("Payment correction rejected.");
    }
    setAct(""); setNote(""); setConfirmed(false);
    onChanged(d);
  }

  async function cancel() {
    const d = await send(`/${x.id}/cancel`, { reason: note.trim() }, `Cancel payment correction ${x.realloc_ref}: ${note.trim()}`);
    if (!d) return;
    notify("Payment correction cancelled.");
    setAct(""); setNote("");
    onChanged(d);
  }

  async function reverse() {
    const d = await send(`/${x.id}/reverse`, { reason: note.trim(), confirmed }, `Reverse payment correction ${x.realloc_ref}: ${note.trim()}`);
    if (!d) return;
    notify(`Reversal ${d.reallocation.realloc_ref} sent for approval`);
    setAct(""); setNote(""); setConfirmed(false);
    onChanged(d);
  }

  async function attach() {
    if (!file) return;
    const d = await send(`/${x.id}/evidence`, { filename: file.name, dataUrl: await fileAsDataUrl(file) }, `Evidence for ${x.realloc_ref}`);
    if (!d) return;
    setFile(null);
    onChanged(d);
  }

  async function edit() {
    setErr(null);
    const [b, p] = await Promise.all([reallocGet<ReallocCheck>(`/check?payment=${x.payment_id}`), reallocGet<Period[]>(`/periods?payment=${x.payment_id}`)]);
    if (!b.ok) { setErr(b.problem); notifyProblem(b.problem); return; }
    setEditing({ base: b.data, periods: p.ok ? p.data : [] });
  }

  const fileProblem = file ? evidenceRefusal(file) : null;
  const [kind, word] = STATUS_WORDS[x.status] ?? ["grey", x.status];
  const before = x.before_state ?? undefined;
  const after = x.after_state ?? undefined;
  const st = detail.student;

  if (editing) {
    return <NewReallocation destinations={destinations} returned={detail} returnedBase={editing.base} returnedPeriods={editing.periods}
      onClose={() => setEditing(null)} onDone={(d) => { setEditing(null); notify(`${d.reallocation.realloc_ref} sent again for approval`); onChanged(d); }} />;
  }

  return (
    <Modal wide title={<>{x.realloc_ref} <Pil kind={kind}>{word}</Pil>{x.kind === "REVERSAL" ? <> <Pil kind="info">Reversal of {x.reverses_ref}</Pil></> : null}</>}
      sub={`${x.reference} · ${money(Number(x.amount))} · ${x.from_purpose} → ${x.to_purpose}`} onClose={onClose}>
      {said ? <Note kind={said.kind} title={said.title}>{said.body}</Note> : null}
      {err ? <ProblemNotice problem={err} /> : null}
      {(pending || returned) && detail.refusalsNow?.length ? (
        <Note kind="bad" title="This correction no longer holds — approving it will fail and change nothing">
          {detail.refusalsNow.map((r) => <div key={r}>{refusalParts(r).words}</div>)}
        </Note>
      ) : null}
      {returned && x.returned_note ? <Note kind="info" title={`Returned for correction by ${x.returned_name ?? "the Bursar"}, ${formatDocDateTime(x.returned_at)}`}>{x.returned_note}</Note> : null}
      {x.failure ? <Note kind="bad" title="Why it failed">{refusalParts(x.failure).words}</Note> : null}
      {flags.map((f) => <Note key={f} kind="info" title="To follow up">{FLAG_WORDS[f] ?? f}</Note>)}
      {x.reversed_by_ref ? <Note kind="info" title={`Reversed by ${x.reversed_by_ref}`}>The payment is back on the purpose and session it carried before this correction.</Note> : null}

      <table className="tbl tbl--data">
        <tbody>
          {st ? <tr><td>Student</td><td>{st.name} · <span className="tnum">{st.matricNo ?? st.admissionNo ?? ""}</span><div className="sub2">{[st.programme, st.department, st.faculty].filter(Boolean).join(" · ")}</div></td></tr> : null}
          <tr><td>Payment reference</td><td className="tnum">{x.reference}{x.legacy ? <> <Pil kind="grey">Old portal</Pil></> : null}</td></tr>
          <tr><td>Amount</td><td className="tnum"><b>{money(Number(x.amount))}</b> — the whole payment</td></tr>
          <tr><td>Channel · receipt</td><td>{x.channel ?? "—"}{x.receipt_no ? ` · ${x.receipt_no}` : ""}</td></tr>
          <tr><td>Payment confirmed</td><td>{formatDocDateTime(x.payment_confirmed_at)} (unchanged by the correction)</td></tr>
          <tr><td>Counts now as</td><td>{x.purpose_now ?? "—"} ({x.session_now ?? "—"})</td></tr>
          <tr><td>What was wrong</td><td>{REASON_WORDS[x.reason_code] ?? x.reason_code}</td></tr>
          <tr><td>Reason</td><td>{x.reason}</td></tr>
          <tr><td>Evidence</td><td>{x.evidence ?? "—"}
            {detail.evidence.map((e) => <div key={e.id}><a href={`${REALLOCS}/${x.id}/evidence/${e.id}`} target="_blank" rel="noreferrer">{e.filename}</a> <span className="sub2">({Math.ceil(e.size_bytes / 1024)} KB, {e.added_by ?? ""})</span></div>)}
          </td></tr>
          <tr><td>Initiated</td><td>{x.initiated_name ?? "—"} ({x.initiated_office}) · {formatDocDateTime(x.initiated_at)}</td></tr>
          {x.decided_at ? <tr><td>Decided</td><td>{x.decided_name ?? "—"} ({x.decided_office}) · {formatDocDateTime(x.decided_at)}{x.decision_note ? ` — ${x.decision_note}` : ""}</td></tr> : null}
          {x.executed_at ? <tr><td>Executed</td><td>{formatDocDateTime(x.executed_at)}{x.journal_no ? ` · ledger journal #${x.journal_no} (reclassification, no bank line)` : " · nothing to reclassify on the ledger"}</td></tr> : null}
        </tbody>
      </table>

      <table className="tbl tbl--data" style={{ marginTop: 10 }}>
        <thead><tr><th /><th>Original</th><th>Destination</th></tr></thead>
        <tbody>
          <tr><td>Purpose</td><td>{x.from_purpose}</td><td>{x.to_purpose}</td></tr>
          <tr><td>Period</td><td>{periodWords(x.from_session, x.from_semester, x.from_level)}</td><td>{periodWords(x.to_session, x.to_semester, x.to_level)}</td></tr>
          <tr><td>Fee</td><td>—</td><td className="tnum">{x.destination_fee == null ? "—" : money(Number(x.destination_fee))}</td></tr>
          <tr><td>Paid towards it before</td><td>—</td><td className="tnum">{x.paid_before == null ? "—" : money(Number(x.paid_before))}</td></tr>
          <tr><td>{Number(x.surplus ?? 0) > 0 ? "Surplus" : "Balance after"}</td><td>—</td><td className="tnum"><b>{Number(x.surplus ?? 0) > 0 ? money(Number(x.surplus)) : x.balance_after == null ? "—" : money(Number(x.balance_after))}</b></td></tr>
          {before && after ? <tr><td>Paid (before → after)</td><td className="tnum">{paidOf(before.source)} → {paidOf(after.source)}</td><td className="tnum">{paidOf(before.destination)} → {paidOf(after.destination)}</td></tr> : null}
          {before && after ? <tr><td>Money received from the student</td><td colSpan={2} className="tnum">{money(Number(before.received))} → {money(Number(after.received))} (unchanged: no new revenue)</td></tr> : null}
        </tbody>
      </table>

      {(pending || returned) && detail.destination ? (
        <>
          <div className="eyebrow" style={{ marginTop: 12 }}>As the finance engine reads it now</div>
          <Calculation check={{ ok: !detail.refusalsNow?.length, refusals: detail.refusalsNow ?? [], destination: detail.destination, source: detail.source }} />
        </>
      ) : null}

      <div className="eyebrow" style={{ marginTop: 12 }}>Timeline</div>
      <table className="tbl tbl--data">
        <tbody>
          {detail.events.map((e, i) => (
            <tr key={i}><td className="sub2" style={{ whiteSpace: "nowrap" }}>{formatDocDateTime(e.at)}</td><td><b>{EVENT_WORDS[e.action] ?? e.action}</b>{e.note ? <div className="sub2">{e.note}</div> : null}</td><td className="sub2">{e.actor ?? ""}{e.actor_office ? ` (${e.actor_office})` : ""}</td></tr>
          ))}
        </tbody>
      </table>
      {detail.paymentHistory.length > 1 ? (
        <>
          <div className="eyebrow" style={{ marginTop: 12 }}>Payment history</div>
          <table className="tbl tbl--data">
            <tbody>
              {detail.paymentHistory.map((h) => (
                <tr key={h.ref}><td className="tnum">{h.ref}</td><td>{h.kind === "SWAP" ? "Swap" : h.kind === "REVERSAL" ? "Reversal" : "Correction"}</td><td>{h.from_what} → {h.to_what}</td><td>{h.status}</td><td className="sub2">{formatDocDateTime(h.executed_at ?? h.initiated_at)}</td></tr>
              ))}
            </tbody>
          </table>
        </>
      ) : null}

      {(pending || returned) && initiator ? (
        <div className="row" style={{ marginTop: 10, alignItems: "flex-end" }}>
          <Field id="ra-file" label="Add evidence" hint="PDF, JPEG or PNG, up to 5 MB" error={fileProblem ?? undefined}>
            <input id="ra-file" type="file" accept="application/pdf,image/jpeg,image/png" onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
          </Field>
          <Btn kind="ghost" disabled={!file || !!fileProblem} busyLabel="Attaching..." onClick={attach}>Attach</Btn>
        </div>
      ) : null}

      <div className="row" style={{ marginTop: 12, gap: 8, flexWrap: "wrap" }}>
        {pending && bursar && !x.initiated_by_me ? <Btn kind="go" onClick={() => { setAct("approve"); setNote(""); setConfirmed(false); }}>Approve</Btn> : null}
        {pending && bursar && x.initiated_by_me ? <Btn kind="ghost" disabled>Awaiting another Bursar officer</Btn> : null}
        {pending && bursar && !x.initiated_by_me ? <Btn kind="ghost" onClick={() => { setAct("return"); setNote(""); }}>Return for correction</Btn> : null}
        {pending && bursar && !x.initiated_by_me ? <Btn kind="ghost" onClick={() => { setAct("reject"); setNote(""); }}>Reject</Btn> : null}
        {returned && (x.initiated_by_me || bursar) && x.kind === "REALLOCATION" ? <Btn kind="primary" busyLabel="Loading..." onClick={edit}>Change and send again</Btn> : null}
        {(pending || returned) && (x.initiated_by_me || bursar) ? <Btn kind="ghost" onClick={() => { setAct("cancel"); setNote(""); }}>Cancel correction</Btn> : null}
        {x.status === "COMPLETED" && x.kind === "REALLOCATION" && bursar ? <Btn kind="urgent" onClick={() => { setAct("reverse"); setNote(""); setConfirmed(false); }}>Reverse this correction</Btn> : null}
        {!bursar && pending ? <span className="sub2">A Bursar officer other than the one who initiated it decides this correction.</span> : null}
      </div>

      {act === "approve" ? (
        <div className="card" style={{ padding: 12, marginTop: 10 }}>
          <b>Approve and execute</b>
          <div className="sub2">The payment counts at once as {x.to_purpose} ({x.to_session}). Its reference, amount, date and gateway record are unchanged; the ledger moves the income with no new cash.</div>
          <Field id="ra-note" label="Note" hint="Optional"><input id="ra-note" className="ctl" value={note} autoComplete="off" onChange={(e) => setNote(e.target.value)} /></Field>
          <label className="row row--inline" style={{ gap: 8, alignItems: "flex-start" }}>
            <input type="checkbox" checked={confirmed} onChange={(e) => setConfirmed(e.target.checked)} />
            <span>I confirm this payment belongs to {x.to_purpose} ({x.to_session}) and was applied to {x.from_purpose} in error.</span>
          </label>
          <div className="row" style={{ marginTop: 8 }}><span className="grow" /><Btn kind="ghost" onClick={() => setAct("")}>Back</Btn>
            <Btn kind="go" size="md" disabled={!confirmed} busyLabel="Executing..." onClick={() => decide("APPROVE")}>Approve and execute</Btn></div>
        </div>
      ) : null}
      {act === "return" || act === "reject" || act === "cancel" ? (
        <div className="card" style={{ padding: 12, marginTop: 10 }}>
          <Field id="ra-why" label={act === "return" ? "What is to be changed?" : act === "reject" ? "Why is it rejected?" : "Why is it cancelled?"} required hint="Ten characters or more; recorded on the correction">
            <input id="ra-why" className="ctl" value={note} autoComplete="off" onChange={(e) => setNote(e.target.value)} />
          </Field>
          <div className="row" style={{ marginTop: 8 }}><span className="grow" /><Btn kind="ghost" onClick={() => setAct("")}>Back</Btn>
            {act === "return" ? <Btn kind="secondary" disabled={note.trim().length < 10} busyLabel="Returning..." onClick={() => decide("RETURN")}>Return for correction</Btn>
              : act === "reject" ? <Btn kind="urgent" disabled={note.trim().length < 10} busyLabel="Rejecting..." onClick={() => decide("REJECT")}>Reject correction</Btn>
                : <Btn kind="urgent" disabled={note.trim().length < 10} busyLabel="Cancelling..." onClick={cancel}>Cancel correction</Btn>}</div>
        </div>
      ) : null}
      {act === "reverse" ? (
        <div className="card" style={{ padding: 12, marginTop: 10 }}>
          <b>Reverse {x.realloc_ref}</b>
          <div className="sub2">A reversal is a correction of its own: the payment goes back to {x.from_purpose} ({x.from_session}) once another Bursar officer approves it. This correction is never edited.</div>
          <Field id="ra-rv" label="Reason" required hint="Twenty characters or more">
            <textarea id="ra-rv" className="ctl" rows={2} value={note} onChange={(e) => setNote(e.target.value)} />
          </Field>
          <label className="row row--inline" style={{ gap: 8, alignItems: "flex-start" }}>
            <input type="checkbox" checked={confirmed} onChange={(e) => setConfirmed(e.target.checked)} />
            <span>I have checked that this payment belongs back to {x.from_purpose} ({x.from_session}).</span>
          </label>
          <div className="row" style={{ marginTop: 8 }}><span className="grow" /><Btn kind="ghost" onClick={() => setAct("")}>Back</Btn>
            <Btn kind="urgent" disabled={!confirmed || !reasonOk(note)} busyLabel="Submitting..." onClick={reverse}>Submit reversal for approval</Btn></div>
        </div>
      ) : null}
    </Modal>
  );
}
