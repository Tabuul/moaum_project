"use client";

/** tExamSession — proto/part28.html: the container everything hangs in, and the sheets it is waiting on. */
import { reasonHeader } from "@/lib/reason";
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import type { Scope } from "@/lib/scope";
import type { ExamSession, Monitor } from "@/lib/results";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Bar, day, Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify } from "@/components/proto/Toast";

export function ExamSessions({ sessions, scope, list, monitor }: { sessions: string[]; scope: Scope; list: ExamSession[]; monitor: Monitor | null }) {
  const router = useRouter();
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [said, setSaid] = useState<string | null>(null);
  const [f, setF] = useState({ session: scope.session, semester: "1", kind: "MAIN", examsFrom: "", examsTo: "", sheetsDue: "" });
  const [today] = useState(() => Date.now());
  const [edit, setEdit] = useState<ExamSession | null>(null);
  const [ed, setEd] = useState({ session: "", semester: "1", kind: "MAIN", examsFrom: "", examsTo: "", sheetsDue: "" });

  function openEdit(e: ExamSession) {
    setEdit(e);
    setEd({ session: e.session, semester: String(e.semester), kind: e.kind, examsFrom: (e.examsFrom ?? "").slice(0, 10), examsTo: (e.examsTo ?? "").slice(0, 10), sheetsDue: (e.sheetsDue ?? "").slice(0, 10) });
    setProblem(null);
  }

  async function saveDates() {
    if (!edit) return;
    setBusy("edit");
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/results/exam-sessions/${edit.id}`, {
        method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Examination session ${ed.session} edited`) }, body: JSON.stringify({ ...ed, semester: Number(ed.semester) }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return; }
      setEdit(null);
      setSaid("The examination session dates were updated.");
      router.refresh();
    } finally {
      setBusy(null);
    }
  }

  async function post(path: string, body: unknown, reason: string, key: string): Promise<Record<string, unknown> | null> {
    setBusy(key);
    setProblem(null);
    try {
      const r = await fetch(path, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (r.status === 202) {
        setSaid((j && j.note) || "Accepted");
        return j;
      }
      if (!r.ok) {
        setProblem(j ?? { status: r.status, title: r.statusText });
        return null;
      }
      notify(reason);
      router.refresh();
      return j;
    } finally {
      setBusy(null);
    }
  }

  async function create(open: boolean) {
    const made = await post("/api/bff/api/v1/results/exam-sessions", { ...f, semester: Number(f.semester) }, `Examination session ${f.session} semester ${f.semester} ${open ? "opened" : "saved as a draft"}`, "create");
    if (made && open && made.id) {
      const r = await post(`/api/bff/api/v1/results/exam-sessions/${made.id}/open`, {}, `Examination session opened`, "open");
      if (r) setSaid(`${r.sheetsMade} score sheets generated; ${r.offeringsWithoutLecturer} offerings have no lecturer and generated none.`);
    }
  }

  const open = list.filter((e) => e.state === "OPEN");
  const courses = open.reduce((n, e) => n + e.sheets, 0);
  const candidates = open.reduce((n, e) => n + e.candidates, 0);
  const due = open.length ? open.map((e) => e.sheetsDue).sort()[0] : null;
  const faculties = monitor?.faculties ?? [];
  const holding = monitor ? (scope.fac && faculties.some((x) => x.facultyCode === scope.fac) ? faculties.find((x) => x.facultyCode === scope.fac) : [...faculties].sort((a, b) => b.outstanding - a.outstanding)[0]) : undefined;
  const outstanding = monitor && holding ? monitor.outstanding.filter((o) => o.facultyCode === holding.facultyCode) : [];

  return (
    <>
      <Note kind="info" title="An examination session is the container everything else hangs in">
        It fixes the dates, the courses to be examined, the halls, the candidates and the deadline by which every score sheet must be in. Once it is open the portal can answer the only question that matters in December: which sheets are missing, and whose are they.
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="info" title="Done">{said}</Note> : null}
      <Tiles items={[
        ["Open sessions", String(open.length), open.length ? "var(--green-ink)" : null, open.length ? `${open[0].session} ${open[0].semester === 1 ? "First" : open[0].semester === 2 ? "Second" : "Third"} semester` : "None open"],
        ["Courses examined", String(courses), null, "Sheets generated over the register"],
        ["Candidates", candidates.toLocaleString(), null, "Registered for an examined course"],
        ["Sheets due", due ? day(due, false) : "—", "var(--red-ink)", due ? `${Math.max(0, Math.round((new Date(due).getTime() - today) / 86400000))} days from today` : "No session open"],
      ]} />

      <Panel title="Create an examination session">
        <PBody>
          <div className="grid grid--3">
            <div className="field"><label htmlFor="es-s">Academic session</label><select id="es-s" className="ctl" value={f.session} onChange={(e) => setF({ ...f, session: e.target.value })}>{sessions.map((s) => <option key={s}>{s}</option>)}</select></div>
            <div className="field"><label htmlFor="es-m">Semester</label><select id="es-m" className="ctl" value={f.semester} onChange={(e) => setF({ ...f, semester: e.target.value })}><option value="1">First</option><option value="2">Second</option><option value="3">Third</option></select></div>
            <div className="field"><label htmlFor="es-t">Type</label><select id="es-t" className="ctl" value={f.kind} onChange={(e) => setF({ ...f, kind: e.target.value })}><option value="MAIN">Main examination</option></select></div>
            <div className="field"><label htmlFor="es-f">Examinations begin</label><input id="es-f" className="ctl" type="date" value={f.examsFrom} onChange={(e) => setF({ ...f, examsFrom: e.target.value })} /></div>
            <div className="field"><label htmlFor="es-e">Examinations end</label><input id="es-e" className="ctl" type="date" value={f.examsTo} onChange={(e) => setF({ ...f, examsTo: e.target.value })} /></div>
            <div className="field"><label htmlFor="es-d">Score sheets due</label><input id="es-d" className="ctl" type="date" value={f.sheetsDue} onChange={(e) => setF({ ...f, sheetsDue: e.target.value })} /></div>
          </div>
          <Note kind="info" title="Opening a session generates every score sheet at once">
            One sheet per course offered, over the approved register at the moment of opening, in the name of the lecturer the department allocated. A course with no allocated lecturer generates no sheet — and is counted the moment the session opens, which is where an unallocated course is found before December rather than in it.
          </Note>
          <div style={{ display: "flex", gap: 9, flexWrap: "wrap" }}>
            <button className="btn btn--primary btn--sm" disabled={busy !== null || !f.examsFrom || !f.examsTo || !f.sheetsDue} onClick={() => void create(true)}>Open the session</button>
            <Btn kind="ghost" disabled={busy !== null || !f.examsFrom || !f.examsTo || !f.sheetsDue} onClick={() => void create(false)}>Save as a draft</Btn>
          </div>
        </PBody>
      </Panel>

      {list.length ? (
        <Panel title="Examination sessions" right={`${list.length} on record`}>
          <DTable
            cols={["Session|mid", "Semester|mid", "Type|mid", "Examinations|mid", "Sheets due|mid", "Sheets|mid", "Outstanding|mid", "State|mid", "|num"]}
            rows={list.map((e) => [
              <b className="tnum" key="s">{e.session}</b>, <span className="tnum" key="m">{e.semester === 1 ? "First" : e.semester === 2 ? "Second" : "Third"}</span>,
              <span className="sub2" key="k">{e.kind === "MAIN" ? "Main" : e.kind === "RESIT" ? "Re-sit" : "Special"}</span>,
              <span className="tnum" key="x">{day(e.examsFrom, false)} – {day(e.examsTo, false)}</span>,
              <span className="tnum" key="d">{day(e.sheetsDue)}</span>, <span className="tnum" key="n">{e.sheets}</span>,
              <span className="tnum" key="o" style={e.outstanding ? { color: "var(--red-ink)", fontWeight: 700 } : undefined}>{e.outstanding}</span>,
              e.state === "OPEN" ? <Pil kind="ok" key="st">Open</Pil> : e.state === "DRAFT" ? <Pil kind="info" key="st">Draft</Pil> : <Pil kind="grey" key="st">Closed</Pil>,
              <span key="a" style={{ display: "inline-flex", gap: 6, justifyContent: "flex-end" }}>
                {e.state !== "CLOSED" ? <Btn kind="ghost" disabled={busy !== null} onClick={() => openEdit(e)}>Edit</Btn> : null}
                {e.state === "DRAFT" ? <Btn kind="primary" disabled={busy !== null} onClick={() => void post(`/api/bff/api/v1/results/exam-sessions/${e.id}/open`, {}, "Examination session opened", e.id).then((r) => r && setSaid(`${r.sheetsMade} score sheets generated; ${r.offeringsWithoutLecturer} offerings have no lecturer.`))}>Open</Btn> : <Link href={`/examinations/sessions?exam=${e.id}`} className="btn btn--ghost btn--sm">Monitor</Link>}
              </span>,
            ])}
          />
        </Panel>
      ) : null}

      {edit ? (
        <Modal title="Edit the examination session" sub={`${edit.session} · ${edit.semester === 1 ? "First" : edit.semester === 2 ? "Second" : "Third"} semester · ${edit.kind === "MAIN" ? "Main" : edit.kind === "RESIT" ? "Re-sit" : "Special"}`} onClose={() => setEdit(null)}
          foot={<><Btn kind="ghost" onClick={() => setEdit(null)}>Cancel</Btn><span style={{ flexGrow: 1 }} />
            <Btn kind="primary" disabled={busy !== null || !ed.examsFrom || !ed.examsTo || !ed.sheetsDue} onClick={() => void saveDates()}>{busy === "edit" ? "Saving…" : "Save the dates"}</Btn></>}>
          <Note kind={edit.sheets > 0 ? "info" : "info"} title={edit.sheets > 0 ? "Only the dates can change" : "Session, semester, type and dates can all change"}>
            {edit.sheets > 0
              ? `This session already has ${edit.sheets} score sheet${edit.sheets === 1 ? "" : "s"} generated, so its academic session, semester and type are fixed — those score sheets belong to them. You can still move the dates.`
              : "No score sheet has been generated yet, so you can move it to another academic session, semester or type as well as change the dates."}
            {edit.state === "OPEN" && edit.sheets > 0 ? " The generated sheets are not affected by a date change." : ""} Score sheets must be due on or after the examinations end.
          </Note>
          {problem ? <ProblemNotice problem={problem} /> : null}
          <div className="grid grid--3">
            <Field id="ee-s" label="Academic session"><select id="ee-s" className="ctl" value={ed.session} disabled={edit.sheets > 0} onChange={(e) => setEd({ ...ed, session: e.target.value })}>{sessions.map((s) => <option key={s}>{s}</option>)}</select></Field>
            <Field id="ee-m" label="Semester"><select id="ee-m" className="ctl" value={ed.semester} disabled={edit.sheets > 0} onChange={(e) => setEd({ ...ed, semester: e.target.value })}><option value="1">First</option><option value="2">Second</option><option value="3">Third</option></select></Field>
            <Field id="ee-t" label="Type"><select id="ee-t" className="ctl" value={ed.kind} disabled={edit.sheets > 0} onChange={(e) => setEd({ ...ed, kind: e.target.value })}><option value="MAIN">Main examination</option><option value="RESIT">Re-sit</option><option value="SPECIAL">Special</option></select></Field>
            <Field id="ee-f" label="Examinations begin"><input id="ee-f" className="ctl" type="date" value={ed.examsFrom} onChange={(e) => setEd({ ...ed, examsFrom: e.target.value })} /></Field>
            <Field id="ee-e" label="Examinations end"><input id="ee-e" className="ctl" type="date" value={ed.examsTo} onChange={(e) => setEd({ ...ed, examsTo: e.target.value })} /></Field>
            <Field id="ee-d" label="Score sheets due"><input id="ee-d" className="ctl" type="date" value={ed.sheetsDue} onChange={(e) => setEd({ ...ed, sheetsDue: e.target.value })} /></Field>
          </div>
        </Modal>
      ) : null}

      <Panel title="Submission monitor" right={monitor ? `${monitor.examSession.session} · every faculty, live` : "Every faculty, live"}>
        <DTable
          cols={["Faculty", "Sheets expected|mid", "Submitted|mid", "Verified|mid", "Past the Board|mid", "Outstanding|mid", "Progress"]}
          rows={faculties.map((x) => [
            <strong key="f">{x.facultyName}</strong>, <span className="tnum" key="e">{x.expected}</span>, <span className="tnum" key="s">{x.submitted}</span>,
            <span className="tnum" key="v">{x.verified}</span>, <span className="tnum" key="b">{x.pastTheBoard}</span>,
            <span className="tnum" key="o" style={x.outstanding ? { color: "var(--red-ink)", fontWeight: 700 } : undefined}>{x.outstanding}</span>,
            <Bar key="p" pct={x.progress} colour={x.outstanding ? (x.progress < 50 ? "var(--red)" : "var(--chrome)") : "var(--green)"} />,
          ])}
        />
        {!faculties.length ? <PBody><div className="sub2">{monitor ? "No sheets were generated in this session yet." : "No examination session is open. Open one above and the monitor fills from the register."}</div></PBody> : null}
      </Panel>

      {holding && outstanding.length ? (
        <Panel title={`The ${outstanding.length} sheet${outstanding.length === 1 ? "" : "s"} holding the Faculty of ${holding.facultyName}`} right="Named, with the person and the days">
          <DTable
            cols={["Course", "Department", "Lecturer", "Candidates|mid", "Days late|mid", "Escalated to", "Action|num"]}
            rows={outstanding.map((o) => [
              <b className="tnum" key="c">{o.courseCode}</b>, <span className="sub2" key="d">{o.deptName}</span>, <span key="l">{o.lecturer ?? "—"}</span>,
              <span className="tnum" key="n">{o.candidates}</span>,
              <span className="tnum" key="x" style={{ color: "var(--red-ink)", fontWeight: 700 }}>{o.daysLate ?? "—"}</span>,
              <span className="sub2" key="e">{o.escalatedTo}</span>,
              <span key="a"><Btn kind="ghost" disabled={busy !== null} onClick={() => void post(`/api/bff/api/v1/results/sheets/${o.id}/remind`, {}, `Reminder for ${o.courseCode}`, o.id)}>Remind</Btn> <Btn kind="urgent" disabled={busy !== null} onClick={() => void post(`/api/bff/api/v1/results/sheets/${o.id}/remind`, {}, `Escalation for ${o.courseCode}`, o.id)}>Escalate</Btn></span>,
            ])}
          />
        </Panel>
      ) : null}
    </>
  );
}
