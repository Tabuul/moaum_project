"use client";

/** the office's side of Help & requests: answer on the record; the student is told (V036). */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
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
  const [now] = useState(() => Date.now());
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
          <DTable cols={["Reference", "Student", "Subject", "Raised", "State", "|num"]} rows={requests.map((r) => [
            <span className="tnum" key="r">{r.ref}</span>,
            <Two key="s" a={r.student ?? ""} b={r.number ?? ""} />,
            <Two key="j" a={r.subject} b={r.answer ? `Answered: ${r.answer}` : r.detail ?? ""} />,
            <span className="sub2 tnum" key="d">{day(r.raised_at)}</span>,
            r.state === "RESOLVED" || r.state === "CLOSED" ? <Pil kind="ok" key="p">Resolved</Pil> : r.state === "WITH_OFFICE" ? <Pil kind="info" key="p">Answered</Pil> : <Pil kind="bad" key="p">Open</Pil>,
            r.state === "RESOLVED" || r.state === "CLOSED" ? <span className="sub2" key="a">{r.answered_by_name ?? ""}</span> : <Btn key="a" kind="primary" onClick={() => { setOpen(r); setAnswer(r.answer ?? ""); setResolved(true); }}>Answer</Btn>,
          ])} texts={requests.map((r) => `${r.ref} ${r.student} ${r.number} ${r.subject}`)} />
        ) : <PBody><div className="sub2">No request has been put to this office.</div></PBody>}
      </Panel>
      {open ? (
        <Modal title={`${open.ref} — ${open.subject}`} sub={`${open.student} · ${open.number} · raised ${day(open.raised_at)}`} onClose={() => setOpen(null)}
          foot={<><Btn kind="ghost" onClick={() => setOpen(null)}>Cancel</Btn><span style={{ flexGrow: 1 }} /><Btn kind="go" disabled={busy || !answer.trim()} onClick={() => void send()}>{resolved ? "Answer and resolve" : "Answer, keep open"}</Btn></>}>
          {open.detail ? <p style={{ margin: "0 0 10px", lineHeight: 1.6 }}>{open.detail}</p> : null}
          <Field id="an-text" label="Your answer" hint="Sent to the student by email and SMS, and shown against the reference."><textarea id="an-text" className="ctl" rows={5} value={answer} onChange={(e) => setAnswer(e.target.value)} /></Field>
          <label style={{ display: "flex", gap: 9, alignItems: "flex-start", fontSize: 13.5, color: "var(--muted)" }}><input type="checkbox" className="chk" checked={resolved} onChange={(e) => setResolved(e.target.checked)} /><span>This resolves the request.</span></label>
        </Modal>
      ) : null}
    </>
  );
}
