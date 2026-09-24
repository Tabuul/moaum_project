"use client";
/** The supervisor's logbook (V245): the postings the acting person supervises this session, and for one
 *  student on one posting what the prospectus asks — the procedures observed or performed (five each,
 *  verified), the cases clerked, attendance at the posting's sessions and at the block's mandatory
 *  events — with the forms that record them. The College's desk sees every posting; a supervisor their own. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { useQueryNav } from "@/lib/query-nav";
import { notify , notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";

/** what the logbook asks, from the prospectus (/college/requirements) */
export interface Requirements {
  postings: { id: string; code: string; name: string; level: number | null; level_note: string | null; tier: string; duration_weeks: number | null; min_cases: number | null; block_code: string; block: string; procedures: number; procedure_list: string | null; slots: number }[];
  attendance: { scope: string; phase: string | null; block_code: string | null; block: string | null; min_pct: number; applies_to: string; note: string | null }[];
  events: { name: string; weekday: number | null; block_code: string | null; block: string | null }[];
}
const WEEKDAY = ["", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
const PHASE: Record<string, string> = { PREMEDICAL: "Pre-Medical", PRECLINICAL: "Pre-clinical", CLINICAL: "Clinical" };
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface Supervised {
  id: string; student_id: string; number: string; surname: string; other_names: string; programme_code: string;
  posting_id: string; posting: string; posting_name: string; tier: string; duration_weeks: number | null; min_cases: number | null;
  block_id: string; block_code: string; block: string; group_label: string | null; starts_on: string | null; ends_on: string | null; state: string;
  supervisor: string | null; requirements: number; requirements_met: number; sessions_recorded: number; sessions_present: number; cases: number;
}
export interface Logbook {
  allocation: { id: string; student_id: string; posting_id: string; session: string; state: string; posting: string; number: string; surname: string; other_names: string };
  requirements: { id: string; name: string; min_count: number; mode: string; done: number; unverified: number }[];
  procedures: { id: string; requirement_id: string; name: string; done_on: string; patient_ref: string | null; mode: string; verified_at: string | null; verified_by: string | null }[];
  cases: { id: string; done_on: string; patient_ref: string | null; presented: boolean; verified_by: string | null }[];
  attendance: { id: string; held_on: string; activity_type: string; present: boolean; starts_at: string | null; ends_at: string | null; slot_type: string | null; topic: string | null }[];
  events: { id: string; name: string; weekday: number | null; held: number; present: number }[];
  slots: { id: string; week_no: number; weekday: number; starts_at: string; ends_at: string; slot_type: string; topic: string | null }[];
  minCases: number | null;
}

const STATE: Record<string, ["ok" | "info" | "bad" | "grey" | "warn", string]> = {
  ALLOCATED: ["info", "Allocated"], IN_PROGRESS: ["warn", "In progress"], COMPLETED: ["ok", "Completed"], INCOMPLETE: ["bad", "Incomplete"],
};
const DAYS = ["", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
const ACTIVITIES = ["LECTURE", "PRACTICAL", "CLINICAL", "TUTORIAL", "TEST", "OTHER"];
const day = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");
const word = (s: string) => s.charAt(0) + s.slice(1).toLowerCase().replace(/_/g, " ");

export function Supervision({ sessions, session, rows, allocation, logbook, problem, desk, requirements }: {
  sessions: string[]; session: string; rows: Supervised[]; allocation: string; logbook: Logbook | null; problem: Problem | null; desk: boolean; requirements: Requirements | null;
}) {
  const router = useRouter();
  const go = useQueryNav();
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [proc, setProc] = useState({ requirementId: "", doneOn: "", patientRef: "", mode: "PERFORM", verified: true });
  const [kase, setKase] = useState({ doneOn: "", patientRef: "", presented: false });
  const [att, setAtt] = useState({ heldOn: "", activityType: "CLINICAL", present: true, slotId: "" });
  const [evt, setEvt] = useState({ eventId: "", heldOn: "", present: true });

  const nav = (patch: Partial<{ session: string; allocation: string }>) =>
    go(`/college/supervision?session=${encodeURIComponent(patch.session ?? session)}${(patch.allocation ?? allocation) ? `&allocation=${encodeURIComponent(patch.allocation ?? allocation)}` : ""}`);

  async function call(method: "POST" | "PUT", path: string, body: unknown, reason: string): Promise<boolean> {
    setBusy(true); setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/college${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      if (!r.ok) { { const p = (await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }; setErr(p); notifyProblem(p); } return false; }
      notify(reason);
      router.refresh();
      return true;
    } finally { setBusy(false); }
  }

  const postings = [...new Map(rows.map((r) => [r.posting_id, r])).values()];
  const students = rows.filter((r) => allocation ? r.id === allocation || true : true);
  const met = rows.filter((r) => r.requirements > 0 && r.requirements_met >= r.requirements).length;
  const lb = logbook;
  const who = lb ? `${lb.allocation.surname}, ${lb.allocation.other_names} (${lb.allocation.number})` : "";
  const attPct = lb && lb.attendance.length ? Math.round((100 * lb.attendance.filter((a) => a.present).length) / lb.attendance.length) : null;

  return (
    <>
      <div className="scope">
        <div className="scope__f"><label htmlFor="sv-session">Session</label>
          <select id="sv-session" className="ws__select" value={session} onChange={(e) => nav({ session: e.target.value, allocation: "" })}>
            {sessions.map((s) => <option key={s} value={s}>{s}</option>)}
          </select></div>
        <div className="scope__f" style={{ flex: "2 1 360px" }}><label htmlFor="sv-student">Student on a posting</label>
          <select id="sv-student" className="ws__select" value={allocation} onChange={(e) => nav({ allocation: e.target.value })}>
            <option value="">{rows.length ? "Choose a student…" : desk ? "Nobody is allocated to a posting this session" : "You supervise nobody this session"}</option>
            {postings.map((p) => (
              <optgroup key={p.posting_id} label={`${p.block} · ${p.posting} — ${p.posting_name}`}>
                {students.filter((r) => r.posting_id === p.posting_id).map((r) => <option key={r.id} value={r.id}>{r.surname}, {r.other_names} · {r.number}{r.group_label ? ` · Group ${r.group_label}` : ""}</option>)}
              </optgroup>
            ))}
          </select></div>
      </div>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {err ? <ProblemNotice problem={err} /> : null}

      <Tiles items={[
        [desk ? "Students on postings" : "Students you supervise", String(rows.length), null, `${postings.length} posting${postings.length === 1 ? "" : "s"} · ${session}`],
        ["Logbooks complete", String(met), met === rows.length && rows.length ? "var(--green-ink)" : null, "Every requirement met and verified"],
        ["In progress", String(rows.filter((r) => r.state === "IN_PROGRESS").length), null, `${rows.filter((r) => r.state === "COMPLETED").length} completed`],
        ["Chosen", lb ? lb.allocation.posting : "—", null, lb ? `${lb.allocation.surname} · ${word(lb.allocation.state)}` : "Choose a student"],
      ]} />

      {!lb ? (
        rows.length ? (
          <Panel title={desk ? "Every student on a posting this session" : "The students you supervise"} right="Where each stands">
            <DTable cols={["Block · posting", "Student", "Group|mid", "Supervisor", "Logbook|mid", "Attendance|mid", "Cases|mid", "Standing|mid", "|num"]} rows={rows.map((r) => [
              <span key="p"><strong>{r.block}</strong> <span className="tnum">{r.posting}</span><div className="sub2">{r.posting_name}</div></span>,
              <span key="s"><strong>{r.surname}, {r.other_names}</strong><div className="sub2 tnum">{r.number}</div></span>,
              <span className="tnum" key="g">{r.group_label ?? "—"}</span>,
              <span className="sub2" key="sv">{r.supervisor ?? "Not yet assigned"}</span>,
              <span className={`tnum${r.requirements && r.requirements_met >= r.requirements ? " ink-green b600" : ""}`} key="l">{r.requirements ? `${r.requirements_met} of ${r.requirements}` : "—"}</span>,
              <span className="tnum" key="a">{r.sessions_recorded ? `${r.sessions_present} of ${r.sessions_recorded}` : "—"}</span>,
              <span className="tnum" key="c">{r.min_cases ? `${r.cases} of ${r.min_cases}` : String(r.cases)}</span>,
              <Pil key="st" kind={STATE[r.state]?.[0] ?? "grey"}>{STATE[r.state]?.[1] ?? r.state}</Pil>,
              <Btn key="o" kind="primary" onClick={() => nav({ allocation: r.id })}>Open</Btn>,
            ])} texts={rows.map((r) => `${r.number} ${r.surname} ${r.other_names} ${r.block} ${r.posting} ${r.state}`)} />
          </Panel>
        ) : (
          <Note kind="info" title={desk ? "No posting allocation this session" : "You supervise nobody this session"} action={desk ? <LinkBtn kind="primary" href={`/college/postings?session=${encodeURIComponent(session)}`}>Postings desk</LinkBtn> : undefined}>
            {desk ? "Allocate students on the Postings desk; each allocation names a supervisor, and the logbook opens here." : "A posting's logbook opens here once the College Secretary names you its supervisor on the allocation. If you supervise students and see none, ask the College Secretary to name you on their allocations."}
          </Note>
        )
      ) : null}

      {!lb && requirements ? (
        <>
          <Panel title="What the logbook asks, by posting" right="From the prospectus; the supervisor verifies each entry">
            <DTable cols={["Block", "Posting", "Level|mid", "Weeks|mid", "Cases|mid", "Procedures", "Timetable|mid"]} rows={requirements.postings.map((p) => [
              <strong key="b">{p.block}</strong>,
              <span key="p"><strong className="tnum">{p.code}</strong> <span className="sub2">{p.name}</span></span>,
              <span className="tnum" key="l">{p.level ?? p.level_note ?? "—"}</span>,
              <span className="tnum" key="w">{p.duration_weeks ?? "—"}</span>,
              <span className="tnum" key="c">{p.min_cases ?? "—"}</span>,
              <span className="sub2" key="r">{p.procedure_list ?? (p.procedures ? `${p.procedures} procedures` : "None named")}</span>,
              <span className="tnum" key="t">{p.slots ? `${p.slots} slots` : "—"}</span>,
            ])} texts={requirements.postings.map((p) => `${p.block} ${p.code} ${p.name} ${p.procedure_list ?? ""}`)} />
          </Panel>
          <div className="grid grid--2">
            <Panel title="Attendance rules" right="The minimum, and what it applies to">
              {requirements.attendance.length ? (
                <DTable cols={["Where", "Minimum|mid", "Applies to", "Note"]} rows={requirements.attendance.map((a, i) => [
                  <strong key={"w" + i}>{a.scope === "PHASE" ? `${PHASE[a.phase ?? ""] ?? a.phase} phase` : a.block ?? a.block_code}</strong>,
                  <span className="tnum" key={"m" + i}>{a.min_pct}%</span>,
                  <span className="sub2" key={"t" + i}>{a.applies_to.toLowerCase().replace(/_/g, " ")}</span>,
                  <span className="sub2" key={"n" + i}>{a.note ?? "—"}</span>,
                ])} />
              ) : <PBody><div className="sub2">The prospectus names no attendance rule.</div></PBody>}
            </Panel>
            <Panel title="Mandatory events" right="Attendance recorded per event">
              {requirements.events.length ? (
                <DTable cols={["Block", "Event", "Day"]} rows={requirements.events.map((e, i) => [
                  <strong key={"b" + i}>{e.block ?? "Every block"}</strong>,
                  <span key={"e" + i}>{e.name}</span>,
                  <span className="sub2" key={"d" + i}>{e.weekday ? WEEKDAY[e.weekday] : "As scheduled"}</span>,
                ])} />
              ) : <PBody><div className="sub2">The prospectus names no mandatory event.</div></PBody>}
            </Panel>
          </div>
        </>
      ) : null}

      {lb ? (
        <>
          <Panel title={`${who} · ${lb.allocation.posting}`} right={<span className="row row--inline"><Pil kind={STATE[lb.allocation.state]?.[0] ?? "grey"}>{STATE[lb.allocation.state]?.[1] ?? lb.allocation.state}</Pil><Btn kind="ghost" onClick={() => nav({ allocation: "" })}>Back to the list</Btn></span>}>
            <PBody><div className="sub2">Everything recorded here is on the audit spine against you. A procedure you record is verified at once unless you untick it; one the student logged waits for your verification. The logbook standing the student sees is what is verified.</div></PBody>
          </Panel>

          <div className="grid grid--2">
            <Panel title="Procedures" right={lb.requirements.length ? `${lb.requirements.filter((r) => r.done >= r.min_count).length} of ${lb.requirements.length} requirements met` : "This posting asks for none"}>
              {lb.requirements.length ? (
                <DTable cols={["Procedure", "Required|mid", "Verified|mid", "Awaiting|mid"]} rows={lb.requirements.map((r) => [
                  <span key="n">{r.name}<div className="sub2">{r.mode === "OBSERVE" ? "Observe" : r.mode === "PERFORM" ? "Perform" : "Observe or perform"}</div></span>,
                  <span className="tnum" key="m">{r.min_count}</span>,
                  <span className={`tnum${r.done >= r.min_count ? " ink-green b700" : ""}`} key="d">{r.done}</span>,
                  <span className={`tnum${r.unverified ? " ink-red" : ""}`} key="u">{r.unverified || "—"}</span>,
                ])} />
              ) : null}
              {lb.requirements.length ? (
                <PBody>
                  <div className="stack">
                    <Field id="pr-req" label="Procedure">
                      <select id="pr-req" className="ctl" value={proc.requirementId} onChange={(e) => setProc({ ...proc, requirementId: e.target.value })}>
                        <option value="">Choose…</option>{lb.requirements.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
                      </select></Field>
                    <div className="row row--tight">
                      <div className="field" style={{ flex: "1 1 130px" }}><label htmlFor="pr-date">Date</label><input id="pr-date" className="ctl" type="date" value={proc.doneOn} onChange={(e) => setProc({ ...proc, doneOn: e.target.value })} /></div>
                      <div className="field" style={{ width: 130 }}><label htmlFor="pr-mode">Mode</label>
                        <select id="pr-mode" className="ctl" value={proc.mode} onChange={(e) => setProc({ ...proc, mode: e.target.value })}><option value="PERFORM">Performed</option><option value="OBSERVE">Observed</option></select></div>
                      <div className="field" style={{ flex: "1 1 140px" }}><label htmlFor="pr-ref">Patient reference</label><input id="pr-ref" className="ctl" value={proc.patientRef} onChange={(e) => setProc({ ...proc, patientRef: e.target.value })} placeholder="Hospital number, never a name" autoComplete="off" /></div>
                    </div>
                    <label className="row row--inline row--tight"><input type="checkbox" checked={proc.verified} onChange={(e) => setProc({ ...proc, verified: e.target.checked })} /> Verified by me now</label>
                    <Btn kind="primary" disabled={busy || !proc.requirementId || !proc.doneOn} onClick={() => void call("POST", `/allocations/${lb.allocation.id}/procedures`, proc, `${lb.allocation.number}: ${lb.requirements.find((r) => r.id === proc.requirementId)?.name ?? "procedure"} ${proc.mode === "PERFORM" ? "performed" : "observed"}`).then((ok) => { if (ok) setProc({ ...proc, doneOn: "", patientRef: "" }); })}>Record the procedure</Btn>
                  </div>
                </PBody>
              ) : null}
              {lb.procedures.length ? (
                <DTable cols={["Date|mid", "Procedure", "Mode|mid", "Patient|mid", "Verified", ...(lb.procedures.some((p) => !p.verified_at) ? ["|num"] : [])]} rows={lb.procedures.map((p) => [
                  <span className="tnum" key="d">{day(p.done_on)}</span>, <span key="n">{p.name}</span>, <span className="sub2" key="m">{p.mode === "PERFORM" ? "Performed" : "Observed"}</span>,
                  <span className="tnum sub2" key="r">{p.patient_ref ?? "—"}</span>,
                  <span className="sub2" key="v">{p.verified_at ? `${p.verified_by ?? "—"} · ${day(p.verified_at)}` : <span className="ink-red">Not yet</span>}</span>,
                  ...(lb.procedures.some((x) => !x.verified_at) ? [!p.verified_at ? <Btn key="vb" kind="go" disabled={busy} onClick={() => void call("PUT", `/allocations/${lb.allocation.id}/procedures/${p.id}/verify`, {}, `${lb.allocation.number}: ${p.name} verified`)}>Verify</Btn> : <span key="vb" />] : []),
                ])} />
              ) : null}
            </Panel>

            <Panel title="Cases clerked" right={lb.minCases ? `${lb.cases.length} of ${lb.minCases} required` : `${lb.cases.length} on record`}>
              <PBody>
                <div className="row row--tight row--end">
                  <div className="field" style={{ flex: "1 1 130px" }}><label htmlFor="cs-date">Date</label><input id="cs-date" className="ctl" type="date" value={kase.doneOn} onChange={(e) => setKase({ ...kase, doneOn: e.target.value })} /></div>
                  <div className="field" style={{ flex: "1 1 140px" }}><label htmlFor="cs-ref">Patient reference</label><input id="cs-ref" className="ctl" value={kase.patientRef} onChange={(e) => setKase({ ...kase, patientRef: e.target.value })} placeholder="Hospital number" autoComplete="off" /></div>
                  <label className="row row--inline row--tight" style={{ paddingBottom: "var(--s-2)" }}><input type="checkbox" checked={kase.presented} onChange={(e) => setKase({ ...kase, presented: e.target.checked })} /> Presented</label>
                  <Btn kind="primary" disabled={busy || !kase.doneOn} onClick={() => void call("POST", `/allocations/${lb.allocation.id}/cases`, kase, `${lb.allocation.number}: a case clerked${kase.presented ? " and presented" : ""}`).then((ok) => { if (ok) setKase({ doneOn: "", patientRef: "", presented: false }); })}>Record the case</Btn>
                </div>
              </PBody>
              {lb.cases.length ? <DTable cols={["Date|mid", "Patient|mid", "Presented|mid", "Verified by"]} rows={lb.cases.map((c) => [<span className="tnum" key="d">{day(c.done_on)}</span>, <span className="tnum sub2" key="r">{c.patient_ref ?? "—"}</span>, <span key="p">{c.presented ? "Yes" : "—"}</span>, <span className="sub2" key="v">{c.verified_by ?? "—"}</span>])} /> : null}
            </Panel>
          </div>

          <div className="grid grid--2">
            <Panel title="Attendance" right={attPct == null ? "Nothing recorded yet" : `${attPct}% present of ${lb.attendance.length} recorded`}>
              <PBody>
                <div className="row row--tight row--end">
                  <div className="field" style={{ flex: "1 1 130px" }}><label htmlFor="at-date">Date</label><input id="at-date" className="ctl" type="date" value={att.heldOn} onChange={(e) => setAtt({ ...att, heldOn: e.target.value })} /></div>
                  <div className="field" style={{ width: 140 }}><label htmlFor="at-type">Activity</label>
                    <select id="at-type" className="ctl" value={att.activityType} onChange={(e) => setAtt({ ...att, activityType: e.target.value })}>{ACTIVITIES.map((a) => <option key={a} value={a}>{word(a)}</option>)}</select></div>
                  {lb.slots.length ? (
                    <div className="field" style={{ flex: "2 1 220px" }}><label htmlFor="at-slot">Timetable slot (optional)</label>
                      <select id="at-slot" className="ctl" value={att.slotId} onChange={(e) => setAtt({ ...att, slotId: e.target.value })}>
                        <option value="">Not against a slot</option>
                        {lb.slots.map((s) => <option key={s.id} value={s.id}>Week {s.week_no} · {DAYS[s.weekday]} {String(s.starts_at).slice(0, 5)}–{String(s.ends_at).slice(0, 5)} · {word(s.slot_type)}{s.topic ? ` · ${s.topic.slice(0, 40)}` : ""}</option>)}
                      </select></div>
                  ) : null}
                  <div className="field" style={{ width: 110 }}><label htmlFor="at-pres">Present</label>
                    <select id="at-pres" className="ctl" value={att.present ? "1" : "0"} onChange={(e) => setAtt({ ...att, present: e.target.value === "1" })}><option value="1">Present</option><option value="0">Absent</option></select></div>
                  <Btn kind="primary" disabled={busy || !att.heldOn} onClick={() => void call("POST", `/allocations/${lb.allocation.id}/attendance`, { ...att, slotId: att.slotId || null }, `${lb.allocation.number}: ${att.present ? "present" : "absent"} at ${word(att.activityType)} on ${att.heldOn}`).then((ok) => { if (ok) setAtt({ ...att, heldOn: "" }); })}>Record</Btn>
                </div>
                <div className="sub2 mt-2">The prospectus requires 75% attendance pre-clinical, 70% clinical and 80% in Surgery to sit the examination; the record here is what that is judged on.</div>
              </PBody>
              {lb.attendance.length ? <DTable cols={["Date|mid", "Activity", "Slot", "Present|mid"]} rows={lb.attendance.map((a) => [<span className="tnum" key="d">{day(a.held_on)}</span>, <span key="t">{word(a.activity_type)}</span>, <span className="sub2" key="s">{a.starts_at ? `${String(a.starts_at).slice(0, 5)}–${String(a.ends_at).slice(0, 5)} · ${word(a.slot_type ?? "")}${a.topic ? ` · ${a.topic}` : ""}` : "—"}</span>, <span key="p" className={`b600 ${a.present ? "ink-green" : "ink-red"}`}>{a.present ? "Present" : "Absent"}</span>])} /> : null}
            </Panel>

            <Panel title="Mandatory events" right={lb.events.length ? `${lb.events.length} of the block` : "None for this block"}>
              {lb.events.length ? (
                <>
                  <DTable cols={["Event", "Day|mid", "Held|mid", "Present|mid"]} rows={lb.events.map((e) => [<strong key="n">{e.name}</strong>, <span key="d">{e.weekday ? DAYS[e.weekday] : "—"}</span>, <span className="tnum" key="h">{e.held}</span>, <span className={`tnum${e.held && e.present < e.held ? " ink-red" : ""}`} key="p">{e.present}</span>])} />
                  <PBody>
                    <div className="row row--tight row--end">
                      <div className="field" style={{ flex: "1 1 180px" }}><label htmlFor="ev-id">Event</label>
                        <select id="ev-id" className="ctl" value={evt.eventId} onChange={(e) => setEvt({ ...evt, eventId: e.target.value })}><option value="">Choose…</option>{lb.events.map((e) => <option key={e.id} value={e.id}>{e.name}</option>)}</select></div>
                      <div className="field" style={{ flex: "1 1 130px" }}><label htmlFor="ev-date">Date</label><input id="ev-date" className="ctl" type="date" value={evt.heldOn} onChange={(e) => setEvt({ ...evt, heldOn: e.target.value })} /></div>
                      <div className="field" style={{ width: 110 }}><label htmlFor="ev-pres">Present</label>
                        <select id="ev-pres" className="ctl" value={evt.present ? "1" : "0"} onChange={(e) => setEvt({ ...evt, present: e.target.value === "1" })}><option value="1">Present</option><option value="0">Absent</option></select></div>
                      <Btn kind="primary" disabled={busy || !evt.eventId || !evt.heldOn} onClick={() => void call("POST", `/allocations/${lb.allocation.id}/events`, evt, `${lb.allocation.number}: ${evt.present ? "present" : "absent"} at ${lb.events.find((e) => e.id === evt.eventId)?.name ?? "the event"} on ${evt.heldOn}`).then((ok) => { if (ok) setEvt({ ...evt, heldOn: "" }); })}>Record</Btn>
                    </div>
                  </PBody>
                </>
              ) : <PBody><div className="sub2">The prospectus names mandatory events for Paediatrics only — the Wednesday Grand Round and the Case Management Conference.</div></PBody>}
            </Panel>
          </div>
        </>
      ) : null}
    </>
  );
}
