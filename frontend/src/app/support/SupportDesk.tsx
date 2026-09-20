"use client";

/** the office's side of Help & requests: answer on the record; the student is told (V036). */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import type { ServiceRequest } from "@/app/student/support/Support";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, day } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export function SupportDesk({ requests }: { requests: ServiceRequest[] }) {
  const router = useRouter();
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [open, setOpen] = useState<ServiceRequest | null>(null);
  const [answer, setAnswer] = useState("");
  const [resolved, setResolved] = useState(true);
  const [docs, setDocs] = useState<{ id: string; filename: string; content_type: string; bytes: number }[]>([]);
  const [now] = useState(() => Date.now());

  async function openRequest(r: ServiceRequest) {
    setOpen(r);
    setAnswer(r.answer ?? "");
    setResolved(true);
    setDocs([]);
    if (r.documents) {
      try {
        const res = await fetch(`/api/bff/api/v1/support/requests/${r.id}/documents`, { cache: "no-store" });
        if (res.ok) setDocs(await res.json());
      } catch { /* the file list could not be read; the answer still works */ }
    }
  }

  function human(bytes: number): string {
    return bytes < 1024 ? `${bytes} B` : bytes < 1048576 ? `${Math.round(bytes / 1024)} KB` : `${(bytes / 1048576).toFixed(1)} MB`;
  }
  const openOnes = requests.filter((r) => r.state === "OPEN" || r.state === "WITH_OFFICE");
  const oldest = openOnes.length ? Math.max(0, Math.round((now - new Date(openOnes[0].raised_at).getTime()) / 864e5)) : 0;

  async function send() {
    if (!open) return;
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/support/requests/${open.id}/answer`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Request ${open.ref} answered`) }, body: JSON.stringify({ answer, resolved }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return; }
      setOpen(null);
      setAnswer("");
      notify(`Request ${open.ref} answered`);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Tiles items={[
        ["Open", String(openOnes.length), openOnes.length ? "var(--red-ink)" : null, openOnes.length ? `Oldest ${oldest} day${oldest === 1 ? "" : "s"}` : "Nothing waiting"],
        ["Answered, still open", String(requests.filter((r) => r.state === "WITH_OFFICE").length), null, "The student may write back"],
        ["Resolved", String(requests.filter((r) => r.state === "RESOLVED" || r.state === "CLOSED").length), "var(--green-ink)", "On the record"],
        ["All", String(requests.length), null, "Newest 300"],
      ]} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Note kind="info" title="A request that sits unanswered is the failure this queue exists to prevent">The oldest open request is at the top. An answer is recorded in your name, the student is told by email and SMS, and the request is resolved or left open for a reply.</Note>
      <Panel title="Requests to this office" right={`${requests.length}`}>
        {requests.length ? (
          <DTable cols={["Reference", "Student", "Subject", "Raised", "Documents|mid", "State", "|num"]} rows={requests.map((r) => [
            <span className="tnum" key="r">{r.ref}</span>,
            <Two key="s" a={r.student ?? ""} b={r.number ?? ""} />,
            <Two key="j" a={r.subject} b={r.answer ? `Answered: ${r.answer}` : r.detail ?? ""} />,
            <span className="sub2 tnum" key="d">{day(r.raised_at)}</span>,
            r.documents ? <Pil kind="info" key="dc">{r.documents} attached</Pil> : <span className="sub2" key="dc">—</span>,
            r.state === "RESOLVED" || r.state === "CLOSED" ? <Pil kind="ok" key="p">Resolved</Pil> : r.state === "WITH_OFFICE" ? <Pil kind="info" key="p">Answered</Pil> : <Pil kind="bad" key="p">Open</Pil>,
            r.state === "RESOLVED" || r.state === "CLOSED" ? <Btn key="a" kind="ghost" onClick={() => void openRequest(r)}>Open</Btn> : <Btn key="a" kind="primary" onClick={() => void openRequest(r)}>Answer</Btn>,
          ])} texts={requests.map((r) => `${r.ref} ${r.student} ${r.number} ${r.subject}`)} />
        ) : <PBody><div className="sub2">No request has been put to this office.</div></PBody>}
      </Panel>
      {open ? (
        (() => { const done = open.state === "RESOLVED" || open.state === "CLOSED"; return (
        <Modal title={`${open.ref} — ${open.subject}`} sub={`${open.student} · ${open.number} · raised ${day(open.raised_at)}`} onClose={() => setOpen(null)}
          foot={done
            ? <><span style={{ flexGrow: 1 }} /><Btn kind="ghost" onClick={() => setOpen(null)}>Close</Btn></>
            : <><Btn kind="ghost" onClick={() => setOpen(null)}>Cancel</Btn><span style={{ flexGrow: 1 }} /><Btn kind="go" disabled={busy || !answer.trim()} onClick={() => void send()}>{resolved ? "Answer and resolve" : "Answer, keep open"}</Btn></>}>
          {open.detail ? <p style={{ margin: "0 0 10px", lineHeight: 1.6 }}>{open.detail}</p> : null}
          {open.documents ? (
            <div style={{ margin: "0 0 12px" }}>
              <div style={{ fontWeight: 600, fontSize: 13, marginBottom: 4 }}>Supporting documents</div>
              {docs.length ? (
                <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
                  {docs.map((d) => <a key={d.id} href={`/api/bff/api/v1/support/requests/${open.id}/documents/${d.id}/content`} target="_blank" rel="noreferrer" className="sub2">📎 {d.filename} <span className="tnum">({human(d.bytes)})</span></a>)}
                </div>
              ) : <div className="sub2">Loading {open.documents} attached file{open.documents === 1 ? "" : "s"}…</div>}
            </div>
          ) : null}
          {done ? (
            open.answer ? <Note kind="ok" title="Answered">{open.answer}</Note> : null
          ) : (
            <>
              <Field id="an-text" label="Your answer" hint="Sent to the student by email and SMS, and shown against the reference."><textarea id="an-text" className="ctl" rows={5} value={answer} onChange={(e) => setAnswer(e.target.value)} /></Field>
              <label style={{ display: "flex", gap: 9, alignItems: "flex-start", fontSize: 13.5, color: "var(--muted)" }}><input type="checkbox" className="chk" checked={resolved} onChange={(e) => setResolved(e.target.checked)} /><span>This resolves the request.</span></label>
            </>
          )}
        </Modal>
      ); })()
      ) : null}
    </>
  );
}
