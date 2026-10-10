"use client";

/**
 * CCE evening classes (V380): a lecturer's classes of the Centre for Continuing Education in the CCE session — the slots, the
 * class list, and the register of each lecture. The lecturer marks each student present, absent, late or excused; a mark
 * already saved is changed only with the reason; the register is locked when it is done (the Centre or the Academic Office
 * reopens a locked register). The Centre and the Academic Office see every CCE class.
 */
import { useEffect, useState } from "react";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { ATT_LABEL, WEEKDAYS, ccall, day, labelOf, semesterWord, when, type Slot } from "@/lib/cce";

interface MyClass { id: string; course_code: string; title: string; units: number; level: number; session: string; semester: number; department: string | null; role: string | null;
  lecturer: string | null; students: number; registers: number; last_held: string | null; slots: Slot[] }
interface Mine { session: string; all: boolean; classes: MyClass[] }
interface ClassView { id: string; course_code: string; title: string; units: number; level: number; session: string; semester: number; lecturer: string | null;
  slots: Slot[]; policy: { min_percent: number | null; warn_band: number | null; min_classes: number; show_students: boolean } | null;
  students: { id: string; number: string; name: string; programme_code: string; programme: string; level: number; registration: string; entry_type: string; counted: number; attended: number; late: number; excused: number }[];
  registers: { id: string; held_on: string; topic: string | null; saved_at: string | null; locked_at: string | null; starts_at: string | null; venue: string | null; marked: number; present: number; late: number; absent: number; excused: number }[] }
interface Sheet { id: string; class_id: string; session: string; semester: number; held_on: string; topic: string | null; saved_at: string | null; locked_at: string | null; locked_by: string | null;
  opened_by: string | null; starts_at: string | null; ends_at: string | null; venue: string | null;
  marks: { student_id: string; name: string; number: string; programme_code: string; level: string; status: string | null; marked_time: string | null; remarks: string | null }[];
  changes: { student_id: string; old_status: string; new_status: string; reason: string; changed_at: string; changed_by: string | null }[] }

const STATUSES = ["PRESENT", "LATE", "ABSENT", "EXCUSED"] as const;
const today = () => new Date(Date.now() + 3600_000).toISOString().slice(0, 10);   // Africa/Lagos is UTC+1

export function CceTeaching() {
  const [mine, setMine] = useState<Mine | null>(null);
  const [cls, setCls] = useState<string | null>(null);
  const [reg, setReg] = useState<string | null>(null);
  useEffect(() => {
    let live = true;
    void ccall<Mine>("/api/v1/cce/teaching").then((r) => { if (!live) return; if (r.ok) setMine(r.data); else notifyProblem(r.problem); });
    return () => { live = false; };
  }, [cls, reg]);
  if (reg) return <RegisterSheet id={reg} back={() => setReg(null)} />;
  if (cls) return <ClassPage id={cls} back={() => setCls(null)} open={setReg} />;
  if (!mine) return <Note kind="info" title="Reading your CCE classes…">One moment.</Note>;
  return (
    <>
      <PageHead title="CCE evening classes" description={`CCE session ${mine.session} and the one after it`} />
      {mine.all ? <Note kind="info" title="Every CCE class" /> : null}
      {mine.classes.length ? (
        <Panel title={`${mine.classes.length} class${mine.classes.length === 1 ? "" : "es"}`}>
          <DTable cols={["Course", "Session", "Lectures", "Students|num", "Registers|num", "Last register|mid", ""]} rows={mine.classes.map((c) => [
            <span key="c"><b className="tnum">{c.course_code}</b> {c.title}<div className="sub2">{c.units} units · {c.level} level · {c.department ?? ""}{c.role ? ` · ${c.role}` : c.lecturer ? ` · ${c.lecturer}` : ""}</div></span>,
            <span key="s" className="sub2">{c.session} · {semesterWord(c.semester).toLowerCase()}</span>,
            c.slots.length ? <span key="t" className="sub2">{c.slots.map((s) => `${WEEKDAYS[s.weekday].slice(0, 3)} ${s.starts_at}–${s.ends_at}, ${s.venue}`).join("; ")}</span> : <span key="t" className="sub2">not on the timetable yet</span>,
            c.students, c.registers, day(c.last_held), <Btn key="o" kind="primary" onClick={() => setCls(c.id)}>Open</Btn>,
          ])} />
        </Panel>
      ) : <Note kind="info" title="No CCE class is allocated to you" />}
    </>
  );
}

function ClassPage({ id, back, open }: { id: string; back: () => void; open: (register: string) => void }) {
  const [v, setV] = useState<ClassView | null>(null);
  const [held, setHeld] = useState(today());
  const [slot, setSlot] = useState("");
  const [topic, setTopic] = useState("");
  useEffect(() => {
    let live = true;
    void ccall<ClassView>(`/api/v1/cce/teaching/classes/${id}`).then((r) => { if (!live) return; if (r.ok) { setV(r.data); setSlot(r.data.slots[0]?.id ?? ""); } else notifyProblem(r.problem); });
    return () => { live = false; };
  }, [id]);
  if (!v) return <Note kind="info" title="Reading the class…">One moment.</Note>;
  async function take() {
    const r = await ccall<Sheet>(`/api/v1/cce/teaching/classes/${id}/registers`, "POST", { heldOn: held, slotId: slot || null, topic: topic.trim() || null }, `The register of ${v!.course_code} for ${held}`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    open(r.data.id);
  }
  const p = v.policy;
  return (
    <>
      <PageHead title={`${v.course_code} ${v.title}`} description={`${v.session} · ${semesterWord(v.semester).toLowerCase()} · ${v.units} units · ${v.level} level${v.lecturer ? ` · ${v.lecturer}` : ""}`} actions={<Btn kind="ghost" onClick={back}>Your classes</Btn>} />
      <Tiles cls="grid--4" items={[
        ["STUDENTS", v.students.length, null, "Registered on the class"],
        ["LECTURES RECORDED", v.registers.length, null, `${v.registers.filter((r) => r.locked_at).length} locked`],
        ["LECTURES A WEEK", v.slots.length, null, v.slots.map((s) => `${WEEKDAYS[s.weekday].slice(0, 3)} ${s.starts_at}`).join(" · ") || "Not on the timetable"],
        ["MINIMUM ATTENDANCE", p?.min_percent != null ? `${p.min_percent}%` : "None set", null, "The Centre's policy"],
      ]} />
      <Panel title="Take the register">
        <PBody>
          <div className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
            <Field id="tr-d" label="Lecture of"><input id="tr-d" type="date" className="ctl" max={today()} value={held} onChange={(e) => setHeld(e.target.value)} /></Field>
            <Field id="tr-s" label="Lecture"><select id="tr-s" className="ctl" value={slot} onChange={(e) => setSlot(e.target.value)}><option value="">Not tied to a slot</option>{v.slots.map((s) => <option key={s.id} value={s.id}>{WEEKDAYS[s.weekday]} {s.starts_at}–{s.ends_at}, {s.venue}</option>)}</select></Field>
            <Field id="tr-t" label="Topic"><input id="tr-t" className="ctl" style={{ width: 280 }} value={topic} onChange={(e) => setTopic(e.target.value)} /></Field>
          </div>
          <Btn kind="primary" disabled={!v.students.length} onClick={() => void take()}>Open the register</Btn>
          {!v.students.length ? <div className="sub2 mt-1">No student is registered on the class yet.</div> : null}
        </PBody>
      </Panel>
      <Panel title="Registers">
        {v.registers.length ? (
          <DTable cols={["Lecture|mid", "Topic", "Present|num", "Late|num", "Absent|num", "Excused|num", "State", ""]} rows={v.registers.map((r) => [
            <span key="d" className="tnum">{day(r.held_on)}{r.starts_at ? ` ${r.starts_at}` : ""}</span>, r.topic ?? "—", r.present, r.late, r.absent, r.excused,
            r.locked_at ? <Pil key="s" kind="grey">Locked</Pil> : r.saved_at ? <Pil key="s" kind="info">Saved</Pil> : <Pil key="s" kind="warn">Not saved</Pil>,
            <Btn key="o" kind="ghost" onClick={() => open(r.id)}>{r.locked_at ? "View" : "Mark"}</Btn>,
          ])} />
        ) : <PBody><div className="sub2">No register taken yet.</div></PBody>}
      </Panel>
      <Panel title="The class list">
        {v.students.length ? (
          <DTable cols={["Student", "Programme", "Level|num", "Attended|num", "Late|num", "Excused|num", "Rate|num"]} texts={v.students.map((s) => `${s.name} ${s.number}`)} rows={v.students.map((s) => [
            <span key="n">{s.name}<div className="sub2 tnum">{s.number}{s.entry_type === "CARRYOVER" ? " · carry-over" : ""}{s.registration === "SUBMITTED" ? " · awaiting approval" : ""}</div></span>,
            s.programme, s.level, `${s.attended} of ${s.counted}`, s.late, s.excused, Number(s.counted) ? `${Math.round((100 * Number(s.attended)) / Number(s.counted))}%` : "—",
          ])} />
        ) : <PBody><div className="sub2">No student is registered on this class yet.</div></PBody>}
      </Panel>
    </>
  );
}

function RegisterSheet({ id, back }: { id: string; back: () => void }) {
  const [v, setV] = useState<Sheet | null>(null);
  const [marks, setMarks] = useState<Record<string, { status: string; remarks: string }>>({});
  const [reason, setReason] = useState("");
  const [tick, setTick] = useState(0);
  useEffect(() => {
    let live = true;
    void ccall<Sheet>(`/api/v1/cce/teaching/registers/${id}`).then((r) => {
      if (!live) return;
      if (!r.ok) { notifyProblem(r.problem); return; }
      setV(r.data);
      setMarks(Object.fromEntries(r.data.marks.map((m) => [m.student_id, { status: m.status ?? "", remarks: m.remarks ?? "" }])));
    });
    return () => { live = false; };
  }, [id, tick]);
  if (!v) return <Note kind="info" title="Reading the register…">One moment.</Note>;
  const locked = !!v.locked_at;
  const changed = v.marks.filter((m) => m.status && (marks[m.student_id]?.status !== m.status || (marks[m.student_id]?.remarks ?? "") !== (m.remarks ?? ""))).length;
  const unmarked = v.marks.filter((m) => !marks[m.student_id]?.status).length;
  async function save() {
    const body = { marks: v!.marks.filter((m) => marks[m.student_id]?.status).map((m) => ({ student: m.student_id, status: marks[m.student_id].status, remarks: marks[m.student_id].remarks.trim() || null })),
      reason: reason.trim() || null };
    const r = await ccall<Sheet & { result: { marked: number; corrected: number; unchanged: number } }>(`/api/v1/cce/teaching/registers/${id}/marks`, "PUT", body, `The register of ${day(v!.held_on)} saved`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    notify(`Saved: ${r.data.result.marked} marked, ${r.data.result.corrected} corrected`);
    setReason(""); setTick((t) => t + 1);
  }
  async function lock() {
    const r = await ccall<Sheet>(`/api/v1/cce/teaching/registers/${id}/lock`, "POST", {}, `The register of ${day(v!.held_on)} locked`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    notify("The register is locked.");
    setTick((t) => t + 1);
  }
  const all = (status: string) => setMarks(Object.fromEntries(v.marks.map((m) => [m.student_id, { status: marks[m.student_id]?.status || status, remarks: marks[m.student_id]?.remarks ?? "" }])));
  return (
    <>
      <PageHead title={`Register of ${day(v.held_on)}`} description={`${v.session} · ${semesterWord(v.semester).toLowerCase()}${v.starts_at ? ` · ${v.starts_at}–${v.ends_at}, ${v.venue}` : ""}${v.topic ? ` · ${v.topic}` : ""}`} actions={<Btn kind="ghost" onClick={back}>Back to the class</Btn>} />
      {locked ? <Note kind="info" title={`Locked ${when(v.locked_at)}${v.locked_by ? ` by ${v.locked_by}` : ""}`}>Only the Centre reopens it for a correction.</Note> : null}
      <Panel title={`${v.marks.length} student${v.marks.length === 1 ? "" : "s"}`} right={!locked ? <span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => all("PRESENT")}>Mark the rest present</Btn></span> : null}>
        <DTable pageSize={0} noPrint={!locked} cols={["Student", "Mark", "Remarks", "Time|mid"]} rows={v.marks.map((m) => {
          const cur = marks[m.student_id] ?? { status: "", remarks: "" };
          return [
            <span key="n">{m.name}<div className="sub2 tnum">{m.number} · {m.programme_code} {m.level}</div></span>,
            locked ? <Pil key="s" kind={labelOf(ATT_LABEL, m.status)[1]}>{labelOf(ATT_LABEL, m.status)[0]}</Pil> : (
              <span key="s" className="row row--inline row--tight" role="radiogroup" aria-label={`Mark for ${m.name}`}>
                {STATUSES.map((s) => <Btn key={s} kind={cur.status === s ? (s === "ABSENT" ? "urgent" : s === "PRESENT" ? "go" : "secondary") : "ghost"} aria-label={`${ATT_LABEL[s][0]}: ${m.name}`}
                  onClick={() => setMarks({ ...marks, [m.student_id]: { ...cur, status: s } })}>{ATT_LABEL[s][0]}</Btn>)}
              </span>
            ),
            locked ? (m.remarks ?? "") : <input key="r" className="ctl" aria-label={`Remarks for ${m.name}`} value={cur.remarks} onChange={(e) => setMarks({ ...marks, [m.student_id]: { ...cur, remarks: e.target.value } })} />,
            <span key="t" className="tnum sub2">{m.marked_time ?? ""}</span>,
          ];
        })} />
        {!locked ? (
          <PBody>
            {changed ? <Field id="rs-why" label={`Reason for changing ${changed} saved mark${changed === 1 ? "" : "s"}`} required><input id="rs-why" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)} /></Field> : null}
            <div className="row row--inline row--tight">
              <Btn kind="primary" disabled={changed > 0 && !reason.trim()} onClick={() => void save()}>Save the register</Btn>
              <Btn kind="ghost" disabled={!v.saved_at || unmarked > 0} onClick={() => void lock()} title={unmarked ? "Mark every student first" : undefined}>Lock it</Btn>
              {unmarked ? <span className="sub2">{unmarked} not marked yet</span> : null}
            </div>
          </PBody>
        ) : null}
      </Panel>
      {v.changes.length ? (
        <Panel title="Corrections">
          <DTable cols={["Student", "From", "To", "Reason", "By", "At|mid"]} rows={v.changes.map((c, i) => [
            <span key={`n${i}`}>{v.marks.find((m) => m.student_id === c.student_id)?.name ?? "—"}</span>, labelOf(ATT_LABEL, c.old_status)[0], labelOf(ATT_LABEL, c.new_status)[0], c.reason, c.changed_by ?? "—", when(c.changed_at),
          ])} />
        </Panel>
      ) : null}
      <KvGrid cls="grid--3" pairs={[["Opened by", v.opened_by ?? "—"], ["Last saved", v.saved_at ? when(v.saved_at) : "Not yet"], ["Lecture", v.starts_at ? `${v.starts_at}–${v.ends_at}` : "Not tied to a slot"]]} />
    </>
  );
}
