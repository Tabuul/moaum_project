"use client";

/** tGovernance — the Nigeria Data Protection Act register: what personal data the University
 *  processes, on what basis, for how long, and whether a DPIA is done; and the log of
 *  data-subject rights requests, each with its statutory due date. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, Note, Panel, PBody, Pil, RoleLine, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, day } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface Activity { id: string; activity: string; lawful_basis: string; sensitive: boolean; retention: string; dpia_state: string; note: string | null }
export interface DsrRow { id: string; reference: string; kind: string; requester: string; received_on: string; due_on: string; state: string; note: string | null }

const DPIA: Record<string, ["ok" | "info" | "bad" | "grey", string]> = { NOT_REQUIRED: ["grey", "Not required"], OUTSTANDING: ["bad", "Outstanding"], COMPLETE: ["ok", "Complete"] };
const DSTATE: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = { RECEIVED: ["warn", "Received"], IN_PROGRESS: ["info", "In progress"], COMPLETED: ["ok", "Completed"], REFUSED: ["grey", "Refused"] };

export function Governance({ register, dsr, actingOffice }: { register: Activity[]; dsr: DsrRow[]; actingOffice: string | null }) {
  const router = useRouter();
  const may = ["registrar", "dregistrar", "ict", "super"].includes(actingOffice ?? "");
  const [f, setF] = useState({ kind: "ACCESS", requester: "", dueOn: "", note: "" });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  const outstanding = register.filter((a) => a.dpia_state === "OUTSTANDING").length;
  const openDsr = dsr.filter((d) => ["RECEIVED", "IN_PROGRESS"].includes(d.state)).length;
  const today = new Date().toISOString().slice(0, 10);
  const overdue = dsr.filter((d) => ["RECEIVED", "IN_PROGRESS"].includes(d.state) && d.due_on < today).length;

  async function send(path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/governance${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j ?? { status: r.status, title: r.statusText }); return null; }
      router.refresh();
      return j as Record<string, unknown>;
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <RoleLine allowed={["registrar", "dregistrar"]} actingOffice={actingOffice} canAct={may}
        action="Keeping the processing register and DPIAs" />
      <Note kind={outstanding ? "bad" : "info"} title={outstanding ? `${outstanding} data-protection impact assessment${outstanding === 1 ? "" : "s"} outstanding` : "The processing register is the University's own record"}>
        The Nigeria Data Protection Act requires a record of processing activities and a data-protection impact assessment for high-risk processing. The register below is the University&rsquo;s own; the DPO keeps it current. Figures shown are counts from the register and the request log — nothing is inferred.
      </Note>
      {said ? <Note kind="ok" title={said}>On the record, in your name.</Note> : null}
      {err ? <ProblemNotice problem={err} /> : null}

      <Tiles items={[
        ["Processing activities", String(register.length), null, "On the register"],
        ["DPIAs outstanding", String(outstanding), outstanding ? "var(--red-ink)" : null, `${register.filter((a) => a.dpia_state === "COMPLETE").length} complete`],
        ["Open subject requests", String(openDsr), openDsr ? "var(--chrome)" : null, "Access, erasure, etc."],
        ["Overdue requests", String(overdue), overdue ? "var(--red-ink)" : null, "Past the statutory date"],
      ]} />

      <Panel title="Record of processing activities" right="Nigeria Data Protection Act 2023">
        {register.length ? (
          <DTable cols={["Activity", "Lawful basis", "Sensitive|mid", "Retention", "DPIA|num"]} rows={register.map((a) => [
            <span key="a">{a.activity}</span>,
            <span className="sub2" key="b">{a.lawful_basis}</span>,
            a.sensitive ? <Pil kind="bad" key="s">Yes</Pil> : <Pil kind="grey" key="s">No</Pil>,
            <span className="sub2" key="r">{a.retention}</span>,
            <span key="d" style={{ display: "inline-flex", gap: 6, alignItems: "center", justifyContent: "flex-end" }}>
              <Pil kind={DPIA[a.dpia_state]?.[0] ?? "grey"}>{DPIA[a.dpia_state]?.[1] ?? a.dpia_state}</Pil>
              {may && a.dpia_state === "OUTSTANDING" ? <Btn kind="go" disabled={busy} onClick={() => void send(`/register/${a.id}/dpia`, { state: "COMPLETE" }, `DPIA complete for ${a.activity}`).then((j) => { if (j) setSaid("DPIA recorded complete"); })}>Mark done</Btn> : null}
            </span>,
          ])} texts={register.map((a) => `${a.activity} ${a.lawful_basis}`)} />
        ) : <PBody><div className="sub2">The register is empty.</div></PBody>}
      </Panel>

      <Panel title="Data-subject rights requests" right="Access, rectification, erasure, portability, objection">
        {dsr.length ? (
          <DTable cols={["Reference", "Type", "Requester", "Due|mid", "Status|num"]} rows={dsr.map((d) => [
            <span className="tnum" key="r">{d.reference}</span>,
            <span className="sub2" key="k">{d.kind.charAt(0) + d.kind.slice(1).toLowerCase()}</span>,
            <Two key="q" a={d.requester} b={`received ${day(d.received_on)}`} />,
            <span className="tnum sub2" key="due" style={{ color: ["RECEIVED", "IN_PROGRESS"].includes(d.state) && d.due_on < today ? "var(--red-ink)" : undefined }}>{day(d.due_on)}</span>,
            <span key="s" style={{ display: "inline-flex", gap: 6, flexWrap: "wrap", justifyContent: "flex-end", alignItems: "center" }}>
              <Pil kind={DSTATE[d.state]?.[0] ?? "grey"}>{DSTATE[d.state]?.[1] ?? d.state}</Pil>
              {may && d.state === "RECEIVED" ? <Btn kind="ghost" disabled={busy} onClick={() => void send(`/dsr/${d.id}/advance`, { state: "IN_PROGRESS" }, `Progress ${d.reference}`)}>Start</Btn> : null}
              {may && ["RECEIVED", "IN_PROGRESS"].includes(d.state) ? <Btn kind="go" disabled={busy} onClick={() => void send(`/dsr/${d.id}/advance`, { state: "COMPLETED" }, `Complete ${d.reference}`)}>Complete</Btn> : null}
            </span>,
          ])} texts={dsr.map((d) => `${d.reference} ${d.requester} ${d.state}`)} />
        ) : <PBody><div className="sub2">No data-subject request has been logged. A request appears here when a person exercises a right under the Act.</div></PBody>}
      </Panel>

      {may ? (
        <Panel title="Log a data-subject request" right="The statutory clock starts on the day it is received">
          <PBody>
            <div className="grid grid--3">
              <Field id="d-kind" label="Type"><select id="d-kind" className="ctl" value={f.kind} onChange={(e) => setF({ ...f, kind: e.target.value })}>{["ACCESS", "RECTIFICATION", "ERASURE", "PORTABILITY", "OBJECTION"].map((k) => <option key={k} value={k}>{k.charAt(0) + k.slice(1).toLowerCase()}</option>)}</select></Field>
              <Field id="d-req" label="Requester" hint="Who is exercising the right"><input id="d-req" className="ctl" value={f.requester} onChange={(e) => setF({ ...f, requester: e.target.value })} /></Field>
              <Field id="d-due" label="Due" hint="Defaults to 30 days"><input id="d-due" className="ctl" type="date" value={f.dueOn} onChange={(e) => setF({ ...f, dueOn: e.target.value })} /></Field>
            </div>
            <div><Btn kind="primary" disabled={busy || !f.requester.trim()} onClick={async () => { const j = await send("/dsr", { kind: f.kind, requester: f.requester.trim(), dueOn: f.dueOn || null, note: f.note || null }, `Log ${f.kind} request`); if (j) { setSaid(`${j.reference} logged`); setF({ kind: "ACCESS", requester: "", dueOn: "", note: "" }); } }}>Log the request</Btn></div>
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
