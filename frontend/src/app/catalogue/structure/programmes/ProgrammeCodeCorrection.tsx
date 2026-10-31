"use client";
/** A programme's code corrected (V716), as a course's is (V713): the new code typed, what the database says the change would be — the
 *  impact, and why it would be refused — read as it is typed; a reason from the list; a ticket where there is one; then confirmed and
 *  made against the version the person read. The same programme under the new code: every student and record follows, the old code
 *  stays as an alias. The server refuses whatever the office may not do. */
import { useEffect, useRef, useState } from "react";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { REASONS, REASON_WORDS, codeProblem, impactLines, impactSentence, normalCode, reasonProblem, type ProgrammeCodeCheck, type ProgrammeCodeDone } from "@/lib/programme-correction";

export function ProgrammeCodeCorrection({ programme, onClose, onDone }: {
  programme: { code: string; name: string };
  onClose: () => void;
  onDone: (d: ProgrammeCodeDone) => void;
}) {
  const [form, setForm] = useState({ code: "", reason: "", remarks: "", ticket: "" });
  const [check, setCheck] = useState<ProgrammeCodeCheck | null>(null);
  const [step, setStep] = useState<"edit" | "confirm">("edit");
  const [busy, setBusy] = useState(false);
  const [stale, setStale] = useState<string | null>(null);
  const seq = useRef(0);

  // what the database says the change would be, read again as the code is typed
  useEffect(() => {
    const n = ++seq.current;
    const t = setTimeout(async () => {
      const r = await fetch(`/api/bff/api/v1/catalogue/programmes/${encodeURIComponent(programme.code)}/code-correction/check`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Programme code correction checked") },
        body: JSON.stringify({ newCode: normalCode(form.code) }),
      });
      const j = await r.json().catch(() => null);
      if (n !== seq.current) return;
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      setCheck(j as ProgrammeCodeCheck);
    }, 350);
    return () => clearTimeout(t);
  }, [form.code, programme.code]);

  const local = codeProblem(form.code, programme.code) ?? reasonProblem(form.reason, form.remarks);
  const refusal = check?.refusal && form.code.trim() ? check.refusal : null;
  const mayNot = check ? !check.may : false;
  const blocker = mayNot ? "Your office may not correct this programme's code." : local ?? refusal?.message ?? null;
  const lines = impactLines(check?.impact);

  async function save() {
    if (!check) return;
    setBusy(true);
    try {
      const q = form.ticket.trim() ? `?ticket=${encodeURIComponent(form.ticket.trim())}` : "";
      const r = await fetch(`/api/bff/api/v1/catalogue/programmes/${encodeURIComponent(programme.code)}/code-correction${q}`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Programme code corrected: ${REASON_WORDS[form.reason] ?? form.reason}${form.remarks.trim() ? ` — ${form.remarks.trim()}` : ""}`) },
        body: JSON.stringify({ newCode: normalCode(form.code), reasonKind: form.reason, remarks: form.remarks.trim() || null, version: check.version }),
      });
      const j = (await r.json().catch(() => null)) as (Record<string, unknown> & { code?: string; detail?: string }) | null;
      if (!r.ok) {
        if (j?.code === "PROGRAMME_CHANGED_SINCE") { setStale(String(j.detail ?? "This programme has been updated by another user.")); setStep("edit"); return; }
        notifyProblem(j ? (j as unknown as Parameters<typeof notifyProblem>[0]) : { status: r.status, title: r.statusText });
        return;
      }
      const d = j as unknown as ProgrammeCodeDone;
      notify(`${d.was} is now ${d.code} — ${d.name}: the same programme`);
      onDone(d);
    } finally {
      setBusy(false);
    }
  }

  if (step === "confirm" && check) {
    return (
      <Modal title="Confirm programme code change" sub={<span>{programme.name} — the same programme before and after</span>} onClose={onClose} wide
        foot={<><Btn kind="ghost" disabled={busy} onClick={() => setStep("edit")}>Back</Btn><Btn kind="urgent" disabled={busy || !!blocker} onClick={() => void save()}>{busy ? "Saving…" : "Confirm change"}</Btn></>}>
        <div className="stack">
          <table className="tbl--data">
            <thead><tr><th /><th>Current</th><th>New</th></tr></thead>
            <tbody>
              <tr><th scope="row">Code</th><td className="tnum">{check.code}</td><td className="tnum"><b>{check.newCode}</b>{check.reused ? <div className="sub2">a code an undone correction left, taken again</div> : null}</td></tr>
              <tr><th scope="row">Programme</th><td>{check.name}</td><td>{check.name}</td></tr>
            </tbody>
          </table>
          <div>
            <div className="eyebrow">Impact</div>
            <div className="sub2">{impactSentence(check.impact)}</div>
            {lines.length ? <ul className="sub2" style={{ margin: "4px 0 0 18px" }}>{lines.map((l) => <li key={l}>{l}</li>)}</ul> : null}
            <div className="sub2 mt-2">The old code {check.code} is archived and kept as an alias: an upload, a JAMB list or an old-portal file written with it lands on {check.newCode}. The change is written down with your reason{form.ticket.trim() ? ` on ticket ${form.ticket.trim()}` : ""}, and the Director of ICT or the ICT Support Desk can undo it.</div>
          </div>
          <div className="sub2">Reason: <b>{REASON_WORDS[form.reason] ?? form.reason}</b>{form.remarks.trim() ? ` — ${form.remarks.trim()}` : ""}</div>
        </div>
      </Modal>
    );
  }

  return (
    <Modal title="Correct programme code" sub={<span className="tnum">{programme.code} — {programme.name}</span>} onClose={onClose} wide
      foot={<><Btn kind="ghost" onClick={onClose}>Cancel</Btn><Btn kind="primary" disabled={!check || !!blocker} onClick={() => setStep("confirm")}>Review the change</Btn></>}>
      <div className="stack">
        {stale ? <Note kind="bad" title="Updated by another user" action={<Btn kind="primary" onClick={() => window.location.reload()}>Reload</Btn>}>{stale}</Note> : null}
        {mayNot ? <Note kind="bad" title="Not within your reach">Your support posting does not carry changing a programme&rsquo;s code over this programme&rsquo;s faculty or department. Escalate it to the Head of the ICT Support Desk or the Director of ICT.</Note> : null}
        <Field id="pcc-code" label="New programme code" required hint="C and five digits, as JAMB writes it (C00023). A code another programme holds is refused: two programmes that are one are merged on Records › Programme Merge, never corrected into each other.">
          <input id="pcc-code" className="ctl tnum" value={form.code} maxLength={10} autoComplete="off" onChange={(e) => setForm({ ...form, code: e.target.value })} placeholder="C00000" />
        </Field>
        {refusal ? <Note kind="bad" title="This change would be refused">{refusal.message}</Note> : null}
        <Field id="pcc-reason" label="Reason" required>
          <select id="pcc-reason" className="ctl" value={form.reason} onChange={(e) => setForm({ ...form, reason: e.target.value })}>
            <option value="">Choose the reason</option>
            {REASONS.map(([k, w]) => <option key={k} value={k}>{w}</option>)}
          </select>
        </Field>
        <Field id="pcc-remarks" label="Remarks" hint={form.reason === "OTHER" ? "Required for Other: what the correction is for" : "Optional: the letter, the JAMB brochure, the Senate minute"}>
          <textarea id="pcc-remarks" className="ctl" rows={2} maxLength={2000} value={form.remarks} onChange={(e) => setForm({ ...form, remarks: e.target.value })} />
        </Field>
        <Field id="pcc-ticket" label="Ticket" hint="Optional: the ICT Support ticket number the correction is made on; the change goes on its timeline">
          <input id="pcc-ticket" className="ctl tnum" value={form.ticket} maxLength={40} autoComplete="off" onChange={(e) => setForm({ ...form, ticket: e.target.value })} placeholder="TICK-…" />
        </Field>
        {check ? (
          <div>
            <div className="eyebrow">What hangs on {check.code}</div>
            <div className="sub2">{impactSentence(check.impact)}</div>
            {lines.length ? <ul className="sub2" style={{ margin: "4px 0 0 18px" }}>{lines.map((l) => <li key={l}>{l}</li>)}</ul> : <div className="sub2">Nothing names it yet.</div>}
          </div>
        ) : null}
      </div>
    </Modal>
  );
}
