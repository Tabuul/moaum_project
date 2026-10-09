"use client";

/**
 * The CCE session in operation (V380): the CCE calendar (each CCE semester's state and dates — the Centre's, opened only in the
 * CCE session), the Centre's classes in the CCE session (opened beside the full-time classes of the same courses, each with its
 * lecturer), the evening timetable (the periods the Centre configures, with the clashes still to settle), the CCE students'
 * course registration, attendance on the register, and the CCE school fees the Bursary states. Every rule is the server's.
 */
import { useEffect, useState } from "react";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { buildXlsx } from "@/lib/xlsx";
import { downloadBlob } from "@/lib/exportbrand";
import {
  ATT_LABEL, CAL_LABEL, CLASH_LABEL, REG_LABEL, VERDICT_LABEL, WEEKDAYS, ccall, day, labelOf, naira, semesterWord, when,
  type AttendanceView, type CalendarSemester, type CalendarView, type CceClass, type ClassesView, type Period, type RegistrationsView,
  type SchoolFeesView, type TimetableView,
} from "@/lib/cce";
import { cceSend } from "./CceDesk";
import type { TabProps } from "./CceList";

const q = (s: string) => encodeURIComponent(s);

/** a small loader every screen here shares */
function useLoad<T>(url: string | null, tick: number): T | null {
  const [data, setData] = useState<T | null>(null);
  useEffect(() => {
    if (!url) return;
    let live = true;
    void ccall<T>(url).then((r) => { if (!live) return; if (r.ok) setData(r.data); else notifyProblem(r.problem); });
    return () => { live = false; };
  }, [url, tick]);
  return data;
}

function SemesterPick({ value, onChange, all }: { value: number | null; onChange: (n: number | null) => void; all?: boolean }) {
  return (
    <select className="ctl" style={{ width: 170 }} aria-label="Semester" value={value ?? ""} onChange={(e) => onChange(e.target.value ? Number(e.target.value) : null)}>
      {all ? <option value="">Every semester</option> : null}
      <option value="1">First semester</option><option value="2">Second semester</option><option value="3">Third semester</option>
    </select>
  );
}

/* ── the CCE calendar ───────────────────────────────────────────────────────────────────────────────────────────── */

type CalForm = { number: number; state: string; lecturesFrom: string; lecturesTo: string; registrationOpens: string; registrationCloses: string;
  lateRegistrationCloses: string; examsFrom: string; examsTo: string; note: string; reason: string; existing: boolean };

interface LoadRow { level: number; applies_to: string; university_min: number; university_max: number; university_probation_max: number | null; cce_min: number | null; cce_max: number | null;
  cce_probation_max: number | null; instrument: string | null; updated_at: string | null; updated_by_name: string | null }

export function CceCalendar({ session, powers, pick }: TabProps) {
  const [tick, setTick] = useState(0);
  const v = useLoad<CalendarView>(`/api/v1/cce/calendar?session=${q(session)}`, tick);
  const loads = useLoad<LoadRow[]>("/api/v1/cce/course-load", tick);
  const [form, setForm] = useState<CalForm | null>(null);
  const [load, setLoad] = useState<{ level: number; min: string; max: string; probation: string; instrument: string } | null>(null);
  if (!v) return <Note kind="info" title="Reading the CCE calendar…">One moment.</Note>;
  async function saveLoad() {
    if (!load) return;
    const out = await cceSend(`/course-load/${load.level}`, "PUT", { minUnits: load.min ? Number(load.min) : null, maxUnits: load.max ? Number(load.max) : null,
      probationMaxUnits: load.probation ? Number(load.probation) : null, instrument: load.instrument.trim() || null },
      load.min || load.max ? `CCE course load at ${load.level} level: ${load.min}–${load.max} units` : `CCE course load at ${load.level} level withdrawn`);
    if (out) { setLoad(null); setTick((x) => x + 1); }
  }
  const edit = (s: CalendarSemester) => setForm({
    number: s.number, state: s.state === "NOT_SET" ? "NOT_YET_OPEN" : s.state, lecturesFrom: s.lectures_from ?? "", lecturesTo: s.lectures_to ?? "",
    registrationOpens: s.registration_opens ?? "", registrationCloses: s.registration_closes ?? "", lateRegistrationCloses: s.late_registration_closes ?? "",
    examsFrom: s.exams_from ?? "", examsTo: s.exams_to ?? "", note: s.note ?? "", reason: "", existing: !!s.id,
  });
  async function save() {
    if (!form) return;
    const body = { state: form.state, lecturesFrom: form.lecturesFrom || null, lecturesTo: form.lecturesTo || null, registrationOpens: form.registrationOpens || null,
      registrationCloses: form.registrationCloses || null, lateRegistrationCloses: form.lateRegistrationCloses || null, examsFrom: form.examsFrom || null,
      examsTo: form.examsTo || null, note: form.note.trim() || null, reason: form.reason.trim() || null };
    // a session in the path is two segments (2025/2026), as the API reads it
    const out = await cceSend(`/calendar/${v!.session}/${form.number}`, "PUT", body, `CCE ${v!.session} ${semesterWord(form.number).toLowerCase()}: ${labelOf(CAL_LABEL, form.state)[0].toLowerCase()}`);
    if (out) { setForm(null); setTick((t) => t + 1); }
  }
  const dateField = (id: string, label: string, key: keyof CalForm) => (
    <Field id={id} label={label}><input id={id} type="date" className="ctl" value={String(form?.[key] ?? "")} onChange={(e) => form && setForm({ ...form, [key]: e.target.value })} /></Field>
  );
  return (
    <>
      <PageHead title="CCE calendar" description={`The Centre's own calendar for ${v.session}: when each CCE semester's lectures, registration and examinations run. A CCE student's registration opens by this calendar — never by the full-time calendar of the same session — and a semester opens only in the CCE session (${v.cceSession}).`} actions={pick} />
      <Note kind={v.session === v.cceSession ? "ok" : "info"} title={`CCE session ${v.cceSession} · undergraduate ${v.undergraduateSession ?? "—"}`}>
        {v.session === v.cceSession ? "You are setting the current CCE session." : `You are looking at ${v.session}; a semester opens only in the CCE session.`}{" "}
        The Directorate of ICT can also hold the CCE registration and CCE school-fees windows on Portal Windows; while it has set one, that window decides.
      </Note>
      <div className="grid grid--3">
        {v.semesters.map((s) => {
          const [word, kind] = labelOf(CAL_LABEL, s.state);
          return (
            <Panel key={s.number} title={semesterWord(s.number)} right={<Pil kind={kind}>{word}</Pil>}>
              <PBody>
                <KvGrid cls="grid--2" pairs={[
                  ["Lectures", s.lectures_from ? `${day(s.lectures_from)} – ${day(s.lectures_to)}` : "—"],
                  ["Registration", s.registration_opens || s.registration_closes ? `${day(s.registration_opens)} – ${day(s.registration_closes)}` : "—"],
                  ["Late registration until", day(s.late_registration_closes)],
                  ["Examinations", s.exams_from ? `${day(s.exams_from)} – ${day(s.exams_to)}` : "—"],
                  ["Classes", s.classes], ["Registered", s.registered],
                  ["CCE registration window", s.window_configured ? `${s.window_state.toLowerCase()}${s.window_closes ? ` · closes ${when(s.window_closes)}` : ""}` : "not set by ICT — the calendar decides"],
                  ["Last set", s.updated_at ? `${when(s.updated_at)}${s.updated_by_name ? ` · ${s.updated_by_name}` : ""}` : "—"],
                ]} />
                {s.note ? <div className="sub2 mt-1">{s.note}</div> : null}
                {powers.decide ? <div className="mt-2"><Btn kind={s.id ? "ghost" : "primary"} onClick={() => edit(s)}>{s.id ? "Change" : "Set this semester"}</Btn></div> : null}
              </PBody>
            </Panel>
          );
        })}
      </div>
      <Panel title="CCE course load" right={<Pil kind="info">The Academic Office&rsquo;s</Pil>}>
        <PBody><div className="sub2">The units a CCE student registers within at each level. A part-time student usually carries less than the full-time range; until the Academic Office states the CCE load for a level, the University&rsquo;s range applies to CCE students too.</div></PBody>
        {loads ? (
          <DTable noPrint cols={["Level|num", "The University's range|mid", "CCE (part-time)|mid", "Instrument", ""]} rows={loads.map((l) => [
            l.level, <span key="u" className="tnum">{l.university_min}–{l.university_max}{l.university_probation_max != null ? ` · probation ${l.university_probation_max}` : ""}</span>,
            l.cce_min != null ? <b key="c" className="tnum">{l.cce_min}–{l.cce_max}{l.cce_probation_max != null ? ` · probation ${l.cce_probation_max}` : ""}</b> : <span key="c" className="sub2">the University&rsquo;s applies</span>,
            <span key="i" className="sub2">{l.instrument ?? "—"}{l.updated_at ? ` · ${when(l.updated_at)}` : ""}</span>,
            powers.academic ? <Btn key="e" kind="ghost" onClick={() => setLoad({ level: l.level, min: l.cce_min != null ? String(l.cce_min) : "", max: l.cce_max != null ? String(l.cce_max) : "", probation: l.cce_probation_max != null ? String(l.cce_probation_max) : "", instrument: l.instrument ?? "" })}>{l.cce_min != null ? "Change" : "State"}</Btn> : <span key="e" />,
          ])} />
        ) : null}
      </Panel>
      {load ? (
        <Modal title={`CCE course load at ${load.level} level`} sub="Blank minimum and maximum: the University's range applies again" onClose={() => setLoad(null)}
          foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setLoad(null)}>Back</Btn><Btn kind="primary" onClick={() => void saveLoad()}>Save</Btn></span>}>
          <div className="grid grid--3">
            <Field id="ld-min" label="Minimum units"><input id="ld-min" className="ctl tnum" inputMode="numeric" value={load.min} onChange={(e) => setLoad({ ...load, min: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
            <Field id="ld-max" label="Maximum units"><input id="ld-max" className="ctl tnum" inputMode="numeric" value={load.max} onChange={(e) => setLoad({ ...load, max: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
            <Field id="ld-prob" label="On probation, at most"><input id="ld-prob" className="ctl tnum" inputMode="numeric" value={load.probation} onChange={(e) => setLoad({ ...load, probation: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
          </div>
          <Field id="ld-ins" label="Instrument" hint="The Senate or Academic Board minute that approved it"><input id="ld-ins" className="ctl" value={load.instrument} onChange={(e) => setLoad({ ...load, instrument: e.target.value })} /></Field>
        </Modal>
      ) : null}
      <Note kind={v.feesWindow.state === "OPEN" ? "ok" : "bad"} title={`CCE school-fees payment for ${v.session}: ${v.feesWindow.state.toLowerCase()}`}>
        {v.feesWindow.configured ? `Set by the Directorate of ICT${v.feesWindow.closes_at ? `, closing ${when(v.feesWindow.closes_at)}` : ""}.${v.feesWindow.reason ? ` ${v.feesWindow.reason}` : ""}` : "Open by default: a CCE student pays against the CCE fee lines the Bursary states."}
      </Note>
      {form ? (
        <Modal title={`${semesterWord(form.number)} of ${v.session}`} sub="The CCE calendar" onClose={() => setForm(null)}
          foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setForm(null)}>Back</Btn><Btn kind="primary" onClick={() => void save()}>Save</Btn></span>}>
          <Field id="cal-state" label="State">
            <select id="cal-state" className="ctl" value={form.state} onChange={(e) => setForm({ ...form, state: e.target.value })}>
              <option value="NOT_YET_OPEN">Not yet open</option><option value="OPEN">Open</option><option value="CLOSED">Closed</option>
            </select>
          </Field>
          <div className="grid grid--3">
            {dateField("cal-ro", "Registration opens", "registrationOpens")}{dateField("cal-rc", "Registration closes", "registrationCloses")}{dateField("cal-lc", "Late registration until", "lateRegistrationCloses")}
            {dateField("cal-lf", "Lectures from", "lecturesFrom")}{dateField("cal-lt", "Lectures to", "lecturesTo")}<span />
            {dateField("cal-ef", "Examinations from", "examsFrom")}{dateField("cal-et", "Examinations to", "examsTo")}<span />
          </div>
          <Field id="cal-note" label="Note"><input id="cal-note" className="ctl" value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} /></Field>
          {form.existing ? <Field id="cal-reason" label="Reason for the change" required><textarea id="cal-reason" className="ctl" rows={2} value={form.reason} onChange={(e) => setForm({ ...form, reason: e.target.value })} /></Field> : null}
          <div className="sub2">Registration is open while the semester is open, from the opening date to the late-registration date (or the closing date).</div>
        </Modal>
      ) : null}
    </>
  );
}

/* ── the Centre's classes ───────────────────────────────────────────────────────────────────────────────────────── */

interface LecturerOpt { id: string; name: string; staff_number: string | null; departments: string | null; cce_classes: number }
interface CourseOpt { code: string; title: string; units: number; level: number; semester: number; department: string | null }

export function CceClasses({ session, powers, pick }: TabProps) {
  const [semester, setSemester] = useState<number | null>(null);
  const [tick, setTick] = useState(0);
  const v = useLoad<ClassesView>(`/api/v1/cce/classes?session=${q(session)}${semester ? `&semester=${semester}` : ""}`, tick);
  const [teach, setTeach] = useState<CceClass | null>(null);
  const [lq, setLq] = useState("");
  const [lecturers, setLecturers] = useState<LecturerOpt[]>([]);
  const [lead, setLead] = useState(""); const [second, setSecond] = useState(""); const [overload, setOverload] = useState(false);
  const [adding, setAdding] = useState(false); const [cq, setCq] = useState(""); const [courses, setCourses] = useState<CourseOpt[]>([]); const [addSem, setAddSem] = useState(1);
  const [withdraw, setWithdraw] = useState<CceClass | null>(null); const [why, setWhy] = useState("");
  const [openSem, setOpenSem] = useState(1);

  useEffect(() => {
    if (!teach) return;
    let live = true;
    const t = setTimeout(() => { void ccall<LecturerOpt[]>(`/api/v1/cce/lecturers?session=${q(session)}${lq.trim() ? `&q=${q(lq.trim())}` : ""}`).then((r) => { if (live && r.ok) setLecturers(r.data); }); }, 250);
    return () => { live = false; clearTimeout(t); };
  }, [teach, lq, session]);
  useEffect(() => {
    if (!adding || cq.trim().length < 2) return;
    let live = true;
    const t = setTimeout(() => { void ccall<CourseOpt[]>(`/api/v1/cce/courses?q=${q(cq.trim())}`).then((r) => { if (live && r.ok) setCourses(r.data); }); }, 250);
    return () => { live = false; clearTimeout(t); };
  }, [adding, cq]);
  if (!v) return <Note kind="info" title="Reading the Centre's classes…">One moment.</Note>;

  async function openAll() {
    const out = await cceSend<ClassesView>("/classes/open", "POST", { session, semester: openSem }, `The Centre's classes for ${session} ${semesterWord(openSem).toLowerCase()} opened`);
    if (out) { notify(out.opened ? `${out.opened} class${out.opened === 1 ? "" : "es"} opened` : "Every class the semester needs was open already."); setTick((t) => t + 1); }
  }
  async function saveTeaching() {
    if (!teach || !lead) return;
    const out = await cceSend(`/classes/${teach.id}/teaching`, "PUT", { lecturerId: lead, secondExaminerId: second || null, overload }, `${teach.course_code}: lecturer allocated`);
    if (out) { setTeach(null); setTick((t) => t + 1); }
  }
  async function add(c: CourseOpt) {
    const out = await cceSend("/classes", "POST", { course: c.code, session, semester: addSem }, `${c.code} added as a CCE class in ${session}`);
    if (out) { setAdding(false); setCq(""); setCourses([]); setTick((t) => t + 1); }
  }
  async function doWithdraw() {
    if (!withdraw || !why.trim()) return;
    const out = await cceSend(`/classes/${withdraw.id}/withdraw`, "POST", { reason: why.trim() }, `${withdraw.course_code}: CCE class withdrawn`);
    if (out) { setWithdraw(null); setWhy(""); setTick((t) => t + 1); }
  }
  const rows = v.classes;
  const exportXlsx = () => downloadBlob(buildXlsx(["Course", "Title", "Units", "Level", "Semester", "Department", "Faculty", "Programmes", "Lecturer", "Second examiner", "Registered", "Slots"],
    rows.map((c) => [c.course_code, c.title, c.units, c.level, c.semester, c.department ?? "", c.faculty ?? "", c.programmes ?? "", c.lecturer ?? "", c.second_examiner ?? "", c.registered,
      c.slots.map((s) => `${WEEKDAYS[s.weekday]} ${s.starts_at}–${s.ends_at} ${s.venue}`).join("; ")]), "CCE classes"), `cce-classes-${session.replace("/", "-")}.xlsx`);

  return (
    <>
      <PageHead title="CCE classes" description={`The Centre's classes in ${session}: each course its CCE programmes offer (and each carry-over its students owe), a class of its own beside the full-time class of the same course — so CCE registration, attendance and, later, the score sheets stay apart from the full-time students'.`}
        actions={<span className="row row--inline row--tight">{pick}<SemesterPick all value={semester} onChange={setSemester} /></span>} />
      {v.session !== v.cceSession ? <Note kind="info" title={`The CCE session is ${v.cceSession}`}>Classes are opened in the CCE session and the one after it.</Note> : null}
      {!v.programmesOnRoute ? <Note kind="bad" title="No programme is offered on CCE yet">The Academic Office offers programmes on the route first (CCE programmes); the classes follow from them.</Note> : null}
      {powers.decide ? (
        <Panel title="Open the classes of a semester" right={<span className="row row--inline row--tight"><SemesterPick value={openSem} onChange={(n) => setOpenSem(n ?? 1)} /><Btn kind="primary" onClick={() => void openAll()}>Open the classes</Btn><Btn kind="ghost" onClick={() => setAdding(true)}>Add one class</Btn></span>}>
          <PBody><div className="sub2">Opens a class for every course the CCE programmes offer in that semester, and every carry-over a CCE student owes from it. A class already open stays as it is.</div></PBody>
        </Panel>
      ) : null}
      <Panel title={`${rows.length} class${rows.length === 1 ? "" : "es"} · ${semesterWord(semester)}`} right={<Btn kind="secondary" disabled={!rows.length} onClick={exportXlsx}>Excel</Btn>}>
        {rows.length ? (
          <DTable cols={["Course", "Level|num", "Programmes", "Lecturer", "Timetable", "Registered|num", "Registers|num", ""]} texts={rows.map((c) => `${c.course_code} ${c.title} ${c.lecturer ?? ""} ${c.department ?? ""}`)} rows={rows.map((c) => [
            <span key="c"><b className="tnum">{c.course_code}</b> {c.title}<div className="sub2">{c.units} units · {semesterWord(c.semester).toLowerCase()} · {c.department ?? c.dept_code}</div></span>,
            c.level, <span key="p" className="sub2">{c.programmes ?? "—"}</span>,
            c.lecturer ? <span key="l">{c.lecturer}{c.second_examiner ? <div className="sub2">2nd: {c.second_examiner}</div> : null}</span> : <Pil key="l" kind="warn">No lecturer</Pil>,
            c.slots.length ? <span key="t" className="sub2">{c.slots.map((s) => `${WEEKDAYS[s.weekday].slice(0, 3)} ${s.starts_at}–${s.ends_at}, ${s.venue}`).join("; ")}</span> : <span key="t" className="sub2">not on the timetable</span>,
            <span key="r">{c.registered}{c.drafted ? <div className="sub2">{c.drafted} on drafts</div> : null}</span>, c.registers,
            powers.decide ? <span key="a" className="row row--inline row--tight row--end"><Btn kind="ghost" onClick={() => { setTeach(c); setLead(c.lecturer_id ?? ""); setSecond(c.second_examiner_id ?? ""); setOverload(false); setLq(""); }}>Lecturer</Btn>
              {!c.registered && !c.drafted && !c.registers ? <Btn kind="ghost" onClick={() => setWithdraw(c)}>Withdraw</Btn> : null}</span> : <span key="a" />,
          ])} />
        ) : <PBody><div className="sub2">No CCE class is open for {session}{semester ? ` in the ${semesterWord(semester).toLowerCase()}` : ""}.</div></PBody>}
      </Panel>
      {teach ? (
        <Modal title={`${teach.course_code}: the lecturer`} sub={`${teach.title} · ${session}`} onClose={() => setTeach(null)}
          foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setTeach(null)}>Back</Btn><Btn kind="primary" disabled={!lead} onClick={() => void saveTeaching()}>Allocate</Btn></span>}>
          <Field id="tl-q" label="Find a lecturer" hint="Anyone holding a lecturer's or a Head of Department's post today"><input id="tl-q" className="ctl" value={lq} onChange={(e) => setLq(e.target.value)} placeholder="Surname, name or staff number" /></Field>
          <Field id="tl-lead" label="Lecturer">
            <select id="tl-lead" className="ctl" value={lead} onChange={(e) => setLead(e.target.value)}>
              <option value="">Choose…</option>
              {teach.lecturer_id && !lecturers.some((l) => l.id === teach.lecturer_id) ? <option value={teach.lecturer_id}>{teach.lecturer} (now)</option> : null}
              {lecturers.map((l) => <option key={l.id} value={l.id}>{l.name}{l.staff_number ? ` · ${l.staff_number}` : ""}{l.departments ? ` · ${l.departments}` : ""}{l.cce_classes ? ` · ${l.cce_classes} CCE class${l.cce_classes === 1 ? "" : "es"}` : ""}</option>)}
            </select>
          </Field>
          <Field id="tl-second" label="Second examiner" hint="Optional; never the lecturer">
            <select id="tl-second" className="ctl" value={second} onChange={(e) => setSecond(e.target.value)}>
              <option value="">None</option>
              {teach.second_examiner_id && !lecturers.some((l) => l.id === teach.second_examiner_id) ? <option value={teach.second_examiner_id}>{teach.second_examiner} (now)</option> : null}
              {lecturers.filter((l) => l.id !== lead).map((l) => <option key={l.id} value={l.id}>{l.name}{l.staff_number ? ` · ${l.staff_number}` : ""}</option>)}
            </select>
          </Field>
          <label className="row row--inline row--tight"><input type="checkbox" checked={overload} onChange={(e) => setOverload(e.target.checked)} /> Allocate as an overload if it takes the lecturer over 12 units of CCE classes this semester</label>
        </Modal>
      ) : null}
      {adding ? (
        <Modal title="Add a CCE class" sub={session} onClose={() => setAdding(false)} foot={<Btn kind="ghost" onClick={() => setAdding(false)}>Close</Btn>}>
          <div className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
            <Field id="ac-q" label="Course" hint="Code or title"><input id="ac-q" className="ctl" value={cq} onChange={(e) => setCq(e.target.value)} /></Field>
            <Field id="ac-sem" label="Semester"><SemesterPick value={addSem} onChange={(n) => setAddSem(n ?? 1)} /></Field>
          </div>
          {courses.length ? (
            <DTable noPrint cols={["Course", "Level|num", "Department", ""]} rows={courses.map((c) => [
              <span key="c"><b className="tnum">{c.code}</b> {c.title}<div className="sub2">{c.units} units · usually {semesterWord(c.semester).toLowerCase()}</div></span>, c.level, c.department ?? "—",
              <Btn key="a" kind="primary" onClick={() => void add(c)}>Add</Btn>,
            ])} />
          ) : <div className="sub2">Type two letters of a code or title.</div>}
        </Modal>
      ) : null}
      {withdraw ? (
        <Modal title={`Withdraw ${withdraw.course_code}`} sub="Only a class nobody has used is withdrawn" onClose={() => setWithdraw(null)}
          foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setWithdraw(null)}>Back</Btn><Btn kind="urgent" disabled={!why.trim()} onClick={() => void doWithdraw()}>Withdraw it</Btn></span>}>
          <Field id="wd-why" label="Reason" required><textarea id="wd-why" className="ctl" rows={2} value={why} onChange={(e) => setWhy(e.target.value)} /></Field>
        </Modal>
      ) : null}
    </>
  );
}

/* ── the evening timetable ──────────────────────────────────────────────────────────────────────────────────────── */

export function CceTimetable({ session, powers, pick }: TabProps) {
  const [semester, setSemester] = useState(1);
  const [tick, setTick] = useState(0);
  const v = useLoad<TimetableView>(`/api/v1/cce/timetable?session=${q(session)}&semester=${semester}`, tick);
  const classes = useLoad<ClassesView>(`/api/v1/cce/classes?session=${q(session)}&semester=${semester}`, tick);
  const [slot, setSlot] = useState<{ offering: string; weekday: string; starts: string; ends: string; venue: string; kind: string } | null>(null);
  const [period, setPeriod] = useState<{ id: string | null; label: string; starts: string; ends: string; active: boolean; ord: string } | null>(null);
  const [saving, setSaving] = useState(false);
  if (!v) return <Note kind="info" title="Reading the evening timetable…">One moment.</Note>;

  async function addSlot() {
    if (!slot || !slot.offering || saving) return;
    const c = classes?.classes.find((x) => x.id === slot.offering);
    setSaving(true);
    const out = await cceSend<TimetableView>(`/classes/${slot.offering}/slots`, "POST", { weekday: Number(slot.weekday), startsAt: slot.starts, endsAt: slot.ends, venue: slot.venue.trim(), kind: slot.kind },
      `${c?.course_code ?? "The class"}: ${WEEKDAYS[Number(slot.weekday)]} ${slot.starts}–${slot.ends} at ${slot.venue.trim()}`).finally(() => setSaving(false));
    if (out) { setSlot(null); setTick((t) => t + 1); }
  }
  async function endSlot(offering: string, id: string, label: string) {
    const out = await cceSend(`/classes/${offering}/slots/${id}/end`, "POST", {}, `${label} taken off the timetable`);
    if (out) setTick((t) => t + 1);
  }
  async function savePeriod() {
    if (!period) return;
    const out = await cceSend("/periods", "PUT", { id: period.id, label: period.label.trim(), startsAt: period.starts, endsAt: period.ends, active: period.active, ord: period.ord ? Number(period.ord) : null },
      `CCE period ${period.label.trim()} saved`);
    if (out) { setPeriod(null); setTick((t) => t + 1); }
  }
  const byDay = [1, 2, 3, 4, 5, 6, 7].map((d) => ({ d, slots: v.slots.filter((s) => s.weekday === d) })).filter((x) => x.slots.length);
  const exportXlsx = () => downloadBlob(buildXlsx(["Day", "Start", "End", "Course", "Title", "Lecturer", "Venue", "Kind", "Programmes", "Department", "Faculty", "Session", "Semester"],
    v.slots.map((s) => [WEEKDAYS[s.weekday], s.starts_at, s.ends_at, s.course_code, s.title, s.lecturer ?? "", s.venue, s.kind, s.programmes ?? "", s.department ?? "", s.faculty ?? "", v.session, v.semester]),
    "CCE timetable"), `cce-timetable-${session.replace("/", "-")}-s${semester}.xlsx`);
  const activePeriods = v.periods.filter((p) => p.active);

  return (
    <>
      <PageHead title="CCE evening timetable" description={`The evening lectures of the Centre's classes in ${session}: the day, the time, the venue and the lecturer. The periods below are quick picks the Centre configures; a lecture may be at any time. No venue or lecturer is in two CCE classes at once.`}
        actions={<span className="row row--inline row--tight">{pick}<SemesterPick value={semester} onChange={(n) => setSemester(n ?? 1)} /></span>} />
      <Tiles cls="grid--4" items={[
        ["LECTURES A WEEK", v.slots.length, null, `${semesterWord(semester)} of ${session}`],
        ["CLASSES NOT TIMETABLED", v.unscheduled.length, v.unscheduled.length ? "var(--amber-ink)" : null, v.unscheduled.slice(0, 4).map((u) => u.course_code).join(", ") || "Every class has a lecture"],
        ["CLASHES TO SETTLE", v.clashes.length, v.clashes.length ? "var(--red-ink)" : "var(--green-ink)", v.clashes.length ? "Listed below" : "None"],
        ["PERIODS", activePeriods.length, null, activePeriods.map((p) => p.label).join(" · ") || "None configured"],
      ]} />
      <Panel title="The week" right={<span className="row row--inline row--tight">{powers.decide ? <Btn kind="primary" onClick={() => setSlot({ offering: v.unscheduled[0]?.id ?? classes?.classes[0]?.id ?? "", weekday: "1", starts: activePeriods[0]?.starts_at ?? "16:00", ends: activePeriods[0]?.ends_at ?? "18:00", venue: "", kind: "LECTURE" })}>Add a lecture</Btn> : null}<Btn kind="secondary" disabled={!v.slots.length} onClick={exportXlsx}>Excel</Btn></span>}>
        {byDay.length ? (
          <DTable pageSize={0} cols={["Day", "Time|mid", "Course", "Lecturer", "Venue", "Programmes", ""]} rows={byDay.flatMap((d) => d.slots.map((s, i) => [
            i === 0 ? <b key="d">{WEEKDAYS[d.d]}</b> : <span key="d" />, <span key="t" className="tnum">{s.starts_at}–{s.ends_at}</span>,
            <span key="c"><b className="tnum">{s.course_code}</b> {s.title}<div className="sub2">{s.kind.toLowerCase()} · {s.department ?? s.dept_code}</div></span>,
            s.lecturer ?? <Pil key="l" kind="warn">No lecturer</Pil>, s.venue, <span key="p" className="sub2">{s.programmes ?? "—"}</span>,
            powers.decide ? <Btn key="e" kind="ghost" onClick={() => void endSlot(s.offering_id, s.id, `${s.course_code} ${WEEKDAYS[s.weekday]} ${s.starts_at}`)}>Remove</Btn> : <span key="e" />,
          ]))} />
        ) : <PBody><div className="sub2">No lecture is on the CCE timetable for this semester yet.</div></PBody>}
      </Panel>
      {v.clashes.length ? (
        <Panel title="Clashes to settle" right={<Pil kind="bad">{v.clashes.length}</Pil>}>
          <DTable cols={["Kind", "When|mid", "Classes", "Detail"]} rows={v.clashes.map((c, i) => [
            <span key={`k${i}`}>{CLASH_LABEL[c.kind] ?? c.kind}</span>, <span key="w" className="tnum">{WEEKDAYS[c.weekday]} {c.starts_at}–{c.ends_at}</span>, `${c.first_course} · ${c.second_course}`, <span key="d" className="sub2">{c.detail}</span>,
          ])} />
        </Panel>
      ) : null}
      <Panel title="The CCE periods" right={powers.decide ? <Btn kind="ghost" onClick={() => setPeriod({ id: null, label: "", starts: "16:00", ends: "18:00", active: true, ord: "" })}>Add a period</Btn> : null}>
        <DTable noPrint cols={["Period", "Times|mid", "In use", ""]} rows={v.periods.map((p: Period) => [
          p.label, <span key="t" className="tnum">{p.starts_at}–{p.ends_at}</span>, <Pil key="a" kind={p.active ? "ok" : "grey"}>{p.active ? "Offered" : "Retired"}</Pil>,
          powers.decide ? <Btn key="e" kind="ghost" onClick={() => setPeriod({ id: p.id, label: p.label, starts: p.starts_at, ends: p.ends_at, active: p.active, ord: String(p.ord) })}>Edit</Btn> : <span key="e" />,
        ])} />
      </Panel>
      {slot ? (
        <Modal title="Add a lecture" sub={`${session} · ${semesterWord(semester).toLowerCase()}`} onClose={() => setSlot(null)}
          foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setSlot(null)}>Back</Btn><Btn kind="primary" disabled={saving || !slot.offering || !slot.venue.trim()} onClick={() => void addSlot()}>{saving ? "Adding…" : "Add"}</Btn></span>}>
          <Field id="sl-o" label="Class">
            <select id="sl-o" className="ctl" value={slot.offering} onChange={(e) => setSlot({ ...slot, offering: e.target.value })}>
              {(classes?.classes ?? []).map((c) => <option key={c.id} value={c.id}>{c.course_code} {c.title}{c.slots.length ? ` (${c.slots.length} lecture${c.slots.length === 1 ? "" : "s"})` : ""}</option>)}
            </select>
          </Field>
          <div className="grid grid--3">
            <Field id="sl-d" label="Day"><select id="sl-d" className="ctl" value={slot.weekday} onChange={(e) => setSlot({ ...slot, weekday: e.target.value })}>{[1, 2, 3, 4, 5, 6, 7].map((d) => <option key={d} value={d}>{WEEKDAYS[d]}</option>)}</select></Field>
            <Field id="sl-s" label="Starts"><input id="sl-s" type="time" className="ctl" value={slot.starts} onChange={(e) => setSlot({ ...slot, starts: e.target.value })} /></Field>
            <Field id="sl-e" label="Ends"><input id="sl-e" type="time" className="ctl" value={slot.ends} onChange={(e) => setSlot({ ...slot, ends: e.target.value })} /></Field>
          </div>
          {activePeriods.length ? (
            <div className="row row--inline row--tight mb-2" style={{ flexWrap: "wrap" }}>
              <span className="sub2">Periods:</span>
              {activePeriods.map((p) => <Btn key={p.id} kind={slot.starts === p.starts_at && slot.ends === p.ends_at ? "secondary" : "ghost"} onClick={() => setSlot({ ...slot, starts: p.starts_at, ends: p.ends_at })}>{p.label}</Btn>)}
            </div>
          ) : null}
          <div className="grid grid--2">
            <Field id="sl-v" label="Venue" required><input id="sl-v" className="ctl" value={slot.venue} onChange={(e) => setSlot({ ...slot, venue: e.target.value })} /></Field>
            <Field id="sl-k" label="Kind"><select id="sl-k" className="ctl" value={slot.kind} onChange={(e) => setSlot({ ...slot, kind: e.target.value })}><option value="LECTURE">Lecture</option><option value="PRACTICAL">Practical</option><option value="TUTORIAL">Tutorial</option></select></Field>
          </div>
        </Modal>
      ) : null}
      {period ? (
        <Modal title={period.id ? "Edit the period" : "Add a period"} sub="A quick pick for the CCE timetable" onClose={() => setPeriod(null)}
          foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setPeriod(null)}>Back</Btn><Btn kind="primary" disabled={!period.label.trim()} onClick={() => void savePeriod()}>Save</Btn></span>}>
          <Field id="pd-l" label="Label" required><input id="pd-l" className="ctl" value={period.label} onChange={(e) => setPeriod({ ...period, label: e.target.value })} placeholder="5:00 pm – 7:00 pm" /></Field>
          <div className="grid grid--3">
            <Field id="pd-s" label="Starts"><input id="pd-s" type="time" className="ctl" value={period.starts} onChange={(e) => setPeriod({ ...period, starts: e.target.value })} /></Field>
            <Field id="pd-e" label="Ends"><input id="pd-e" type="time" className="ctl" value={period.ends} onChange={(e) => setPeriod({ ...period, ends: e.target.value })} /></Field>
            <Field id="pd-o" label="Order"><input id="pd-o" className="ctl tnum" inputMode="numeric" value={period.ord} onChange={(e) => setPeriod({ ...period, ord: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
          </div>
          <label className="row row--inline row--tight"><input type="checkbox" checked={period.active} onChange={(e) => setPeriod({ ...period, active: e.target.checked })} /> Offered as a quick pick (untick to retire it)</label>
        </Modal>
      ) : null}
    </>
  );
}

/* ── course registration ────────────────────────────────────────────────────────────────────────────────────────── */

export function CceRegistrations({ session, pick }: TabProps) {
  const [semester, setSemester] = useState(1);
  const [status, setStatus] = useState("");
  const v = useLoad<RegistrationsView>(`/api/v1/cce/registrations?session=${q(session)}&semester=${semester}${status ? `&status=${status}` : ""}`, 0);
  if (!v) return <Note kind="info" title="Reading the CCE registrations…">One moment.</Note>;
  const c = v.counts;
  const exportXlsx = () => downloadBlob(buildXlsx(["Number", "Name", "Programme", "Level", "Registration", "Units", "Submitted", "Approved", "Fees stated", "Fees cleared"],
    v.rows.map((r) => [r.number, r.name, r.programme, r.level, labelOf(REG_LABEL, r.registration)[0], r.units, r.submitted_at ? when(r.submitted_at) : "", r.approved_at ? when(r.approved_at) : "",
      r.fees_stated ? "Yes" : "No", r.fees_cleared ? "Yes" : "No"]), "CCE registrations"), `cce-registrations-${session.replace("/", "-")}-s${semester}.xlsx`);
  return (
    <>
      <PageHead title="CCE course registration" description={`Where each CCE student's course registration for ${session} stands. They register on the student portal through the University's registration engine, on the Centre's classes only; the Head of Department of the programme approves, as for every student.`}
        actions={<span className="row row--inline row--tight">{pick}<SemesterPick value={semester} onChange={(n) => setSemester(n ?? 1)} /></span>} />
      <Note kind={v.gate ? "bad" : "ok"} title={v.gate ? "Registration is closed to CCE students now" : `Registration is open for the ${semesterWord(semester).toLowerCase()} of ${session}`}>
        {v.gate ?? "The Centre's classes are set up and the CCE calendar (and any CCE window the Directorate of ICT holds) lets students register."}{" "}
        <LinkBtn kind="ghost" size="sm" href="/cce/calendar">CCE calendar</LinkBtn>
      </Note>
      <Tiles cls="grid--5" items={[
        ["CCE STUDENTS", c.students ?? 0, null, "Admitted, active or on probation"],
        ["NOT REGISTERED", c.none ?? 0, (c.none ?? 0) ? "var(--amber-ink)" : null, "No registration for the semester"],
        ["DRAFTING", c.drafting ?? 0, null, "A draft or a returned registration"],
        ["WITH THE HOD", c.submitted ?? 0, (c.submitted ?? 0) ? "var(--amber-ink)" : null, "Submitted, awaiting approval"],
        ["APPROVED", c.approved ?? 0, "var(--green-ink)", "Approved or locked"],
      ]} />
      <Panel title={`${v.rows.length} student${v.rows.length === 1 ? "" : "s"}`} right={<span className="row row--inline row--tight">
        <select className="ctl" aria-label="Registration" value={status} onChange={(e) => setStatus(e.target.value)}>
          <option value="">Every state</option>{Object.entries(REG_LABEL).map(([k, [w]]) => <option key={k} value={k}>{w}</option>)}
        </select><Btn kind="secondary" disabled={!v.rows.length} onClick={exportXlsx}>Excel</Btn></span>}>
        {v.rows.length ? (
          <DTable cols={["Student", "Programme", "Level|num", "Registration", "Units|num", "Fees"]} texts={v.rows.map((r) => `${r.name} ${r.number} ${r.programme}`)} rows={v.rows.map((r) => {
            const [w, k] = labelOf(REG_LABEL, r.registration);
            return [
              <span key="n">{r.name}<div className="sub2 tnum">{r.number}</div></span>, r.programme, r.level, <Pil key="r" kind={k}>{w}</Pil>, r.units,
              !r.fees_stated ? <span key="f" className="sub2">CCE fees not stated</span> : <Pil key="f" kind={r.fees_cleared ? "ok" : "warn"}>{r.fees_cleared ? "Cleared" : "Outstanding"}</Pil>,
            ];
          })} />
        ) : <PBody><div className="sub2">No CCE student in this state.</div></PBody>}
      </Panel>
    </>
  );
}

/* ── attendance ─────────────────────────────────────────────────────────────────────────────────────────────────── */

export function CceAttendance({ session, powers, pick }: TabProps) {
  const [f, setF] = useState({ semester: null as number | null, faculty: "", programme: "", course: "", from: "", to: "" });
  const [tick, setTick] = useState(0);
  const qs = [`session=${q(session)}`, f.semester ? `semester=${f.semester}` : "", f.faculty ? `faculty=${q(f.faculty)}` : "", f.programme ? `programme=${q(f.programme)}` : "",
    f.course.trim() ? `course=${q(f.course.trim())}` : "", f.from ? `from=${f.from}` : "", f.to ? `to=${f.to}` : ""].filter(Boolean).join("&");
  const v = useLoad<AttendanceView>(`/api/v1/cce/attendance?${qs}`, tick);
  const [pol, setPol] = useState<{ scope: string; min: string; warn: string; classes: string; show: boolean } | null>(null);
  if (!v) return <Note kind="info" title="Reading the CCE attendance…">One moment.</Note>;
  async function savePolicy() {
    if (!pol) return;
    const out = await cceSend("/attendance/policy", "PUT", { session: pol.scope, minPercent: pol.min ? Number(pol.min) : null, warnBand: pol.warn ? Number(pol.warn) : null,
      minClasses: pol.classes ? Number(pol.classes) : 3, showStudents: pol.show }, `CCE attendance policy for ${pol.scope === "*" ? "every session" : pol.scope} saved`);
    if (out) { setPol(null); setTick((t) => t + 1); }
  }
  const p = v.policy;
  const below = v.rows.filter((r) => r.verdict === "NOT_ELIGIBLE").length;
  const exportXlsx = () => downloadBlob(buildXlsx(["Number", "Name", "Programme", "Level", "Faculty", "Department", "Course", "Semester", "Lectures", "Present", "Late", "Absent", "Excused", "Rate %", "Standing"],
    v.rows.map((r) => [r.number, r.name, r.programme, r.level, r.faculty ?? "", r.department ?? "", r.course_code, r.semester, r.total, r.present, r.late, r.absent, r.excused, r.rate ?? "",
      r.verdict ? labelOf(VERDICT_LABEL, r.verdict)[0] : ""]), "CCE attendance"), `cce-attendance-${session.replace("/", "-")}.xlsx`);
  const facultyProgs = v.programmes.filter((x) => !f.faculty || x.faculty_code === f.faculty);
  return (
    <>
      <PageHead title="CCE attendance" description={`The register of the Centre's evening classes in ${session}: each lecture's attendance as the lecturer marked it (present, absent, late or excused), by student and class. A corrected mark keeps its reason; a locked register is reopened only by the Centre or the Academic Office.`} actions={pick} />
      <Panel title="Filter">
        <PBody>
          <div className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
            <Field id="at-sem" label="Semester"><SemesterPick all value={f.semester} onChange={(n) => setF({ ...f, semester: n })} /></Field>
            <Field id="at-fac" label="Faculty"><select id="at-fac" className="ctl" value={f.faculty} onChange={(e) => setF({ ...f, faculty: e.target.value, programme: "" })}><option value="">Every faculty</option>{v.faculties.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}</select></Field>
            <Field id="at-prog" label="Programme"><select id="at-prog" className="ctl" value={f.programme} onChange={(e) => setF({ ...f, programme: e.target.value })}><option value="">Every CCE programme</option>{facultyProgs.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}</select></Field>
            <Field id="at-c" label="Course"><input id="at-c" className="ctl" style={{ width: 110 }} value={f.course} onChange={(e) => setF({ ...f, course: e.target.value.toUpperCase() })} placeholder="CSC 101" /></Field>
            <Field id="at-f" label="From"><input id="at-f" type="date" className="ctl" value={f.from} onChange={(e) => setF({ ...f, from: e.target.value })} /></Field>
            <Field id="at-t" label="To"><input id="at-t" type="date" className="ctl" value={f.to} onChange={(e) => setF({ ...f, to: e.target.value })} /></Field>
          </div>
        </PBody>
      </Panel>
      <Note kind="info" title={p?.min_percent != null ? `The Centre's minimum attendance: ${p.min_percent}%` : "No minimum attendance is set"}
        action={powers.decide ? <Btn kind="ghost" onClick={() => setPol({ scope: p?.session ?? session, min: p?.min_percent != null ? String(p.min_percent) : "", warn: p?.warn_band != null ? String(p.warn_band) : "", classes: String(p?.min_classes ?? 3), show: p?.show_students ?? true })}>Set the policy</Btn> : null}>
        {p ? <>For {p.session === "*" ? "every session" : p.session}{p.warn_band != null ? `; a warning within ${p.warn_band} points above it` : ""}; counted after {p.min_classes} lectures. Students {p.show_students ? "read" : "do not read"} their own attendance on the portal.</>
          : "Until the Centre sets one, the register shows the rates and no student is judged against a minimum. Students read their own attendance."}
      </Note>
      <Tiles cls="grid--4" items={[
        ["CLASSES", v.classes.length, null, `${v.classes.filter((c) => c.registers).length} with a register taken`],
        ["LECTURES RECORDED", v.classes.reduce((n, c) => n + Number(c.registers), 0), null, `${v.classes.reduce((n, c) => n + Number(c.locked), 0)} locked`],
        ["STUDENT × CLASS ROWS", v.rows.length, null, "Students with a mark"],
        ["BELOW THE MINIMUM", below, below ? "var(--red-ink)" : null, p?.min_percent != null ? `Under ${p.min_percent}%` : "No minimum set"],
      ]} />
      <Panel title="By class">
        {v.classes.length ? (
          <DTable cols={["Course", "Lecturer", "Lectures|num", "Locked|num", "Last held|mid", "Attendance|num"]} rows={v.classes.map((c) => [
            <span key="c"><b className="tnum">{c.course_code}</b> {c.title}<div className="sub2">{semesterWord(c.semester).toLowerCase()}</div></span>, c.lecturer ?? "—", c.registers, c.locked, day(c.last_held),
            Number(c.counted) ? `${Math.round((100 * Number(c.attended)) / Number(c.counted))}%` : "—",
          ])} />
        ) : <PBody><div className="sub2">No CCE class in this selection.</div></PBody>}
      </Panel>
      <Panel title="By student and class" right={<Btn kind="secondary" disabled={!v.rows.length} onClick={exportXlsx}>Excel</Btn>}>
        {v.rows.length ? (
          <DTable cols={["Student", "Course", "Lectures|num", "Present|num", "Late|num", "Absent|num", "Excused|num", "Rate|num", "Standing"]} texts={v.rows.map((r) => `${r.name} ${r.number} ${r.course_code} ${r.programme}`)} rows={v.rows.map((r) => {
            const [w, k] = r.verdict ? labelOf(VERDICT_LABEL, r.verdict) : ["—", "grey" as const];
            return [<span key="n">{r.name}<div className="sub2 tnum">{r.number} · {r.programme_code} {r.level}</div></span>, r.course_code, r.total, r.present, r.late, r.absent, r.excused,
              r.rate == null ? "—" : `${Math.round(Number(r.rate))}%`, r.verdict ? <Pil key="v" kind={k}>{w}</Pil> : <span key="v" className="sub2">—</span>];
          })} />
        ) : <PBody><div className="sub2">No attendance is recorded in this selection.</div></PBody>}
      </Panel>
      <div className="sub2">Marks: {Object.values(ATT_LABEL).map(([w]) => w).join(", ")}. The rate counts present and late over the lectures not excused.</div>
      {pol ? (
        <Modal title="CCE attendance policy" sub="The Centre's own; the full-time classes are not affected" onClose={() => setPol(null)}
          foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setPol(null)}>Back</Btn><Btn kind="primary" onClick={() => void savePolicy()}>Save</Btn></span>}>
          <Field id="po-s" label="For"><select id="po-s" className="ctl" value={pol.scope} onChange={(e) => setPol({ ...pol, scope: e.target.value })}><option value={session}>{session} only</option><option value="*">Every session (unless one says otherwise)</option></select></Field>
          <div className="grid grid--3">
            <Field id="po-m" label="Minimum attendance %" hint="Blank: none is enforced"><input id="po-m" className="ctl tnum" inputMode="decimal" value={pol.min} onChange={(e) => setPol({ ...pol, min: e.target.value.replace(/[^0-9.]/g, "") })} /></Field>
            <Field id="po-w" label="Warning band (points)"><input id="po-w" className="ctl tnum" inputMode="decimal" value={pol.warn} onChange={(e) => setPol({ ...pol, warn: e.target.value.replace(/[^0-9.]/g, "") })} /></Field>
            <Field id="po-c" label="Lectures before judging"><input id="po-c" className="ctl tnum" inputMode="numeric" value={pol.classes} onChange={(e) => setPol({ ...pol, classes: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
          </div>
          <label className="row row--inline row--tight"><input type="checkbox" checked={pol.show} onChange={(e) => setPol({ ...pol, show: e.target.checked })} /> Students read their own attendance on the portal</label>
        </Modal>
      ) : null}
    </>
  );
}

/* ── the CCE school fees ────────────────────────────────────────────────────────────────────────────────────────── */

export function CceSchoolFees({ session, powers, pick }: TabProps) {
  const v = useLoad<SchoolFeesView>(`/api/v1/cce/school-fees?session=${q(session)}`, 0);
  if (!v) return <Note kind="info" title="Reading the CCE school fees…">One moment.</Note>;
  const s = v.students;
  const fee = (l: SchoolFeesView["lines"][number]) => [l.level ? `${l.level} Level` : "Every level", l.semester ? semesterWord(l.semester) : "The session", l.programme ?? l.faculty ?? null,
    l.indigene === "INDIGENE" ? "Indigene" : l.indigene === "NON_INDIGENE" ? "Non-indigene" : null, l.spillover ? "Spillover" : null].filter(Boolean).join(" · ");
  return (
    <>
      <PageHead title="CCE school fees" description={`The school-fee lines the Bursary stated for CCE in ${v.session}, and the CCE students' standing against them. A CCE student is charged only these lines (entry mode CCE) — never the full-time lines of the same session — and pays on the University's one payment system.`} actions={pick} />
      {!v.lines.length ? (
        <Note kind="bad" title={`The Bursary has not stated CCE school fees for ${v.session}`} action={powers.bursar ? <LinkBtn kind="primary" href={`/finance/fees?session=${q(v.session)}`}>State them</LinkBtn> : null}>
          Until it does, a CCE student has nothing to pay and is not cleared for registration; their portal says the fees are not yet stated.
          {v.fullTimeLines ? ` The ${v.fullTimeLines} full-time line${v.fullTimeLines === 1 ? "" : "s"} of ${v.session} never reach a CCE student.` : ""}
        </Note>
      ) : null}
      <Tiles cls="grid--5" items={[
        ["CCE STUDENTS", s.students, null, `${s.stated} with fees stated`],
        ["PAID IN FULL", s.paid_in_full, "var(--green-ink)", "Of those charged"],
        ["PART PAID", s.part_paid, s.part_paid ? "var(--amber-ink)" : null, "A payment, a balance left"],
        ["NOT PAID", s.unpaid, s.unpaid ? "var(--red-ink)" : null, "Charged, nothing paid"],
        ["COLLECTED", naira(s.paid), null, `${naira(s.balance)} outstanding of ${naira(s.due)}`],
      ]} />
      <Panel title={`CCE fee lines · ${v.lines.length}`} right={powers.bursar ? <LinkBtn kind="ghost" href={`/finance/fees?session=${q(v.session)}`}>Fee schedule</LinkBtn> : <Pil kind="info">The Bursary&rsquo;s</Pil>}>
        {v.lines.length ? (
          <DTable cols={["Item", "Applies to", "Kind", "Amount|num"]} rows={v.lines.map((l) => [l.item, <span key="a" className="sub2">{fee(l)}</span>, l.kind === "FEE" ? "School fee" : l.kind.replace("_", " ").toLowerCase(), naira(l.amount)])} />
        ) : <PBody><div className="sub2">None stated.</div></PBody>}
      </Panel>
      <div className="grid grid--2">
        <Panel title="CCE payments confirmed" right={<Pil kind="info">{v.session}</Pil>}>
          {v.payments.length ? (
            <DTable noPrint cols={["Payer", "Purpose", "Payments|num", "Amount|num"]} rows={v.payments.map((p, i) => [<span key={`p${i}`}>{p.payer === "STUDENT" ? "Students" : "Applicants"}</span>, p.purpose, p.payments, naira(p.amount)])} />
          ) : <PBody><div className="sub2">No CCE payment is confirmed for {v.session} yet.</div></PBody>}
        </Panel>
        <Panel title="CCE school-fees payment window" right={<Pil kind={v.window.state === "OPEN" ? "ok" : "warn"}>{v.window.state}{v.window.phase === "LATE" ? " · LATE" : ""}</Pil>}>
          <PBody>
            <div className="sub2">{v.window.configured ? `Set by the Directorate of ICT${v.window.closes_at ? `; closes ${when(v.window.closes_at)}` : ""}${v.window.late_until ? `; late payment until ${when(v.window.late_until)}` : ""}.` : "Open by default. The Directorate of ICT may schedule or close it on Portal Windows; the full-time window of the same session never governs CCE students."}</div>
            {v.window.reason ? <div className="sub2 mt-1">{v.window.reason}</div> : null}
          </PBody>
        </Panel>
      </div>
    </>
  );
}

