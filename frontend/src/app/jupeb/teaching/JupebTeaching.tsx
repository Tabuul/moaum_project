"use client";

/**
 * A lecturer's JUPEB workspace (V354): the subjects (and classes) the JUPEB Office assigned them this session; today's lectures
 * from the timetable, each opening its register; the week; the courses and their syllabus; how their students are doing in
 * attendance and practice; and notices to the students of the subjects they teach. The server decides everything shown — a
 * lecturer sees only their own subjects and students, and a notice reaches only the students of a subject they teach.
 */
import { useEffect, useState } from "react";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, PageHead, Panel, PBody, Pil, Tabs } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { day, eventDates, jcall, when, type CalendarEvent, type Slot } from "@/lib/jupeb";
import { TimetableGrid } from "../TimetableGrid";
import { SyllabusModal, UnitsBySemester, unitId, type UnitRow } from "../Syllabus";
import { LecturesDue, STATE_WORD, lectureName, type Lecture } from "../attendance/LecturesDue";
import { RegisterView } from "../attendance/JupebAttendance";
import { CoveragePanel } from "../attendance/Coverage";
import { CaSheetEditor } from "../ca/CaSheet";

interface Assignment { subject_id: string; code: string; title: string; class_id: string | null; class_name: string | null; students: number }
interface Workspace {
  session: string; semester: number; today: string; assignments: Assignment[]; week: Slot[]; lectures: Lecture[]; missed: Lecture[];
  units: (UnitRow & { id: string; subject_id: string })[]; calendar: CalendarEvent[];
}
interface Student { id: string; application_no: string; name: string; class_name: string | null; exam_no: string | null; classes: number | null; attendance_rate: number | null; verdict: string | null; attempts: number; practice_average: number | null; practice_best: number | null }
interface Notice { id: string; title: string; body: string; send_email: boolean; published_at: string; withdrawn_at: string | null; withdrawn_reason: string | null; audience_name: string; reach: number; reads: number }
type Tab = "today" | "week" | "students" | "assessment" | "courses" | "notices";

export function JupebTeaching() {
  const [w, setW] = useState<Workspace | null>(null);
  const [tab, setTab] = useState<Tab>("today");
  const [open, setOpen] = useState<string | null>(null);
  useEffect(() => {
    let live = true;
    void jcall<Workspace>("/api/v1/jupeb/teaching").then((r) => { if (live) { if (r.ok) setW(r.data); else notifyProblem(r.problem); } });
    return () => { live = false; };
  }, [open]);
  if (!w) return <Note kind="info" title="Loading your JUPEB teaching…">One moment.</Note>;
  const sem = w.semester === 2 ? "second" : "first";
  return (
    <>
      <PageHead title="JUPEB teaching" description={`Your JUPEB subjects for ${w.session}, ${sem} semester: today's lectures and their attendance, your week, your students, the courses and their syllabus, and notices to your students.`} />
      {!w.assignments.length ? <Note kind="info" title="No JUPEB subject is assigned to you this session">The JUPEB Office assigns lecturers to subjects (and classes) on its Attendance page. Once you are assigned, your subjects appear here.</Note> : (
        <>
          <KvGrid cls="grid--4" pairs={[["You teach", w.assignments.map((a) => `${a.title}${a.class_name ? ` (${a.class_name})` : ""}`).join(" · ")],
            ["Students", w.assignments.reduce((n, a) => n + Number(a.students), 0)], ["Today's lectures", w.lectures.length], ["Not yet recorded", w.missed.filter((x) => x.state === "MISSED").length]]} />
          {open ? <RegisterView id={open} onBack={() => setOpen(null)} /> : (
            <>
              <Tabs<Tab> look="line" value={tab} onChange={setTab} items={[{ id: "today", label: "Today" }, { id: "week", label: "My week" }, { id: "students", label: "My students" },
                { id: "assessment", label: "Assessment" }, { id: "courses", label: "Courses" }, { id: "notices", label: "Notices" }]} />
              {tab === "today" ? (
                <>
                  <LecturesDue session={w.session} office={false} onOpen={setOpen} />
                  {w.missed.length ? (
                    <Panel title="Earlier lectures not yet recorded">
                      <PBody>
                        <p className="sub2">Your lectures of the semester gone with no register saved. Take the attendance (a past day may be taken), or record that the lecture was not held, with the reason.</p>
                        <DTable pageSize={10} cols={["Day", "Time", "Lecture", "Class", "State"]} rows={w.missed.map((x) => [day(x.held_on), `${x.starts_at}–${x.ends_at}`, lectureName(x), x.class_name ?? "Every class",
                          <Pil key="s" kind={STATE_WORD[x.state]?.[1] ?? "grey"}>{STATE_WORD[x.state]?.[0] ?? x.state}</Pil>])} />
                        <p className="sub2 mt-2">Find each under &ldquo;The week&rdquo; or &ldquo;The semester so far&rdquo; above to take it.</p>
                      </PBody>
                    </Panel>
                  ) : null}
                  {w.calendar.length ? (
                    <Panel title="Coming up on the JUPEB calendar">
                      <PBody><DTable noPrint pageSize={0} cols={["Dates", "Event", "Deadline"]} rows={w.calendar.map((e) => [eventDates(e), e.title, e.deadline_on ? day(e.deadline_on) : "—"])} /></PBody>
                    </Panel>
                  ) : null}
                </>
              ) : null}
              {tab === "week" ? (
                <Panel title={`Your week — ${sem} semester`}>
                  <PBody>{w.week.filter((x) => x.semester === w.semester).length ? <TimetableGrid slots={w.week.filter((x) => x.semester === w.semester)} />
                    : <Note kind="info" title="Not on the timetable yet">The JUPEB Office has not put your subjects on this semester&rsquo;s timetable.</Note>}</PBody>
                </Panel>
              ) : null}
              {tab === "students" ? <MyStudents w={w} /> : null}
              {tab === "assessment" ? <Assessment w={w} /> : null}
              {tab === "courses" ? <><Courses w={w} /><CoveragePanel session={w.session} /></> : null}
              {tab === "notices" ? <Notices w={w} /> : null}
            </>
          )}
        </>
      )}
    </>
  );
}

/** the students of a subject this lecturer teaches: attendance in the subject, and practice in it */
function MyStudents({ w }: { w: Workspace }) {
  const subjects = [...new Map(w.assignments.map((a) => [a.subject_id, a])).values()];
  const [subject, setSubject] = useState(subjects[0]?.subject_id ?? "");
  const [rows, setRows] = useState<Student[] | null>(null);
  useEffect(() => {
    let live = true;
    if (subject) void jcall<Student[]>(`/api/v1/jupeb/teaching/subjects/${subject}/students`).then((r) => { if (live) { if (r.ok) setRows(r.data); else notifyProblem(r.problem); } });
    return () => { live = false; };
  }, [subject]);
  return (
    <Panel title="Your students" right={<select className="ctl" style={{ width: 260 }} aria-label="Subject" value={subject} onChange={(e) => setSubject(e.target.value)}>
      {subjects.map((a) => <option key={a.subject_id} value={a.subject_id}>{`${a.title} (${a.code})`}</option>)}</select>}>
      <PBody>
        <p className="sub2">Attendance in the subject (present or late, over the classes not excused) and practice tests in it — so a student falling behind can be seen early. Practice is never part of a result.</p>
        {!rows ? <p className="sub2">Loading…</p> : (
          <DTable pageSize={50} cols={["Application No", "Name", "Class", "Classes|num", "Attendance|num", "Practice tests|num", "Practice average|num", "Best|num"]} texts={rows.map((r) => `${r.application_no} ${r.name}`)}
            rows={rows.map((r) => [r.application_no, r.name, r.class_name ?? "—", r.classes ?? 0,
              r.attendance_rate == null ? "—" : <span key="a" style={{ color: r.verdict === "NOT_ELIGIBLE" ? "var(--bad)" : undefined }}>{`${Number(r.attendance_rate).toFixed(1)}%`}</span>,
              r.attempts, r.practice_average == null ? "—" : `${Number(r.practice_average).toFixed(1)}%`, r.practice_best == null ? "—" : `${Number(r.practice_best).toFixed(1)}%`])} />
        )}
        {subject ? <WeakTopics subject={subject} /> : null}
      </PBody>
    </Panel>
  );
}

/** V355: the assessment sheet of a subject this lecturer teaches — their classes' students; not once the office locks it */
function Assessment({ w }: { w: Workspace }) {
  const subjects = [...new Map(w.assignments.map((a) => [a.subject_id, a])).values()];
  const [subject, setSubject] = useState(subjects[0]?.subject_id ?? "");
  return (
    <Panel title="Continuous assessment" right={<select className="ctl" style={{ width: 260 }} aria-label="Subject" value={subject} onChange={(e) => setSubject(e.target.value)}>
      {subjects.map((a) => <option key={a.subject_id} value={a.subject_id}>{`${a.title} (${a.code})`}</option>)}</select>}>
      <PBody>
        <p className="sub2">Enter each student&rsquo;s score in each part of the assessment, within its maximum. Once the JUPEB Office locks the subject, the scores are final for the Board.</p>
        {subject ? <CaSheetEditor key={subject} url={`/api/v1/jupeb/teaching/ca?subject=${subject}`} saveUrl="/api/v1/jupeb/teaching/ca" canEdit /> : null}
      </PBody>
    </Panel>
  );
}

/** V355: a subject's students' practice by syllabus topic, weakest first */
function WeakTopics({ subject }: { subject: string }) {
  const [rows, setRows] = useState<{ topic_id: string; label: string; students: number; answered: number; percentage: number }[] | null>(null);
  useEffect(() => {
    let live = true;
    void jcall<{ topic_id: string; label: string; students: number; answered: number; percentage: number }[]>(`/api/v1/jupeb/teaching/topics?subject=${subject}`).then((r) => { if (live && r.ok) setRows(r.data); });
    return () => { live = false; };
  }, [subject]);
  if (!rows || !rows.length) return <p className="sub2 mt-2">No practice questions tagged to the syllabus have been answered yet, so there is no topic to show.</p>;
  return (
    <>
      <div className="eyebrow mt-3">The class&rsquo;s weakest topics in practice</div>
      <DTable pageSize={10} cols={["Topic", "Students|num", "Questions answered|num", "Right|num"]} rows={rows.map((t) => [t.label, t.students, t.answered,
        <span key="p" style={{ color: Number(t.percentage) < 50 ? "var(--bad)" : undefined }}>{`${Number(t.percentage).toFixed(1)}%`}</span>])} />
    </>
  );
}

/** the courses of the subjects this lecturer teaches, with their syllabus */
function Courses({ w }: { w: Workspace }) {
  const subjects = [...new Map(w.assignments.map((a) => [a.subject_id, a])).values()];
  const [subject, setSubject] = useState(subjects[0]?.subject_id ?? "");
  const [open, setOpen] = useState<string | null>(null);
  const units = w.units.filter((u) => u.subject_id === subject);
  return (
    <Panel title="Courses and syllabus" right={<select className="ctl" style={{ width: 260 }} aria-label="Subject" value={subject} onChange={(e) => setSubject(e.target.value)}>
      {subjects.map((a) => <option key={a.subject_id} value={a.subject_id}>{`${a.title} (${a.code})`}</option>)}</select>}>
      <PBody>
        <p className="sub2">The subject&rsquo;s course units, two in each semester, as the Board&rsquo;s syllabus lists them. Open one for its objectives and topics.</p>
        <UnitsBySemester units={units} showSubject={new Set(units.map((u) => u.board_title)).size > 1} onOpen={(u) => setOpen(unitId(u))} />
      </PBody>
      {open ? <SyllabusModal url={`/api/v1/jupeb/teaching/units/${open}/syllabus`} onClose={() => setOpen(null)} /> : null}
    </Panel>
  );
}

/** notices to the students of the subjects this lecturer teaches — on their dashboards, and by email when asked */
function Notices({ w }: { w: Workspace }) {
  const [list, setList] = useState<Notice[] | null>(null);
  const [tick, setTick] = useState(0);
  const [form, setForm] = useState({ to: "", title: "", body: "", email: true });
  const [busy, setBusy] = useState(false);
  const [withdraw, setWithdraw] = useState<{ n: Notice; reason: string } | null>(null);
  useEffect(() => {
    let live = true;
    void jcall<Notice[]>("/api/v1/jupeb/teaching/notices").then((r) => { if (live && r.ok) setList(r.data); });
    return () => { live = false; };
  }, [tick]);
  const options = w.assignments.map((a) => ({ key: `${a.subject_id}|${a.class_id ?? ""}`, label: `${a.title}${a.class_name ? ` — ${a.class_name}` : " — every class"} (${a.students} students)` }));
  const to = form.to || options[0]?.key || "";
  async function post() {
    const [subjectId, classId] = to.split("|");
    setBusy(true);
    try {
      const r = await jcall<{ reach: number }>("/api/v1/jupeb/teaching/notices", "POST", { subjectId, classId: classId || null, title: form.title.trim(), body: form.body.trim(), email: form.email },
        `JUPEB notice: ${form.title.trim()}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(`The notice reaches ${r.data.reach} student${r.data.reach === 1 ? "" : "s"}.`);
      setForm({ to, title: "", body: "", email: true }); setTick((t) => t + 1);
    } finally { setBusy(false); }
  }
  async function pull() {
    if (!withdraw) return;
    const r = await jcall(`/api/v1/jupeb/teaching/notices/${withdraw.n.id}/withdraw`, "POST", { reason: withdraw.reason.trim() }, `JUPEB notice withdrawn: ${withdraw.n.title}`);
    if (r.ok) { setWithdraw(null); setTick((t) => t + 1); notify("Withdrawn."); } else notifyProblem(r.problem);
  }
  return (
    <>
      <Panel title="A notice to your students">
        <PBody>
          <div className="grid grid--2">
            <Field id="tn-to" label="To"><select id="tn-to" className="ctl" value={to} onChange={(e) => setForm({ ...form, to: e.target.value })}>{options.map((o) => <option key={o.key} value={o.key}>{o.label}</option>)}</select></Field>
            <Field id="tn-title" label="Title" required><input id="tn-title" className="ctl" maxLength={160} value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} /></Field>
          </div>
          <Field id="tn-body" label="Notice" required><textarea id="tn-body" className="ctl" rows={4} maxLength={5000} value={form.body} onChange={(e) => setForm({ ...form, body: e.target.value })} /></Field>
          <div className="row" style={{ gap: "var(--s-2)" }}>
            <label className="row row--inline row--tight"><input type="checkbox" checked={form.email} onChange={(e) => setForm({ ...form, email: e.target.checked })} /> also by email</label>
            <Btn kind="primary" disabled={busy || !to || form.title.trim().length < 3 || form.body.trim().length < 3} onClick={() => void post()}>{busy ? "Publishing…" : "Publish"}</Btn>
          </div>
          <p className="sub2 mt-2">It appears on the students&rsquo; JUPEB dashboard at once; the JUPEB Office sees every notice. Text messages are the Office&rsquo;s to send.</p>
        </PBody>
      </Panel>
      <Panel title="Your notices">
        <PBody>
          {!list ? <p className="sub2">Loading…</p> : !list.length ? <p className="sub2">None yet.</p> : (
            <DTable pageSize={20} cols={["Published", "To", "Title", "Reaches|num", "Read|num", "", "|mid"]} rows={list.map((n) => [when(n.published_at), n.audience_name, n.title, n.reach, n.reads,
              n.withdrawn_at ? <Pil key="w" kind="grey">Withdrawn</Pil> : <Pil key="w" kind="ok">Live</Pil>,
              n.withdrawn_at ? "—" : <Btn key="x" kind="ghost" onClick={() => setWithdraw({ n, reason: "" })}>Withdraw</Btn>])} />
          )}
        </PBody>
      </Panel>
      {withdraw ? (
        <Modal title={`Withdraw "${withdraw.n.title}"`} onClose={() => setWithdraw(null)}
          foot={<><Btn kind="ghost" onClick={() => setWithdraw(null)}>Cancel</Btn><Btn kind="primary" disabled={withdraw.reason.trim().length < 5} onClick={() => void pull()}>Withdraw</Btn></>}>
          <Field id="tn-why" label="Why" required><input id="tn-why" className="ctl" maxLength={300} value={withdraw.reason} onChange={(e) => setWithdraw({ ...withdraw, reason: e.target.value })} /></Field>
        </Modal>
      ) : null}
    </>
  );
}
