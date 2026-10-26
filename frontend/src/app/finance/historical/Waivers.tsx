"use client";

/**
 * V665: waivers and adjustments of a past period's school fees. The Students Account Officer or the Bursar proposes one for a session
 * and semester — a waiver (the University forgoes the amount) or an adjustment (the amount assessed was too high) — with the reason, the
 * approval it rests on and its evidence; another officer of the Bursar's office approves or rejects it; an approved one is revoked
 * with a reason, never edited. It lowers what the period owes and is never a payment. The amounts and every rule are the database's.
 */
import { useEffect, useState } from "react";
import { Btn, Note, Pil, Spinner } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { can, KIND_WORDS, naira, PERIOD_WORDS, semesterWords, WAIVER_WORDS, waiverAmountProblem, type Desk, type Period, type Waiver, type WaiverKind, type WaiverState } from "@/lib/historical-fees";
import { HF, hfCall, readDataUrl } from "./hf-call";

const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" }) : "—");

/** a waiver or adjustment proposed for one period of the student's record */
export function WaiverForm({ studentId, studentName, period, onClose, onSaved }: {
  studentId: string; studentName: string; period: Period; onClose: () => void; onSaved: (id: string) => void;
}) {
  const [kind, setKind] = useState<WaiverKind>("WAIVER");
  const [amount, setAmount] = useState("");
  const [reason, setReason] = useState("");
  const [authority, setAuthority] = useState("");
  const [file, setFile] = useState<File | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const amountProblem = amount ? waiverAmountProblem(amount, period.outstanding) : null;

  async function save() {
    setProblem(null);
    const evidence = file ? { filename: file.name, dataUrl: await readDataUrl(file) } : null;
    const r = await hfCall<Waiver>("/waivers", { method: "POST", reason: `${KIND_WORDS[kind]} proposed for ${period.session} ${semesterWords(period.semester).toLowerCase()}`,
      body: { studentId, session: period.session, semester: period.semester, kind, amount: Number(amount.replace(/[^0-9.]/g, "")), reason: reason.trim(), authority: authority.trim(), evidence } });
    if (!r.ok) { setProblem(r.problem); return; }
    notify(`${r.data.reference} proposed — another Bursar officer decides it`);
    onSaved(r.data.id);
  }

  return (
    <Modal title="Propose a waiver or adjustment" sub={`${studentName} · ${period.session} · ${semesterWords(period.semester)}`} onClose={onClose}
      foot={<><Btn kind="ghost" onClick={onClose}>Cancel</Btn><span className="grow" />
        <Btn kind="primary" disabled={!!waiverAmountProblem(amount, period.outstanding) || reason.trim().length < 20 || authority.trim().length < 3} busyLabel="Proposing…" onClick={save}>Propose for the Bursar&rsquo;s approval</Btn></>}>
      <div className="grid grid--3 mb-2">
        <div className="kv"><span className="k">Assessed</span><span className="v tnum">{period.assessed == null ? "—" : naira(period.assessed)}</span></div>
        <div className="kv"><span className="k">Paid</span><span className="v tnum">{naira(period.paid)}</span></div>
        <div className="kv"><span className="k">Still owed</span><span className="v tnum">{period.outstanding == null ? "—" : naira(period.outstanding)}</span></div>
      </div>
      <Note kind="info" title="Never a payment">A waiver lowers what the period owes once another Bursar officer approves it. It is not marked paid, and it is kept with its reason and evidence.</Note>
      <Field id="hfw-kind" label="Kind">
        <select id="hfw-kind" className="ctl" value={kind} onChange={(e) => setKind(e.target.value as WaiverKind)}>
          <option value="WAIVER">Waiver — the University forgoes the amount (a scholarship, a concession)</option>
          <option value="ADJUSTMENT">Adjustment — the amount assessed was too high</option>
        </select>
      </Field>
      <Field id="hfw-amount" label="Amount (₦)" required hint={amountProblem ?? `At most ${naira(period.outstanding)}`}>
        <input id="hfw-amount" className="ctl tnum" inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)} aria-invalid={!!amountProblem} />
      </Field>
      <Field id="hfw-authority" label="Approval it rests on" required hint="The letter, the minute or the award — its reference">
        <input id="hfw-authority" className="ctl" value={authority} maxLength={300} onChange={(e) => setAuthority(e.target.value)} />
      </Field>
      <Field id="hfw-reason" label="Reason" required hint="Twenty characters at least">
        <textarea id="hfw-reason" className="ctl" rows={3} value={reason} maxLength={2000} onChange={(e) => setReason(e.target.value)} />
      </Field>
      <Field id="hfw-file" label="Evidence" hint="PDF, JPEG or PNG, up to 5 MB">
        <input id="hfw-file" type="file" className="ctl" accept="application/pdf,image/jpeg,image/png" onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
      </Field>
      {problem ? <ProblemNotice problem={problem} /> : null}
    </Modal>
  );
}

/** one waiver, and what the acting office may do with it */
export function WaiverView({ id, desk, onClose, onChanged }: { id: string; desk: Desk; onClose: () => void; onChanged: () => void }) {
  const [w, setW] = useState<Waiver | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [tick, setTick] = useState(0);
  const [note, setNote] = useState("");
  useEffect(() => {
    let alive = true;
    void hfCall<Waiver>(`/waivers/${id}`).then((r) => { if (!alive) return; if (r.ok) setW(r.data); else setProblem(r.problem); });
    return () => { alive = false; };
  }, [id, tick]);
  if (!w) return <Modal title="Waiver" onClose={onClose}>{problem ? <ProblemNotice problem={problem} /> : <div className="row row--tight sub2"><Spinner /> Reading…</div>}</Modal>;
  const pending = w.state === "PENDING_BURSAR_APPROVAL";
  const files = Array.isArray(w.evidence) ? w.evidence : [];

  async function act(path: string, body: unknown, words: string, done: string) {
    setProblem(null);
    const r = await hfCall<Waiver>(path, { method: "POST", body, reason: words });
    if (!r.ok) { setProblem(r.problem); return; }
    notify(done);
    setNote("");
    setTick((n) => n + 1);
    onChanged();
  }

  async function upload(file: File) {
    setProblem(null);
    const r = await hfCall<Waiver>(`/waivers/${id}/evidence`, { method: "POST", body: { filename: file.name, dataUrl: await readDataUrl(file) }, reason: `Evidence for ${w!.reference}` });
    if (!r.ok) { setProblem(r.problem); return; }
    notify("Evidence added");
    setTick((n) => n + 1);
  }

  return (
    <Modal wide title={`${w.reference} · ${KIND_WORDS[w.kind]} · ${WAIVER_WORDS[w.state]?.[0] ?? w.state}`} sub={`${w.surname}, ${w.other_names} · ${w.matric_no ?? "—"} · ${w.programme}`} onClose={onClose}
      foot={<>
        {pending && (w.mine || can(desk, "APPROVE_HISTORICAL_FEE_ASSESSMENT")) ? <Btn kind="ghost" busyLabel="Withdrawing…" onClick={() => act(`/waivers/${id}/withdraw`, { note: note || null }, `${w.reference} withdrawn`, `${w.reference} withdrawn`)}>Withdraw</Btn> : null}
        <span className="grow" />
        {pending && !w.mine && can(desk, "REJECT_HISTORICAL_FEE_ASSESSMENT") ? <Btn kind="urgent" disabled={note.trim().length < 10} busyLabel="Rejecting…" onClick={() => act(`/waivers/${id}/decide`, { decision: "REJECT", note }, `${w.reference} rejected`, `${w.reference} rejected`)}>Reject</Btn> : null}
        {pending && !w.mine && can(desk, "APPROVE_HISTORICAL_FEE_ASSESSMENT") ? <Btn kind="primary" busyLabel="Approving…" onClick={() => act(`/waivers/${id}/decide`, { decision: "APPROVE", note: note || null }, `${w.reference} approved`, `${w.reference} approved — the period owes less`)}>Approve</Btn> : null}
        {w.state === "APPROVED" && can(desk, "APPROVE_HISTORICAL_FEE_ASSESSMENT") ? <Btn kind="urgent" disabled={note.trim().length < 20} busyLabel="Revoking…" onClick={() => act(`/waivers/${id}/revoke`, { reason: note }, `${w.reference} revoked`, `${w.reference} revoked — the amount is owed again`)}>Revoke</Btn> : null}
      </>}>
      {pending && w.mine ? <Note kind="info" title="You proposed this waiver">Another Bursar officer approves or rejects it.</Note> : null}
      <div className="grid grid--4">
        <div className="kv"><span className="k">Period</span><span className="v">{w.session} · {semesterWords(w.semester)}</span></div>
        <div className="kv"><span className="k">{KIND_WORDS[w.kind]}</span><span className="v tnum">{naira(w.amount)}</span></div>
        <div className="kv"><span className="k">Assessed</span><span className="v tnum">{w.period?.assessed == null ? "—" : naira(w.period.assessed)}</span></div>
        <div className="kv"><span className="k">Paid towards the period</span><span className="v tnum">{naira(w.period?.paid)}</span></div>
        <div className="kv"><span className="k">Waived in force</span><span className="v tnum">{naira(w.period?.waived)}</span></div>
        <div className="kv"><span className="k">Outstanding now</span><span className="v tnum">{w.period?.outstanding == null ? "—" : naira(w.period.outstanding)}</span></div>
        <div className="kv"><span className="k">The period now</span><span className="v">{w.period ? <Pil kind={PERIOD_WORDS[w.period.status]?.[1] ?? "grey"}>{PERIOD_WORDS[w.period.status]?.[0]}</Pil> : "—"}</span></div>
        <div className="kv"><span className="k">Proposed by</span><span className="v">{w.created_by_name ?? w.created_office ?? "—"} · {when(w.created_at)}</span></div>
      </div>
      <div className="mt-2"><span className="sub2">Approval it rests on</span><div>{w.authority}</div></div>
      <div className="mt-2"><span className="sub2">Reason</span><div>{w.reason}</div></div>
      {w.decided_at && w.state !== "WITHDRAWN" ? <Note kind={w.state === "REJECTED" ? "bad" : "info"} title={`${WAIVER_WORDS[w.state]?.[0]} by ${w.decided_by_name ?? w.decided_office ?? "the Bursar"} · ${when(w.decided_at)}`}>{w.decision_note ?? "No note."}</Note> : null}
      {w.revoked_at ? <Note kind="bad" title={`Revoked by ${w.revoked_by_name ?? "the Bursar"} · ${when(w.revoked_at)}`}>{w.revoke_reason}</Note> : null}
      <div className="mt-2"><strong>Evidence</strong></div>
      {files.length ? (
        <ul className="m-0">{files.map((e) => (
          <li key={e.id}><a href={`${HF}/waivers/${id}/evidence/${e.id}`} target="_blank" rel="noreferrer">{e.filename}</a> <span className="sub2">· {Math.ceil(e.size_bytes / 1024)} KB · {e.added_by ?? "—"} · {when(e.added_at)}</span></li>
        ))}</ul>
      ) : <div className="sub2">None attached.</div>}
      {pending && can(desk, "CREATE_HISTORICAL_FEE_ASSESSMENT") ? (
        <label className="btn btn--ghost btn--sm mt-1" style={{ cursor: "pointer" }}>
          Attach evidence (PDF, JPEG or PNG, up to 5 MB)
          <input type="file" accept="application/pdf,image/jpeg,image/png" style={{ display: "none" }} onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(f); e.target.value = ""; }} />
        </label>
      ) : null}
      {pending || w.state === "APPROVED" ? (
        <Field id="hfw-note" label={w.state === "APPROVED" ? "Reason to revoke" : "Note"} className="mt-2"
          hint={w.state === "APPROVED" ? "Twenty characters at least; the amount is owed again" : "Required to reject (ten characters at least)"}>
          <textarea id="hfw-note" className="ctl" rows={2} value={note} maxLength={2000} onChange={(e) => setNote(e.target.value)} />
        </Field>
      ) : null}
      {problem ? <ProblemNotice problem={problem} /> : null}
    </Modal>
  );
}

/** the waivers by state — the Bursar's queue first */
export function WaiverQueue({ desk, tick, onChanged }: { desk: Desk; tick: number; onChanged: () => void }) {
  const [state, setState] = useState<WaiverState | "ALL">("PENDING_BURSAR_APPROVAL");
  const [rows, setRows] = useState<{ total: number; rows: Waiver[] } | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [viewing, setViewing] = useState<string | null>(null);
  useEffect(() => {
    let alive = true;
    void hfCall<{ total: number; rows: Waiver[] }>(`/waivers?state=${state}`).then((r) => { if (!alive) return; if (r.ok) { setRows(r.data); setProblem(null); } else setProblem(r.problem); });
    return () => { alive = false; };
  }, [state, tick]);
  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <div className="row row--end mb-1">
        <Field id="hfw-state" label="State">
          <select id="hfw-state" className="ctl" value={state} onChange={(e) => setState(e.target.value as WaiverState | "ALL")}>
            {(Object.keys(WAIVER_WORDS) as WaiverState[]).map((k) => <option key={k} value={k}>{WAIVER_WORDS[k][0]}</option>)}
            <option value="ALL">Every state</option>
          </select>
        </Field>
      </div>
      {!rows ? <div className="row row--tight sub2"><Spinner /> Reading…</div> : rows.rows.length ? (
        <DTable cols={["S/N|num", "Student", "Programme", "Period", "Kind", "Amount|num", "Assessed|num", "Paid|num", "Outstanding|num", "Proposed by", "State", "|num"]}
          rows={rows.rows.map((r, i) => [
            <span key="n" className="tnum sub2">{i + 1}</span>,
            <span key="s"><strong>{r.surname}, {r.other_names}</strong><span className="blk sub2 tnum">{r.reference} · {r.matric_no ?? "—"}</span></span>,
            <span key="p" className="sub2">{r.programme}</span>, <span key="pe" className="tnum">{r.session} · S{r.semester}</span>, <span key="k">{KIND_WORDS[r.kind]}</span>,
            <span key="a" className="tnum">{naira(r.amount)}</span>, <span key="as" className="tnum">{r.assessed == null ? "—" : naira(r.assessed)}</span>,
            <span key="pd" className="tnum">{naira(r.paid)}</span>, <span key="o" className="tnum">{r.outstanding == null ? "—" : naira(r.outstanding)}</span>,
            <span key="c" className="sub2">{r.created_by_name ?? "—"}{r.mine ? " (you)" : ""}<span className="blk">{when(r.created_at)}</span></span>,
            <Pil key="st" kind={WAIVER_WORDS[r.state]?.[1] ?? "grey"}>{WAIVER_WORDS[r.state]?.[0] ?? r.state}</Pil>,
            <Btn key="v" kind="secondary" onClick={() => setViewing(r.id)}>View</Btn>,
          ])} />
      ) : <div className="sub2">No waiver {state === "PENDING_BURSAR_APPROVAL" ? "awaits the Bursar" : "in this state"}.</div>}
      {viewing ? <WaiverView id={viewing} desk={desk} onClose={() => setViewing(null)} onChanged={onChanged} /> : null}
    </>
  );
}
