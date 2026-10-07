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
import { Btn, Note, PageHead, Panel, PBody, Pil, Tabs } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { WEEKDAYS, jcall, laterSessions, type Room, type Slot } from "@/lib/jupeb";
import { TimetableGrid, boardRules, cellText, printGrid } from "../TimetableGrid";

interface Unit { id: string; subject_id: string; code: string; title: string; semester: number | null; prefix: string | null }
interface Data { slots: Slot[]; classes: { id: string; name: string }[]; subjects: { id: string; code: string; title: string }[]; units?: Unit[]; rooms?: Room[]; currentSemester?: number }
interface Form { id: string | null; subjectId: string; classId: string; weekday: string; startsAt: string; endsAt: string; roomId: string; note: string; courseCode: string; practical: boolean; tell: boolean }
const EMPTY: Form = { id: null, subjectId: "", classId: "", weekday: "1", startsAt: "08:00", endsAt: "09:00", roomId: "", note: "", courseCode: "", practical: false, tell: false };
interface RoomForm { id: string | null; code: string; name: string; kind: string; capacity: string; active: boolean }

export function JupebTimetable({ canWrite }: { canWrite: boolean }) {
  const [sessions, setSessions] = useState<string[]>([]);
  const [session, setSession] = useState("");
  const [semester, setSemester] = useState("");
  const [roomForm, setRoomForm] = useState<RoomForm | null>(null);
  const [copy, setCopy] = useState<{ toSession: string; toSemester: string } | null>(null);
  const [klass, setKlass] = useState("");
  const [data, setData] = useState<Data | null>(null);
  const [form, setForm] = useState<Form | null>(null);
  const [busy, setBusy] = useState(false);
  const [tick, setTick] = useState(0);
  const [view, setView] = useState<"grid" | "list">("grid");
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
    /* the first read names the semester the calendar is in; the page opens on it */
    void jcall<Data>(`/api/v1/jupeb/office/timetable?session=${encodeURIComponent(session)}${semester ? `&semester=${semester}` : ""}`).then((r) => {
      if (!live) return;
      if (!r.ok) { notifyProblem(r.problem); return; }
      if (!semester) { setSemester(String(r.data.currentSemester ?? 1)); return; }
      setData(r.data);
    });
    return () => { live = false; };
  }, [session, semester, tick]);

  const rows = (data?.slots ?? []).filter((x) => !klass || !x.class_id || x.class_id === klass);
  async function save() {
    if (!form) return;
    setBusy(true);
    try {
      const body = { session, semester: Number(semester), classId: form.classId || null, subjectId: form.subjectId, weekday: Number(form.weekday), startsAt: form.startsAt, endsAt: form.endsAt,
        roomId: form.roomId || null, note: form.note.trim() || null, courseCode: form.practical ? null : form.courseCode.trim() || null, practical: form.practical, tell: form.tell };
      const r = form.id ? await jcall<{ told?: number }>(`/api/v1/jupeb/office/timetable/${form.id}`, "PUT", body) : await jcall<{ told?: number }>("/api/v1/jupeb/office/timetable", "POST", body);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(`${form.id ? "The slot is moved." : "The slot is on the timetable."}${r.data.told != null ? ` ${r.data.told} student${r.data.told === 1 ? " is" : "s are"} told.` : ""}`);
      setForm(null);
      setTick((t) => t + 1);
    } finally { setBusy(false); }
  }
  async function remove(x: Slot) {
    if (!window.confirm(`Remove ${x.course_code ?? x.code} on ${WEEKDAYS[x.weekday]} ${x.starts_at}–${x.ends_at}?`)) return;
    const tell = window.confirm(`Tell the students of ${x.title} that the lecture is removed? (On their dashboard and by email.)`);
    const r = await jcall<{ told?: number }>(`/api/v1/jupeb/office/timetable/${x.id}/remove`, "POST", { tell });
    if (r.ok) { notify(`The slot is removed.${r.data.told != null ? ` ${r.data.told} told.` : ""}`); setTick((t) => t + 1); } else notifyProblem(r.problem);
  }
  async function saveRoom() {
    if (!roomForm) return;
    setBusy(true);
    try {
      const body = { code: roomForm.code, name: roomForm.name.trim() || null, kind: roomForm.kind, capacity: roomForm.capacity ? Number(roomForm.capacity) : null, active: roomForm.active };
      const r = roomForm.id ? await jcall<Room[]>(`/api/v1/jupeb/office/rooms/${roomForm.id}`, "PUT", body, `JUPEB room ${roomForm.code}`) : await jcall<Room[]>("/api/v1/jupeb/office/rooms", "POST", body, `JUPEB room ${roomForm.code}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      setRoomForm(null); setTick((t) => t + 1); notify("The room is saved.");
    } finally { setBusy(false); }
  }
  async function runCopy() {
    if (!copy) return;
    setBusy(true);
    try {
      const r = await jcall<{ copied: number }>("/api/v1/jupeb/office/timetable/copy", "POST", { session, semester: Number(semester), toSession: copy.toSession, toSemester: Number(copy.toSemester) },
        `JUPEB timetable copied into ${copy.toSession} semester ${copy.toSemester}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(`${r.data.copied} lectures copied.`);
      setSession(copy.toSession); setSemester(copy.toSemester); setCopy(null); setTick((t) => t + 1);
    } finally { setBusy(false); }
  }
  const heads = ["Day", "Time", "Course", "Subject", "Class", "Venue", "Lecturer", "Note"];
  const cells = rows.map((x) => [WEEKDAYS[x.weekday], `${x.starts_at}–${x.ends_at}`, x.practical ? "Practical" : x.course_code ?? "", `${x.code} ${x.title}`, x.class_name ?? "All classes",
    x.venue ?? "", x.instructors ?? "", x.note ?? ""]);
  const rules = boardRules(rows);
  /* V354: a lecture with more students than its room holds */
  const crowded = rows.filter((x) => x.capacity != null && (x.students ?? 0) > x.capacity);
  const rooms = data?.rooms ?? [];
  /* V353: a semester's courses of the subjects on the timetable that no slot teaches yet */
  const taught = new Set(rows.map((x) => x.course_code).filter(Boolean));
  const onTimetable = new Set(rows.map((x) => x.subject_id));
  const untaught = (data?.units ?? []).filter((u) => onTimetable.has(u.subject_id) && u.semester === Number(semester) && !taught.has(u.code));
  const formUnits = form ? (data?.units ?? []).filter((u) => u.subject_id === form.subjectId) : [];
  const title = `JUPEB lecture timetable — ${session}, ${semester === "1" ? "first" : "second"} semester`;
  const className = data?.classes.find((c) => c.id === klass)?.name;
  async function excel() {
    downloadBlob(await brandedXlsx(title, heads, cells, { sheetName: "Timetable", serial: docSerial("JUPEBTT"), meta: className ? [["Class", className]] : [] }),
      `jupeb-timetable-${session.replace("/", "-")}-sem${semester}.xlsx`);
  }
  return (
    <>
      <PageHead title="JUPEB timetable" description="The week's lectures of each JUPEB subject, for a class or for every class. A room, or a class, is never booked twice in the same hour — lectures in other rooms run side by side; the lecturer is the instructor assigned on Attendance."
        actions={<span className="row">
          <select className="ctl" aria-label="Session" value={session} onChange={(e) => setSession(e.target.value)}>{sessions.map((x) => <option key={x}>{x}</option>)}</select>
          <select className="ctl" aria-label="Semester" value={semester} onChange={(e) => setSemester(e.target.value)}><option value="1">First semester</option><option value="2">Second semester</option></select>
        </span>} />
      <Panel title={`${rows.length} slot${rows.length === 1 ? "" : "s"}`} right={<span className="row">
        <select className="ctl" style={{ width: 200 }} aria-label="Class" value={klass} onChange={(e) => setKlass(e.target.value)}>
          <option value="">Every class</option>{(data?.classes ?? []).map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</select>
        {rows.length ? <><Btn kind="ghost" onClick={() => void excel()}>Excel</Btn>
          <Btn kind="ghost" onClick={() => (view === "grid" ? printGrid(rows, session, Number(semester), className ? `Class: ${className}` : "")
            : brandedPrint(title, className ? `Class: ${className}` : "Every class", heads, cells, docSerial("JUPEBTT")))}>PDF</Btn></> : null}
        {canWrite && rows.length ? <Btn kind="ghost" onClick={() => setCopy({ toSession: session, toSemester: semester === "1" ? "2" : "1" })}>Copy into…</Btn> : null}
        {canWrite ? <Btn kind="primary" disabled={!data?.subjects.length} onClick={() => setForm({ ...EMPTY, classId: klass })}>Add a slot</Btn> : null}
      </span>}>
        <PBody>
          {rows.length ? <Tabs<"grid" | "list"> look="line" value={view} onChange={setView} items={[{ id: "grid", label: "Week" }, { id: "list", label: "Slots" }]} /> : null}
          {!data ? <p className="sub2">Loading…</p> : !rows.length ? <Note kind="info" title="No lectures on the timetable">{canWrite ? "Add the week's slots of each subject; the students see those of their subjects on their dashboard." : "The JUPEB Office has not published the timetable for this semester."}</Note>
          : view === "grid" ? <TimetableGrid slots={rows} /> : (
            <DTable pageSize={0} cols={[...heads, ...(canWrite ? [""] : [])]} rows={rows.map((x, i) => [...cells[i].map((c) => c || "—"), ...(canWrite ? [
              <span key="a" className="row"><Btn kind="ghost" onClick={() => setForm({ id: x.id, subjectId: x.subject_id ?? "", classId: x.class_id ?? "", weekday: String(x.weekday), startsAt: x.starts_at, endsAt: x.ends_at, roomId: x.room_id ?? "", note: x.note ?? "", courseCode: x.course_code ?? "", practical: !!x.practical, tell: false })}>Move</Btn>
                <Btn kind="ghost" onClick={() => void remove(x)}>Remove</Btn></span>] : [])])} />
          )}
        </PBody>
      </Panel>
      {rows.length ? (
        <Panel title="The Board's rules" right={rules.short.length || rules.shortPractical.length || rules.noRoom.length || untaught.length || crowded.length ? <Pil kind="warn">To look at</Pil> : <Pil kind="ok">All met</Pil>}>
          <PBody>
            <p className="sub2">{`Every course at least three hours a week (${rules.courses} courses), every practical at least two hours (${rules.practicals} subject${rules.practicals === 1 ? "" : "s"} with practicals), every slot with its room. Two lectures in one room at the same hour are refused when entered.`}</p>
            {rules.short.length ? <Note kind="bad" title="Under three hours a week">{rules.short.map((x) => `${x.course}: ${x.hours} h`).join(" · ")}</Note> : null}
            {rules.shortPractical.length ? <Note kind="bad" title="Practicals under two hours a week">{rules.shortPractical.map((x) => `${x.subject}: ${x.hours} h`).join(" · ")}</Note> : null}
            {untaught.length ? <Note kind="info" title="Courses of the semester not on the timetable">{untaught.map((u) => `${u.code} ${u.title}`).join(" · ")}{untaught.some((u) => u.code.startsWith("MAT 004") || u.prefix === "ISS" || u.prefix === "YOR") ? " — an alternative (MAT 004A/B) or an option (ISS, YOR) needs a slot only if students take it." : ""}</Note> : null}
            {crowded.length ? <Note kind="bad" title="More students than the room holds">{crowded.map((x) => `${WEEKDAYS[x.weekday]} ${x.starts_at} ${cellText(x)}: ${x.students} students, room for ${x.capacity}`).join(" · ")}</Note> : null}
            {rules.noRoom.length ? <Note kind="bad" title="Without a room">{rules.noRoom.map((x) => `${WEEKDAYS[x.weekday]} ${x.starts_at}–${x.ends_at} ${cellText(x)}${x.note ? ` — ${x.note}` : ""}`).join(" · ")}</Note> : null}
          </PBody>
        </Panel>
      ) : null}
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
            {formUnits.length ? (
              <Field id="tt-course" label="Course" hint="The subject's course units of this semester, as the Board's syllabus lists them"><select id="tt-course" className="ctl" disabled={form.practical}
                value={form.practical ? "" : form.courseCode} onChange={(e) => setForm({ ...form, courseCode: e.target.value })}>
                <option value="">— Choose —</option>
                {formUnits.map((u) => <option key={u.id} value={u.code} disabled={u.semester != null && u.semester !== Number(semester)}>{`${u.code} — ${u.title}${u.semester != null && u.semester !== Number(semester) ? ` (${u.semester === 1 ? "first" : "second"} semester)` : ""}`}</option>)}
              </select></Field>
            ) : (
              <Field id="tt-course" label="Course code" hint="As the Board's timetable prints it, e.g. GRY 001"><input id="tt-course" className="ctl" maxLength={12} disabled={form.practical}
                value={form.practical ? "" : form.courseCode} onChange={(e) => setForm({ ...form, courseCode: e.target.value.toUpperCase() })} /></Field>
            )}
            <Field id="tt-prac" label="Practical"><div className="stack" style={{ gap: 4 }}><label className="row row--inline row--tight"><input type="checkbox" checked={form.practical}
              onChange={(e) => setForm({ ...form, practical: e.target.checked })} /> a practical of the subject (shown as PRACTICAL)</label></div></Field>
            <Field id="tt-room" label="Room" hint="From the list of rooms below; add a room there first if it is not on it"><select id="tt-room" className="ctl" value={form.roomId} onChange={(e) => setForm({ ...form, roomId: e.target.value })}>
              <option value="">— Room to confirm —</option>
              {rooms.filter((r) => r.active || r.id === form.roomId).map((r) => <option key={r.id} value={r.id}>{`${r.code}${r.name ? ` — ${r.name}` : ""}${r.capacity ? ` (${r.capacity} seats)` : ""}`}</option>)}</select></Field>
            <Field id="tt-note" label="Note"><input id="tt-note" className="ctl" maxLength={300} value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} /></Field>
            <Field id="tt-tell" label="The students"><div className="stack" style={{ gap: 4 }}><label className="row row--inline row--tight"><input type="checkbox" checked={form.tell}
              onChange={(e) => setForm({ ...form, tell: e.target.checked })} /> tell the subject&rsquo;s students (on their dashboard and by email)</label></div></Field>
          </div>
        </Modal>
      ) : null}
      <Panel title={`Rooms (${rooms.filter((r) => r.active).length})`} right={canWrite ? <Btn kind="secondary" onClick={() => setRoomForm({ id: null, code: "", name: "", kind: "LECTURE", capacity: "", active: true })}>Add a room</Btn> : null}>
        <PBody>
          <p className="sub2">The rooms and laboratories JUPEB lectures are held in. A lecture names one of these, so one room is never written two ways; a room&rsquo;s seats, when given, are weighed against the students of each lecture in it.</p>
          <DTable pageSize={0} cols={["Room", "Name", "Kind", "Seats|num", "Lectures this session|num", "State", ...(canWrite ? ["|mid"] : [])]}
            rows={rooms.map((r) => [<b key="c">{r.code}</b>, r.name ?? "—", r.kind === "LAB" ? "Laboratory" : r.kind === "HALL" ? "Hall" : r.kind === "OTHER" ? "Other" : "Lecture room",
              r.capacity ?? "—", r.lectures ?? 0, r.active ? <Pil key="s" kind="ok">In use</Pil> : <Pil key="s" kind="grey">Closed</Pil>,
              ...(canWrite ? [<Btn key="e" kind="ghost" onClick={() => setRoomForm({ id: r.id, code: r.code, name: r.name ?? "", kind: r.kind, capacity: r.capacity ? String(r.capacity) : "", active: r.active })}>Edit</Btn>] : [])])} />
        </PBody>
      </Panel>
      {roomForm ? (
        <Modal title={roomForm.id ? `Room ${roomForm.code}` : "Add a room"} onClose={() => setRoomForm(null)}
          foot={<><Btn kind="ghost" onClick={() => setRoomForm(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || !roomForm.code.trim()} onClick={() => void saveRoom()}>{busy ? "Saving…" : "Save"}</Btn></>}>
          <div className="grid grid--2">
            <Field id="rm-code" label="Code" required hint="As the timetable prints it, e.g. LR8 (spaces are dropped)"><input id="rm-code" className="ctl" maxLength={40} value={roomForm.code} onChange={(e) => setRoomForm({ ...roomForm, code: e.target.value.toUpperCase() })} /></Field>
            <Field id="rm-name" label="Name"><input id="rm-name" className="ctl" maxLength={120} placeholder="Lecture Room 8" value={roomForm.name} onChange={(e) => setRoomForm({ ...roomForm, name: e.target.value })} /></Field>
            <Field id="rm-kind" label="Kind"><select id="rm-kind" className="ctl" value={roomForm.kind} onChange={(e) => setRoomForm({ ...roomForm, kind: e.target.value })}>
              <option value="LECTURE">Lecture room</option><option value="LAB">Laboratory</option><option value="HALL">Hall</option><option value="OTHER">Other</option></select></Field>
            <Field id="rm-cap" label="Seats"><input id="rm-cap" type="number" min={1} max={5000} className="ctl" value={roomForm.capacity} onChange={(e) => setRoomForm({ ...roomForm, capacity: e.target.value })} /></Field>
            <Field id="rm-act" label="State"><select id="rm-act" className="ctl" value={roomForm.active ? "yes" : "no"} onChange={(e) => setRoomForm({ ...roomForm, active: e.target.value === "yes" })}>
              <option value="yes">In use</option><option value="no">Closed (takes no new lecture)</option></select></Field>
          </div>
        </Modal>
      ) : null}
      {copy ? (
        <Modal title={`Copy the ${semester === "1" ? "first" : "second"} semester of ${session}`} onClose={() => setCopy(null)}
          foot={<><Btn kind="ghost" onClick={() => setCopy(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || (copy.toSession === session && copy.toSemester === semester)} onClick={() => void runCopy()}>{busy ? "Copying…" : "Copy"}</Btn></>}>
          <p>Every lecture is copied into a timetable that has none yet — its day, hours, room and class. Into the other semester each course moves on to the course in the same place there (GRY 001 → GRY 003, GRY 002 → GRY 004; MAT 002 → MAT 004A, with MAT 004B noted). Look over the copy, then tell the students.</p>
          <div className="grid grid--2">
            <Field id="cp-ses" label="Into the session"><select id="cp-ses" className="ctl" value={copy.toSession} onChange={(e) => setCopy({ ...copy, toSession: e.target.value })}>
              {[session, ...laterSessions(session)].map((x) => <option key={x}>{x}</option>)}</select></Field>
            <Field id="cp-sem" label="Into the semester"><select id="cp-sem" className="ctl" value={copy.toSemester} onChange={(e) => setCopy({ ...copy, toSemester: e.target.value })}>
              <option value="1">First</option><option value="2">Second</option></select></Field>
          </div>
        </Modal>
      ) : null}
    </>
  );
}
