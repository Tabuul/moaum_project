"use client";

/**
 * JUPEB attendance (V342), on the University's attendance engine. The JUPEB Office (and Super) see and correct every
 * register, assign instructors and set the minimum attendance; an administrator reads; a lecturer sees ONLY the subjects
 * (and classes) the JUPEB Office assigned them — the server decides every list, register and photograph, the page hides
 * nothing it was given. A register is a subject (and class) on a day: the class list with each student's passport, one
 * mark each (present, absent, late or excused, with a time and a remark), "mark all present", one save; a saved mark is
 * corrected only with a reason, kept with who and when; a locked register only by the JUPEB Office.
 */
import { useCallback, useEffect, useMemo, useState } from "react";
import type { Problem } from "@/lib/api";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, PageHead, Panel, PBody, Pil, Tabs } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { day, jcall, when } from "@/lib/jupeb";
import { LecturesDue } from "./LecturesDue";
import { CoveragePanel, RegisterTopics } from "./Coverage";

const BASE = "/api/v1/attendance/jupeb";
const STATUSES = ["PRESENT", "ABSENT", "LATE", "EXCUSED"] as const;
type Status = (typeof STATUSES)[number];
const STATUS_WORD: Record<Status, string> = { PRESENT: "Present", ABSENT: "Absent", LATE: "Late", EXCUSED: "Excused" };
const STATUS_KIND: Record<Status, "ok" | "bad" | "warn" | "grey"> = { PRESENT: "ok", ABSENT: "bad", LATE: "warn", EXCUSED: "grey" };

interface Options {
  session: string; sessions: string[]; office: boolean; reader: boolean; policy: number | null; warnBand: number | null; minClasses: number;
  subjects: { id: string; code: string; title: string }[]; classes: { id: string; name: string; combination_id: string | null }[];
  assignments: { subject_id: string; code: string; title: string; class_id: string | null; class_name: string | null }[];
}
interface RegisterRow { id: string; session: string; semester: number; subject_code: string; subject_title: string; class_name: string | null; held_on: string; topic: string | null; saved_at: string | null; locked_at: string | null; present: number; absent: number; late: number; excused: number; marked: number }
interface Member { member_ref: string; name: string; application_no: string; exam_no: string | null; combination_code: string | null; class_name: string | null; status: Status | null; marked_time: string | null; remarks: string | null; has_photo: boolean }
interface Register {
  id: string; session: string; semester: number; subject_code: string; subject_title: string; class_name: string | null; held_on: string; topic: string | null;
  opened_by: string | null; saved_at: string | null; locked_at: string | null; locked_by: string | null;
  rows: Member[]; total: number; page: number; size: number; counts: { roster: number; present: number; absent: number; late: number; excused: number }; mayMark: boolean; mayUnlock: boolean;
}
interface Change { changed_at: string; name: string; application_no: string; old_status: string | null; new_status: string; old_remarks: string | null; new_remarks: string | null; reason: string; changed_office: string | null; changed_by: string | null }
interface Instructor { id: string; session: string; subject_code: string; subject_title: string; class_name: string | null; name: string; staff_number: string | null; email: string | null; assigned_at: string }
type Tab = "lectures" | "registers" | "coverage" | "standing" | "reports" | "instructors" | "policy";

const today = () => new Date(Date.now() + 3600_000).toISOString().slice(0, 10);

export function JupebAttendance() {
  const [session, setSession] = useState("");
  const [o, setO] = useState<Options | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [tab, setTab] = useState<Tab>("lectures");
  const [open, setOpen] = useState<string | null>(null);
  useEffect(() => {
    let live = true;
    void jcall<Options>(`${BASE}/options${session ? `?session=${encodeURIComponent(session)}` : ""}`).then((r) => {
      if (!live) return;
      if (r.ok) { setO(r.data); setProblem(null); } else setProblem(r.problem);
    });
    return () => { live = false; };
  }, [session]);
  if (problem) return <ProblemNotice problem={problem} />;
  if (!o) return <Note kind="info" title="Loading attendance…">One moment.</Note>;
  const tabs: { id: Tab; label: string }[] = [{ id: "lectures", label: "Lectures" }, { id: "registers", label: "Registers" }, { id: "coverage", label: "Coverage" }, ...(o.reader ? [{ id: "standing" as Tab, label: "Standing" }] : []), { id: "reports", label: "Reports" },
    ...(o.reader ? [{ id: "instructors" as Tab, label: "Instructors" }] : []), ...(o.office ? [{ id: "policy" as Tab, label: "Minimum attendance" }] : [])];
  return (
    <>
      <PageHead title="JUPEB attendance" description={o.reader ? "Every JUPEB register of the session: take, correct, lock and report attendance; assign who takes each subject." : "The JUPEB subjects you are assigned to: take each class's attendance and read its reports."}
        actions={<select className="ctl" aria-label="Session" value={o.session} onChange={(e) => { setSession(e.target.value); setOpen(null); }}>{o.sessions.map((s) => <option key={s}>{s}</option>)}</select>} />
      {!o.reader && !o.assignments.length ? <Note kind="info" title="No JUPEB subject is assigned to you">The JUPEB Office assigns lecturers to subjects and classes. Once assigned, the subject appears here.</Note> : null}
      {!o.reader && o.assignments.length ? <Note kind="info" title="You take attendance for">{o.assignments.map((a) => `${a.title}${a.class_name ? ` (${a.class_name})` : " (every class)"}`).join(" · ")}</Note> : null}
      {open ? <RegisterView id={open} onBack={() => setOpen(null)} /> : (
        <>
          <Tabs items={tabs} value={tab} onChange={setTab} look="line" label="Attendance" />
          {tab === "lectures" ? <LecturesDue session={o.session} office={o.office} onOpen={setOpen} /> : null}
          {tab === "registers" ? <Registers o={o} onOpen={setOpen} /> : null}
          {tab === "coverage" ? <CoveragePanel session={o.session} /> : null}
          {tab === "standing" ? <Standing o={o} /> : null}
          {tab === "reports" ? <Reports o={o} /> : null}
          {tab === "instructors" ? <Instructors o={o} /> : null}
          {tab === "policy" ? <Policy o={o} onSaved={(x) => setO({ ...o, ...x })} /> : null}
        </>
      )}
    </>
  );
}

function Registers({ o, onOpen }: { o: Options; onOpen: (id: string) => void }) {
  const [rows, setRows] = useState<RegisterRow[]>([]);
  const [f, setF] = useState<Record<string, string>>({ semester: "", subject: "", klass: "" });
  const [n, setN] = useState<Record<string, string>>({ semester: "1", subjectId: o.subjects[0]?.id ?? "", classId: "", heldOn: today(), topic: "" });
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let live = true;
    const q = new URLSearchParams({ session: o.session, ...Object.fromEntries(Object.entries(f).filter(([, v]) => v)) });
    void jcall<RegisterRow[]>(`${BASE}/registers?${q}`).then((r) => { if (live && r.ok) setRows(r.data); });
    return () => { live = false; };
  }, [o.session, f]);
  /* a lecturer assigned to one class of a subject takes only that class; one assigned to the subject takes any */
  const classesFor = (subject: string) => {
    if (o.reader) return o.classes;
    const mine = o.assignments.filter((a) => a.subject_id === subject);
    return mine.some((a) => !a.class_id) ? o.classes : o.classes.filter((c) => mine.some((a) => a.class_id === c.id));
  };
  async function create() {
    setBusy(true);
    try {
      const r = await jcall<Register>(`${BASE}/registers`, "POST", { session: o.session, semester: Number(n.semester), subjectId: n.subjectId, classId: n.classId || null, heldOn: n.heldOn, topic: n.topic.trim() || null }, "Attendance register opened");
      if (!r.ok) { notifyProblem(r.problem); return; }
      onOpen(r.data.id);
    } finally { setBusy(false); }
  }
  const mayOpen = o.subjects.length > 0 && (o.office || o.assignments.length > 0);
  return (
    <>
      {mayOpen ? (
        <Panel title="Take attendance">
          <PBody>
            <div className="grid grid--3">
              <Field id="n-sub" label="Subject"><select id="n-sub" className="ctl" value={n.subjectId} onChange={(e) => setN({ ...n, subjectId: e.target.value, classId: "" })}>{o.subjects.map((s) => <option key={s.id} value={s.id}>{s.title} ({s.code})</option>)}</select></Field>
              <Field id="n-cls" label="Class" hint="Blank: every student registered for the subject"><select id="n-cls" className="ctl" value={n.classId} onChange={(e) => setN({ ...n, classId: e.target.value })}>
                {o.reader || o.assignments.some((a) => a.subject_id === n.subjectId && !a.class_id) ? <option value="">Every class</option> : null}
                {classesFor(n.subjectId).map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</select></Field>
              <Field id="n-sem" label="Semester"><select id="n-sem" className="ctl" value={n.semester} onChange={(e) => setN({ ...n, semester: e.target.value })}><option value="1">First</option><option value="2">Second</option></select></Field>
              <Field id="n-day" label="Date"><input id="n-day" type="date" className="ctl" value={n.heldOn} max={today()} onChange={(e) => setN({ ...n, heldOn: e.target.value })} /></Field>
              <Field id="n-topic" label="Topic (optional)"><input id="n-topic" className="ctl" maxLength={300} value={n.topic} onChange={(e) => setN({ ...n, topic: e.target.value })} /></Field>
              <div className="field"><label>&nbsp;</label><Btn kind="primary" disabled={busy || !n.subjectId || !n.heldOn} onClick={() => void create()}>{busy ? "Opening…" : "Open the register"}</Btn></div>
            </div>
            <p className="sub2">A subject&rsquo;s register for a class on a day is opened once; opening it again finds the same register.</p>
          </PBody>
        </Panel>
      ) : null}
      <Panel title={`Registers (${rows.length})`}>
        <PBody>
          <div className="row" style={{ gap: "var(--s-2)", marginBottom: "var(--s-2)", flexWrap: "wrap" }}>
            <select className="ctl" style={{ width: 170 }} aria-label="Semester" value={f.semester} onChange={(e) => setF({ ...f, semester: e.target.value })}><option value="">Both semesters</option><option value="1">First</option><option value="2">Second</option></select>
            <select className="ctl" style={{ width: 220 }} aria-label="Subject" value={f.subject} onChange={(e) => setF({ ...f, subject: e.target.value })}><option value="">All subjects</option>{o.subjects.map((s) => <option key={s.id} value={s.id}>{s.title}</option>)}</select>
            <select className="ctl" style={{ width: 170 }} aria-label="Class" value={f.klass} onChange={(e) => setF({ ...f, klass: e.target.value })}><option value="">All classes</option>{o.classes.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</select>
          </div>
          <DTable pageSize={25} cols={["Date", "Subject", "Class", "Semester|num", "Present|num", "Late|num", "Absent|num", "Excused|num", "State", "|mid"]}
            texts={rows.map((r) => `${r.subject_code} ${r.subject_title} ${r.class_name ?? ""} ${r.held_on}`)}
            rows={rows.map((r) => [day(r.held_on), `${r.subject_title} (${r.subject_code})`, r.class_name ?? "Every class", r.semester, r.present, r.late, r.absent, r.excused,
              r.locked_at ? <Pil key="l" kind="grey">Locked</Pil> : r.saved_at ? <Pil key="l" kind="ok">Saved</Pil> : <Pil key="l" kind="warn">Not saved</Pil>,
              <Btn key="o" kind="ghost" onClick={() => onOpen(r.id)}>Open</Btn>])} />
        </PBody>
      </Panel>
    </>
  );
}

interface Draft { status: Status | null; time: string; remarks: string }

export function RegisterView({ id, onBack }: { id: string; onBack: () => void }) {
  const [r, setR] = useState<Register | null>(null);
  const [q, setQ] = useState("");
  const [page, setPage] = useState(0);
  const [drafts, setDrafts] = useState<Record<string, Draft>>({});
  const [ask, setAsk] = useState<"save" | "unlock" | null>(null);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [changes, setChanges] = useState<Change[] | null>(null);
  const take = useCallback((x: Register) => {
    setR(x);
    setDrafts(Object.fromEntries(x.rows.map((m) => [m.member_ref, { status: m.status, time: m.marked_time ? m.marked_time.slice(0, 5) : "", remarks: m.remarks ?? "" }])));
  }, []);
  useEffect(() => {
    let live = true;
    const t = setTimeout(() => {
      void jcall<Register>(`${BASE}/registers/${id}?page=${page}&size=200${q.trim() ? `&q=${encodeURIComponent(q.trim())}` : ""}`).then((x) => { if (live) { if (x.ok) take(x.data); else notifyProblem(x.problem); } });
    }, q ? 300 : 0);
    return () => { live = false; clearTimeout(t); };
  }, [id, q, page, take]);
  const changed = useMemo(() => (r ? r.rows.filter((m) => {
    const d = drafts[m.member_ref];
    return d && d.status && (d.status !== m.status || d.time !== (m.marked_time ? m.marked_time.slice(0, 5) : "") || d.remarks !== (m.remarks ?? ""));
  }) : []), [r, drafts]);
  if (!r) return <Note kind="info" title="Loading the register…">One moment.</Note>;
  const corrections = changed.filter((m) => m.status);
  const set = (m: string, patch: Partial<Draft>) => setDrafts({ ...drafts, [m]: { ...drafts[m], ...patch } });
  /* every student not yet saved becomes present; "the rest" fills only those with no mark at all — a saved mark is never overwritten in bulk */
  const markAll = () => setDrafts(Object.fromEntries(r.rows.map((m) => [m.member_ref, { ...drafts[m.member_ref], status: m.status ? drafts[m.member_ref].status : "PRESENT" }])));
  const markRest = (s: Status) => setDrafts(Object.fromEntries(r.rows.map((m) => [m.member_ref, { ...drafts[m.member_ref], status: drafts[m.member_ref]?.status ?? s }])));
  async function save(why: string | null) {
    if (!r) return;
    setBusy(true);
    try {
      const marks = changed.map((m) => ({ member: m.member_ref, status: drafts[m.member_ref].status, time: drafts[m.member_ref].time || null, remarks: drafts[m.member_ref].remarks.trim() || null }));
      const x = await jcall<Register>(`${BASE}/registers/${r.id}/marks`, "POST", { marks, reason: why }, why ? `Attendance corrected: ${why}` : "Attendance taken");
      if (!x.ok) { notifyProblem(x.problem); return; }
      take(x.data); setAsk(null); setReason(""); setChanges(null);
      notify(`${marks.length} mark${marks.length === 1 ? "" : "s"} saved.`);
    } finally { setBusy(false); }
  }
  async function lock(on: boolean, why?: string) {
    if (!r) return;
    setBusy(true);
    try {
      const x = await jcall<Register>(`${BASE}/registers/${r.id}/${on ? "lock" : "unlock"}`, "POST", on ? {} : { reason: why }, on ? "Attendance register locked" : `Attendance register unlocked: ${why}`);
      if (!x.ok) { notifyProblem(x.problem); return; }
      take(x.data); setAsk(null); setReason("");
      notify(on ? "The register is locked." : "The register is unlocked.");
    } finally { setBusy(false); }
  }
  async function showChanges() {
    const x = await jcall<Change[]>(`${BASE}/registers/${id}/changes`);
    if (x.ok) setChanges(x.data); else notifyProblem(x.problem);
  }
  const unmarked = r.counts.roster - (r.counts.present + r.counts.absent + r.counts.late + r.counts.excused);
  const pages = Math.max(1, Math.ceil(r.total / r.size));
  const editable = r.mayMark;
  return (
    <>
      <div className="row"><Btn kind="ghost" onClick={onBack}>← All registers</Btn><span className="grow" />
        {r.locked_at ? <Pil kind="grey">{`Locked ${when(r.locked_at)}${r.locked_by ? ` by ${r.locked_by}` : ""}`}</Pil> : null}</div>
      <Panel title={`${r.subject_title} (${r.subject_code}) · ${day(r.held_on)}`}>
        <PBody>
          <KvGrid cls="grid--4" pairs={[["Session", r.session], ["Semester", r.semester === 1 ? "First" : r.semester === 2 ? "Second" : String(r.semester)], ["Class", r.class_name ?? "Every class"], ["Topic", r.topic ?? "—"],
            ["On the class list", r.counts.roster], ["Present", r.counts.present], ["Late", r.counts.late], ["Absent", r.counts.absent], ["Excused", r.counts.excused], ["Not marked", unmarked],
            ["Opened by", r.opened_by ?? "—"], ["Last saved", r.saved_at ? when(r.saved_at) : "Not yet"]]} />
          {r.locked_at && !r.mayMark ? <Note kind="info" title="This register is locked">Only the JUPEB Office corrects a locked register.</Note> : null}
          <div className="row mt-3" style={{ flexWrap: "wrap" }}>
            <input className="ctl" style={{ maxWidth: 280 }} aria-label="Search the class list" placeholder="Search name, application or exam number" value={q} onChange={(e) => { setQ(e.target.value); setPage(0); }} />
            {editable ? <><Btn kind="secondary" onClick={markAll}>Mark all present</Btn><Btn kind="ghost" onClick={() => markRest("ABSENT")}>Mark the rest absent</Btn></> : null}
            <span className="grow" />
            <Btn kind="ghost" onClick={() => void showChanges()}>Corrections</Btn>
            {!r.locked_at && editable ? <Btn kind="ghost" disabled={busy || !r.saved_at || changed.length > 0} onClick={() => void lock(true)}>Lock</Btn> : null}
            {r.locked_at && r.mayUnlock ? <Btn kind="ghost" disabled={busy} onClick={() => setAsk("unlock")}>Unlock…</Btn> : null}
            {editable ? <Btn kind="primary" disabled={busy || !changed.length} onClick={() => (corrections.length ? setAsk("save") : void save(null))}>{busy ? "Saving…" : `Save${changed.length ? ` (${changed.length})` : ""}`}</Btn> : null}
          </div>
          <DTable noPrint pageSize={0} cols={["Photo|mid", "Name", "Application / exam no", "Class", "Status", "Time", "Remarks"]} rows={r.rows.map((m) => {
            const d = drafts[m.member_ref] ?? { status: null, time: "", remarks: "" };
            return [
              m.has_photo
                // eslint-disable-next-line @next/next/no-img-element
                ? <img key="p" src={`/api/bff${BASE}/photo/${m.member_ref}`} alt={`Passport of ${m.name}`} loading="lazy" style={{ width: 44, height: 55, objectFit: "cover", borderRadius: "var(--r-sm)", border: "1px solid var(--line-2)" }} />
                : <span key="p" className="sub2">No photo</span>,
              <b key="n">{m.name}</b>, <span key="a" className="tnum">{m.application_no}{m.exam_no ? <div className="sub2">{m.exam_no}</div> : null}</span>, m.class_name ?? "—",
              editable ? (
                <span key="s" className="row" style={{ gap: 4, flexWrap: "wrap" }} role="radiogroup" aria-label={`Attendance of ${m.name}`}>
                  {STATUSES.map((s) => (
                    <button key={s} type="button" role="radio" aria-checked={d.status === s} onClick={() => set(m.member_ref, { status: s })}
                      className={`btn btn--sm ${d.status === s ? "btn--primary" : "btn--ghost"}`} title={STATUS_WORD[s]}>{STATUS_WORD[s]}</button>
                  ))}
                </span>
              ) : d.status ? <Pil key="s" kind={STATUS_KIND[d.status]}>{STATUS_WORD[d.status]}</Pil> : <span key="s" className="sub2">Not marked</span>,
              editable ? <input key="t" type="time" className="ctl" style={{ width: 110 }} aria-label={`Time for ${m.name}`} value={d.time} onChange={(e) => set(m.member_ref, { time: e.target.value })} /> : (m.marked_time?.slice(0, 5) ?? "—"),
              editable ? <input key="r" className="ctl" maxLength={300} aria-label={`Remarks for ${m.name}`} value={d.remarks} onChange={(e) => set(m.member_ref, { remarks: e.target.value })} /> : (m.remarks ?? "—"),
            ];
          })} />
          {pages > 1 ? <div className="row mt-2"><Btn kind="ghost" disabled={page === 0} onClick={() => setPage(page - 1)}>Previous</Btn><span className="sub2">Page {page + 1} of {pages} · {r.total} students</span><Btn kind="ghost" disabled={page + 1 >= pages} onClick={() => setPage(page + 1)}>Next</Btn></div> : null}
          {changed.length && pages > 1 ? <p className="hint">Save before moving to another page; unsaved marks on this page are lost.</p> : null}
        </PBody>
      </Panel>
      <RegisterTopics registerId={r.id} heldOn={r.held_on} editable={r.mayMark} />
      {changes ? (
        <Panel title={`Corrections (${changes.length})`} right={<Btn kind="ghost" onClick={() => setChanges(null)}>Hide</Btn>}>
          <PBody><DTable pageSize={20} cols={["When", "Student", "From", "To", "Reason", "By"]} rows={changes.map((c) => [when(c.changed_at), `${c.name} (${c.application_no})`,
            `${c.old_status ?? "—"}${c.old_remarks ? ` · ${c.old_remarks}` : ""}`, `${c.new_status}${c.new_remarks ? ` · ${c.new_remarks}` : ""}`, c.reason, `${c.changed_by ?? "—"}${c.changed_office ? ` (${c.changed_office})` : ""}`])} /></PBody>
        </Panel>
      ) : null}
      {ask ? (
        <Modal title={ask === "save" ? "Correct saved attendance" : "Unlock the register"} onClose={() => setAsk(null)}
          foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || reason.trim().length < 3} onClick={() => void (ask === "save" ? save(reason.trim()) : lock(false, reason.trim()))}>{ask === "save" ? "Save the corrections" : "Unlock"}</Btn></>}>
          <p>{ask === "save" ? `${corrections.length} saved mark${corrections.length === 1 ? " is" : "s are"} being changed. The reason is kept with each correction, with who made it and when.` : "Unlocking lets the register be corrected again. The reason is kept."}</p>
          <Field id="a-why" label="Reason" required><input id="a-why" className="ctl" maxLength={600} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
        </Modal>
      ) : null}
    </>
  );
}

type ReportRow = Record<string, string | number | boolean | null>;

function Reports({ o }: { o: Options }) {
  const [f, setF] = useState<Record<string, string>>({ by: "student", semester: "", subject: "", klass: "", below: "", absences: "" });
  const [d, setD] = useState<{ minPercent: number | null; rows: ReportRow[] } | null>(null);
  useEffect(() => {
    let live = true;
    const q = new URLSearchParams({ session: o.session, by: f.by, ...(f.semester ? { semester: f.semester } : {}), ...(f.subject ? { subject: f.subject } : {}), ...(f.klass ? { klass: f.klass } : {}),
      ...(f.below ? { below: "true" } : {}), ...(f.absences ? { absences: f.absences } : {}) });
    void jcall<{ minPercent: number | null; rows: ReportRow[] }>(`${BASE}/reports?${q}`).then((r) => { if (live) { if (r.ok) setD(r.data); else notifyProblem(r.problem); } });
    return () => { live = false; };
  }, [o.session, f]);
  const rate = (x: ReportRow) => (x.rate == null ? "—" : `${Number(x.rate)}%`);
  const counts = (x: ReportRow) => [x.total, x.present, x.late, x.absent, x.excused, rate(x)] as (string | number)[];
  const COUNT_COLS = ["Classes|num", "Present|num", "Late|num", "Absent|num", "Excused|num", "Rate|num"];
  const shape: { cols: string[]; cells: (x: ReportRow) => (string | number)[] } = f.by === "subject"
    ? { cols: ["Subject", "Registers|num", "Students|num", ...COUNT_COLS], cells: (x) => [`${x.title} (${x.code})`, Number(x.registers), Number(x.students), ...counts(x)] }
    : f.by === "class" ? { cols: ["Class", "Registers|num", "Students|num", ...COUNT_COLS], cells: (x) => [String(x.class_name), Number(x.registers), Number(x.students), ...counts(x)] }
    : f.by === "date" ? { cols: ["Date", "Subject", "Class", ...COUNT_COLS, "Locked"], cells: (x) => [day(String(x.held_on)), `${x.title} (${x.code})`, String(x.class_name), ...counts(x), x.locked ? "Yes" : "No"] }
    : { cols: ["Student", "Application no", "Exam no", "Subject", ...COUNT_COLS, "Longest absence run|num", "Standing"],
        cells: (x) => [String(x.name), String(x.application_no), String(x.exam_no ?? "—"), String(x.code), ...counts(x), Number(x.longest_absence_run ?? 0),
          d?.minPercent == null || x.rate == null ? "—" : Number(x.rate) >= Number(d.minPercent) ? "Meets the minimum" : "Below the minimum"] };
  async function exportXlsx() {
    if (!d) return;
    const blob = await brandedXlsx(`JUPEB attendance by ${f.by} — ${o.session}`, shape.cols.map((c) => c.split("|")[0]), d.rows.map(shape.cells),
      { sheetName: "Attendance", serial: docSerial("JUPEBATT"), meta: [["Session", o.session], ["Minimum attendance", d.minPercent == null ? "Not set" : `${d.minPercent}%`]] });
    downloadBlob(blob, `jupeb-attendance-${f.by}.xlsx`);
  }
  return (
    <Panel title="Attendance reports" right={<Btn kind="ghost" disabled={!d?.rows.length} onClick={() => void exportXlsx()}>Export (Excel)</Btn>}>
      <PBody>
        <div className="grid grid--4">
          <Field id="r-by" label="By"><select id="r-by" className="ctl" value={f.by} onChange={(e) => setF({ ...f, by: e.target.value })}><option value="student">Student</option><option value="subject">Subject</option><option value="class">Class</option><option value="date">Date</option></select></Field>
          <Field id="r-sem" label="Semester"><select id="r-sem" className="ctl" value={f.semester} onChange={(e) => setF({ ...f, semester: e.target.value })}><option value="">Both</option><option value="1">First</option><option value="2">Second</option></select></Field>
          <Field id="r-sub" label="Subject"><select id="r-sub" className="ctl" value={f.subject} onChange={(e) => setF({ ...f, subject: e.target.value })}><option value="">All</option>{o.subjects.map((s) => <option key={s.id} value={s.id}>{s.title}</option>)}</select></Field>
          <Field id="r-cls" label="Class"><select id="r-cls" className="ctl" value={f.klass} onChange={(e) => setF({ ...f, klass: e.target.value })}><option value="">All</option>{o.classes.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</select></Field>
          {f.by === "student" ? <>
            <Field id="r-below" label="Below the minimum only" hint={d?.minPercent == null ? "No minimum is set" : `Minimum ${d.minPercent}%`}><select id="r-below" className="ctl" value={f.below} disabled={d?.minPercent == null} onChange={(e) => setF({ ...f, below: e.target.value })}><option value="">No</option><option value="yes">Yes</option></select></Field>
            <Field id="r-abs" label="Absent at least" hint="Times"><input id="r-abs" className="ctl tnum" inputMode="numeric" value={f.absences} onChange={(e) => setF({ ...f, absences: e.target.value.replace(/\D/g, "") })} /></Field>
          </> : null}
        </div>
        {d?.minPercent == null ? <p className="sub2">No minimum attendance is set for {o.session}; standings are not judged until the JUPEB Office sets one.</p> : null}
        {d ? <DTable pageSize={50} cols={shape.cols} rows={d.rows.map(shape.cells)} /> : <p className="sub2">Loading…</p>}
      </PBody>
    </Panel>
  );
}

function Instructors({ o }: { o: Options }) {
  const [rows, setRows] = useState<Instructor[]>([]);
  const [f, setF] = useState<Record<string, string>>({ subjectId: o.subjects[0]?.id ?? "", classId: "", staff: "" });
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let live = true;
    void jcall<Instructor[]>(`${BASE}/instructors?session=${encodeURIComponent(o.session)}`).then((r) => { if (live && r.ok) setRows(r.data); });
    return () => { live = false; };
  }, [o.session]);
  async function assign() {
    setBusy(true);
    try {
      const r = await jcall<Instructor[]>(`${BASE}/instructors`, "POST", { session: o.session, subjectId: f.subjectId, classId: f.classId || null, staff: f.staff.trim() }, "JUPEB instructor assigned");
      if (!r.ok) { notifyProblem(r.problem); return; }
      setRows(r.data); setF({ ...f, staff: "" }); notify("Assigned.");
    } finally { setBusy(false); }
  }
  async function end(i: Instructor) {
    const r = await jcall<Instructor[]>(`${BASE}/instructors/${i.id}/end`, "POST", {}, "JUPEB instructor assignment ended");
    if (r.ok) { setRows(r.data); notify("Assignment ended."); } else notifyProblem(r.problem);
  }
  return (
    <>
      {o.office ? (
        <Panel title="Assign a lecturer to a subject">
          <PBody>
            <div className="grid grid--4">
              <Field id="i-sub" label="Subject"><select id="i-sub" className="ctl" value={f.subjectId} onChange={(e) => setF({ ...f, subjectId: e.target.value })}>{o.subjects.map((s) => <option key={s.id} value={s.id}>{s.title} ({s.code})</option>)}</select></Field>
              <Field id="i-cls" label="Class"><select id="i-cls" className="ctl" value={f.classId} onChange={(e) => setF({ ...f, classId: e.target.value })}><option value="">Every class</option>{o.classes.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</select></Field>
              <Field id="i-staff" label="Staff number or email"><input id="i-staff" className="ctl" maxLength={160} value={f.staff} onChange={(e) => setF({ ...f, staff: e.target.value })} /></Field>
              <div className="field"><label>&nbsp;</label><Btn kind="primary" disabled={busy || !f.subjectId || !f.staff.trim()} onClick={() => void assign()}>Assign</Btn></div>
            </div>
            <p className="sub2">An assigned lecturer sees only the students registered for that subject (in that class), and only while the assignment stands. They need the Lecturer role.</p>
          </PBody>
        </Panel>
      ) : null}
      <Panel title={`Instructors — ${o.session} (${rows.length})`}>
        <PBody><DTable pageSize={50} cols={["Subject", "Class", "Lecturer", "Staff number", "Assigned", ...(o.office ? ["|mid"] : [])]} rows={rows.map((i) => [`${i.subject_title} (${i.subject_code})`, i.class_name ?? "Every class", i.name, i.staff_number ?? "—", day(i.assigned_at),
          ...(o.office ? [<Btn key="e" kind="ghost" onClick={() => void end(i)}>End</Btn>] : [])])} /></PBody>
      </Panel>
    </>
  );
}

function Policy({ o, onSaved }: { o: Options; onSaved: (x: Partial<Options>) => void }) {
  const [scope, setScope] = useState<"session" | "*">("session");
  const [v, setV] = useState(o.policy == null ? "" : String(o.policy));
  const [band, setBand] = useState(o.warnBand == null ? "" : String(o.warnBand));
  const [min, setMin] = useState(String(o.minClasses ?? 3));
  const [busy, setBusy] = useState(false);
  async function save() {
    const n = v.trim() === "" ? null : Number(v);
    const b = band.trim() === "" ? null : Number(band);
    const c = Number(min);
    if (n != null && (Number.isNaN(n) || n < 0 || n > 100)) { notifyProblem({ status: 400, title: "A percentage from 0 to 100, or blank for none." }); return; }
    if (b != null && (Number.isNaN(b) || b < 0 || b > 50)) { notifyProblem({ status: 400, title: "The warning band is 0 to 50 points, or blank for none." }); return; }
    if (!Number.isInteger(c) || c < 1 || c > 50) { notifyProblem({ status: 400, title: "The classes counted before a warning are 1 to 50." }); return; }
    setBusy(true);
    try {
      const r = await jcall(`${BASE}/policy`, "PUT", { session: scope === "*" ? "*" : o.session, minPercent: n, warnBand: b, minClasses: c }, "JUPEB minimum attendance");
      if (!r.ok) { notifyProblem(r.problem); return; }
      onSaved({ policy: n, warnBand: b, minClasses: c }); notify(n == null ? "No minimum is set." : `Minimum attendance set to ${n}%.`);
    } finally { setBusy(false); }
  }
  return (
    <Panel title="Minimum attendance">
      <PBody>
        <p>The share of a subject&rsquo;s classes (excused ones left out; late counts as attended) a student must attend. While none is set, the portal judges no one and warns no one.</p>
        <div className="grid grid--3">
          <Field id="p-scope" label="For"><select id="p-scope" className="ctl" value={scope} onChange={(e) => setScope(e.target.value as "session" | "*")}><option value="session">{o.session} only</option><option value="*">Every session without its own</option></select></Field>
          <Field id="p-min" label="Minimum (%)" hint="Blank for none"><input id="p-min" className="ctl tnum" inputMode="decimal" value={v} onChange={(e) => setV(e.target.value)} /></Field>
          <Field id="p-band" label="At risk within (points above the minimum)" hint="Blank: nobody is flagged at risk"><input id="p-band" className="ctl tnum" inputMode="decimal" value={band} onChange={(e) => setBand(e.target.value)} /></Field>
          <Field id="p-classes" label="Classes counted before a warning" hint="A first absence is not a 0% to warn about"><input id="p-classes" className="ctl tnum" inputMode="numeric" value={min} onChange={(e) => setMin(e.target.value.replace(/\D/g, ""))} /></Field>
          <div className="field"><label>&nbsp;</label><Btn kind="primary" disabled={busy} onClick={() => void save()}>Save</Btn></div>
        </div>
        <p className="sub2">Now: {o.policy == null ? "no minimum set" : `${o.policy}%`}{o.warnBand != null && o.policy != null ? `; at risk below ${Number(o.policy) + Number(o.warnBand)}%` : ""}; warnings after {o.minClasses ?? 3} classes counted.
          Students below the minimum are warned by email on the &ldquo;Attendance below the minimum&rdquo; reminder (JUPEB settings → Reminders); what a shortfall means for the examination is the University&rsquo;s decision.</p>
      </PBody>
    </Panel>
  );
}

interface StandingRow {
  member_ref: string; application_no: string; name: string; exam_no: string | null; class_name: string | null; semester: number; code: string; title: string;
  total: number; counted: number; absent: number; rate: number | null; min_percent: number | null; verdict: string | null; at_risk: boolean; warnable: boolean; last_warned: string | null;
}

/** who is below the minimum, or close to it, subject by subject — and warning them now */
function Standing({ o }: { o: Options }) {
  const [only, setOnly] = useState<"below" | "risk" | "all">("below");
  const [d, setD] = useState<{ policy: { min_percent: number | null; warn_band: number | null; min_classes: number } | null; rows: StandingRow[] } | null>(null);
  const [tick, setTick] = useState(0);
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let live = true;
    void jcall<{ policy: { min_percent: number | null; warn_band: number | null; min_classes: number } | null; rows: StandingRow[] }>(`${BASE}/standing?session=${encodeURIComponent(o.session)}&only=${only}`)
      .then((r) => { if (live) { if (r.ok) setD(r.data); else notifyProblem(r.problem); } });
    return () => { live = false; };
  }, [o.session, only, tick]);
  const min = d?.policy?.min_percent ?? null;
  const students = new Set((d?.rows ?? []).map((r) => r.member_ref)).size;
  const word = (r: StandingRow) => r.verdict === "NOT_ELIGIBLE" ? <Pil kind="bad">Below the minimum</Pil> : r.at_risk ? <Pil kind="warn">Close to the minimum</Pil>
    : r.verdict === "ELIGIBLE" ? <Pil kind="ok">Meets the minimum</Pil> : r.verdict === "REQUIRES_REVIEW" ? <Pil kind="grey">All excused</Pil> : <span className="sub2">—</span>;
  async function warn() {
    setBusy(true);
    try {
      const r = await jcall<{ result: { sent: number } }>(`${BASE}/warn`, "POST", {}, "JUPEB attendance warnings sent");
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(`${r.data.result.sent} student${r.data.result.sent === 1 ? "" : "s"} warned. A student warned in the last day, or as often as the rule allows, is not warned again.`);
      setTick((t) => t + 1);
    } finally { setBusy(false); }
  }
  async function exportXlsx() {
    if (!d) return;
    const blob = await brandedXlsx(`JUPEB attendance standing — ${o.session}`, ["Student", "Application no", "Exam no", "Class", "Subject", "Semester", "Classes counted", "Absent", "Rate (%)", "Minimum (%)", "Standing", "Last warned"],
      d.rows.map((r) => [r.name, r.application_no, r.exam_no ?? "", r.class_name ?? "", r.title, r.semester, r.counted, r.absent, r.rate == null ? "" : Number(r.rate), r.min_percent == null ? "" : Number(r.min_percent),
        r.verdict === "NOT_ELIGIBLE" ? "Below the minimum" : r.at_risk ? "Close to the minimum" : r.verdict === "ELIGIBLE" ? "Meets the minimum" : "", r.last_warned ? when(r.last_warned) : ""]),
      { sheetName: "Standing", serial: docSerial("JUPEBSTAND"), meta: [["Session", o.session], ["Minimum", min == null ? "Not set" : `${min}%`]] });
    downloadBlob(blob, `jupeb-attendance-standing-${only}.xlsx`);
  }
  if (!d) return <Note kind="info" title="Loading the standing…">One moment.</Note>;
  if (min == null) return <Note kind="info" title="No minimum attendance is set">Set it on the Minimum attendance tab; until then nobody is below it, at risk or warned.</Note>;
  return (
    <Panel title={only === "below" ? `Below the minimum (${students} student${students === 1 ? "" : "s"})` : only === "risk" ? `Close to the minimum (${students})` : `Every student (${students})`}
      right={<span className="row">
        <Btn kind="ghost" disabled={!d.rows.length} onClick={() => void exportXlsx()}>Export (Excel)</Btn>
        {o.office ? <Btn kind="secondary" disabled={busy} onClick={() => void warn()}>{busy ? "Warning…" : "Warn students below the minimum now"}</Btn> : null}
      </span>}>
      <PBody>
        <select className="ctl" style={{ width: 220, marginBottom: "var(--s-2)" }} aria-label="Show" value={only} onChange={(e) => setOnly(e.target.value as typeof only)}>
          <option value="below">Below the minimum</option><option value="risk" disabled={d.policy?.warn_band == null}>Close to the minimum</option><option value="all">Everyone</option></select>
        <p className="sub2">Minimum {min}%{d.policy?.warn_band != null ? `; close to it below ${Number(min) + Number(d.policy.warn_band)}%` : ""}. A student is warned once {d.policy?.min_classes ?? 3} classes of a subject are counted.</p>
        <DTable pageSize={50} cols={["Student", "Application no", "Class", "Subject", "Semester|num", "Classes|num", "Absent|num", "Rate|num", "Standing", "Last warned"]}
          texts={d.rows.map((r) => `${r.name} ${r.application_no} ${r.exam_no ?? ""} ${r.title}`)}
          rows={d.rows.map((r) => [r.name, r.application_no, r.class_name ?? "—", r.title, r.semester, r.counted, r.absent, r.rate == null ? "—" : `${Number(r.rate)}%`,
            <span key="w">{word(r)}{r.verdict === "NOT_ELIGIBLE" && !r.warnable ? <div className="sub2">too few classes to warn yet</div> : null}</span>, r.last_warned ? when(r.last_warned) : "—"])} />
      </PBody>
    </Panel>
  );
}
