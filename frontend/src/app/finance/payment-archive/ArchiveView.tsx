"use client";

/**
 * One archived payment (V670): the original payment (as it was received, unchanged), its gateway and old-portal identifiers, the
 * archive information, the verification status, the student's fees with the archived money apart, the payment it repeats and what
 * the two share, the requests it paid for, the evidence (items and files), the timeline and the payment's own history; and what the
 * officer may do — the Students Account Officer or the Bursar records the investigation and proposes the settlement (restore,
 * reallocate to its true owner through the payment swap, duplicate, never received); a Bursar officer other than the proposer
 * approves it (executed at once), returns it for correction or rejects it. The server refuses whatever the officer may not do; these
 * buttons only follow it.
 */
import { useState } from "react";
import type { Problem } from "@/lib/api";
import { Btn, Note, Pil } from "@/components/proto/ui";
import { Field, Modal, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { formatDocDateTime } from "@/lib/document/institution";
import {
  ARCHIVE_OUTCOMES, EVENT_WORDS, OUTCOME_WORDS, SIGNAL_WORDS, SOURCE_WORDS, STATE_WORDS, fileRefusal, isOpen, longEnough, proposalReadiness, refusalParts,
  verificationWords, type Account, type ArchiveDetail, type ArchiveOutcome, type Catalogue, type EvidenceItem, type FoundStudent,
} from "@/lib/payment-archive";
import { ARCHIVE, archiveGet, archivePost, fileAsDataUrl } from "./archive-call";

type Draft = { kind: string; value: string };

function AccountTable({ title, a }: { title: string; a?: Account | null }) {
  if (!a) return null;
  return (
    <div className="card" style={{ padding: 12, minWidth: 0 }}>
      <div className="eyebrow">{title}</div>
      <table className="tbl tbl--data">
        <tbody>
          <tr><td>Assessed school fees ({a.session})</td><td className="num tnum">{a.stated ? money(Number(a.assessed)) : "Not stated"}</td></tr>
          <tr><td>Verified paid</td><td className="num tnum">{money(Number(a.verifiedPaid))}</td></tr>
          <tr><td>Archived — under review</td><td className="num tnum">{money(Number(a.archived))}</td></tr>
          <tr><td><b>Outstanding</b></td><td className="num tnum"><b>{money(Number(a.outstanding))}</b></td></tr>
        </tbody>
      </table>
      <div className="sub2">The archived money is never in the verified paid figure until the Bursary settles it.</div>
    </div>
  );
}

function ItemsEditor({ kinds, items, setItems }: { kinds: Catalogue["evidenceKinds"]; items: Draft[]; setItems: (d: Draft[]) => void }) {
  return (
    <div>
      {items.map((it, i) => (
        <div key={i} className="row" style={{ gap: 8, alignItems: "flex-end", marginTop: 4 }}>
          <Field id={`ev-k-${i}`} label={i === 0 ? "Evidence" : ""}>
            <select id={`ev-k-${i}`} className="ctl" value={it.kind} onChange={(e) => setItems(items.map((x, j) => (j === i ? { ...x, kind: e.target.value } : x)))}>
              <option value="">Kind…</option>
              <optgroup label="Strong — may establish ownership or a duplicate">
                {kinds.filter((k) => k.strength === "STRONG").map((k) => <option key={k.code} value={k.code}>{k.label}</option>)}
              </optgroup>
              <optgroup label="Supporting — never on its own">
                {kinds.filter((k) => k.strength === "SUPPORTING").map((k) => <option key={k.code} value={k.code}>{k.label}</option>)}
              </optgroup>
            </select>
          </Field>
          <Field id={`ev-v-${i}`} label={i === 0 ? "What it shows" : ""}>
            <input id={`ev-v-${i}`} className="ctl" value={it.value} autoComplete="off" onChange={(e) => setItems(items.map((x, j) => (j === i ? { ...x, value: e.target.value } : x)))} />
          </Field>
          <Btn kind="ghost" onClick={() => setItems(items.filter((_, j) => j !== i))}>Remove</Btn>
        </div>
      ))}
      <Btn kind="ghost" onClick={() => setItems([...items, { kind: "", value: "" }])}>Add an item of evidence</Btn>
    </div>
  );
}

export function ArchiveView({ detail, office, catalogue, onClose, onChanged }: {
  detail: ArchiveDetail; office: string | null; catalogue: Catalogue; onClose: () => void; onChanged: (d: ArchiveDetail | null) => void;
}) {
  const a = detail.archive;
  const p = detail.payment;
  const [act, setAct] = useState<"" | "investigate" | "propose" | "approve" | "return" | "reject">("");
  const [note, setNote] = useState("");
  const [items, setItems] = useState<Draft[]>([]);
  const [outcome, setOutcome] = useState<ArchiveOutcome>(a.outcome ?? "RESTORE");
  const [ownerQ, setOwnerQ] = useState("");
  const [owners, setOwners] = useState<FoundStudent[] | null>(null);
  const [owner, setOwner] = useState<FoundStudent | null>(null);
  const [confirmed, setConfirmed] = useState(false);
  const [file, setFile] = useState<File | null>(null);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<{ kind: "ok" | "bad" | "info"; title: string; body?: string } | null>(null);
  const initiator = office === "bursar" || office === "studentaccounts";
  const bursar = office === "bursar";
  const open = isOpen(a.state);
  const investigating = a.state === "ARCHIVED" || a.state === "UNDER_REVIEW" || a.state === "RETURNED";
  const pending = a.state === "PENDING_BURSAR_APPROVAL";
  const [sk, sw] = STATE_WORDS[a.state] ?? ["grey", a.state];
  const [vk, vw] = verificationWords(a.state);
  const evidence: EvidenceItem[] = Array.isArray(a.evidence) ? a.evidence : [];
  const authoritative = detail.signalsNow?.authoritative ?? a.signals?.authoritative ?? [];
  const supporting = detail.signalsNow?.supporting ?? a.signals?.supporting ?? [];
  const drafts = items.filter((x) => x.kind && x.value.trim().length >= 2);
  const draftItems: EvidenceItem[] = drafts.map((d) => ({ kind: d.kind, label: d.kind, value: d.value,
    strength: catalogue.evidenceKinds.find((k) => k.code === d.kind)?.strength ?? "SUPPORTING" }));
  const notReady = proposalReadiness(outcome, [...evidence, ...draftItems], authoritative, !!a.related_payment_id);

  function reset() { setAct(""); setNote(""); setItems([]); setConfirmed(false); setOwner(null); setOwners(null); setOwnerQ(""); }

  async function send(path: string, body: unknown, reason: string): Promise<ArchiveDetail | null> {
    setErr(null);
    const r = await archivePost<ArchiveDetail>(path, body, reason);
    if (!r.ok) { setErr(r.problem); notifyProblem(r.problem); return null; }
    return r.data;
  }

  async function investigate() {
    const d = await send(`/${a.id}/investigation`, { note: note.trim() || null, items: drafts.map((x) => ({ kind: x.kind, value: x.value.trim() })) },
      `Investigation of ${a.archive_ref}`);
    if (!d) return;
    notify("Investigation recorded."); reset(); onChanged(d);
  }

  async function findOwner() {
    setErr(null);
    const r = await archiveGet<FoundStudent[]>(`/students?q=${encodeURIComponent(ownerQ.trim())}`);
    if (!r.ok) { setErr(r.problem); return; }
    setOwners(r.data.filter((s) => s.id !== p.student_id));
  }

  async function propose() {
    const d = await send(`/${a.id}/proposal`, { outcome, owner: outcome === "REALLOCATE" ? owner?.id ?? null : null, note: note.trim(),
      items: drafts.map((x) => ({ kind: x.kind, value: x.value.trim() })), confirmed }, `Settlement of ${a.archive_ref} proposed: ${OUTCOME_WORDS[outcome][0]}`);
    if (!d) return;
    notify(`${a.archive_ref} sent to the Bursar`); reset(); onChanged(d);
  }

  async function decide(decision: "APPROVE" | "RETURN" | "REJECT") {
    const d = await send(`/${a.id}/decision`, { decision, note: note.trim() || null, confirmed: decision === "APPROVE" ? confirmed : false },
      `${decision === "APPROVE" ? "Approve" : decision === "RETURN" ? "Return" : "Reject"} the settlement of ${a.archive_ref}${note.trim() ? `: ${note.trim()}` : ""}`);
    if (!d) return;
    const st = d.result?.state ?? d.archive.state;
    if (st === "RECONCILED") {
      setSaid({ kind: "ok", title: a.outcome === "REALLOCATE" ? "Payment reallocated to its owner." : "Payment restored.",
        body: `${money(Number(a.amount))} counts again${a.outcome === "REALLOCATE" && detail.owner ? ` for ${detail.owner.name}` : ""}; its reference, amount, date and receipt are unchanged and the income is recognised.` });
    } else if (st === "DUPLICATE_CONFIRMED" || st === "NOT_RECEIVED") {
      setSaid({ kind: "info", title: st === "DUPLICATE_CONFIRMED" ? "Duplicate confirmed." : "Confirmed never received.",
        body: "The record stays archived for good and is never counted; its ledger posting is reversed." });
    } else if (d.result?.failure) {
      setSaid({ kind: "bad", title: "The settlement could not be completed — the payment stays archived.", body: refusalParts(d.result.failure).words });
    } else {
      notify(st === "RETURNED" ? "Returned for correction." : "Proposal rejected.");
    }
    reset(); onChanged(d);
  }

  async function attach() {
    if (!file) return;
    const d = await send(`/${a.id}/files`, { filename: file.name, dataUrl: await fileAsDataUrl(file) }, `Evidence for ${a.archive_ref}`);
    if (!d) return;
    setFile(null); onChanged(d);
  }

  const fileProblem = file ? fileRefusal(file) : null;
  const student = detail.student;
  const sem = (n?: number | null) => (n === 1 ? "First" : n === 2 ? "Second" : n === 3 ? "Third" : "—");

  return (
    <Modal wide title={<>{a.archive_ref} <Pil kind={sk}>{sw}</Pil></>} sub={`${a.reference} · ${money(Number(a.amount))} · ${a.reason}`} onClose={onClose}>
      {said ? <Note kind={said.kind} title={said.title}>{said.body}</Note> : null}
      {err ? <ProblemNotice problem={err} /> : null}
      <div className="card" style={{ padding: 12 }}>
        <div className="eyebrow">Verification status</div>
        <Pil kind={vk}>{vw}</Pil>
        {a.outcome ? <div className="sub2" style={{ marginTop: 4 }}>Proposed: {OUTCOME_WORDS[a.outcome][0]}{detail.owner ? ` — ${detail.owner.name} (${detail.owner.matric_no ?? detail.owner.admission_no ?? ""})` : ""}</div> : null}
      </div>
      {a.state === "RETURNED" && a.returned_note ? <Note kind="info" title={`Returned for correction by ${a.returned_by_name ?? "the Bursar"}, ${formatDocDateTime(a.returned_at)}`}>{refusalParts(a.returned_note).words}</Note> : null}

      <div className="eyebrow" style={{ marginTop: 12 }}>Original payment — as received, never changed</div>
      <table className="tbl tbl--data">
        <tbody>
          <tr><td>Payment reference (invoice)</td><td className="tnum">{a.reference}{a.legacy ? <> <Pil kind="grey">Old portal</Pil></> : null}</td></tr>
          <tr><td>Gateway references</td><td className="tnum">{detail.gateway.length ? detail.gateway.map((g, i) => <div key={i}>{g.ref ?? "—"} <span className="sub2">({g.gateway ?? g.kind}{g.outcome ? `, ${g.outcome.toLowerCase()}` : ""})</span></div>) : "—"}</td></tr>
          <tr><td>Amount</td><td className="tnum"><b>{money(Number(a.amount))}</b></td></tr>
          <tr><td>Payment date</td><td>{formatDocDateTime(a.payment_confirmed_at)}</td></tr>
          <tr><td>Channel · receipt</td><td>{a.channel ?? "—"}{a.receipt_no ? ` · ${a.receipt_no}` : ""}</td></tr>
          <tr><td>Purpose</td><td>{a.purpose}<div className="sub2">Session {a.session}{a.semester ? `, ${sem(a.semester).toLowerCase()} semester` : ""}</div></td></tr>
          <tr><td>Original student</td><td>{student ? <>{student.name} · <span className="tnum">{student.matric_no ?? student.admission_no ?? ""}</span><div className="sub2">{[student.programme, student.department, student.faculty, student.current_level ? `${student.current_level} Level` : null].filter(Boolean).join(" · ")}</div></> : "—"}</td></tr>
          <tr><td>Stands on now</td><td>{detail.currentStudent ? `${detail.currentStudent.name} · ${detail.currentStudent.matric_no ?? detail.currentStudent.admission_no ?? ""}` : "—"}</td></tr>
          <tr><td>Old-portal numbers</td><td className="tnum">{detail.legacyNumbers.length ? detail.legacyNumbers.map((n) => n.payref).join(", ") : "—"}</td></tr>
          {p.paid_as ? <tr><td>Paid as</td><td>{p.paid_as}</td></tr> : null}
          {p.batch_ref ? <tr><td>Migration batch</td><td className="tnum">{p.batch_ref}</td></tr> : null}
        </tbody>
      </table>

      <div className="eyebrow" style={{ marginTop: 12 }}>Archive information</div>
      <table className="tbl tbl--data">
        <tbody>
          <tr><td>Archive reference</td><td className="tnum">{a.archive_ref}</td></tr>
          <tr><td>Reason</td><td>{a.reason}{a.reason_explanation ? <div className="sub2">{a.reason_explanation}</div> : null}</td></tr>
          <tr><td>Source</td><td>{SOURCE_WORDS[a.source] ?? a.source}</td></tr>
          <tr><td>Archived</td><td>{a.archived_by_name ?? "—"} ({a.archived_office}) · {formatDocDateTime(a.archived_at)}</td></tr>
          <tr><td>Note</td><td>{a.archive_note}</td></tr>
          {a.proposal_note ? <tr><td>Proposal</td><td>{a.proposed_by_name ?? "—"} ({a.proposed_office}) · {formatDocDateTime(a.proposed_at)}<div>{a.proposal_note}</div></td></tr> : null}
          {a.decided_at ? <tr><td>Decided</td><td>{a.decided_by_name ?? "—"} ({a.decided_office}) · {formatDocDateTime(a.decided_at)}{a.decision_note ? ` — ${a.decision_note}` : ""}</td></tr> : null}
          {detail.swap ? <tr><td>Payment swap</td><td className="tnum">{detail.swap.swap_ref} · {detail.swap.from_number} → {detail.swap.to_number} · {detail.swap.status.toLowerCase().replace(/_/g, " ")}</td></tr> : null}
          <tr><td>Ledger</td><td className="sub2">{a.archive_journal_no ? `#${a.archive_journal_no} income to Payments under review (2400)` : "Not posted when archived: left unposted until settled"}
            {a.settle_journal_no ? ` · #${a.settle_journal_no} ${a.state === "RECONCILED" ? "back to income" : "reclassification reversed"}` : ""}
            {a.payment_reversal_no ? ` · #${a.payment_reversal_no} the payment's posting reversed` : ""}</td></tr>
        </tbody>
      </table>

      <div className="grid grid--2" style={{ marginTop: 12 }}>
        <AccountTable title={`${detail.currentStudent?.name ?? "The student"}'s fees now`} a={detail.account} />
        {detail.ownerAccount && detail.owner?.id !== detail.currentStudent?.id ? <AccountTable title={`${detail.owner?.name ?? "The owner"}'s fees now`} a={detail.ownerAccount} /> : null}
      </div>

      {detail.related ? (
        <>
          <div className="eyebrow" style={{ marginTop: 12 }}>The payment it repeats (kept)</div>
          <table className="tbl tbl--data">
            <tbody>
              <tr><td>Payment</td><td className="tnum">{detail.related.reference} · {money(Number(detail.related.amount))} · {formatDocDateTime(detail.related.confirmed_at)}{detail.related.archived_at ? <> <Pil kind="warn">Archived</Pil></> : null}</td></tr>
              <tr><td>On</td><td>{detail.related.name} · {detail.related.number}</td></tr>
              <tr><td>Authoritative identifiers shared</td><td>{authoritative.length ? authoritative.map((s) => <Pil key={s} kind="bad">{SIGNAL_WORDS[s] ?? s}</Pil>) : <span className="sub2">None — a duplicate is confirmed only on strong evidence</span>}</td></tr>
              <tr><td>Supporting signals</td><td className="sub2">{supporting.length ? supporting.map((s) => SIGNAL_WORDS[s] ?? s).join(" · ") : "—"} (never proof on their own)</td></tr>
            </tbody>
          </table>
        </>
      ) : null}

      {detail.linked.length ? (
        <Note kind="info" title="What the payment paid for">
          {detail.linked.map((l, i) => <div key={i}>{l.kind === "HOSTEL" ? "A hostel booking" : l.kind === "TRANSCRIPT" ? `Transcript request ${l.ref}` : l.kind === "DEFERMENT_FEE" ? "A deferment application fee" : `Refund ${l.ref}`} ({String(l.state ?? "").toLowerCase()})</div>)}
          <div className="sub2">These stand as they were; the office concerned decides on them.</div>
        </Note>
      ) : null}

      <div className="eyebrow" style={{ marginTop: 12 }}>Evidence</div>
      {evidence.length ? (
        <table className="tbl tbl--data">
          <tbody>
            {evidence.map((e, i) => <tr key={i}><td>{catalogue.evidenceKinds.find((k) => k.code === e.kind)?.label ?? e.label}</td><td>{e.value}</td><td><Pil kind={e.strength === "STRONG" ? "ok" : "grey"}>{e.strength === "STRONG" ? "Strong" : "Supporting"}</Pil></td><td className="sub2">{formatDocDateTime(e.addedAt ?? null)}</td></tr>)}
          </tbody>
        </table>
      ) : <div className="sub2">No evidence recorded yet.</div>}
      {detail.files.map((f) => <div key={f.id}><a href={`${ARCHIVE}/${a.id}/files/${f.id}`} target="_blank" rel="noreferrer">{f.filename}</a> <span className="sub2">({Math.ceil(f.size_bytes / 1024)} KB, {f.added_by ?? ""})</span></div>)}
      {open && initiator ? (
        <div className="row" style={{ marginTop: 6, alignItems: "flex-end" }}>
          <Field id="par-file" label="Add a file" hint="PDF, JPEG or PNG, up to 5 MB" error={fileProblem ?? undefined}>
            <input id="par-file" type="file" accept="application/pdf,image/jpeg,image/png" onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
          </Field>
          <Btn kind="ghost" disabled={!file || !!fileProblem} busyLabel="Attaching..." onClick={attach}>Attach</Btn>
        </div>
      ) : null}

      <div className="row" style={{ marginTop: 12, gap: 8, flexWrap: "wrap" }}>
        {investigating && initiator ? <Btn kind="secondary" onClick={() => { reset(); setAct("investigate"); }}>Record the investigation</Btn> : null}
        {investigating && initiator ? <Btn kind="primary" onClick={() => { reset(); setAct("propose"); setOutcome(a.outcome ?? "RESTORE"); }}>{a.state === "RETURNED" ? "Change and propose again" : "Propose the settlement"}</Btn> : null}
        {pending && bursar && !a.proposed_by_me ? <Btn kind="go" onClick={() => { reset(); setAct("approve"); }}>Approve</Btn> : null}
        {pending && bursar && !a.proposed_by_me ? <Btn kind="ghost" onClick={() => { reset(); setAct("return"); }}>Return for correction</Btn> : null}
        {pending && bursar && !a.proposed_by_me ? <Btn kind="ghost" onClick={() => { reset(); setAct("reject"); }}>Reject</Btn> : null}
        {pending && a.proposed_by_me ? <span className="sub2">You proposed this settlement: another Bursar officer decides it.</span> : null}
        {pending && !bursar ? <span className="sub2">A Bursar officer other than the proposer decides this settlement.</span> : null}
      </div>

      {act === "investigate" ? (
        <div className="card" style={{ padding: 12, marginTop: 10 }}>
          <b>Record the investigation</b>
          <Field id="par-inote" label="What was found" hint="Ten characters or more, or an item of evidence">
            <textarea id="par-inote" className="ctl" rows={2} value={note} onChange={(e) => setNote(e.target.value)} />
          </Field>
          <ItemsEditor kinds={catalogue.evidenceKinds} items={items} setItems={setItems} />
          <div className="row" style={{ marginTop: 8 }}><span className="grow" /><Btn kind="ghost" onClick={reset}>Back</Btn>
            <Btn kind="primary" disabled={!longEnough(note, 10) && drafts.length === 0} busyLabel="Recording..." onClick={investigate}>Record</Btn></div>
        </div>
      ) : null}

      {act === "propose" ? (
        <div className="card" style={{ padding: 12, marginTop: 10 }}>
          <b>Propose the settlement</b>
          {ARCHIVE_OUTCOMES.map((o) => (
            <label key={o} className="row row--inline" style={{ gap: 8, alignItems: "flex-start", marginTop: 4 }}>
              <input type="radio" name="par-outcome" checked={outcome === o} onChange={() => setOutcome(o)} />
              <span><b>{OUTCOME_WORDS[o][0]}</b><div className="sub2">{OUTCOME_WORDS[o][1]}</div></span>
            </label>
          ))}
          {outcome === "REALLOCATE" ? (
            <div style={{ marginTop: 8 }}>
              <div className="row" style={{ gap: 8, alignItems: "flex-end" }}>
                <Field id="par-owner" label="The student it belongs to" hint="Matriculation, JAMB, admission or application number, or name">
                  <input id="par-owner" className="ctl" value={ownerQ} autoComplete="off" onChange={(e) => setOwnerQ(e.target.value)} />
                </Field>
                <Btn kind="secondary" disabled={ownerQ.trim().length < 3} busyLabel="Searching..." onClick={findOwner}>Find</Btn>
              </div>
              {owners ? (owners.length ? (
                <table className="tbl tbl--data">
                  <tbody>
                    {owners.map((s) => (
                      <tr key={s.id}><td>{s.name}<div className="sub2 tnum">{s.matric_no ?? s.admission_no ?? ""}{s.jamb_reg_no ? ` · JAMB ${s.jamb_reg_no}` : ""}</div></td>
                        <td className="sub2">{s.programme ?? ""}{s.current_level ? ` · ${s.current_level} Level` : ""} · {String(s.status ?? "").toLowerCase()}</td>
                        <td>{s.merged ? <span className="sub2">Merged record</span> : <Btn kind={owner?.id === s.id ? "primary" : "ghost"} onClick={() => setOwner(s)}>{owner?.id === s.id ? "Chosen" : "Choose"}</Btn>}</td></tr>
                    ))}
                  </tbody>
                </table>
              ) : <div className="sub2">No student matches.</div>) : null}
              <div className="sub2">The move is a school-fees payment swap: the payment&apos;s reference, amount, date and receipt stay as they are; the Bursar&apos;s approval executes it.</div>
            </div>
          ) : null}
          <Field id="par-pnote" label="What the investigation established" required hint="Twenty characters or more">
            <textarea id="par-pnote" className="ctl" rows={2} value={note} onChange={(e) => setNote(e.target.value)} />
          </Field>
          <ItemsEditor kinds={catalogue.evidenceKinds} items={items} setItems={setItems} />
          {notReady ? <Note kind="info" title="Before it can be proposed">{notReady}</Note> : null}
          <label className="row row--inline" style={{ gap: 8, alignItems: "flex-start", marginTop: 8 }}>
            <input type="checkbox" checked={confirmed} onChange={(e) => setConfirmed(e.target.checked)} />
            <span>I have verified what I propose against the evidence recorded.</span>
          </label>
          <div className="row" style={{ marginTop: 8 }}><span className="grow" /><Btn kind="ghost" onClick={reset}>Back</Btn>
            <Btn kind="primary" disabled={!confirmed || !longEnough(note, 20) || !!notReady || (outcome === "REALLOCATE" && !owner)} busyLabel="Sending..." onClick={propose}>Send to the Bursar</Btn></div>
        </div>
      ) : null}

      {act === "approve" ? (
        <div className="card" style={{ padding: 12, marginTop: 10 }}>
          <b>Approve and execute: {a.outcome ? OUTCOME_WORDS[a.outcome][0] : ""}</b>
          <div className="sub2">{a.outcome ? OUTCOME_WORDS[a.outcome][1] : ""} It is executed at once, or nothing changes.</div>
          <Field id="par-dnote" label="Note" hint="Optional"><input id="par-dnote" className="ctl" value={note} autoComplete="off" onChange={(e) => setNote(e.target.value)} /></Field>
          <label className="row row--inline" style={{ gap: 8, alignItems: "flex-start" }}>
            <input type="checkbox" checked={confirmed} onChange={(e) => setConfirmed(e.target.checked)} />
            <span>I have checked the evidence and approve the settlement proposed.</span>
          </label>
          <div className="row" style={{ marginTop: 8 }}><span className="grow" /><Btn kind="ghost" onClick={reset}>Back</Btn>
            <Btn kind="go" size="md" disabled={!confirmed} busyLabel="Executing..." onClick={() => decide("APPROVE")}>Approve and execute</Btn></div>
        </div>
      ) : null}
      {act === "return" || act === "reject" ? (
        <div className="card" style={{ padding: 12, marginTop: 10 }}>
          <Field id="par-why" label={act === "return" ? "What is to be corrected?" : "Why is it rejected?"} required hint="Ten characters or more; recorded on the archive">
            <input id="par-why" className="ctl" value={note} autoComplete="off" onChange={(e) => setNote(e.target.value)} />
          </Field>
          <div className="row" style={{ marginTop: 8 }}><span className="grow" /><Btn kind="ghost" onClick={reset}>Back</Btn>
            {act === "return" ? <Btn kind="secondary" disabled={!longEnough(note, 10)} busyLabel="Returning..." onClick={() => decide("RETURN")}>Return for correction</Btn>
              : <Btn kind="urgent" disabled={!longEnough(note, 10)} busyLabel="Rejecting..." onClick={() => decide("REJECT")}>Reject the proposal</Btn>}</div>
        </div>
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
              {detail.paymentHistory.map((h) => <tr key={h.ref}><td className="tnum">{h.ref}</td><td>{h.kind === "ARCHIVE" ? "Archive" : h.kind === "SWAP" ? "Swap" : "Correction"}</td><td>{h.what}</td><td>{h.status.toLowerCase().replace(/_/g, " ")}</td><td className="sub2">{formatDocDateTime(h.at)}</td></tr>)}
            </tbody>
          </table>
        </>
      ) : null}
    </Modal>
  );
}
