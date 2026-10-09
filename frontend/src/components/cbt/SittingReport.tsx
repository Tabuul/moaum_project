"use client";
/** V375: the report of a sitting. The chief invigilator (any invigilator where none is chief, or the office) files it once the
 *  candidates have finished or the sitting's time is over: when it really began and ended, which invigilators were present, the
 *  remarks; the counts and the incidents are the record's, as they stood. A filed report is not changed — the office adds to it.
 *  It prints with a line for each invigilator to sign. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { esc, printDocument } from "@/lib/document/html";
import { num, whenAt } from "@/lib/cbt";
import { cbtSend } from "./CbtExam";
import { INCIDENT_WORD } from "./IncidentForm";
import type { Incident } from "./InvigilatorBoard";

interface Person { person_id: string; name: string; staff_number: string | null; chief?: boolean }
interface Counts { seated: number; checked_in: number; started: number; not_come: number; not_started?: number; absent: number; late: number; writing: number; submitted: number; time_expired: number; terminated: number; incidents: number; minutes_lost: number }
export interface ReportView {
  sitting: { id: string; label: string; venue: string; starts_at: string; ends_at: string };
  exam: { id: string; reference: string; title: string; course_code: string; session: string; duration_minutes: number };
  report: { began_at: string; ended_at: string; remarks: string | null; counts: Counts; filed_at: string; filed_by: string | null; filed_office: string | null; addendum: string | null; present: Person[] } | null;
  counts: Counts; incidents: Incident[]; invigilators: Person[]; canFile: boolean; canAdd: boolean; now: string;
}

const hhmm = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" }) : "—");
/** a datetime-local value for a moment */
const local = (iso: string) => { const d = new Date(iso); const p = (n: number) => String(n).padStart(2, "0"); return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`; };

export function SittingReport({ initial }: { initial: ReportView }) {
  const router = useRouter();
  const [v, setV] = useState(initial);
  const [began, setBegan] = useState(local(initial.sitting.starts_at));
  const [ended, setEnded] = useState(local(new Date(initial.now) < new Date(initial.sitting.ends_at) ? initial.now : initial.sitting.ends_at));
  const [present, setPresent] = useState<string[]>(initial.invigilators.map((p) => p.person_id));
  const [remarks, setRemarks] = useState("");
  const [addendum, setAddendum] = useState("");
  const [busy, setBusy] = useState(false);
  const r = v.report;
  const c = r ? r.counts : v.counts;
  const s = v.sitting;

  async function file() {
    setBusy(true);
    try {
      const j = await cbtSend(`/sittings/${s.id}/report`, "POST", { began: new Date(began).toISOString(), ended: new Date(ended).toISOString(), invigilators: present, remarks: remarks.trim() || null }, `The report of ${s.label} filed`);
      if (j) { setV(j as unknown as ReportView); router.refresh(); }
    } finally { setBusy(false); }
  }
  async function add() {
    setBusy(true);
    try {
      const j = await cbtSend(`/sittings/${s.id}/report/addendum`, "POST", { text: addendum.trim() }, `Added to the report of ${s.label}`);
      if (j) { setV(j as unknown as ReportView); setAddendum(""); }
    } finally { setBusy(false); }
  }
  function print() {
    if (!r) return;
    const rows: [string, string][] = [
      ["Examination", `${v.exam.course_code} · ${v.exam.title} (${v.exam.reference})`], ["Sitting", `${s.label} · ${s.venue}`],
      ["Scheduled", `${whenAt(s.starts_at)} to ${hhmm(s.ends_at)}`], ["Began and ended", `${whenAt(r.began_at)} to ${hhmm(r.ended_at)}`],
      ["Seated", String(c.seated)], ["Checked in", String(c.checked_in)], ["Started", String(c.started)], ["Absent", String(c.absent)],
      ["Not come (no mark)", String(c.not_come)], ["Admitted late", String(c.late)], ["Submitted", String(c.submitted)], ["Time expired", String(c.time_expired)],
      ["Terminated", String(c.terminated)], ["Incidents", `${c.incidents}${c.minutes_lost ? ` · ${c.minutes_lost} minutes lost by the hall` : ""}`],
      ["Remarks", r.remarks ?? "—"], ["Filed", `${whenAt(r.filed_at)} by ${r.filed_by ?? "—"}`],
    ];
    const incidents = v.incidents.map((x) => `<tr><td>${esc(hhmm(x.occurred_at))}</td><td>${esc(INCIDENT_WORD[x.kind] ?? x.kind)}${x.minutes_lost ? ` (${esc(x.minutes_lost)} min)` : ""}${x.time_given_at ? ` · ${esc(x.time_given_minutes)} min given back to ${esc(x.time_given_to)}` : ""}${x.after_filing ? " · after the report" : ""}</td><td>${x.candidate_id ? esc(`Seat ${x.seat_no ?? "—"} · ${(x.surname ?? "").toUpperCase()}, ${x.other_names ?? ""} · ${x.number ?? ""}`) : "The hall"}</td><td>${esc(x.detail)}</td></tr>`).join("");
    const signatures = r.present.map((p) => `<tr><td>${esc(p.name)}</td><td>${esc(p.staff_number ?? "")}</td><td style="height:28px"></td><td></td></tr>`).join("");
    void printDocument("FORM", {
      title: "CBT sitting report", subtitle: `${v.exam.course_code} · ${s.label} · ${s.venue}`, reference: v.exam.reference,
      bodyHtml: `<table><tbody>${rows.map(([k, val]) => `<tr><th style="text-align:left;width:34%">${esc(k)}</th><td>${esc(val)}</td></tr>`).join("")}</tbody></table>
        <h3 style="margin:14px 0 6px">Incidents</h3>${incidents ? `<table><thead><tr><th>When</th><th>What</th><th>Candidate</th><th>Detail</th></tr></thead><tbody>${incidents}</tbody></table>` : "<p>None recorded.</p>"}
        ${r.addendum ? `<h3 style="margin:14px 0 6px">Addendum</h3><p style="white-space:pre-wrap">${esc(r.addendum)}</p>` : ""}
        <h3 style="margin:14px 0 6px">Invigilators present</h3><table><thead><tr><th>Name</th><th>Staff number</th><th>Signature</th><th>Date</th></tr></thead><tbody>${signatures}</tbody></table>`,
    });
  }

  return (
    <>
      <Note kind={r ? "ok" : "info"} title={`${v.exam.course_code} · ${s.label} · ${s.venue}`}>
        {v.exam.title} ({v.exam.reference}) · scheduled {whenAt(s.starts_at)} to {hhmm(s.ends_at)}.
        {r ? <> Report filed {whenAt(r.filed_at)} by {r.filed_by ?? "—"}.</> : <> The report is filed once the candidates have finished or the sitting&rsquo;s time is over; after that it is not changed.</>}
      </Note>
      <Tiles cls="grid--5" items={[
        ["SEATED", num(c.seated), null, `${num(c.checked_in)} checked in`],
        ["STARTED", num(c.started), null, `${num(c.late)} admitted late`],
        ["ABSENT", num(c.absent), c.absent ? "var(--red-ink)" : null, `${num(c.not_come)} not come without a mark`],
        ["FINISHED", num(c.submitted + c.time_expired + c.terminated), null, `${num(c.time_expired)} time expired · ${num(c.terminated)} terminated`],
        ["INCIDENTS", num(c.incidents), c.incidents ? "var(--amber-ink)" : null, c.minutes_lost ? `${num(c.minutes_lost)} min lost by the hall` : "No time lost by the hall"],
      ]} />

      <Panel title="Incidents" right={<span className="row row--inline row--tight"><LinkBtn kind="ghost" size="sm" href={`/cbt/invigilate/${s.id}`}>← The board</LinkBtn>{r ? <Btn kind="secondary" size="sm" onClick={print}>Print the report</Btn> : null}</span>}>
        {v.incidents.length ? (
          <DTable cols={["When", "What", "Candidate", "Detail", "Recorded by"]} rows={v.incidents.map((x) => [
            <span key="w" className="tnum">{hhmm(x.occurred_at)}</span>,
            <span key="k">{INCIDENT_WORD[x.kind] ?? x.kind}{x.minutes_lost ? <span className="sub2"> · {x.minutes_lost} min</span> : null}{x.time_given_at ? <span className="sub2"> · {x.time_given_minutes} min given back to {x.time_given_to}</span> : null}{x.after_filing ? <Pil kind="grey" className="ml-1">after the report</Pil> : null}</span>,
            <span key="c" className="sub2">{x.candidate_id ? `Seat ${x.seat_no ?? "—"} · ${(x.surname ?? "").toUpperCase()}, ${x.other_names ?? ""}` : "The hall"}</span>,
            <span key="d">{x.detail}</span>, <span key="b" className="sub2">{x.recorded_by ?? "—"}</span>,
          ])} />
        ) : <PBody><div className="sub2">No incident recorded. Record them on the board as they happen.</div></PBody>}
      </Panel>

      {r ? (
        <Panel title="The report">
          <PBody>
            <div><b>Began and ended:</b> {whenAt(r.began_at)} to {hhmm(r.ended_at)}</div>
            <div><b>Invigilators present:</b> {r.present.map((p) => p.name).join("; ") || "—"}</div>
            <div><b>Remarks:</b> {r.remarks ?? "—"}</div>
            {r.addendum ? <div className="mt-2"><b>Addendum</b><div style={{ whiteSpace: "pre-wrap" }}>{r.addendum}</div></div> : null}
            {v.canAdd ? (
              <div className="mt-2">
                <Field id="rep-add" label="Add to the report" hint="The office's addendum; the report itself is not changed"><textarea id="rep-add" className="ctl" rows={2} value={addendum} onChange={(e) => setAddendum(e.target.value)} /></Field>
                <Btn kind="secondary" disabled={busy || !addendum.trim()} onClick={() => void add()}>Add</Btn>
              </div>
            ) : null}
          </PBody>
        </Panel>
      ) : v.canFile ? (
        <Panel title="File the report">
          <PBody>
            <div className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
              <Field id="rep-began" label="The sitting began"><input id="rep-began" type="datetime-local" className="ctl" value={began} onChange={(e) => setBegan(e.target.value)} /></Field>
              <Field id="rep-ended" label="and ended"><input id="rep-ended" type="datetime-local" className="ctl" value={ended} onChange={(e) => setEnded(e.target.value)} /></Field>
            </div>
            <div className="mb-2"><b>Invigilators present</b>
              {v.invigilators.map((p) => (
                <label key={p.person_id} className="row row--inline row--tight" style={{ gap: 6 }}>
                  <input type="checkbox" checked={present.includes(p.person_id)} onChange={() => setPresent((x) => (x.includes(p.person_id) ? x.filter((y) => y !== p.person_id) : [...x, p.person_id]))} />
                  {p.name}{p.chief ? " (chief)" : ""}
                </label>
              ))}
            </div>
            <Field id="rep-remarks" label="Remarks" hint="What the office should know: how the sitting went, what was done about each incident"><textarea id="rep-remarks" className="ctl" rows={4} value={remarks} onChange={(e) => setRemarks(e.target.value)} /></Field>
            <Btn kind="primary" disabled={busy || !present.length || !began || !ended} onClick={() => { if (window.confirm("File the report? It is not changed after filing; the office may add to it.")) void file(); }}>{busy ? "Filing…" : "File the report"}</Btn>
            <div className="sub2 mt-1">The counts and the incidents are taken from the record as they stand when it is filed.</div>
          </PBody>
        </Panel>
      ) : <Note kind="info" title="Not yet filed">The chief invigilator files the report{v.invigilators.find((p) => p.chief) ? ` (${v.invigilators.find((p) => p.chief)?.name})` : ""}, or the office running the examination.</Note>}
    </>
  );
}
