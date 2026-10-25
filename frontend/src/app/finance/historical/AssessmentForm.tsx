"use client";

/**
 * V654: a historical assessment made, changed (a draft or one returned for correction) or a correction of an approved one proposed:
 * the amount and its components, the source from the University's list (a document named where the source is a document or an
 * approval), the reason and remarks; saved as a draft or submitted for the Bursar's approval. The database checks every rule.
 */
import { useState } from "react";
import { Btn, IcoBtn, Note } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { naira, num, readComponents, semesterWords, SOURCE_NEEDS_REFERENCE, SOURCE_WORDS, type Assessment, type Period } from "@/lib/historical-fees";
import { hfCall } from "./hf-call";

export function AssessmentForm({ studentId, studentName, period, existing, corrects, sources, onClose, onSaved }: {
  studentId: string; studentName: string; period: Pick<Period, "session" | "semester" | "level" | "structure_amount" | "paid">;
  /** a draft or returned assessment being changed */
  existing?: Assessment | null;
  /** the approved assessment a correction replaces */
  corrects?: Assessment | null;
  sources: string[]; onClose: () => void; onSaved: (id: string) => void;
}) {
  const parsed = existing?.components ? (JSON.parse(existing.components) as { item: string; amount: number }[]) : [];
  const [amount, setAmount] = useState(existing ? String(num(existing.amount)) : "");
  const [rows, setRows] = useState<{ item: string; amount: string }[]>(parsed.length ? parsed.map((c) => ({ item: c.item, amount: String(c.amount) })) : [{ item: "", amount: "" }]);
  const [source, setSource] = useState(existing?.source ?? (corrects ? "OFFICIAL_FEE_DOCUMENT" : ""));
  const [sourceRef, setSourceRef] = useState(existing?.source_reference ?? "");
  const [reason, setReason] = useState(existing?.reason ?? "");
  const [remarks, setRemarks] = useState(existing?.remarks ?? "");
  const [problem, setProblem] = useState<Problem | null>(null);
  const comps = readComponents(rows);
  const compSum = comps.reduce((n, c) => n + (Number.isFinite(c.amount) ? c.amount : 0), 0);
  const amt = Number(amount.replace(/[^0-9.]/g, ""));
  const mismatch = comps.length > 0 && Math.abs(compSum - amt) >= 0.005;
  const needsRef = SOURCE_NEEDS_REFERENCE.has(source);
  const ready = amt > 0 && !!source && reason.trim().length >= 20 && !mismatch && (!needsRef || sourceRef.trim().length >= 4);

  async function save(submit: boolean) {
    setProblem(null);
    const body = { studentId, session: period.session, semester: period.semester, amount: amt, components: comps, source, sourceReference: sourceRef.trim() || null,
      reason: reason.trim(), remarks: remarks.trim() || null, corrects: corrects?.id ?? null, submit };
    const words = `${corrects ? "Correction of " + corrects.reference : "Historical assessment"} for ${studentName}, ${period.session} ${semesterWords(period.semester).toLowerCase()}`;
    const r = existing
      ? await hfCall<{ id: string; reference: string; state: string }>(`/assessments/${existing.id}`, { method: "PUT", body, reason: words })
      : await hfCall<{ id: string; reference: string; state: string }>("/assessments", { method: "POST", body, reason: words });
    if (!r.ok) { setProblem(r.problem); return; }
    notify(submit ? `${r.data.reference} submitted for the Bursar's approval` : `${r.data.reference} saved as a draft`);
    onSaved(r.data.id);
  }

  return (
    <Modal wide title={corrects ? `Correct ${corrects.reference}` : existing ? `Change ${existing.reference}` : "Create historical assessment"}
      sub={`${studentName} · ${period.session} · ${semesterWords(period.semester)} · ${period.level ?? "—"} Level`} onClose={onClose}
      foot={<>
        <Btn kind="ghost" onClick={onClose}>Cancel</Btn>
        <span className="grow" />
        <Btn kind="secondary" disabled={!ready} busyLabel="Saving…" onClick={() => save(false)}>Save as draft</Btn>
        <Btn kind="primary" disabled={!ready} busyLabel="Submitting…" onClick={() => save(true)}>Submit for Bursar approval</Btn>
      </>}>
      {period.structure_amount != null && !corrects ? (
        <Note kind="info" title={`The ${period.session} fee structure reads ${naira(period.structure_amount)} for this semester`}>
          An assessment replaces it for this student alone — a fee that was legitimately different (a concession, a special category). The global fee
          structure is never changed for one student.
        </Note>
      ) : corrects ? (
        <Note kind="info" title={`${corrects.reference} (${naira(corrects.amount)}) stays as it was until the Bursar approves this correction`}>
          Approved, the correction supersedes it; both stay on the record.
        </Note>
      ) : (
        <Note kind="bad" title="Historical fee structure not found">
          Nothing is assessed for this semester until an amount is approved. Use the official historical fee for the student&rsquo;s session, level and category —
          or, where a whole cohort lacks it, state the session&rsquo;s fee structure in School Fees Setup instead.
        </Note>
      )}
      <div className="grid grid--2">
        <Field id="hfa-amount" label="Amount (₦)" required hint={`Paid towards the session so far: ${naira(period.paid)}`}>
          <input id="hfa-amount" className="ctl tnum" inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)} />
        </Field>
        <Field id="hfa-source" label="Assessment source" required>
          <select id="hfa-source" className="ctl" value={source} onChange={(e) => setSource(e.target.value)}>
            <option value="">Choose…</option>
            {sources.map((s) => <option key={s} value={s}>{SOURCE_WORDS[s] ?? s}</option>)}
          </select>
        </Field>
        <Field id="hfa-ref" label="Supporting reference" required={needsRef} hint="The fee schedule, circular, approval or record the amount comes from">
          <input id="hfa-ref" className="ctl" value={sourceRef} maxLength={300} onChange={(e) => setSourceRef(e.target.value)} placeholder="BUR/2021/14 fee circular" />
        </Field>
        <Field id="hfa-remarks" label="Remarks"><input id="hfa-remarks" className="ctl" value={remarks} maxLength={2000} onChange={(e) => setRemarks(e.target.value)} /></Field>
      </div>
      <Field id="hfa-reason" label="Reason" required hint="Twenty characters at least: why this amount, for this student and period">
        <textarea id="hfa-reason" className="ctl" rows={3} value={reason} maxLength={2000} onChange={(e) => setReason(e.target.value)} />
      </Field>
      <div className="mt-2"><strong>Fee components</strong> <span className="sub2">optional — when given, they add up to the amount</span></div>
      {rows.map((r, i) => (
        <div key={i} className="row row--tight mt-1" style={{ alignItems: "flex-end", flexWrap: "wrap" }}>
          <Field id={`hfa-i${i}`} label={i === 0 ? "Item" : <span className="sr-only">Item {i + 1}</span>} style={{ flex: "2 1 220px" }}>
            <input id={`hfa-i${i}`} className="ctl" value={r.item} onChange={(e) => setRows(rows.map((x, k) => (k === i ? { ...x, item: e.target.value } : x)))} />
          </Field>
          <Field id={`hfa-a${i}`} label={i === 0 ? "Amount (₦)" : <span className="sr-only">Amount {i + 1}</span>} style={{ flex: "1 1 120px" }}>
            <input id={`hfa-a${i}`} className="ctl tnum" inputMode="decimal" value={r.amount} onChange={(e) => setRows(rows.map((x, k) => (k === i ? { ...x, amount: e.target.value } : x)))} />
          </Field>
          <IcoBtn icon="trash" label={`Remove component ${i + 1}`} disabled={rows.length === 1} onClick={() => setRows(rows.filter((_, k) => k !== i))} />
        </div>
      ))}
      <div className="row row--tight mt-1">
        <Btn kind="ghost" disabled={rows.length >= 30} onClick={() => setRows([...rows, { item: "", amount: "" }])}>Add component</Btn>
        <span className="grow" />
        {comps.length ? <span className={mismatch ? "ink-red" : "sub2"}>Components add up to <b className="tnum">{naira(compSum)}</b>{mismatch ? ` — not ${naira(amt)}` : ""}</span> : null}
      </div>
      {problem ? <ProblemNotice problem={problem} /> : null}
    </Modal>
  );
}
