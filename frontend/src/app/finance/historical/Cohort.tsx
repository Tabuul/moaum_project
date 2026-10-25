"use client";

/**
 * V654: a cohort's historical fee — the students of a session and semester in a scope (faculty, department, programme, the level
 * they were at) previewed first: the fee structure found for some (nothing to make), already assessed, pending, or still needing an
 * amount; then one amount assessed for those that need it, under one batch HFA-B/YYYY/NNNNNN the Bursar decides together (never its
 * maker). Nothing is made before the confirmation.
 */
import { useEffect, useState } from "react";
import { Btn, Note, Panel, PBody, Pil, Spinner } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { can, naira, num, semesterWords, SOURCE_NEEDS_REFERENCE, SOURCE_WORDS, STATE_WORDS, type Desk } from "@/lib/historical-fees";
import { hfCall } from "./hf-call";

interface PreviewRow { student_id: string; verdict: string; level: number | null; structure_amount: number | string | null; assessed: number | string | null; paid: number | string;
  outstanding: number | string | null; reference: string | null; surname: string; other_names: string; matric_no: string | null; status: string; programme: string }
interface Preview { total: number; byVerdict: Record<string, number>; paid: number | string; rows: PreviewRow[] }
interface Batch { id: string; reference: string; session: string; semester: number; scope: string; amount: number | string; source: string; source_reference: string | null;
  reason: string; students: number; state: string; created_at: string; created_by_name: string | null; mine: boolean; decided_at: string | null; decision_note: string | null }

const VERDICT: Record<string, [string, "ok" | "warn" | "bad" | "grey" | "info"]> = {
  REQUIRES_ASSESSMENT: ["Requires assessment", "bad"], STRUCTURE_FOUND: ["Fee structure found", "ok"], ALREADY_ASSESSED: ["Already assessed", "grey"], PENDING: ["Pending", "warn"],
};

export function Cohort({ desk, faculties, programmes, onChanged }: { desk: Desk; faculties: { code: string; name: string }[]; programmes: { code: string; name: string; faculty_code: string }[]; onChanged: () => void }) {
  const [scope, setScope] = useState({ session: desk.sessions[1] ?? desk.sessions[0] ?? "", semester: "1", faculty: "", programme: "", level: "" });
  const [preview, setPreview] = useState<Preview | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [making, setMaking] = useState(false);
  const [form, setForm] = useState({ amount: "", source: "COHORT_FEE_RECORD", sourceRef: "", reason: "" });
  const [batches, setBatches] = useState<Batch[] | null>(null);
  const [batchState, setBatchState] = useState("PENDING_BURSAR_APPROVAL");
  const [tick, setTick] = useState(0);
  const [deciding, setDeciding] = useState<Batch | null>(null);
  const [note, setNote] = useState("");

  useEffect(() => {
    let alive = true;
    void hfCall<Batch[]>(`/batches?state=${batchState}`).then((r) => { if (alive && r.ok) setBatches(r.data); });
    return () => { alive = false; };
  }, [batchState, tick]);

  async function read() {
    setProblem(null);
    setPreview(null);
    const r = await hfCall<Preview>("/bulk/preview", { method: "POST", body: { session: scope.session, semester: Number(scope.semester), faculty: scope.faculty || null,
      programme: scope.programme || null, level: scope.level ? Number(scope.level) : null, graduatedOnly: true } });
    if (!r.ok) { setProblem(r.problem); return; }
    setPreview(r.data);
  }

  const need = preview?.rows.filter((r) => r.verdict === "REQUIRES_ASSESSMENT") ?? [];
  const amt = Number(form.amount.replace(/[^0-9.]/g, ""));
  const ready = amt > 0 && form.reason.trim().length >= 20 && (!SOURCE_NEEDS_REFERENCE.has(form.source) || form.sourceRef.trim().length >= 4);

  async function confirm() {
    setProblem(null);
    const r = await hfCall<{ batch_id: string; reference: string; created: number; skipped: number }>("/bulk", { method: "POST",
      body: { studentIds: need.map((x) => x.student_id), session: scope.session, semester: Number(scope.semester), amount: amt, components: [], source: form.source,
        sourceReference: form.sourceRef.trim() || null, reason: form.reason.trim(), scope: { faculty: scope.faculty || null, programme: scope.programme || null, level: scope.level || null } },
      reason: `Cohort historical assessment for ${scope.session} ${semesterWords(Number(scope.semester)).toLowerCase()}` });
    if (!r.ok) { setProblem(r.problem); return; }
    notify(`${r.data.reference}: ${r.data.created} student${r.data.created === 1 ? "" : "s"} assessed and submitted for the Bursar's approval`);
    setMaking(false);
    setPreview(null);
    setTick((n) => n + 1);
    onChanged();
  }

  async function decide(decision: "APPROVE" | "RETURN" | "REJECT") {
    if (!deciding) return;
    const r = await hfCall<{ decided: number; state: string }>(`/batches/${deciding.id}/decide`, { method: "POST", body: { decision, note: note || null }, reason: `${deciding.reference} ${decision.toLowerCase()}` });
    if (!r.ok) { setProblem(r.problem); return; }
    notify(`${deciding.reference}: ${r.data.decided} assessment${r.data.decided === 1 ? "" : "s"} ${r.data.state.toLowerCase().replace(/_/g, " ")}`);
    setDeciding(null);
    setNote("");
    setTick((n) => n + 1);
    onChanged();
  }

  return (
    <>
      <Panel title="Cohort historical assessment">
        <PBody>
          <Note kind="info" title="Where a whole cohort lacks a session's fee structure, state it in School Fees Setup first">
            The setup&rsquo;s lines for that session then assess every student of the cohort at once, and the session&rsquo;s payments are reconciled against them. A cohort batch
            here assesses the graduates chosen without changing the session&rsquo;s structure for anyone else.
          </Note>
          <div className="row row--end" style={{ flexWrap: "wrap" }}>
            <Field id="co-ses" label="Session"><select id="co-ses" className="ctl" value={scope.session} onChange={(e) => setScope({ ...scope, session: e.target.value })}>{desk.sessions.map((x) => <option key={x} value={x}>{x}</option>)}</select></Field>
            <Field id="co-sem" label="Semester"><select id="co-sem" className="ctl" value={scope.semester} onChange={(e) => setScope({ ...scope, semester: e.target.value })}><option value="1">First semester</option><option value="2">Second semester</option><option value="3">Third semester</option></select></Field>
            <Field id="co-fac" label="Faculty"><select id="co-fac" className="ctl" value={scope.faculty} onChange={(e) => setScope({ ...scope, faculty: e.target.value, programme: "" })}><option value="">Every faculty</option>{faculties.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}</select></Field>
            <Field id="co-prog" label="Programme"><select id="co-prog" className="ctl" value={scope.programme} onChange={(e) => setScope({ ...scope, programme: e.target.value })}><option value="">Every programme</option>{programmes.filter((x) => !scope.faculty || x.faculty_code === scope.faculty).map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}</select></Field>
            <Field id="co-lvl" label="Level in that session"><select id="co-lvl" className="ctl" value={scope.level} onChange={(e) => setScope({ ...scope, level: e.target.value })}><option value="">Any</option>{[100, 200, 300, 400, 500, 600, 700, 800, 900].map((l) => <option key={l} value={l}>{l}</option>)}</select></Field>
            <Btn kind="primary" busyLabel="Reading…" disabled={!scope.session} onClick={read}>Preview</Btn>
          </div>
        </PBody>
        {preview ? (
          <>
            <PBody>
              <div className="grid grid--4">
                <div className="tile"><span className="eyebrow">Students selected</span><span className="n tnum">{preview.total.toLocaleString()}</span><span className="c">Graduates with this period on their record</span></div>
                <div className="tile"><span className="eyebrow">Fee structure found</span><span className="n tnum ink-green">{(preview.byVerdict.STRUCTURE_FOUND ?? 0).toLocaleString()}</span><span className="c">Assessed from the setup: nothing to make</span></div>
                <div className="tile"><span className="eyebrow">Already assessed or pending</span><span className="n tnum">{((preview.byVerdict.ALREADY_ASSESSED ?? 0) + (preview.byVerdict.PENDING ?? 0)).toLocaleString()}</span><span className="c">Left as they are</span></div>
                <div className="tile"><span className="eyebrow">Fee structure missing</span><span className="n tnum" style={{ color: need.length ? "var(--red-ink)" : undefined }}>{need.length.toLocaleString()}</span><span className="c">{naira(preview.paid)} already paid by them for the session</span></div>
              </div>
              {need.length && can(desk, "SUBMIT_HISTORICAL_FEE_ASSESSMENT") ? <div className="mt-2"><Btn kind="primary" onClick={() => setMaking(true)}>Assess the {need.length.toLocaleString()} student{need.length === 1 ? "" : "s"}…</Btn></div> : null}
            </PBody>
            <DTable cols={["Student", "Programme", "Level|num", "Fee structure|num", "Paid|num", "Verdict", "Reference"]} rows={preview.rows.map((r) => [
              <span key="s"><strong>{r.surname}, {r.other_names}</strong><span className="blk sub2 tnum">{r.matric_no ?? "—"}</span></span>, <span key="p" className="sub2">{r.programme}</span>,
              <span key="l" className="tnum">{r.level ?? "—"}</span>, <span key="f" className="tnum">{r.structure_amount == null ? "—" : naira(r.structure_amount)}</span>,
              <span key="pd" className="tnum">{naira(r.paid)}</span>, <Pil key="v" kind={VERDICT[r.verdict]?.[1] ?? "grey"}>{VERDICT[r.verdict]?.[0] ?? r.verdict}</Pil>,
              <span key="r" className="tnum sub2">{r.reference ?? ""}</span>,
            ])} />
          </>
        ) : null}
        {problem ? <PBody><ProblemNotice problem={problem} /></PBody> : null}
      </Panel>

      <Panel title="Cohort batches" right={
        <Field id="co-bs" label="State"><select id="co-bs" className="ctl" value={batchState} onChange={(e) => setBatchState(e.target.value)}>
          <option value="PENDING_BURSAR_APPROVAL">Awaiting the Bursar</option><option value="APPROVED">Approved</option><option value="RETURNED_FOR_CORRECTION">Returned</option><option value="REJECTED">Rejected</option><option value="ALL">Every batch</option>
        </select></Field>}>
        {!batches ? <PBody><div className="row row--tight sub2"><Spinner /> Reading…</div></PBody> : batches.length ? (
          <DTable cols={["Batch", "Period", "Students|num", "Amount|num", "Source", "Made by", "State", "|num"]} rows={batches.map((b) => [
            <span key="r" className="tnum">{b.reference}</span>, <span key="p">{b.session} · {semesterWords(b.semester)}</span>, <span key="n" className="tnum">{b.students}</span>,
            <span key="a" className="tnum">{naira(b.amount)}</span>, <span key="s" className="sub2">{SOURCE_WORDS[b.source] ?? b.source}{b.source_reference ? ` · ${b.source_reference}` : ""}</span>,
            <span key="m" className="sub2">{b.created_by_name ?? "—"}{b.mine ? " (you)" : ""}</span>,
            <Pil key="st" kind={STATE_WORDS[b.state as keyof typeof STATE_WORDS]?.[1] ?? "grey"}>{STATE_WORDS[b.state as keyof typeof STATE_WORDS]?.[0] ?? b.state}</Pil>,
            b.state === "PENDING_BURSAR_APPROVAL" && !b.mine && can(desk, "APPROVE_HISTORICAL_FEE_ASSESSMENT") ? <Btn key="d" kind="primary" onClick={() => setDeciding(b)}>Decide…</Btn> : <span key="d" />,
          ])} />
        ) : <PBody><div className="sub2">No batch.</div></PBody>}
      </Panel>

      {making ? (
        <Modal title={`Assess ${need.length.toLocaleString()} student${need.length === 1 ? "" : "s"}`} sub={`${scope.session} · ${semesterWords(Number(scope.semester))}`} onClose={() => setMaking(false)}
          foot={<><Btn kind="ghost" onClick={() => setMaking(false)}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={!ready} busyLabel="Assessing…" onClick={confirm}>Confirm assessment</Btn></>}>
          <Note kind="info" title={`Estimated: ${naira(amt * need.length)} assessed, ${naira(Math.max(amt * need.length - num(preview?.paid), 0))} outstanding`}>
            Each student gets their own assessment, submitted for the Bursar&rsquo;s approval under one batch. A student assessed or pending meanwhile is skipped.
          </Note>
          <div className="grid grid--2">
            <Field id="co-amt" label="Amount for each student (₦)" required><input id="co-amt" className="ctl tnum" inputMode="decimal" value={form.amount} onChange={(e) => setForm({ ...form, amount: e.target.value })} /></Field>
            <Field id="co-src" label="Assessment source" required><select id="co-src" className="ctl" value={form.source} onChange={(e) => setForm({ ...form, source: e.target.value })}>{desk.sources.map((s) => <option key={s} value={s}>{SOURCE_WORDS[s] ?? s}</option>)}</select></Field>
          </div>
          <Field id="co-ref" label="Supporting reference" required={SOURCE_NEEDS_REFERENCE.has(form.source)}><input id="co-ref" className="ctl" value={form.sourceRef} maxLength={300} onChange={(e) => setForm({ ...form, sourceRef: e.target.value })} /></Field>
          <Field id="co-why" label="Reason" required hint="Twenty characters at least"><textarea id="co-why" className="ctl" rows={3} value={form.reason} onChange={(e) => setForm({ ...form, reason: e.target.value })} /></Field>
          {problem ? <ProblemNotice problem={problem} /> : null}
        </Modal>
      ) : null}
      {deciding ? (
        <Modal title={`Decide ${deciding.reference}`} sub={`${deciding.students} students · ${naira(deciding.amount)} each · ${deciding.session} ${semesterWords(deciding.semester)}`} onClose={() => setDeciding(null)}
          foot={<><Btn kind="ghost" onClick={() => setDeciding(null)}>Cancel</Btn><span className="grow" />
            <Btn kind="urgent" disabled={note.trim().length < 10} busyLabel="Rejecting…" onClick={() => decide("REJECT")}>Reject</Btn>
            <Btn kind="secondary" disabled={note.trim().length < 10} busyLabel="Returning…" onClick={() => decide("RETURN")}>Return for correction</Btn>
            <Btn kind="primary" busyLabel="Approving…" onClick={() => decide("APPROVE")}>Approve every assessment</Btn></>}>
          <div className="sub2">{deciding.reason}</div>
          <Field id="co-note" label="Note" hint="Required to return or reject"><textarea id="co-note" className="ctl" rows={2} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
          {problem ? <ProblemNotice problem={problem} /> : null}
        </Modal>
      ) : null}
    </>
  );
}
