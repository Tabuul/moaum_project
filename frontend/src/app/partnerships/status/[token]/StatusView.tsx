"use client";
/** V658: the applicant's own view of their enquiry — its status in words, the University's request and messages, their answers and
 *  documents, the steps it has been through; never an internal note, a reviewer's comment or an officer's name */
import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { Btn, Note, Pil } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { bytes, dateWords, fileProblem } from "@/lib/partnerships";

interface View {
  reference: string; title: string; org_name: string; status_words: string; received_at: string; email: string; category: string | null; closed: boolean;
  timeline: { at: string; action: string; to_words: string | null }[];
  messages: { kind: string; body: string; at: string }[];
  request: { question: string; documents: string | null; deadline: string } | null;
  attachments: { id: string; kind: string; filename: string; size_bytes: number; added_at: string }[];
  maxFileMb: number;
}
const API = "/api/bff/api/v1/public/partnerships";

/** the enquiry as its status page reads it, or what to tell the applicant */
async function readStatus(token: string): Promise<{ view: View } | { problem: string }> {
  try {
    const r = await fetch(`${API}/status/${encodeURIComponent(token)}`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (!r.ok) {
      return { problem: j?.code === "PTN_NOT_FOUND" ? "This link does not open an enquiry. It may have been replaced by a newer link; ask for a new one on the collaboration page."
        : j?.code === "PTN_DRAFT" ? "This enquiry has not been submitted yet; continue it on the collaboration form." : (j?.detail || j?.title || "The enquiry could not be opened.") };
    }
    return { view: j as View };
  } catch { return { problem: "The University's portal could not be reached; try again." }; }
}
const STEP_WORDS: Record<string, string> = {
  SUBMITTED: "Received", ACCEPT: "Accepted for review", REQUEST_INFORMATION: "Information requested from you", INFORMATION_RECEIVED: "Your answer received",
  MESSAGE_SENT: "A message from the University", DOCUMENT_ADDED: "A document added", MEETING: "Meeting proposed", APPROVE: "Approved for development",
  DECLINE: "Not taken forward", AGREEMENT_CREATED: "Agreement being prepared", AGREEMENT_EXECUTED: "Agreement executed", IMPLEMENT: "Implementation started",
  ACTIVATE: "Partnership active", CLOSE: "Closed", CANCEL: "Withdrawn",
};

function readDataUrl(file: File): Promise<string> {
  return new Promise((resolve, reject) => { const r = new FileReader(); r.onload = () => resolve(String(r.result)); r.onerror = () => reject(r.error); r.readAsDataURL(file); });
}

export function StatusView({ token }: { token: string }) {
  const [v, setV] = useState<View | null>(null);
  const [problem, setProblem] = useState<string | null>(null);
  const [answer, setAnswer] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [note, setNote] = useState<{ kind: "ok" | "bad"; text: string } | null>(null);

  const apply = useCallback((x: { view: View } | { problem: string }) => { if ("view" in x) setV(x.view); else setProblem(x.problem); }, []);
  const load = useCallback(async () => apply(await readStatus(token)), [token, apply]);
  useEffect(() => {
    let alive = true;
    void readStatus(token).then((x) => { if (alive) apply(x); });
    return () => { alive = false; };
  }, [token, apply]);

  async function reply() {
    if (answer.trim().length < 2) { setNote({ kind: "bad", text: "Your answer: write your answer to the request." }); return; }
    setBusy("reply"); setNote(null);
    try {
      const r = await fetch(`${API}/status/${encodeURIComponent(token)}/reply`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ answer: answer.trim() }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setNote({ kind: "bad", text: j?.detail || j?.title || "The answer did not go through; try again." }); return; }
      setAnswer(""); setNote({ kind: "ok", text: "Your answer has been sent." });
      await load();
    } finally { setBusy(null); }
  }
  async function upload(list: File[]) {
    if (!list.length) return;
    setBusy("upload"); setNote(null);
    try {
      for (const f of list) {
        const bad = fileProblem(f.name, f.size, v?.maxFileMb ?? 5);
        if (bad) { setNote({ kind: "bad", text: `Document: ${bad}` }); continue; }
        const r = await fetch(`${API}/status/${encodeURIComponent(token)}/attachments`, { method: "POST", headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ kind: "REQUESTED_DOCUMENT", filename: f.name, dataUrl: await readDataUrl(f) }) });
        const j = await r.json().catch(() => null);
        if (!r.ok) { setNote({ kind: "bad", text: j?.detail || j?.title || "The document did not go through." }); continue; }
        setNote({ kind: "ok", text: `${f.name} added.` });
      }
      await load();
    } finally { setBusy(null); }
  }

  if (problem) return <><h1 className="ptn-h1">Your collaboration enquiry</h1><Note kind="bad" title={problem} /><p><Link href="/partnerships/collaboration">The collaboration page</Link></p></>;
  if (!v) return <p aria-live="polite">Opening your enquiry…</p>;
  return (
    <>
      <h1 className="ptn-h1">Your collaboration enquiry</h1>
      <dl className="ptn-dl">
        <div className="ptn-dlrow"><dt>Reference</dt><dd className="tnum b700">{v.reference}</dd></div>
        <div className="ptn-dlrow"><dt>Title</dt><dd>{v.title}</dd></div>
        <div className="ptn-dlrow"><dt>Organisation</dt><dd>{v.org_name}</dd></div>
        <div className="ptn-dlrow"><dt>Category</dt><dd>{v.category ?? "—"}</dd></div>
        <div className="ptn-dlrow"><dt>Received</dt><dd>{dateWords(v.received_at, true)}</dd></div>
        <div className="ptn-dlrow"><dt>Status</dt><dd><Pil kind={v.closed ? "grey" : v.request ? "warn" : "info"}>{v.status_words}</Pil></dd></div>
      </dl>
      {note ? <Note kind={note.kind} title={note.text} /> : null}

      {v.request ? (
        <section aria-labelledby="st-req">
          <h2 className="ptn-h2" id="st-req">The University asks</h2>
          <p className="ptn-text">{v.request.question}</p>
          {v.request.documents ? <p><strong>Documents requested:</strong> {v.request.documents}</p> : null}
          <p><strong>Please respond by:</strong> {dateWords(v.request.deadline)}</p>
          <Field id="st-answer" label="Your answer" required>
            <textarea id="st-answer" className="ctl" rows={4} maxLength={8000} value={answer} onChange={(e) => setAnswer(e.target.value)} />
          </Field>
          <div className="row" style={{ gap: 8, flexWrap: "wrap" }}>
            <Btn kind="primary" onClick={() => void reply()} busy={busy === "reply"} busyLabel="Sending…">Send answer</Btn>
          </div>
        </section>
      ) : null}

      {!v.closed ? (
        <section aria-labelledby="st-docs">
          <h2 className="ptn-h2" id="st-docs">Add a document</h2>
          <Field id="st-file" label="Choose a file" hint="PDF, DOCX, XLSX or PPTX.">
            <input id="st-file" type="file" className="ctl" accept=".pdf,.docx,.xlsx,.pptx" disabled={busy === "upload"} onChange={(e) => { const picked = Array.from(e.target.files ?? []); e.target.value = ""; void upload(picked); }} />
          </Field>
          {busy === "upload" ? <p className="sub2" aria-live="polite">Uploading…</p> : null}
        </section>
      ) : null}

      {v.attachments.length ? (
        <section aria-labelledby="st-files">
          <h2 className="ptn-h2" id="st-files">Your documents</h2>
          <ul className="ptn-files">{v.attachments.map((f) => <li key={f.id}>{f.filename} <span className="sub2">{bytes(f.size_bytes)} · {dateWords(f.added_at)}</span></li>)}</ul>
        </section>
      ) : null}

      {v.messages.length ? (
        <section aria-labelledby="st-msgs">
          <h2 className="ptn-h2" id="st-msgs">Messages</h2>
          {v.messages.map((m, i) => (
            <div key={i} className="ptn-msg"><div className="sub2">{m.kind === "APPLICANT_REPLY" ? "You" : "The University"} · {dateWords(m.at, true)}</div><div className="ptn-text">{m.body}</div></div>
          ))}
        </section>
      ) : null}

      <section aria-labelledby="st-steps">
        <h2 className="ptn-h2" id="st-steps">Steps so far</h2>
        <ol className="ptn-timeline">{v.timeline.map((t, i) => <li key={i}><span className="sub2">{dateWords(t.at, true)}</span> — {STEP_WORDS[t.action] ?? t.to_words ?? "Updated"}</li>)}</ol>
      </section>
      <p className="sub2">Keep this link to yourself. <Link href="/privacy-policy">Privacy policy</Link> · <Link href="/partnerships/collaboration">Collaboration page</Link></p>
    </>
  );
}
