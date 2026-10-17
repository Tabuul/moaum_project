"use client";

/**
 * One payment swap (V527): the payment as it was, both students with their accounts (before and after once executed, as they
 * stand while it waits), the reason, the evidence, the timeline and the payment's own history of swaps; and what the officer
 * may do — a Bursar officer other than the initiator approves (with the ownership confirmation; it is executed at once) or
 * rejects (with a reason), the initiator or the Bursar cancels one waiting, the Bursar reverses one completed (another Bursar
 * officer decides the reversal). The server refuses whatever the officer may not do; these buttons only follow it.
 */
import { useState } from "react";
import type { Problem } from "@/lib/api";
import { Btn, Note, Pil } from "@/components/proto/ui";
import { Field, Modal, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { formatDocDateTime } from "@/lib/document/institution";
import { EVENT_WORDS, FLAG_WORDS, clearsWord, STATUS_WORDS, evidenceRefusal, reasonOk, refusalParts, studentLine, type SwapAccount, type SwapDetail, type SwapProfile } from "@/lib/payment-swaps";
import { SWAPS, fileAsDataUrl, swapPost } from "./swap-call";

function Side({ title, profile, now, before, after }: { title: string; profile: SwapProfile; now: SwapAccount; before?: SwapAccount; after?: SwapAccount }) {
  const rows: [string, (a: SwapAccount) => React.ReactNode][] = [
    ["School fees due", (a) => money(Number(a.due))],
    ["Paid", (a) => money(Number(a.paid))],
    ["Balance", (a) => <b>{money(Number(a.balance))}</b>],
    ["Clears registration", (a) => clearsWord(a.clearsRegistration)],
    ["Clears examination", (a) => clearsWord(a.clearsExamination)],
  ];
  return (
    <div className="card" style={{ padding: 12, minWidth: 0 }}>
      <div className="eyebrow">{title}</div>
      <b>{profile.name}</b>
      <div className="sub2 tnum">{profile.matric_no ?? profile.admission_no ?? ""}{profile.jamb_reg_no ? ` · JAMB ${profile.jamb_reg_no}` : ""}</div>
      <div className="sub2">{[profile.programme, profile.department, profile.faculty].filter(Boolean).join(" · ")}</div>
      <table className="tbl tbl--data" style={{ marginTop: 8 }}>
        <thead><tr><th />{before ? <th className="num">Before</th> : null}{after ? <th className="num">After</th> : null}<th className="num">Now</th></tr></thead>
        <tbody>
          {rows.map(([label, cell]) => (
            <tr key={label}><td>{label}</td>{before ? <td className="num tnum">{cell(before)}</td> : null}{after ? <td className="num tnum">{cell(after)}</td> : null}<td className="num tnum">{cell(now)}</td></tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function SwapView({ detail, office, onClose, onChanged }: { detail: SwapDetail; office: string | null; onClose: () => void; onChanged: (d: SwapDetail | null) => void }) {
  const s = detail.swap;
  const [act, setAct] = useState<"" | "approve" | "reject" | "cancel" | "reverse">("");
  const [note, setNote] = useState("");
  const [confirmed, setConfirmed] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<{ kind: "ok" | "bad" | "info"; title: string; body?: string } | null>(null);
  const bursar = office === "bursar";
  const initiator = office === "bursar" || office === "studentaccounts";
  const pending = s.status === "PENDING_APPROVAL";
  const flags = Array.isArray(s.flags) ? s.flags : typeof s.flags === "string" ? s.flags.replace(/[{}]/g, "").split(",").filter(Boolean) : [];
  const [file, setFile] = useState<File | null>(null);

  async function send(path: string, body: unknown, reason: string): Promise<SwapDetail | null> {
    setErr(null);
    const r = await swapPost<SwapDetail>(path, body, reason);
    if (!r.ok) { setErr(r.problem); notifyProblem(r.problem); return null; }
    return r.data;
  }

  async function approve() {
    const d = await send(`/${s.id}/decide`, { approve: true, note: note.trim() || null, confirmed }, `Approve payment swap ${s.swap_ref}`);
    if (!d) return;
    const status = d.result?.status ?? d.swap.status;
    if (status === "COMPLETED") {
      setSaid({ kind: "ok", title: "Payment swap completed successfully.", body: `${money(Number(s.amount))} now counts for ${studentLine(d.to)}; ${studentLine(d.from)}'s account no longer carries it. Both students have been told.` });
      notify("Payment swap completed successfully.");
    } else if (status === "FAILED") {
      setSaid({ kind: "bad", title: "Payment swap failed — nothing was changed.", body: refusalParts(d.result?.failure ?? d.swap.failure ?? "").words });
    }
    setAct(""); setNote(""); setConfirmed(false);
    onChanged(d);
  }

  async function reject() {
    const d = await send(`/${s.id}/decide`, { approve: false, note: note.trim(), confirmed: false }, `Reject payment swap ${s.swap_ref}: ${note.trim()}`);
    if (!d) return;
    setSaid({ kind: "info", title: "Payment swap rejected." });
    notify("Payment swap rejected.");
    setAct(""); setNote("");
    onChanged(d);
  }

  async function cancel() {
    const d = await send(`/${s.id}/cancel`, { reason: note.trim() }, `Cancel payment swap ${s.swap_ref}: ${note.trim()}`);
    if (!d) return;
    setSaid({ kind: "info", title: "Payment swap cancelled." });
    setAct(""); setNote("");
    onChanged(d);
  }

  async function reverse() {
    const d = await send(`/${s.id}/reverse`, { reason: note.trim(), confirmed }, `Reverse payment swap ${s.swap_ref}: ${note.trim()}`);
    if (!d) return;
    notify(`Reversal ${d.swap.swap_ref} sent for approval`);
    setAct(""); setNote(""); setConfirmed(false);
    onChanged(d);
  }

  async function attach() {
    if (!file) return;
    const d = await send(`/${s.id}/evidence`, { filename: file.name, dataUrl: await fileAsDataUrl(file) }, `Evidence for ${s.swap_ref}`);
    if (!d) return;
    setFile(null);
    onChanged(d);
  }

  const fileProblem = file ? evidenceRefusal(file) : null;
  const before = s.before_state ?? undefined;
  const after = s.after_state ?? undefined;
  const [kind, word] = STATUS_WORDS[s.status] ?? ["grey", s.status];

  return (
    <Modal wide title={<>{s.swap_ref} <Pil kind={kind}>{word}</Pil>{s.kind === "REVERSAL" ? <> <Pil kind="info">Reversal of {s.reverses_ref}</Pil></> : null}</>}
      sub={`${s.reference} · ${money(Number(s.amount))} · ${s.session}`} onClose={onClose}>
      {said ? <Note kind={said.kind} title={said.title}>{said.body}</Note> : null}
      {err ? <ProblemNotice problem={err} /> : null}
      {pending && detail.refusalsNow?.length ? (
        <Note kind="bad" title="This swap no longer holds — approving it will fail and change nothing">
          {detail.refusalsNow.map((r) => <div key={r}>{refusalParts(r).words}</div>)}
        </Note>
      ) : null}
      {s.failure ? <Note kind="bad" title="Why it failed">{refusalParts(s.failure).words}</Note> : null}
      {flags.map((f) => <Note key={f} kind="info" title="To follow up">{FLAG_WORDS[f] ?? f}</Note>)}
      {s.reversed_by_ref ? <Note kind="info" title={`Reversed by ${s.reversed_by_ref}`}>The payment is back with the student it was first credited to.</Note> : null}

      <table className="tbl tbl--data">
        <tbody>
          <tr><td>Payment reference</td><td className="tnum">{s.reference}{s.legacy ? <> <Pil kind="grey">Old portal</Pil></> : null}</td></tr>
          <tr><td>Purpose</td><td>{s.purpose}</td></tr>
          <tr><td>Amount</td><td className="tnum"><b>{money(Number(s.amount))}</b> — the whole payment</td></tr>
          <tr><td>Channel · receipt</td><td>{s.channel ?? "—"}{s.receipt_no ? ` · ${s.receipt_no}` : ""}</td></tr>
          <tr><td>Payment confirmed</td><td>{formatDocDateTime(s.payment_confirmed_at)} (unchanged by the swap)</td></tr>
          <tr><td>Reason</td><td>{s.reason}</td></tr>
          <tr><td>Evidence</td><td>{s.evidence ?? "—"}
            {detail.evidence.map((e) => <div key={e.id}><a href={`${SWAPS}/${s.id}/evidence/${e.id}`} target="_blank" rel="noreferrer">{e.filename}</a> <span className="sub2">({Math.ceil(e.size_bytes / 1024)} KB, {e.added_by ?? ""})</span></div>)}
          </td></tr>
          <tr><td>Initiated</td><td>{s.initiated_name ?? "—"} ({s.initiated_office}) · {formatDocDateTime(s.initiated_at)}</td></tr>
          {s.decided_at ? <tr><td>Decided</td><td>{s.decided_name ?? "—"} ({s.decided_office}) · {formatDocDateTime(s.decided_at)}{s.decision_note ? ` — ${s.decision_note}` : ""}</td></tr> : null}
          {s.executed_at ? <tr><td>Executed</td><td>{formatDocDateTime(s.executed_at)}</td></tr> : null}
        </tbody>
      </table>

      <div className="grid grid--2" style={{ marginTop: 10 }}>
        <Side title="From — credited in error" profile={detail.from} now={detail.fromAccount} before={before?.from} after={after?.from} />
        <Side title="To — the student it belongs to" profile={detail.to} now={detail.toAccount} before={before?.to} after={after?.to} />
      </div>

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
          <div className="eyebrow" style={{ marginTop: 12 }}>Every swap of this payment</div>
          <table className="tbl tbl--data">
            <tbody>
              {detail.paymentHistory.map((h) => (
                <tr key={h.swap_ref}><td className="tnum">{h.swap_ref}</td><td>{h.kind === "REVERSAL" ? "Reversal" : "Swap"}</td><td className="tnum">{h.from_matric} → {h.to_matric}</td><td>{STATUS_WORDS[h.status]?.[1] ?? h.status}</td><td className="sub2">{formatDocDateTime(h.executed_at ?? h.initiated_at)}</td></tr>
              ))}
            </tbody>
          </table>
        </>
      ) : null}

      {pending && initiator ? (
        <div className="row" style={{ marginTop: 10, alignItems: "flex-end" }}>
          <Field id="sw-file" label="Add evidence" hint="PDF, JPEG or PNG, up to 5 MB" error={fileProblem ?? undefined}>
            <input id="sw-file" type="file" accept="application/pdf,image/jpeg,image/png" onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
          </Field>
          <Btn kind="ghost" disabled={!file || !!fileProblem} busyLabel="Attaching..." onClick={attach}>Attach</Btn>
        </div>
      ) : null}

      <div className="row" style={{ marginTop: 12, gap: 8, flexWrap: "wrap" }}>
        {pending && bursar && !s.initiated_by_me ? <Btn kind="go" onClick={() => { setAct("approve"); setNote(""); setConfirmed(false); }}>Approve</Btn> : null}
        {pending && bursar && s.initiated_by_me ? <Btn kind="ghost" disabled>Awaiting another Bursar officer</Btn> : null}
        {pending && bursar && !s.initiated_by_me ? <Btn kind="ghost" onClick={() => { setAct("reject"); setNote(""); }}>Reject</Btn> : null}
        {pending && (s.initiated_by_me || bursar) ? <Btn kind="ghost" onClick={() => { setAct("cancel"); setNote(""); }}>Cancel swap</Btn> : null}
        {s.status === "COMPLETED" && s.kind === "SWAP" && bursar ? <Btn kind="urgent" onClick={() => { setAct("reverse"); setNote(""); setConfirmed(false); }}>Reverse this swap</Btn> : null}
        {!bursar && pending ? <span className="sub2">A Bursar officer other than the one who initiated it decides this swap.</span> : null}
      </div>

      {act === "approve" ? (
        <div className="card" style={{ padding: 12, marginTop: 10 }}>
          <b>Approve and execute</b>
          <div className="sub2">The payment moves at once from {studentLine(detail.from)} to {studentLine(detail.to)}. Its reference, amount, date and gateway record are unchanged.</div>
          <Field id="sw-note" label="Note" hint="Optional"><input id="sw-note" className="ctl" value={note} autoComplete="off" onChange={(e) => setNote(e.target.value)} /></Field>
          <label className="row row--inline" style={{ gap: 8, alignItems: "flex-start" }}>
            <input type="checkbox" checked={confirmed} onChange={(e) => setConfirmed(e.target.checked)} />
            <span>I confirm this payment belongs to {studentLine(detail.to)} and was credited to {studentLine(detail.from)} in error.</span>
          </label>
          <div className="row" style={{ marginTop: 8 }}><span className="grow" /><Btn kind="ghost" onClick={() => setAct("")}>Back</Btn>
            <Btn kind="go" size="md" disabled={!confirmed} busyLabel="Processing Financial Reallocation..." onClick={approve}>Approve and execute</Btn></div>
        </div>
      ) : null}
      {act === "reject" || act === "cancel" ? (
        <div className="card" style={{ padding: 12, marginTop: 10 }}>
          <Field id="sw-why" label={act === "reject" ? "Why is it rejected?" : "Why is it cancelled?"} required hint="Ten characters or more; recorded on the swap">
            <input id="sw-why" className="ctl" value={note} autoComplete="off" onChange={(e) => setNote(e.target.value)} />
          </Field>
          <div className="row" style={{ marginTop: 8 }}><span className="grow" /><Btn kind="ghost" onClick={() => setAct("")}>Back</Btn>
            {act === "reject"
              ? <Btn kind="urgent" disabled={note.trim().length < 10} busyLabel="Rejecting..." onClick={reject}>Reject swap</Btn>
              : <Btn kind="urgent" disabled={note.trim().length < 10} busyLabel="Cancelling..." onClick={cancel}>Cancel swap</Btn>}</div>
        </div>
      ) : null}
      {act === "reverse" ? (
        <div className="card" style={{ padding: 12, marginTop: 10 }}>
          <b>Reverse {s.swap_ref}</b>
          <div className="sub2">A reversal is a swap of its own: the payment goes back to {studentLine(detail.from)} once another Bursar officer approves it. This swap is never edited.</div>
          <Field id="sw-rv" label="Reason" required hint="Twenty characters or more">
            <textarea id="sw-rv" className="ctl" rows={2} value={note} onChange={(e) => setNote(e.target.value)} />
          </Field>
          <label className="row row--inline" style={{ gap: 8, alignItems: "flex-start" }}>
            <input type="checkbox" checked={confirmed} onChange={(e) => setConfirmed(e.target.checked)} />
            <span>I have verified that this payment belongs to {studentLine(detail.from)}.</span>
          </label>
          <div className="row" style={{ marginTop: 8 }}><span className="grow" /><Btn kind="ghost" onClick={() => setAct("")}>Back</Btn>
            <Btn kind="urgent" disabled={!confirmed || !reasonOk(note)} busyLabel="Submitting for Review..." onClick={reverse}>Submit reversal for review</Btn></div>
        </div>
      ) : null}
    </Modal>
  );
}
