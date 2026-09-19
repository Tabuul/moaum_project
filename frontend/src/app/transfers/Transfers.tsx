"use client";

/** tTransfers — inter-departmental transfer pipeline. A student applies; the application moves through
 *  four desks, each a single Approve: the current department, the new department, the Registrar, and the
 *  Academic office. Every office sees the whole pipeline; the Approve button shows only on the row and to
 *  the office whose turn it is (the server decides). Once approved, the student pays the Bursary-set fee
 *  and the registry effects the change. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, Note, Panel, PBody, Pil, RoleLine, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface TransferRow {
  id: string; student_id: string; name: string; matric_no: string | null;
  from_programme: string; from_dept: string | null; from_level: number;
  to_programme: string; to_dept: string | null; mode_of_entry: string;
  utme_score: number | null; cgpa: number | null; reason: string; state: string;
  stageLabel?: string; canApprove?: boolean;
  recommended_level: number | null; committee_note: string | null; decline_note: string | null; withdrawn_why: string | null;
  applied_at: string; from_dept_at: string | null; to_dept_at: string | null; reg_at: string | null; acad_at: string | null; effected_at: string | null;
  fee_reference: string | null; fee_confirmed_at: string | null; session: string;
}
export interface Programme { code: string; name: string; faculty: string }

const STATE: Record<string, "ok" | "info" | "bad" | "grey" | "warn"> = {
  APPLIED: "warn", FROM_OK: "info", TO_OK: "info", REG_OK: "info",
  APPROVED: "info", EFFECTED: "ok", DECLINED: "bad", WITHDRAWN: "grey",
};
const LABEL: Record<string, string> = {
  APPLIED: "With current department", FROM_OK: "With new department", TO_OK: "With Registrar",
  REG_OK: "With Academic office", APPROVED: "Approved — awaiting fee", EFFECTED: "Completed",
  DECLINED: "Declined", WITHDRAWN: "Withdrawn",
};

export function Transfers({ rows, programmes, actingOffice }: { rows: TransferRow[]; programmes: Programme[]; actingOffice: string | null }) {
  const router = useRouter();
  const o = actingOffice ?? "";
  const mayRecord = ["academic", "registrar", "dregistrar", "super"].includes(o);

  const [tab, setTab] = useState("APPLIED");
  const [rec, setRec] = useState({ number: "", programme: "", reason: "", utme: "" });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  const count = (s: string) => rows.filter((r) => r.state === s).length;
  const shown = tab === "ALL" ? rows : rows.filter((r) => r.state === tab);

  async function send(path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/transfers${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
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
      <RoleLine allowed={["hod", "registrar", "dregistrar", "academic"]} actingOffice={actingOffice}
        canAct={mayRecord || o === "hod"}
        action="Approving inter-departmental transfers" />
      <Note kind="info" title="One application, four approvals — each a single Approve">
        A matriculated student applies to move to another department. It goes to the <b>current department</b>, then the
        <b> new department</b>, then the <b>Registrar</b>, then the <b>Academic office</b> — each simply approves (or
        declines). Once all four have approved, the student pays the non-refundable processing fee set by the Bursary and
        the registry effects the change: the programme and level move, the matriculation number does not.
      </Note>
      {said ? <Note kind="ok" title={said}>On the record, in your name.</Note> : null}
      {err ? <ProblemNotice problem={err} /> : null}

      <Tiles items={[
        ["With current department", String(count("APPLIED")), count("APPLIED") ? "var(--chrome)" : null, "First approval"],
        ["With new department", String(count("FROM_OK")), count("FROM_OK") ? "var(--chrome)" : null, "Accepting the student"],
        ["With Registrar", String(count("TO_OK")), count("TO_OK") ? "var(--chrome)" : null, "Third approval"],
        ["With Academic office", String(count("REG_OK")), count("REG_OK") ? "var(--chrome)" : null, "Final approval"],
      ]} />

      <div className="card"><div className="card__body">
        <div className="role-tabs" role="tablist">
          {[["APPLIED", "Current dept"], ["FROM_OK", "New dept"], ["TO_OK", "Registrar"], ["REG_OK", "Academic"], ["EFFECTED", "Completed"], ["DECLINED", "Declined"], ["ALL", "All"]].map(([k, l]) => (
            <button key={k} type="button" role="tab" aria-selected={tab === k ? "true" : "false"} onClick={() => setTab(k)}>{l}{k !== "ALL" && count(k) ? ` (${count(k)})` : ""}</button>
          ))}
        </div>
      </div></div>

      <Panel title="Transfer applications" right={`${shown.length} shown`}>
        {shown.length ? (
          <DTable cols={["Student", "From → To", "Entry · UTME · CGPA|mid", "Reason", "Stage", "Action|num"]} rows={shown.map((r) => [
            <Two key="s" a={r.name} b={r.matric_no ?? ""} />,
            <span key="ft"><span className="sub2">{r.from_programme} · {r.from_level}L</span><div><b>→ {r.to_programme}</b></div></span>,
            <span className="sub2 tnum" key="e">{r.mode_of_entry}{r.utme_score != null ? ` · ${r.utme_score}` : ""}{r.cgpa != null ? ` · ${Number(r.cgpa).toFixed(2)}` : ""}</span>,
            <span className="sub2" key="r">{r.reason}{r.decline_note ? <div className="sub2">Declined: {r.decline_note}</div> : null}{r.withdrawn_why ? <div className="sub2">Withdrawn: {r.withdrawn_why}</div> : null}</span>,
            <span key="st"><Pil kind={STATE[r.state] ?? "grey"}>{r.stageLabel ?? LABEL[r.state] ?? r.state}</Pil>{r.fee_reference ? <div className="sub2 tnum">{r.fee_reference}{r.fee_confirmed_at ? " · paid" : " · unpaid"}</div> : null}</span>,
            <span key="ac" style={{ display: "inline-flex", gap: 6, flexWrap: "wrap", justifyContent: "flex-end" }}>
              {r.canApprove ? <Btn kind="go" disabled={busy} onClick={() => { if (window.confirm(`Approve ${r.name}'s transfer at this stage? It moves to the next office.`)) void send(`/${r.id}/approve`, {}, `Approve transfer for ${r.name}`).then((j) => { if (j) setSaid(`${r.name} approved — ${LABEL[String(j.state)] ?? "advanced"}`); }); }}>Approve</Btn> : null}
              {r.canApprove ? <Btn kind="ghost" disabled={busy} onClick={() => { const w = window.prompt("Decline this application — why? The reason is recorded and shown to the student."); if (w && w.trim()) void send(`/${r.id}/decline`, { why: w.trim() }, `Decline transfer for ${r.name}`).then((j) => { if (j) setSaid(`${r.name} declined`); }); }}>Decline</Btn> : null}
            </span>,
          ])} texts={shown.map((r) => `${r.name} ${r.matric_no ?? ""} ${r.from_programme} ${r.to_programme} ${r.state}`)} />
        ) : <PBody><div className="sub2">No application in this stage.</div></PBody>}
      </Panel>

      {mayRecord ? (
        <Panel title="Record an application" right="For a case brought to the office on paper">
          <PBody>
            <div className="grid grid--2">
              <Field id="tr-num" label="Student number"><input id="tr-num" className="ctl tnum" value={rec.number} onChange={(e) => setRec({ ...rec, number: e.target.value })} placeholder="MOAUM/CSC/23/0001" /></Field>
              <Field id="tr-prog" label="Course applied for"><select id="tr-prog" className="ctl" value={rec.programme} onChange={(e) => setRec({ ...rec, programme: e.target.value })}><option value="">Select a programme…</option>{programmes.map((p) => <option key={p.code} value={p.code}>{p.name} — {p.faculty}</option>)}</select></Field>
            </div>
            <div className="grid grid--2">
              <Field id="tr-reason" label="Reason for seeking transfer"><input id="tr-reason" className="ctl" value={rec.reason} onChange={(e) => setRec({ ...rec, reason: e.target.value })} /></Field>
              <Field id="tr-utme" label="UTME score" hint="Optional"><input id="tr-utme" className="ctl tnum" inputMode="numeric" value={rec.utme} onChange={(e) => setRec({ ...rec, utme: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
            </div>
            <div><Btn kind="primary" disabled={busy || !rec.number.trim() || !rec.programme || !rec.reason.trim()} onClick={async () => { const j = await send("", { number: rec.number.trim(), toProgramme: rec.programme, reason: rec.reason.trim(), utme: rec.utme ? Number(rec.utme) : null }, `Record transfer application for ${rec.number.trim()}`); if (j) { setSaid("Application recorded — it goes to the current department"); setRec({ number: "", programme: "", reason: "", utme: "" }); } }}>Record the application</Btn></div>
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
