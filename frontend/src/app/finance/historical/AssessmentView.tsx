"use client";

/**
 * V654: one historical assessment — the student and the period's account, the amount and its components, the source and the
 * reason, the evidence, the timeline — and what the acting office may do with it: the officer changes, submits or withdraws a draft
 * or one returned; the Bursar (never the officer who made it) approves, returns or rejects; an approved one is corrected by a new one.
 */
import { useEffect, useState } from "react";
import { Btn, Note, Pil, Spinner } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { can, naira, PERIOD_WORDS, semesterWords, SOURCE_WORDS, STATE_WORDS, type Assessment, type Desk, type Period } from "@/lib/historical-fees";
import { AssessmentForm } from "./AssessmentForm";
import { HF, hfCall, readDataUrl } from "./hf-call";

type Detail = Assessment & {
  student_id: string; surname: string; other_names: string; matric_no: string | null; jamb_reg_no: string | null; student_status: string; programme: string;
  period: Period | null; events?: { action: string; at: string; office: string | null; note: string | null; amount: number | string | null; actor_name: string | null }[];
  evidence: { id: string; filename: string; content_type: string; size_bytes: number; added_at: string; added_by: string | null }[];
};

const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" }) : "—");
const ACTION: Record<string, string> = { CREATED: "Created", EDITED: "Changed", SUBMITTED: "Submitted for approval", RETURNED: "Returned for correction", APPROVED: "Approved",
  REJECTED: "Rejected", CANCELLED: "Withdrawn", SUPERSEDED: "Superseded", EVIDENCE_ADDED: "Evidence added" };

export function AssessmentView({ id, desk, onClose, onChanged }: { id: string; desk: Desk; onClose: () => void; onChanged: () => void }) {
  const [d, setD] = useState<Detail | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [tick, setTick] = useState(0);
  const [note, setNote] = useState("");
  const [editing, setEditing] = useState<"edit" | "correct" | null>(null);
  useEffect(() => {
    let alive = true;
    void hfCall<Detail>(`/assessments/${id}`).then((r) => { if (!alive) return; if (r.ok) setD(r.data); else setProblem(r.problem); });
    return () => { alive = false; };
  }, [id, tick]);
  if (!d) return <Modal title="Historical assessment" onClose={onClose}>{problem ? <ProblemNotice problem={problem} /> : <div className="row row--tight sub2"><Spinner /> Reading…</div>}</Modal>;
  const name = `${d.surname}, ${d.other_names}`;
  const open = d.state === "DRAFT" || d.state === "RETURNED_FOR_CORRECTION";
  const pending = d.state === "PENDING_BURSAR_APPROVAL";
  const comps = d.components ? (JSON.parse(d.components) as { item: string; amount: number }[]) : [];

  async function act(path: string, body: unknown, words: string, done: string) {
    setProblem(null);
    const r = await hfCall<Detail>(path, { method: "POST", body, reason: words });
    if (!r.ok) { setProblem(r.problem); return; }
    notify(done);
    setNote("");
    setTick((n) => n + 1);
    onChanged();
  }

  async function upload(file: File) {
    setProblem(null);
    const r = await hfCall<Detail>(`/assessments/${id}/evidence`, { method: "POST", body: { filename: file.name, dataUrl: await readDataUrl(file) }, reason: `Evidence for ${d!.reference}` });
    if (!r.ok) { setProblem(r.problem); return; }
    notify("Evidence added");
    setTick((n) => n + 1);
  }

  if (editing) {
    return (
      <AssessmentForm studentId={d.student_id} studentName={name}
        period={{ session: d.session, semester: d.semester, level: d.level, structure_amount: d.period?.structure_amount ?? null, paid: d.period?.paid ?? 0 }}
        existing={editing === "edit" ? d : null} corrects={editing === "correct" ? d : null} sources={desk.sources}
        onClose={() => setEditing(null)} onSaved={() => { setEditing(null); setTick((n) => n + 1); onChanged(); }} />
    );
  }

  return (
    <Modal wide title={`${d.reference} · ${STATE_WORDS[d.state]?.[0] ?? d.state}`} sub={`${name} · ${d.matric_no ?? "—"} · ${d.programme}`} onClose={onClose}
      foot={<>
        {open && can(desk, "EDIT_HISTORICAL_FEE_ASSESSMENT") ? <Btn kind="secondary" onClick={() => setEditing("edit")}>Change</Btn> : null}
        {open && can(desk, "SUBMIT_HISTORICAL_FEE_ASSESSMENT") ? <Btn kind="primary" busyLabel="Submitting…" onClick={() => act(`/assessments/${id}/submit`, {}, `${d.reference} submitted`, `${d.reference} submitted for the Bursar's approval`)}>Submit for Bursar approval</Btn> : null}
        {d.state === "APPROVED" && can(desk, "CORRECT_HISTORICAL_ASSESSMENT") ? <Btn kind="secondary" onClick={() => setEditing("correct")}>Correct historical assessment</Btn> : null}
        {(open || pending) && (d.mine || can(desk, "APPROVE_HISTORICAL_FEE_ASSESSMENT")) ? <Btn kind="ghost" busyLabel="Withdrawing…" onClick={() => act(`/assessments/${id}/cancel`, { note: note || null }, `${d.reference} withdrawn`, `${d.reference} withdrawn`)}>Withdraw</Btn> : null}
        <span className="grow" />
        {pending && !d.mine && can(desk, "REJECT_HISTORICAL_FEE_ASSESSMENT") ? <Btn kind="urgent" disabled={note.trim().length < 10} busyLabel="Rejecting…" onClick={() => act(`/assessments/${id}/decide`, { decision: "REJECT", note }, `${d.reference} rejected`, `${d.reference} rejected`)}>Reject</Btn> : null}
        {pending && !d.mine && can(desk, "RETURN_HISTORICAL_FEE_ASSESSMENT") ? <Btn kind="secondary" disabled={note.trim().length < 10} busyLabel="Returning…" onClick={() => act(`/assessments/${id}/decide`, { decision: "RETURN", note }, `${d.reference} returned`, `${d.reference} returned for correction`)}>Return for correction</Btn> : null}
        {pending && !d.mine && can(desk, "APPROVE_HISTORICAL_FEE_ASSESSMENT") ? <Btn kind="primary" busyLabel="Approving…" onClick={() => act(`/assessments/${id}/decide`, { decision: "APPROVE", note: note || null }, `${d.reference} approved`, `${d.reference} approved — it is now owed`)}>Approve</Btn> : null}
      </>}>
      {pending && d.mine ? <Note kind="info" title="You made this assessment">Another Bursar officer approves, returns or rejects it.</Note> : null}
      <div className="grid grid--4">
        <div className="kv"><span className="k">Period</span><span className="v">{d.session} · {semesterWords(d.semester)}</span></div>
        <div className="kv"><span className="k">Level then</span><span className="v">{d.level ?? "—"}</span></div>
        <div className="kv"><span className="k">Historical fee</span><span className="v tnum">{naira(d.amount)}</span></div>
        <div className="kv"><span className="k">Source</span><span className="v">{SOURCE_WORDS[d.source] ?? d.source}{d.source_reference ? ` · ${d.source_reference}` : ""}</span></div>
        <div className="kv"><span className="k">Paid towards the period</span><span className="v tnum">{naira(d.period?.paid)}</span></div>
        <div className="kv"><span className="k">Outstanding now</span><span className="v tnum">{d.period?.outstanding == null ? "—" : naira(d.period.outstanding)}</span></div>
        <div className="kv"><span className="k">The period now</span><span className="v">{d.period ? <Pil kind={PERIOD_WORDS[d.period.status]?.[1] ?? "grey"}>{PERIOD_WORDS[d.period.status]?.[0]}</Pil> : "—"}</span></div>
        <div className="kv"><span className="k">Made by</span><span className="v">{d.created_by_name ?? d.created_office ?? "—"} · {when(d.created_at)}</span></div>
      </div>
      {d.batch || d.corrects || d.superseded_by ? (
        <div className="sub2 mt-2">{d.batch ? `Batch ${d.batch}. ` : ""}{d.corrects ? `Corrects ${d.corrects}. ` : ""}{d.superseded_by ? `Superseded by ${d.superseded_by}.` : ""}</div>
      ) : null}
      <div className="mt-2"><span className="sub2">Reason</span><div>{d.reason}</div>{d.remarks ? <div className="sub2 mt-1">Remarks: {d.remarks}</div> : null}</div>
      {d.decision_note ? <Note kind={d.state === "REJECTED" ? "bad" : "info"} title={`${d.decided_by_name ?? d.decided_office ?? "The Bursar"} · ${when(d.decided_at)}`}>{d.decision_note}</Note> : null}
      {comps.length ? (
        <DTable cols={["Component", "Amount|num"]} rows={comps.map((c, i) => [<span key={`i${i}`}>{c.item}</span>, <span key={`a${i}`} className="tnum">{naira(c.amount)}</span>])} />
      ) : null}
      <div className="mt-2"><strong>Evidence</strong></div>
      {d.evidence.length ? (
        <ul className="m-0">{d.evidence.map((e) => (
          <li key={e.id}><a href={`${HF}/assessments/${id}/evidence/${e.id}`} target="_blank" rel="noreferrer">{e.filename}</a> <span className="sub2">· {Math.ceil(e.size_bytes / 1024)} KB · {e.added_by ?? "—"} · {when(e.added_at)}</span></li>
        ))}</ul>
      ) : <div className="sub2">None attached.</div>}
      {(open || pending) && can(desk, "EDIT_HISTORICAL_FEE_ASSESSMENT") ? (
        <label className="btn btn--ghost btn--sm mt-1" style={{ cursor: "pointer" }}>
          Attach evidence (PDF, JPEG or PNG, up to 5 MB)
          <input type="file" accept="application/pdf,image/jpeg,image/png" style={{ display: "none" }} onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(f); e.target.value = ""; }} />
        </label>
      ) : null}
      {pending || open ? (
        <Field id="hfa-note" label="Note" hint={pending ? "Required to return or reject (ten characters at least)" : "Optional, kept with a withdrawal"} className="mt-2">
          <textarea id="hfa-note" className="ctl" rows={2} value={note} maxLength={2000} onChange={(e) => setNote(e.target.value)} />
        </Field>
      ) : null}
      {d.events?.length ? (
        <>
          <div className="mt-2"><strong>Timeline</strong></div>
          <DTable cols={["When", "What", "Who", "Amount|num", "Note"]} rows={d.events.map((e, i) => [
            <span key={`w${i}`} className="sub2 tnum">{when(e.at)}</span>, <span key={`a${i}`}>{ACTION[e.action] ?? e.action}</span>,
            <span key={`o${i}`} className="sub2">{e.actor_name ?? e.office ?? "—"}</span>, <span key={`m${i}`} className="tnum">{e.amount == null ? "" : naira(e.amount)}</span>,
            <span key={`n${i}`} className="sub2">{e.note ?? ""}</span>,
          ])} />
        </>
      ) : null}
      {problem ? <ProblemNotice problem={problem} /> : null}
    </Modal>
  );
}
