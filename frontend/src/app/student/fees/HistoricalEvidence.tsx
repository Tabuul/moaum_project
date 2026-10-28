"use client";

/**
 * V683: payment evidence a graduate gives for a past semester their school fees history shows as unpaid — the receipt, teller or
 * old-portal receipt, the amount, the day and how it was paid, with the file. The Bursary checks it against the payments on record:
 * verified (against the payment it shows), more information needed (added here and sent again), or not accepted. It never counts as
 * paid by itself; only the payment does, once it is put right. Every rule is the database's.
 */
import { useState } from "react";
import { Btn, Note, Pil } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify } from "@/components/proto/Toast";
import {
  CHANNEL_WORDS, EVIDENCE_WORDS, evidenceBody, evidencePeriods, evidenceProblem, naira, semesterWords,
  type Evidence, type EvidenceChannel, type EvidenceForm, type Period,
} from "@/lib/historical-fees";
import { useAct } from "../common";

const BLANK: EvidenceForm = { amount: "", paidOn: "", channel: "", reference: "", note: "" };
const lagosToday = () => new Date().toLocaleDateString("en-CA", { timeZone: "Africa/Lagos" });
const keyOf = (p: { session: string; semester: number }) => `${p.session}|${p.semester}`;
const onDay = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric", timeZone: "Africa/Lagos" }) : "—");

function readDataUrl(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result));
    r.onerror = () => reject(r.error);
    r.readAsDataURL(file);
  });
}

/** what the graduate says about the payment: the same fields when first sent and when sent again */
function EvidenceFields({ id, f, set, today }: { id: string; f: EvidenceForm; set: (f: EvidenceForm) => void; today: string }) {
  return (
    <div className="grid grid--2">
      <Field id={`${id}-amount`} label="Amount paid (₦)" required>
        <input id={`${id}-amount`} className="ctl tnum" inputMode="decimal" value={f.amount} onChange={(e) => set({ ...f, amount: e.target.value })} />
      </Field>
      <Field id={`${id}-day`} label="Day paid" hint="As on the receipt, if you know it">
        <input id={`${id}-day`} type="date" className="ctl" max={today} value={f.paidOn} onChange={(e) => set({ ...f, paidOn: e.target.value })} />
      </Field>
      <Field id={`${id}-channel`} label="How you paid" required>
        <select id={`${id}-channel`} className="ctl" value={f.channel} onChange={(e) => set({ ...f, channel: e.target.value as EvidenceChannel | "" })}>
          <option value="">Choose…</option>
          {(Object.keys(CHANNEL_WORDS) as EvidenceChannel[]).map((c) => <option key={c} value={c}>{CHANNEL_WORDS[c]}</option>)}
        </select>
      </Field>
      <Field id={`${id}-ref`} label="Receipt, teller or transaction number" required hint="As printed on your evidence">
        <input id={`${id}-ref`} className="ctl tnum" maxLength={80} value={f.reference} onChange={(e) => set({ ...f, reference: e.target.value })} />
      </Field>
      <div style={{ gridColumn: "1 / -1" }}>
        <Field id={`${id}-note`} label="Anything the Bursary should know" hint="Optional, up to 1,000 characters">
          <textarea id={`${id}-note`} className="ctl" rows={2} maxLength={1000} value={f.note} onChange={(e) => set({ ...f, note: e.target.value })} />
        </Field>
      </div>
    </div>
  );
}

export function HistoricalEvidence({ periods, evidence }: { periods: Period[]; evidence: Evidence[] }) {
  const { act, busy, problem } = useAct();
  const today = lagosToday();
  const choices = evidencePeriods(periods, evidence);
  const [open, setOpen] = useState(false);
  const [period, setPeriod] = useState(choices[0] ? keyOf(choices[0]) : "");
  const [f, setF] = useState<EvidenceForm>(BLANK);
  const [files, setFiles] = useState<File[]>([]);
  const [again, setAgain] = useState<string | null>(null);
  const [g, setG] = useState<EvidenceForm>(BLANK);
  const [moreFiles, setMoreFiles] = useState<File[]>([]);
  const chosen = choices.find((p) => keyOf(p) === period) ?? choices[0] ?? null;
  const fp = evidenceProblem(f, today);
  const gp = evidenceProblem(g, today);

  async function upload(id: string, list: File[]): Promise<boolean> {
    for (const file of list) {
      const ok = await act(`file-${id}`, "POST", `/me/historical-evidence/${id}/files`, { filename: file.name, dataUrl: await readDataUrl(file) },
        "Payment evidence file added by the student", "");
      if (!ok) return false;
    }
    return true;
  }

  async function submit() {
    if (!chosen) return;
    const j = await act("hpe", "POST", "/me/historical-evidence", { session: chosen.session, semester: chosen.semester, ...evidenceBody(f) },
      `Payment evidence for ${chosen.session} ${semesterWords(chosen.semester).toLowerCase()} submitted by the student`, "");
    if (!j) return;
    const filed = await upload(String(j.id), files);
    notify(filed ? `Payment evidence ${String(j.reference)} is with the Bursary` : `Payment evidence ${String(j.reference)} is with the Bursary; add the file again below`);
    setOpen(false);
    setF(BLANK);
    setFiles([]);
  }

  async function sendAgain(e: Evidence) {
    if (!(await upload(e.id, moreFiles))) return;
    const j = await act(`again-${e.id}`, "POST", `/me/historical-evidence/${e.id}/resubmit`, evidenceBody(g), `Payment evidence ${e.reference} sent again by the student`, "");
    if (!j) return;
    notify(`${e.reference} sent again to the Bursary`);
    setAgain(null);
    setMoreFiles([]);
  }

  return (
    <div className="mt-3">
      <div className="row" style={{ alignItems: "center", flexWrap: "wrap", gap: 8 }}>
        <b className="grow">Payment evidence</b>
        {choices.length && !open ? <Btn kind="secondary" size="sm" onClick={() => { setOpen(true); setPeriod(keyOf(choices[0])); }}>Submit payment evidence</Btn> : null}
      </div>
      <div className="sub2 mt-1">
        Paid a semester your history shows as unpaid? Give the Bursary your receipt, bank teller or old-portal receipt. It is checked against the payments on
        record; until it is verified and the payment is put right, the semester still shows what is owed.
      </div>
      {open && chosen ? (
        <div className="card mt-2"><div className="card__body">
          <Field id="hpe-period" label="Semester the payment was for" required>
            <select id="hpe-period" className="ctl" value={keyOf(chosen)} onChange={(e) => setPeriod(e.target.value)}>
              {choices.map((p) => <option key={keyOf(p)} value={keyOf(p)}>{p.session} — {semesterWords(p.semester)}{p.outstanding != null ? ` — ${naira(p.outstanding)} outstanding` : ""}</option>)}
            </select>
          </Field>
          <EvidenceFields id="hpe" f={f} set={setF} today={today} />
          <Field id="hpe-files" label="Your evidence" hint="PDF, JPEG or PNG, up to 5 MB each">
            <input id="hpe-files" type="file" multiple className="ctl" accept="application/pdf,image/jpeg,image/png" onChange={(e) => setFiles(Array.from(e.target.files ?? []))} />
          </Field>
          {f.amount || f.reference ? (fp ? <div className="sub2 ink-red">{fp}</div> : null) : null}
          <div className="row mt-2">
            <Btn kind="ghost" disabled={busy !== null} onClick={() => setOpen(false)}>Cancel</Btn>
            <Btn kind="primary" disabled={!!fp || busy !== null} busy={busy === "hpe" || (busy?.startsWith("file-") ?? false)} busyLabel="Sending…" onClick={() => void submit()}>Send to the Bursary</Btn>
          </div>
        </div></div>
      ) : null}
      {evidence.map((e) => {
        const [word, tone] = EVIDENCE_WORDS[e.state] ?? [e.state, "grey"];
        const live = e.state === "SUBMITTED" || e.state === "MORE_INFORMATION_REQUIRED";
        return (
          <div key={e.id} className="card mt-2"><div className="card__body">
            <div className="row" style={{ flexWrap: "wrap", gap: 8, alignItems: "center" }}>
              <b className="tnum">{e.reference}</b>
              <span className="sub2">{e.session} · {semesterWords(e.semester)} · {naira(e.amount)} · {CHANNEL_WORDS[e.channel] ?? e.channel} · No. <span className="tnum">{e.payment_reference}</span></span>
              <span className="grow" />
              <Pil kind={tone}>{word}</Pil>
            </div>
            <div className="sub2 mt-1">Sent {onDay(e.submitted_at)}{e.paid_on ? ` · paid ${onDay(e.paid_on)}` : ""}
              {e.files?.length ? <> · {e.files.map((x, i) => <span key={x.id}>{i ? ", " : " "}<a className="lnk" href={`/api/bff/api/v1/me/historical-evidence/${e.id}/files/${x.id}`} target="_blank" rel="noopener">{x.filename}</a></span>)}</> : " · no file yet"}</div>
            {e.decision_note && e.state !== "SUBMITTED" ? (
              <Note kind={e.state === "VERIFIED" ? "ok" : e.state === "WITHDRAWN" ? "info" : "bad"} title={e.state === "MORE_INFORMATION_REQUIRED" ? "The Bursary needs more" : e.state === "VERIFIED" ? "Verified" : "The Bursary's reason"}>
                {e.decision_note}{e.state === "VERIFIED" ? " The semester shows what it owes once the payment is put right on the record." : ""}
              </Note>
            ) : null}
            {again === e.id ? (
              <div className="mt-2">
                <EvidenceFields id={`hpe-${e.id}`} f={g} set={setG} today={today} />
                <Field id={`hpe-more-${e.id}`} label="Add files" hint="PDF, JPEG or PNG, up to 5 MB each">
                  <input id={`hpe-more-${e.id}`} type="file" multiple className="ctl" accept="application/pdf,image/jpeg,image/png" onChange={(ev) => setMoreFiles(Array.from(ev.target.files ?? []))} />
                </Field>
                {gp ? <div className="sub2 ink-red">{gp}</div> : null}
                <div className="row mt-2">
                  <Btn kind="ghost" disabled={busy !== null} onClick={() => setAgain(null)}>Cancel</Btn>
                  <Btn kind="primary" disabled={!!gp || busy !== null} busy={busy === `again-${e.id}` || busy === `file-${e.id}`} busyLabel="Sending…" onClick={() => void sendAgain(e)}>Send again</Btn>
                </div>
              </div>
            ) : live ? (
              <div className="row mt-2" style={{ flexWrap: "wrap", gap: 8 }}>
                {e.state === "MORE_INFORMATION_REQUIRED" ? (
                  <Btn kind="primary" size="sm" disabled={busy !== null} onClick={() => {
                    setAgain(e.id);
                    setG({ amount: String(Number(e.amount)), paidOn: e.paid_on ?? "", channel: e.channel, reference: e.payment_reference, note: e.note ?? "" });
                    setMoreFiles([]);
                  }}>Add information and send again</Btn>
                ) : (
                  <label className="btn btn--ghost btn--sm" style={{ cursor: "pointer" }}>
                    {busy === `file-${e.id}` ? "Adding…" : "Add a file"}
                    <input type="file" className="sr-only" accept="application/pdf,image/jpeg,image/png" disabled={busy !== null}
                      onChange={async (ev) => { const file = ev.target.files?.[0]; ev.target.value = ""; if (file && (await upload(e.id, [file]))) notify("File added"); }} />
                  </label>
                )}
                <Btn kind="ghost" size="sm" disabled={busy !== null} busy={busy === `wd-${e.id}`} busyLabel="Withdrawing…"
                  onClick={() => void act(`wd-${e.id}`, "POST", `/me/historical-evidence/${e.id}/withdraw`, { reason: "Withdrawn by the student" }, `Payment evidence ${e.reference} withdrawn by the student`, "Withdrawn")}>Withdraw</Btn>
              </div>
            ) : null}
          </div></div>
        );
      })}
      {problem ? <ProblemNotice problem={problem} /> : null}
    </div>
  );
}
