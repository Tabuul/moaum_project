"use client";

/** one programme swap, in a window (V578): the placement before and after, the review points, the evidence, the student's programme
 *  history, and — while it awaits a decision — what it would do on the record as it stands now, with the decision itself */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, day } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { KIND_WORDS, STATUS_WORDS, changeWords, refusalWords, type CheckResult, type Swap } from "@/lib/programme-swap";
import { SWAPS, fileAsDataUrl, swapGet, swapPost } from "./swap-call";
import { ProgrammeHistory } from "./ProgrammeHistory";

type Detail = Omit<Swap, "evidence"> & {
  evidence: { id: string; filename: string; content_type: string; size_bytes: number; added_at: string; added_by: string | null }[];
  history: Record<string, unknown>[];
  /** while the swap awaits a decision: what it would do on the record as it stands now */
  now?: CheckResult;
  mayDecide: boolean;
};

const naira = (v: unknown) => `₦${Number(v ?? 0).toLocaleString("en-GB", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

export function SwapDetail({ id, actingOffice, onClose, onChanged }: { id: string; actingOffice: string | null; onClose: () => void; onChanged: () => void }) {
  const [d, setD] = useState<Detail | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [changed, setChanged] = useState(false);

  useEffect(() => {
    let live = true;
    void swapGet<Detail>(`/${id}`).then((r) => { if (!live) return; if (r.ok) setD(r.data); else setProblem(r.problem); });
    return () => { live = false; };
  }, [id]);

  async function decide(approve: boolean) {
    setBusy(approve ? "approve" : "reject");
    try {
      const r = await swapPost<Detail>(`/${id}/decide`, { approve, note }, `Programme swap ${approve ? "approved" : "rejected"}: ${d?.swap_ref}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      setD(r.data);
      setChanged(true);
      notify(r.data.status === "COMPLETED" ? `Programme swap completed: ${r.data.swap_ref}` : r.data.status === "FAILED" ? `The swap failed: ${r.data.failure ?? ""}` : `Swap ${r.data.status.toLowerCase()}`,
        r.data.status === "FAILED" ? "bad" : undefined);
    } finally { setBusy(null); }
  }
  async function cancel() {
    setBusy("cancel");
    try {
      const r = await swapPost<Detail>(`/${id}/cancel`, { reason: note }, `Programme swap cancelled: ${d?.swap_ref}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      setD(r.data);
      setChanged(true);
      notify("Swap cancelled");
    } finally { setBusy(null); }
  }
  async function addEvidence(file: File) {
    setBusy("evidence");
    try {
      const dataUrl = await fileAsDataUrl(file);
      const r = await swapPost<Detail>(`/${id}/evidence`, { filename: file.name, dataUrl }, `Programme swap evidence added: ${file.name}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      setD(r.data);
      notify("Evidence added");
    } finally { setBusy(null); }
  }

  const pending = d?.status === "PENDING_APPROVAL";
  const prepares = ["academic", "ict", "registrar", "dregistrar", "super"].includes(actingOffice ?? "");
  const close = () => { onClose(); if (changed) onChanged(); };
  return (
    <Modal wide title={d ? `Programme swap ${d.swap_ref}` : "Programme swap"} sub={d ? `${d.student} · ${d.matric_no ?? d.jamb_reg_no ?? ""}` : ""} onClose={close}
      foot={<>
        <Btn kind="ghost" onClick={close}>Close</Btn>
        {d && pending && prepares ? <Btn kind="ghost" busy={busy === "cancel"} busyLabel="Cancelling…" disabled={!!busy || note.trim().length < 10} onClick={cancel} title="Cancelled by the officer who prepared it, the Academic Office or the Registry; say why below">Cancel the swap</Btn> : null}
        {d && pending && d.mayDecide ? <Btn kind="ghost" busy={busy === "reject"} busyLabel="Rejecting…" disabled={!!busy || note.trim().length < 10} onClick={() => decide(false)}>Reject</Btn> : null}
        {d && pending && d.mayDecide ? <Btn kind="primary" busy={busy === "approve"} busyLabel="Processing programme swap…" disabled={!!busy || !d.now?.ok} onClick={() => decide(true)}>Confirm programme swap</Btn> : null}
      </>}>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {!d && !problem ? <div className="sub2">Opening the swap…</div> : null}
      {d ? (
        <>
          <div className="row" style={{ gap: "var(--s-3)", flexWrap: "wrap", marginBottom: "var(--s-3)" }}>
            <Pil kind={d.status === "COMPLETED" ? "ok" : pending ? "warn" : d.status === "REJECTED" || d.status === "FAILED" ? "bad" : "grey"}>{STATUS_WORDS[d.status]}</Pil>
            <Pil kind="info">{KIND_WORDS[d.kind]}</Pil>
            <span className="sub2">Changes: {changeWords(d)} · effective {d.effective_session}</span>
          </div>
          <div className="grid grid--2">
            <div>
              <div className="eyebrow">Current record{d.status === "COMPLETED" ? " (before)" : ""}</div>
              <KvGrid cls="grid--2" pairs={[["Faculty", d.from_faculty_name ?? d.from_faculty ?? "—"], ["Department", d.from_department ?? d.from_dept ?? "—"],
                ["Programme", d.from_programme_name ?? d.from_programme], ["Level", d.from_level == null ? "—" : `${d.from_level} Level`]]} />
            </div>
            <div>
              <div className="eyebrow">New record</div>
              <KvGrid cls="grid--2" pairs={[["Faculty", d.to_faculty_name ?? d.to_faculty ?? "—"], ["Department", d.to_department ?? d.to_dept ?? "—"],
                ["Programme", d.to_programme_name ?? d.to_programme], ["Level", `${d.to_level} Level`]]} />
            </div>
          </div>
          <KvGrid cls="grid--3" pairs={[["Reason", d.reason], ["Prepared by", `${d.prepared_by ?? "—"} (${d.prepared_office}) · ${day(d.prepared_at)}`],
            ["Decided by", d.decided_by ? `${d.decided_by} (${d.decided_office}) · ${day(d.decided_at)}${d.decision_note ? ` · ${d.decision_note}` : ""}` : "—"]]} />
          {d.failure ? <Note kind="bad" title="The swap failed">{refusalWords(d.failure)}</Note> : null}
          {d.review.length ? (
            <Note kind="info" title="Points to look at">
              {d.review.map((w) => <div key={w.code}>{w.text}</div>)}
            </Note>
          ) : null}
          {pending && d.now ? (
            <Note kind={d.now.ok ? "ok" : "bad"} title={d.now.ok ? "On the record as it stands now, the swap goes through" : "On the record as it stands now, the swap is refused"}>
              {d.now.refusals.map((r) => <div key={r}>{refusalWords(r)}</div>)}
              {d.now.fees ? <div className="sub2">School fees {d.now.fees.session}: {naira(d.now.fees.current)} under the current programme, {naira(d.now.fees.new)} under the new one — nothing is charged by the swap.</div> : null}
            </Note>
          ) : null}
          {d.impact ? (
            <Note kind="info" title={`Course registration for ${d.effective_session}`}>
              {d.impact.registered} course{d.impact.registered === 1 ? "" : "s"} registered, {d.impact.applicable} applicable to the new programme, {d.impact.extra.length} not offered to it
              {d.impact.extra.length ? ` (${d.impact.extra.map((c) => c.code).join(", ")})` : ""}; {d.impact.missingCore.length} core course{d.impact.missingCore.length === 1 ? "" : "s"} of the new programme not registered
              {d.impact.missingCore.length ? ` (${d.impact.missingCore.map((c) => c.code).join(", ")})` : ""}. The registration is kept as it is; the Academic Office reviews it.
            </Note>
          ) : null}
          <div className="row row--between" style={{ marginTop: "var(--s-3)" }}>
            <div className="eyebrow">Evidence</div>
            {pending && prepares ? <label className="btn btn--ghost btn--sm">{busy === "evidence" ? "Adding…" : "Add a file"}<input type="file" accept="application/pdf,image/jpeg,image/png" hidden disabled={!!busy}
              onChange={(e) => { const f = e.target.files?.[0]; if (f) void addEvidence(f); e.target.value = ""; }} /></label> : null}
          </div>
          {d.evidence.length ? <DTable pageSize={0} cols={["File", "Size|num", "Added"]} rows={d.evidence.map((e) => [
            <a key="f" href={`${SWAPS}/${id}/evidence/${e.id}`} target="_blank" rel="noopener" className="ink-chrome">{e.filename}</a>,
            <span key="s" className="tnum">{Math.round(e.size_bytes / 1024)} KB</span>, <span key="a" className="sub2">{e.added_by ?? ""} · {day(e.added_at)}</span>])} />
            : <div className="sub2">No file attached.</div>}
          {pending && (d.mayDecide || prepares) ? (
            <Field id="sd-note" label="Note" hint="Required to reject or cancel; kept on the swap" full>
              <textarea id="sd-note" className="ctl" rows={2} value={note} onChange={(e) => setNote(e.target.value)} />
            </Field>
          ) : null}
          {pending && !d.mayDecide ? <div className="sub2">Decided by an officer of the Academic Office or the Registry other than the one who prepared it{d.kind === "LEGACY_MIGRATION_CORRECTION" ? ", or the Director of ICT" : ""}.</div> : null}
          <div className="eyebrow" style={{ marginTop: "var(--s-4)" }}>Programme history</div>
          <ProgrammeHistory rows={d.history} />
        </>
      ) : null}
    </Modal>
  );
}
