"use client";

/** tMovement — the seventeen staff-movement processes, one workflow: request, a second
 *  officer approves, and the instrument is issued. Approved is not real until the letter
 *  exists — issuing it is what changes the record from the effective date. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify , notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tabs, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, day } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface MovementRow {
  id: string; person_id: string; name: string; staff_no: string; grade: string; kind: string; effective_date: string;
  what_changes: string; reason: string | null; new_grade: string | null; new_step: number | null; state: string;
  requested_at: string; approved_at: string | null; instrument: string | null; decision_note: string | null;
}
export interface Grade { grade: string; step: number; category: string }

const KINDS: [string, string][] = [
  ["APPOINTMENT", "Appointment"], ["CONFIRMATION", "Confirmation of appointment"], ["PROMOTION", "Promotion"],
  ["UPGRADING", "Upgrading"], ["CONVERSION", "Conversion"], ["TRANSFER", "Transfer"], ["SECONDMENT", "Secondment"],
  ["ACTING", "Acting appointment"], ["REDESIGNATION", "Redesignation"], ["LEAVE_OF_ABSENCE", "Leave of absence"],
  ["SABBATICAL", "Sabbatical"], ["SUSPENSION", "Suspension"], ["REINSTATEMENT", "Reinstatement"],
  ["RETIREMENT", "Retirement"], ["RESIGNATION", "Resignation"], ["DISENGAGEMENT", "Disengagement"], ["DISMISSAL", "Dismissal"],
];
const KIND_NAME = Object.fromEntries(KINDS);
const STATE: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  REQUESTED: ["warn", "Requested"], APPROVED: ["info", "Approved — instrument not issued"], IMPLEMENTED: ["ok", "Implemented"], DECLINED: ["grey", "Declined"], RETURNED: ["grey", "Returned"],
};

export function Movements({ rows, grades, actingOffice }: { rows: MovementRow[]; grades: Grade[]; actingOffice: string | null }) {
  const router = useRouter();
  const o = actingOffice ?? "";
  const mayOfficer = ["hrm", "registrar", "super"].includes(o);
  const mayApprove = ["hrm", "registrar", "dregistrar", "vc", "dvc", "super"].includes(o);
  const [tab, setTab] = useState("REQUESTED");
  const [f, setF] = useState({ number: "", kind: "PROMOTION", effectiveDate: "", whatChanges: "", reason: "", grade: "" });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  const count = (s: string) => rows.filter((r) => r.state === s).length;
  const shown = tab === "ALL" ? rows : rows.filter((r) => r.state === tab);
  const promotionish = ["PROMOTION", "UPGRADING", "CONVERSION"].includes(f.kind);

  async function send(path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/hr/movements${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return null; }
      notify(reason);
      router.refresh();
      return j as Record<string, unknown>;
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Note kind="info" title="Approved is not implemented until the instrument exists">
        A movement is requested and approved by a second officer, but until the letter is issued it changes nothing — not the grade, not the payroll, not the offices held. Issuing the instrument is the act that changes the record from the effective date, and the portal refuses to write an office that cites no instrument.
      </Note>
      {said ? <Note kind="ok" title={said}>On the record, in your name.</Note> : null}
      {err ? <ProblemNotice problem={err} /> : null}

      <Tiles items={[
        ["Awaiting approval", String(count("REQUESTED")), count("REQUESTED") ? "var(--red-ink)" : null, "Requests to consider"],
        ["Approved, no letter", String(count("APPROVED")), count("APPROVED") ? "var(--chrome)" : null, "Not yet real"],
        ["Implemented", String(count("IMPLEMENTED")), "var(--green-ink)", "Instrument issued"],
        ["Movements", String(rows.length), null, "All"],
      ]} />

      <div className="card"><PBody>
        <Tabs look="segmented" value={tab} onChange={setTab}
          items={[["REQUESTED", "Awaiting"], ["APPROVED", "To issue"], ["IMPLEMENTED", "Implemented"], ["ALL", "All"]].map(([k, l]) => ({ id: k, label: l, count: k !== "ALL" && count(k) ? count(k) : undefined }))} />
      </PBody></div>

      <Panel title="Staff movements" right={`${shown.length} shown`}>
        {shown.length ? (
          <DTable cols={["Staff", "Movement", "What changes", "Effective|mid", "Stage", "Action|num"]} rows={shown.map((r) => [
            <Two key="s" a={r.name} b={`${r.staff_no} · ${r.grade}`} />,
            <span key="k">{KIND_NAME[r.kind] ?? r.kind}</span>,
            <span className="sub2" key="w">{r.what_changes}{r.reason ? <div className="sub2">{r.reason}</div> : null}{r.instrument ? <div className="sub2 tnum">Instrument {r.instrument}</div> : null}{r.decision_note ? <div className="sub2">{r.decision_note}</div> : null}</span>,
            <span className="sub2 tnum" key="e">{day(r.effective_date)}</span>,
            <Pil kind={STATE[r.state]?.[0] ?? "grey"} key="st">{STATE[r.state]?.[1] ?? r.state}</Pil>,
            <span key="ac" className="row row--inline row--tight row--right">
              {mayApprove && r.state === "REQUESTED" ? <Btn kind="go" disabled={busy} onClick={() => void send(`/${r.id}/approve`, {}, `Approve movement for ${r.name}`).then((j) => { if (j) setSaid(`${r.name}'s movement approved — issue the instrument to make it real`); })}>Approve</Btn> : null}
              {mayApprove && r.state === "REQUESTED" ? <Btn kind="ghost" disabled={busy} onClick={() => { const w = window.prompt("Why is it declined? The reason is recorded."); if (w && w.trim()) void send(`/${r.id}/decline`, { why: w.trim() }, `Decline movement for ${r.name}`); }}>Decline</Btn> : null}
              {mayOfficer && r.state === "APPROVED" ? <Btn kind="primary" disabled={busy} onClick={() => { if (window.confirm(`Issue the instrument for ${r.name}? This changes the record from ${day(r.effective_date)}.`)) void send(`/${r.id}/issue`, {}, `Issue instrument for ${r.name}`).then((j) => { if (j) setSaid(`Instrument ${j.instrument} issued — the record is changed`); }); }}>Issue instrument</Btn> : null}
            </span>,
          ])} texts={shown.map((r) => `${r.name} ${r.staff_no} ${r.kind} ${r.state}`)} />
        ) : <PBody><div className="sub2">No movement in this stage.</div></PBody>}
      </Panel>

      {mayOfficer ? (
        <Panel title="Open a movement" right="It goes to a second officer to approve">
          <PBody>
            <div className="grid grid--3">
              <Field id="mv-num" label="Staff number"><input id="mv-num" className="ctl tnum" value={f.number} onChange={(e) => setF({ ...f, number: e.target.value })} placeholder="MOAUM/STAFF/016" /></Field>
              <Field id="mv-kind" label="Movement type"><select id="mv-kind" className="ctl" value={f.kind} onChange={(e) => setF({ ...f, kind: e.target.value })}>{KINDS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></Field>
              <Field id="mv-eff" label="Effective from"><input id="mv-eff" className="ctl" type="date" value={f.effectiveDate} onChange={(e) => setF({ ...f, effectiveDate: e.target.value })} /></Field>
            </div>
            {promotionish ? (
              <Field id="mv-grade" label="New grade and step"><select id="mv-grade" className="ctl" value={f.grade} onChange={(e) => setF({ ...f, grade: e.target.value })}><option value="">Select…</option>{grades.map((g) => <option key={`${g.grade}|${g.step}`} value={`${g.grade}|${g.step}`}>{g.grade} · step {g.step} ({g.category === "ACADEMIC" ? "Academic" : "Non-academic"})</option>)}</select></Field>
            ) : (
              <Field id="mv-what" label="What it changes"><input id="mv-what" className="ctl" value={f.whatChanges} onChange={(e) => setF({ ...f, whatChanges: e.target.value })} placeholder="e.g. Confirmed to permanent appointment" /></Field>
            )}
            <Field id="mv-reason" label="Reason / minute" hint="Optional"><input id="mv-reason" className="ctl" value={f.reason} onChange={(e) => setF({ ...f, reason: e.target.value })} /></Field>
            <div><Btn kind="primary" disabled={busy || !f.number.trim() || !f.effectiveDate || (promotionish ? !f.grade : !f.whatChanges.trim())} onClick={async () => {
              const [g, s] = promotionish && f.grade ? f.grade.split("|") : [null, null];
              const j = await send("", { number: f.number.trim(), kind: f.kind, effectiveDate: f.effectiveDate, whatChanges: promotionish ? "" : f.whatChanges.trim(), reason: f.reason || null, newGrade: g, newStep: s ? Number(s) : null }, `Open ${KIND_NAME[f.kind]} for ${f.number.trim()}`);
              if (j) { setSaid("Movement opened — it goes to a second officer"); setF({ number: "", kind: "PROMOTION", effectiveDate: "", whatChanges: "", reason: "", grade: "" }); }
            }}>Open the movement</Btn></div>
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
