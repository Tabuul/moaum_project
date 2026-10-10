"use client";

/**
 * The JUPEB session calendar (V354): the Board's published calendar for the session with the University's own JUPEB events beside
 * it, in date order — what is past, what is on, what comes next, and the deadlines. The JUPEB Office keeps it: adds, corrects and
 * removes events, marks the few the portal works from (teaching starts, the second semester starts, the Board's registration, the
 * examinations, the results), and copies a session's calendar forward as the plan of the next — a year on, planned until the
 * Board publishes its own and the Office confirms it.
 */
import { useEffect, useState } from "react";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { MARKER, day, eventDates, jcall, laterSessions, type CalendarEvent } from "@/lib/jupeb";

interface Data { session: string; sessions: string[]; currentSession: string; semester: number; today: string; events: CalendarEvent[] }
interface Form { id: string | null; startsOn: string; endsOn: string; title: string; deadlineOn: string; deadlineNote: string; source: string; marker: string; forStudents: boolean; planned: boolean }
const EMPTY: Form = { id: null, startsOn: "", endsOn: "", title: "", deadlineOn: "", deadlineNote: "", source: "SCHOOL", marker: "", forStudents: false, planned: false };

const when = (e: CalendarEvent, today: string) => {
  const end = e.ends_on ?? e.starts_on;
  return end < today ? "past" : e.starts_on <= today ? "now" : "ahead";
};

export function JupebCalendar({ canWrite }: { canWrite: boolean }) {
  const [session, setSession] = useState("");
  const [d, setD] = useState<Data | null>(null);
  const [form, setForm] = useState<Form | null>(null);
  const [copyTo, setCopyTo] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [tick, setTick] = useState(0);
  useEffect(() => {
    let live = true;
    void jcall<Data>(`/api/v1/jupeb/office/calendar${session ? `?session=${encodeURIComponent(session)}` : ""}`).then((r) => {
      if (!live) return;
      if (r.ok) { setD(r.data); if (!session) setSession(r.data.session); } else notifyProblem(r.problem);
    });
    return () => { live = false; };
  }, [session, tick]);
  if (!d) return <Note kind="info" title="Loading the calendar…">One moment.</Note>;
  const ahead = d.events.filter((e) => when(e, d.today) !== "past");
  const next = ahead[0];
  const deadlines = d.events.filter((e) => e.deadline_on && e.deadline_on >= d.today).sort((a, b) => (a.deadline_on ?? "").localeCompare(b.deadline_on ?? "")).slice(0, 4);
  const planned = d.events.some((e) => e.planned);
  const later = laterSessions(d.session).filter((x) => !d.sessions.includes(x));
  async function save() {
    if (!form) return;
    setBusy(true);
    try {
      const body = { session: d!.session, startsOn: form.startsOn, endsOn: form.endsOn || null, title: form.title.trim(), deadlineOn: form.deadlineOn || null,
        deadlineNote: form.deadlineNote.trim() || null, source: form.source, marker: form.marker || null, forStudents: form.forStudents, planned: form.planned };
      const r = form.id ? await jcall<Data>(`/api/v1/jupeb/office/calendar/${form.id}`, "PUT", body, `JUPEB calendar: ${form.title.trim()}`)
        : await jcall<Data>("/api/v1/jupeb/office/calendar", "POST", body, `JUPEB calendar: ${form.title.trim()}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      setD(r.data); setForm(null); notify("The calendar is saved.");
    } finally { setBusy(false); }
  }
  async function remove(e: CalendarEvent) {
    if (!e.id || !window.confirm(`Remove "${e.title}" from the ${d!.session} calendar?`)) return;
    const r = await jcall<Data>(`/api/v1/jupeb/office/calendar/${e.id}/remove`, "POST", {}, `JUPEB calendar: removed ${e.title}`);
    if (r.ok) { setD(r.data); notify("Removed."); } else notifyProblem(r.problem);
  }
  async function copy() {
    if (!copyTo) return;
    setBusy(true);
    try {
      const r = await jcall<Data>("/api/v1/jupeb/office/calendar/copy", "POST", { from: d!.session, to: copyTo }, `JUPEB calendar copied to ${copyTo}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      setCopyTo(null); setSession(copyTo); setTick((t) => t + 1);
      notify(`${copyTo}'s calendar is planned from ${d!.session}'s — confirm it when the Board publishes its own.`);
    } finally { setBusy(false); }
  }
  async function confirmAll() {
    const r = await jcall<Data>("/api/v1/jupeb/office/calendar/confirm", "POST", { session: d!.session }, `JUPEB calendar ${d!.session} confirmed`);
    if (r.ok) { setD(r.data); notify("The calendar is confirmed."); } else notifyProblem(r.problem);
  }
  const heads = ["Dates", "Event", "Deadline", "From"];
  const cells = d.events.map((e) => [eventDates(e), e.title, e.deadline_on ? `${day(e.deadline_on)}${e.deadline_note ? ` — ${e.deadline_note}` : ""}` : e.deadline_note ?? "", e.source === "BOARD" ? "JUPEB Board" : "University"]);
  async function excel() {
    downloadBlob(await brandedXlsx(`JUPEB calendar — ${d!.session} session`, heads, cells, { sheetName: "Calendar", serial: docSerial("JUPEBCAL") }), `jupeb-calendar-${d!.session.replace("/", "-")}.xlsx`);
  }
  return (
    <>
      <PageHead title="JUPEB calendar" description="The JUPEB Board's calendar and the University's own JUPEB events. Marked deadlines are reminded daily."
        actions={<select className="ctl" aria-label="Session" value={d.session} onChange={(e) => setSession(e.target.value)}>{d.sessions.map((x) => <option key={x}>{x}</option>)}</select>} />
      {planned ? <Note kind="info" title="A planned calendar">{`Carried forward a year. Check them against the Board's calendar for ${d.session}, then confirm.`}</Note> : null}
      <KvGrid cls="grid--4" pairs={[["Session", `${d.session}${d.session === d.currentSession ? " (current)" : ""}`], ["Semester now", d.session === d.currentSession ? (d.semester === 2 ? "Second" : "First") : "—"],
        ["Next", next ? `${next.title} · ${eventDates(next)}` : "Nothing ahead"], ["Events", d.events.length]]} />
      {deadlines.length ? (
        <Panel title="Deadlines coming up">
          <PBody>
            <DTable noPrint pageSize={0} cols={["Deadline", "For", "Note"]} rows={deadlines.map((e) => [<b key="d">{day(e.deadline_on!)}</b>, e.title, e.deadline_note ?? "—"])} />
          </PBody>
        </Panel>
      ) : null}
      <Panel title={`The ${d.session} calendar`} right={<span className="row">
        {d.events.length ? <><Btn kind="ghost" onClick={() => void excel()}>Excel</Btn>
          <Btn kind="ghost" onClick={() => brandedPrint(`JUPEB calendar for the ${d.session} session`, "The JUPEB Board's calendar and the University's own events", heads, cells, docSerial("JUPEBCAL"))}>PDF</Btn></> : null}
        {canWrite && planned ? <Btn kind="secondary" onClick={() => void confirmAll()}>Confirm the calendar</Btn> : null}
        {canWrite && d.events.length && later.length ? <Btn kind="secondary" onClick={() => setCopyTo(later[0])}>Plan the next session from this</Btn> : null}
        {canWrite ? <Btn kind="primary" onClick={() => setForm(EMPTY)}>Add an event</Btn> : null}
      </span>}>
        <PBody>
          {!d.events.length ? <Note kind="info" title="No calendar for this session">{canWrite ? "Add its events, or open the session before and plan this one from it." : "The JUPEB Office has not put this session's calendar on the record."}</Note> : (
            <DTable pageSize={0} cols={["Dates", "Event", "Deadline", "From", "", ...(canWrite ? ["|mid"] : [])]}
              rows={d.events.map((e) => {
                const w = when(e, d.today);
                return [<span key="d" style={{ whiteSpace: "nowrap", opacity: w === "past" ? 0.6 : 1 }}>{eventDates(e)}</span>,
                  <span key="t" style={{ opacity: w === "past" ? 0.6 : 1 }}>{e.title}{e.marker ? <span className="sub2">{` · ${MARKER[e.marker] ?? e.marker}`}</span> : null}</span>,
                  e.deadline_on ? `${day(e.deadline_on)}${e.deadline_note ? ` — ${e.deadline_note}` : ""}` : e.deadline_note ?? "—",
                  e.source === "BOARD" ? "JUPEB Board" : "University",
                  <span key="s" className="row" style={{ gap: 4 }}>{w === "now" ? <Pil kind="ok">On now</Pil> : w === "past" ? <Pil kind="grey">Past</Pil> : null}
                    {e.planned ? <Pil kind="warn">Planned</Pil> : null}{e.for_students ? <Pil kind="info">Students see it</Pil> : null}</span>,
                  ...(canWrite ? [<span key="a" className="row"><Btn kind="ghost" onClick={() => setForm({ id: e.id ?? null, startsOn: e.starts_on, endsOn: e.ends_on ?? "", title: e.title, deadlineOn: e.deadline_on ?? "",
                    deadlineNote: e.deadline_note ?? "", source: e.source ?? "SCHOOL", marker: e.marker ?? "", forStudents: !!e.for_students, planned: e.planned })}>Edit</Btn>
                    <Btn kind="ghost" onClick={() => void remove(e)}>Remove</Btn></span>] : [])];
              })} />
          )}
          {!d.events.some((e) => e.marker === "SEMESTER_2_STARTS") && d.events.length ? <p className="sub2 mt-2">Add the University&rsquo;s second-semester start, marked &ldquo;Second semester starts&rdquo;.</p> : null}
        </PBody>
      </Panel>
      {form ? (
        <Modal wide title={form.id ? "Edit the event" : `Add an event to ${d.session}`} onClose={() => setForm(null)}
          foot={<><Btn kind="ghost" onClick={() => setForm(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || !form.startsOn || form.title.trim().length < 3 || (!!form.endsOn && form.endsOn < form.startsOn)} onClick={() => void save()}>{busy ? "Saving…" : "Save"}</Btn></>}>
          <div className="grid grid--2">
            <Field id="ev-title" label="Event" required><input id="ev-title" className="ctl" maxLength={300} value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} /></Field>
            <Field id="ev-src" label="From"><select id="ev-src" className="ctl" value={form.source} onChange={(e) => setForm({ ...form, source: e.target.value })}><option value="BOARD">The JUPEB Board&rsquo;s calendar</option><option value="SCHOOL">The University&rsquo;s own</option></select></Field>
            <Field id="ev-start" label="From (date)" required><input id="ev-start" type="date" className="ctl" value={form.startsOn} onChange={(e) => setForm({ ...form, startsOn: e.target.value })} /></Field>
            <Field id="ev-end" label="To (date)" hint="Blank for a single day" error={form.endsOn && form.endsOn < form.startsOn ? "After it starts" : undefined}><input id="ev-end" type="date" className="ctl" value={form.endsOn} onChange={(e) => setForm({ ...form, endsOn: e.target.value })} /></Field>
            <Field id="ev-dl" label="Deadline"><input id="ev-dl" type="date" className="ctl" value={form.deadlineOn} onChange={(e) => setForm({ ...form, deadlineOn: e.target.value })} /></Field>
            <Field id="ev-dln" label="Deadline note"><input id="ev-dln" className="ctl" maxLength={300} value={form.deadlineNote} onChange={(e) => setForm({ ...form, deadlineNote: e.target.value })} /></Field>
            <Field id="ev-mark" label="The portal works from it as" hint="Only one event of a session carries each mark"><select id="ev-mark" className="ctl" value={form.marker} onChange={(e) => setForm({ ...form, marker: e.target.value })}>
              <option value="">— Nothing —</option>{Object.entries(MARKER).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field>
            <Field id="ev-flags" label="Shown"><div className="stack" style={{ gap: 4 }}>
              <label className="row row--inline row--tight"><input type="checkbox" checked={form.forStudents} onChange={(e) => setForm({ ...form, forStudents: e.target.checked })} /> to the students, on their dashboard</label>
              <label className="row row--inline row--tight"><input type="checkbox" checked={form.planned} onChange={(e) => setForm({ ...form, planned: e.target.checked })} /> as planned (not yet confirmed)</label>
            </div></Field>
          </div>
        </Modal>
      ) : null}
      {copyTo ? (
        <Modal title={`Plan ${copyTo} from ${d.session}`} onClose={() => setCopyTo(null)}
          foot={<><Btn kind="ghost" onClick={() => setCopyTo(null)}>Cancel</Btn><Btn kind="primary" disabled={busy} onClick={() => void copy()}>{busy ? "Copying…" : "Plan it"}</Btn></>}>
          <p>{`Every event of ${d.session} is copied into ${copyTo} a year on, marked planned.`}</p>
          <Field id="cp-to" label="Into"><select id="cp-to" className="ctl" value={copyTo} onChange={(e) => setCopyTo(e.target.value)}>{later.map((x) => <option key={x}>{x}</option>)}</select></Field>
        </Modal>
      ) : null}
    </>
  );
}
