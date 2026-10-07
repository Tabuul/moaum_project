"use client";

/**
 * The JUPEB lecture timetable (V347): the week's slots of each subject in a session and semester, for one class or for every
 * class. The JUPEB Office adds, moves and removes slots; the server refuses a class booked twice in the same hour. The
 * lecturer shown is the instructor the Office assigned on the attendance module — nothing is typed twice. Students read
 * the slots of their own subjects (and class) on their dashboard.
 */
import { useEffect, useState } from "react";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, PageHead, Panel, PBody } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { WEEKDAYS, jcall, type Slot } from "@/lib/jupeb";

interface Data { slots: Slot[]; classes: { id: string; name: string }[]; subjects: { id: string; code: string; title: string }[] }
interface Form { id: string | null; subjectId: string; classId: string; weekday: string; startsAt: string; endsAt: string; venue: string; note: string }
const EMPTY: Form = { id: null, subjectId: "", classId: "", weekday: "1", startsAt: "08:00", endsAt: "10:00", venue: "", note: "" };

export function JupebTimetable({ canWrite }: { canWrite: boolean }) {
  const [sessions, setSessions] = useState<string[]>([]);
  const [session, setSession] = useState("");
  const [semester, setSemester] = useState("1");
  const [klass, setKlass] = useState("");
  const [data, setData] = useState<Data | null>(null);
  const [form, setForm] = useState<Form | null>(null);
  const [busy, setBusy] = useState(false);
  const [tick, setTick] = useState(0);
  useEffect(() => {
    let live = true;
    void jcall<{ session: string; sessions: { session: string }[] }>("/api/v1/jupeb/office/dashboard").then((r) => {
      if (live && r.ok) { setSessions(r.data.sessions.map((x) => x.session)); setSession((s) => s || r.data.session); }
    });
    return () => { live = false; };
  }, []);
  useEffect(() => {
    if (!session) return;
    let live = true;
    void jcall<Data>(`/api/v1/jupeb/office/timetable?session=${encodeURIComponent(session)}&semester=${semester}`).then((r) => {
      if (!live) return;
      if (r.ok) setData(r.data); else notifyProblem(r.problem);
    });
    return () => { live = false; };
  }, [session, semester, tick]);

  const rows = (data?.slots ?? []).filter((x) => !klass || !x.class_id || x.class_id === klass);
  async function save() {
    if (!form) return;
    setBusy(true);
    try {
      const body = { session, semester: Number(semester), classId: form.classId || null, subjectId: form.subjectId, weekday: Number(form.weekday), startsAt: form.startsAt, endsAt: form.endsAt,
        venue: form.venue.trim() || null, note: form.note.trim() || null };
      const r = form.id ? await jcall(`/api/v1/jupeb/office/timetable/${form.id}`, "PUT", body) : await jcall("/api/v1/jupeb/office/timetable", "POST", body);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(form.id ? "The slot is moved." : "The slot is on the timetable.");
      setForm(null);
      setTick((t) => t + 1);
    } finally { setBusy(false); }
  }
  async function remove(x: Slot) {
    if (!window.confirm(`Remove ${x.code} on ${WEEKDAYS[x.weekday]} ${x.starts_at}–${x.ends_at}?`)) return;
    const r = await jcall(`/api/v1/jupeb/office/timetable/${x.id}/remove`, "POST", {});
    if (r.ok) { notify("The slot is removed."); setTick((t) => t + 1); } else notifyProblem(r.problem);
  }
  const heads = ["Day", "Time", "Subject", "Class", "Venue", "Lecturer", "Note"];
  const cells = rows.map((x) => [WEEKDAYS[x.weekday], `${x.starts_at}–${x.ends_at}`, `${x.code} ${x.title}`, x.class_name ?? "All classes", x.venue ?? "", x.instructors ?? "", x.note ?? ""]);
  const title = `JUPEB lecture timetable — ${session}, ${semester === "1" ? "first" : "second"} semester`;
  const className = data?.classes.find((c) => c.id === klass)?.name;
  async function excel() {
    downloadBlob(await brandedXlsx(title, heads, cells, { sheetName: "Timetable", serial: docSerial("JUPEBTT"), meta: className ? [["Class", className]] : [] }),
      `jupeb-timetable-${session.replace("/", "-")}-sem${semester}.xlsx`);
  }
  return (
    <>
      <PageHead title="JUPEB timetable" description="The week's lectures of each JUPEB subject, for a class or for every class. A class is never booked twice in the same hour; the lecturer is the instructor assigned on Attendance."
        actions={<span className="row">
          <select className="ctl" aria-label="Session" value={session} onChange={(e) => setSession(e.target.value)}>{sessions.map((x) => <option key={x}>{x}</option>)}</select>
          <select className="ctl" aria-label="Semester" value={semester} onChange={(e) => setSemester(e.target.value)}><option value="1">First semester</option><option value="2">Second semester</option></select>
        </span>} />
      <Panel title={`${rows.length} slot${rows.length === 1 ? "" : "s"}`} right={<span className="row">
        <select className="ctl" style={{ width: 200 }} aria-label="Class" value={klass} onChange={(e) => setKlass(e.target.value)}>
          <option value="">Every class</option>{(data?.classes ?? []).map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</select>
        {rows.length ? <><Btn kind="ghost" onClick={() => void excel()}>Excel</Btn><Btn kind="ghost" onClick={() => brandedPrint(title, className ? `Class: ${className}` : "Every class", heads, cells, docSerial("JUPEBTT"))}>PDF</Btn></> : null}
        {canWrite ? <Btn kind="primary" disabled={!data?.subjects.length} onClick={() => setForm({ ...EMPTY, classId: klass })}>Add a slot</Btn> : null}
      </span>}>
        <PBody>
          {!data ? <p className="sub2">Loading…</p> : !rows.length ? <Note kind="info" title="No lectures on the timetable">{canWrite ? "Add the week's slots of each subject; the students see those of their subjects on their dashboard." : "The JUPEB Office has not published the timetable for this semester."}</Note> : (
            <DTable pageSize={0} cols={[...heads, ...(canWrite ? [""] : [])]} rows={rows.map((x, i) => [...cells[i].map((c) => c || "—"), ...(canWrite ? [
              <span key="a" className="row"><Btn kind="ghost" onClick={() => setForm({ id: x.id, subjectId: x.subject_id ?? "", classId: x.class_id ?? "", weekday: String(x.weekday), startsAt: x.starts_at, endsAt: x.ends_at, venue: x.venue ?? "", note: x.note ?? "" })}>Move</Btn>
                <Btn kind="ghost" onClick={() => void remove(x)}>Remove</Btn></span>] : [])])} />
          )}
        </PBody>
      </Panel>
      {form ? (
        <Modal title={form.id ? "Move the slot" : "Add a lecture slot"} onClose={() => setForm(null)}
          foot={<><Btn kind="ghost" onClick={() => setForm(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || !form.subjectId || form.endsAt <= form.startsAt} onClick={() => void save()}>{busy ? "Saving…" : "Save"}</Btn></>}>
          <div className="grid grid--2">
            <Field id="tt-sub" label="Subject" required><select id="tt-sub" className="ctl" value={form.subjectId} onChange={(e) => setForm({ ...form, subjectId: e.target.value })}>
              <option value="">— Choose —</option>{(data?.subjects ?? []).map((x) => <option key={x.id} value={x.id}>{x.code} — {x.title}</option>)}</select></Field>
            <Field id="tt-class" label="Class" hint="Every class, or one"><select id="tt-class" className="ctl" value={form.classId} onChange={(e) => setForm({ ...form, classId: e.target.value })}>
              <option value="">Every class</option>{(data?.classes ?? []).map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</select></Field>
            <Field id="tt-day" label="Day" required><select id="tt-day" className="ctl" value={form.weekday} onChange={(e) => setForm({ ...form, weekday: e.target.value })}>
              {WEEKDAYS.slice(1).map((d, i) => <option key={d} value={String(i + 1)}>{d}</option>)}</select></Field>
            <div className="grid grid--2">
              <Field id="tt-start" label="Starts" required><input id="tt-start" type="time" className="ctl" value={form.startsAt} onChange={(e) => setForm({ ...form, startsAt: e.target.value })} /></Field>
              <Field id="tt-end" label="Ends" required error={form.endsAt <= form.startsAt ? "After it starts" : undefined}><input id="tt-end" type="time" className="ctl" value={form.endsAt} onChange={(e) => setForm({ ...form, endsAt: e.target.value })} /></Field>
            </div>
            <Field id="tt-venue" label="Venue"><input id="tt-venue" className="ctl" maxLength={120} value={form.venue} onChange={(e) => setForm({ ...form, venue: e.target.value })} /></Field>
            <Field id="tt-note" label="Note"><input id="tt-note" className="ctl" maxLength={300} value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} /></Field>
          </div>
        </Modal>
      ) : null}
    </>
  );
}
