"use client";
/** V375: moderating a bank by sample. The moderator chooses how many of the questions waiting (those they did not set) to read; the
 *  server draws them at random and keeps the rest as they stood. Every sampled question approved — the rest are approved with them,
 *  each decision naming the sample; one returned — the sample fails and the rest are moderated one by one. A question changed since
 *  the draw is left as it is. The rules and the draw are the server's. */
import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { cbtSend } from "./CbtExam";
import { MathText } from "@/components/proto/MathText";

interface SampleQuestion { id: string; topic: string | null; stem: string; options: string[]; answers: number[]; kind: string; marks: number; explanation: string | null; version: number; drawn_version: number;
  moderation: "PENDING" | "APPROVED" | "RETURNED"; moderated_version: number | null; moderation_note: string | null; set_by: string | null }
interface Sample { id: string; bank: string; state: "OPEN" | "APPROVED" | "FAILED" | "WITHDRAWN"; drawn_at: string; decided_at: string | null; approved: number | null; left_as_they_were: number | null; population: number; size: number; questions: SampleQuestion[] }
interface Recent { id: string; state: string; drawn_at: string; size: number; population: number; approved: number | null; left_as_they_were: number | null }
interface Data { waitingForMe: number; waitingMine?: number; returned?: number; approved?: number; open: Sample | null; recent: Recent[] }

const STATE_WORD: Record<string, string> = { APPROVED: "approved the rest", FAILED: "failed — a sampled question was returned", WITHDRAWN: "withdrawn" };

export function ModerationSample({ course }: { course: string }) {
  const router = useRouter();
  const [d, setD] = useState<Data | null>(null);
  const [size, setSize] = useState("");
  const [busy, setBusy] = useState(false);
  const [returning, setReturning] = useState<SampleQuestion | null>(null);
  const [note, setNote] = useState("");
  const [last, setLast] = useState<Sample | null>(null);

  const load = useCallback(async () => {
    const r = await fetch(`/api/bff/api/v1/cbt/questions/samples?course=${encodeURIComponent(course)}`);
    if (r.ok) setD((await r.json()) as Data);
  }, [course]);
  useEffect(() => { const t = window.setTimeout(() => void load(), 0); return () => window.clearTimeout(t); }, [load]);

  async function run(path: string, body: unknown, reason: string) {
    setBusy(true);
    try {
      const j = await cbtSend(path, "POST", body, reason);
      if (j) { await load(); router.refresh(); }
      return j;
    } finally { setBusy(false); }
  }
  async function draw() {
    const j = await run("/questions/samples", { course, size: Number(size) }, `A sample of ${size} drawn from ${course}`);
    if (j) setSize("");
  }
  async function close(s: Sample) {
    const j = await run(`/questions/samples/${s.id}/close`, {}, `The sample of ${course} decided`);
    if (j) setLast(j as unknown as Sample);
  }

  if (!d) return null;
  const s = d.open;
  const decided = s ? s.questions.filter((q) => (q.moderation === "APPROVED" && q.moderated_version === q.drawn_version) || (q.moderation === "RETURNED" && q.version === q.drawn_version)).length : 0;
  const returned = s ? s.questions.filter((q) => q.moderation === "RETURNED").length : 0;

  return (
    <Panel title="Moderate by sample" right={<span className="sub2">{d.waitingForMe} waiting for you in {course}</span>}>
      <PBody>
        {last && last.state !== "OPEN" ? (
          <Note kind={last.state === "APPROVED" ? "ok" : "info"} title={`The sample ${STATE_WORD[last.state] ?? last.state}`}>
            {last.state === "APPROVED" ? <>{last.approved} more approved with it{last.left_as_they_were ? `; ${last.left_as_they_were} left as they were (changed or decided since the draw, or yours)` : ""}.</> : <>The other {last.left_as_they_were} questions wait to be moderated one by one.</>}
          </Note>
        ) : null}
        {!s && !Number(d.waitingForMe) ? (
          <Note kind="info" title="Nothing here waits for you to moderate">
            {Number(d.waitingMine) ? <>{d.waitingMine} question{Number(d.waitingMine) === 1 ? " waiting was" : "s waiting were"} set (written or imported) by you, and a question is approved by someone other than the person who set it — another member of the office, the Head of Department, an Examinations Officer, the Dean or the Super Administrator signs in and approves {Number(d.waitingMine) === 1 ? "it" : "them"}. </> : null}
            {Number(d.approved) ? <>{d.approved} question{Number(d.approved) === 1 ? " is" : "s are"} approved already (those in the bank before moderation began count as approved). </> : null}
            {Number(d.returned) ? <>{d.returned} {Number(d.returned) === 1 ? "was" : "were"} returned and wait{Number(d.returned) === 1 ? "s" : ""} for the setter to correct. </> : null}
            A sample is drawn from the questions waiting that you did not set.
          </Note>
        ) : !s ? (
          <>
            <div className="sub2 mb-2">Read a random sample of the questions waiting that you did not set. When every question in the sample is approved, the rest are approved with it, each decision naming the sample; if you return one, the sample fails and the rest wait to be moderated one by one. You choose how many to read.</div>
            <div className="row row--inline row--tight" style={{ flexWrap: "wrap", alignItems: "flex-end" }}>
              <Field id="smp-size" label="Questions to read" hint={`1 to ${d.waitingForMe}`}><input id="smp-size" className="ctl tnum" inputMode="numeric" style={{ maxWidth: 120 }} value={size} onChange={(e) => setSize(e.target.value.replace(/[^0-9]/g, ""))} /></Field>
              <Btn kind="primary" disabled={busy || !d.waitingForMe || !Number(size) || Number(size) > d.waitingForMe} onClick={() => void draw()}>Draw the sample</Btn>
            </div>
            {Number(size) > Number(d.waitingForMe) ? <div className="sub2 mt-1">Only {d.waitingForMe} question{Number(d.waitingForMe) === 1 ? " waits" : "s wait"} for you here; a sample is at most that many.</div> : null}
          </>
        ) : (
          <>
            <div className="row row--inline row--tight mb-2" style={{ flexWrap: "wrap" }}>
              <span>A sample of <b>{s.size}</b> from <b>{s.population}</b> waiting · <b>{decided}</b> decided{returned ? <> · <b>{returned}</b> returned</> : null}</span>
              <Btn kind="primary" size="sm" disabled={busy || decided < s.size} onClick={() => void close(s)}>{returned ? "Close the sample (it fails)" : `Approve the other ${s.population - s.size}`}</Btn>
              <Btn kind="ghost" size="sm" disabled={busy} onClick={() => { if (window.confirm("Withdraw the sample? Nothing is approved by it; the questions you decided keep your decisions.")) void run(`/questions/samples/${s.id}/withdraw`, {}, `The sample of ${course} withdrawn`); }}>Withdraw</Btn>
            </div>
            <div style={{ display: "grid", gap: 10 }}>
              {s.questions.map((q, i) => (
                <div key={q.id} style={{ border: "1px solid var(--line, #d0d5dd)", borderRadius: 8, padding: "8px 10px" }}>
                  <div className="row row--inline row--tight" style={{ justifyContent: "space-between", flexWrap: "wrap" }}>
                    <b>{i + 1}. <MathText text={q.stem} /></b>
                    {q.moderation === "APPROVED" ? <Pil kind="ok">Approved</Pil> : q.moderation === "RETURNED" ? <Pil kind="bad">Returned</Pil> : <Pil kind="warn">Awaiting</Pil>}
                  </div>
                  <ol type="A" style={{ margin: "4px 0 4px 18px" }}>{q.options.map((o, k) => <li key={k}><MathText text={o} />{q.answers.includes(k) ? <b> — key</b> : null}</li>)}</ol>
                  <div className="sub2">{q.marks} mark{q.marks === 1 ? "" : "s"}{q.topic ? ` · ${q.topic}` : ""}{q.set_by ? ` · set by ${q.set_by}` : ""}{q.version !== q.drawn_version ? " · changed since the draw: moderated on its own" : ""}{q.explanation ? ` · ${q.explanation}` : ""}</div>
                  {q.moderation === "PENDING" && q.version === q.drawn_version ? (
                    <div className="row row--inline row--tight mt-1">
                      <Btn kind="secondary" size="sm" disabled={busy} onClick={() => void run(`/questions/${q.id}/moderation`, { decision: "APPROVE" }, `A sampled question in ${course} approved`)}>Approve</Btn>
                      <Btn kind="ghost" size="sm" disabled={busy} onClick={() => { setReturning(q); setNote(""); }}>Return</Btn>
                    </div>
                  ) : q.moderation === "RETURNED" ? <div className="sub2 mt-1">&ldquo;{q.moderation_note}&rdquo;</div> : null}
                </div>
              ))}
            </div>
          </>
        )}
        {d.recent.length ? <div className="sub2 mt-2">Your earlier samples here: {d.recent.map((r) => `${new Date(r.drawn_at).toLocaleDateString("en-GB")} — ${r.size} of ${r.population}, ${STATE_WORD[r.state] ?? r.state.toLowerCase()}${r.state === "APPROVED" ? ` (${r.approved} more)` : ""}`).join("; ")}.</div> : null}
      </PBody>
      {returning ? (
        <Modal title="Return the question" sub={course} onClose={() => setReturning(null)}
          foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setReturning(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || !note.trim()} onClick={async () => { const j = await run(`/questions/${returning.id}/moderation`, { decision: "RETURN", note: note.trim() }, `A sampled question in ${course} returned: ${note.trim()}`); if (j) setReturning(null); }}>Return with this note</Btn></span>}>
          <p><MathText text={returning.stem} /></p>
          <Field id="smp-note" label="What should change" required><textarea id="smp-note" className="ctl" rows={3} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
          <div className="sub2">Returning a sampled question fails the sample: the rest are moderated one by one.</div>
        </Modal>
      ) : null}
    </Panel>
  );
}
