"use client";

/** sSupport — proto/part8.html: your requests, and a new one to an office (V036). */
import { useState } from "react";
import { Btn, Note, Panel, PBody, Pil, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { onDay, useAct } from "../common";

export interface ServiceRequest { id: string; ref: string; office_code: string; office: string; subject: string; detail: string | null; raised_at: string; state: string; answer: string | null; answered_at: string | null; student?: string; number?: string; answered_by_name?: string | null }

const OFFICES: [string, string][] = [["registrar", "Registry"], ["bursar", "Bursary"], ["ict", "ICT"], ["library", "Library"], ["services", "Student Services"], ["academic", "Academic Office"], ["hod", "My department"], ["housing", "Housing"]];

export function Support({ requests }: { requests: ServiceRequest[] }) {
  const { act, busy, problem } = useAct();
  const [office, setOffice] = useState("registrar");
  const [subject, setSubject] = useState("");
  const [detail, setDetail] = useState("");
  const [said, setSaid] = useState<string | null>(null);
  return (
    <>
      <Panel title="Your requests" right={requests.length ? `${requests.filter((r) => r.state === "OPEN" || r.state === "WITH_OFFICE").length} open` : "none yet"}>
        {requests.length ? (
          <DTable cols={["Reference", "Subject", "Office", "Raised", "Status|num"]} rows={requests.map((r) => [
            <span className="tnum" key="r">{r.ref}</span>,
            <Two key="s" a={r.subject} b={r.answer ? `Answer: ${r.answer}` : r.detail ?? ""} />,
            <span key="o">{r.office}</span>,
            <span className="sub2 tnum" key="d">{onDay(r.raised_at)}</span>,
            r.state === "RESOLVED" || r.state === "CLOSED" ? <Pil kind="ok" key="p">Resolved</Pil> : r.state === "WITH_OFFICE" ? <Pil kind="info" key="p">Answered — still open</Pil> : <Pil kind="info" key="p">With {r.office}</Pil>,
          ])} />
        ) : <PBody><div className="sub2">Nothing raised yet.</div></PBody>}
      </Panel>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title={said}>You will be notified here and by SMS when it is answered.</Note> : null}
      <Panel title="Raise a new request">
        <PBody>
          <div className="field"><label>Which office?</label>
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
              {OFFICES.map(([c, l]) => <button type="button" key={c} className={`pill ${office === c ? "pill--info" : ""}`} style={office === c ? { cursor: "pointer" } : { background: "var(--bg)", border: "1px solid var(--line)", color: "var(--muted)", cursor: "pointer" }} onClick={() => setOffice(c)}>{l}</button>)}
            </div></div>
          <Field id="hl-problem" label="What is the problem?"><input id="hl-problem" className="ctl" value={subject} onChange={(e) => setSubject(e.target.value)} placeholder="Describe it in one line" autoComplete="off" /></Field>
          <Field id="hl-detail" label="Anything more the office should know" hint="A reference, a date, an amount."><textarea id="hl-detail" className="ctl" rows={3} value={detail} onChange={(e) => setDetail(e.target.value)} /></Field>
          <div><Btn kind="primary" disabled={busy !== null || !subject.trim()} onClick={async () => { const r = await act("raise", "POST", "/me/requests", { office, subject, detail: detail || null }, `Request to ${office}: ${subject}`); if (r) { setSaid(`Request ${r.ref} is with ${OFFICES.find((o) => o[0] === office)?.[1]}`); setSubject(""); setDetail(""); } }}>Submit request</Btn></div>
          <div className="sub2">Each office answers on the record; the answer appears against the reference above.</div>
        </PBody>
      </Panel>
    </>
  );
}
