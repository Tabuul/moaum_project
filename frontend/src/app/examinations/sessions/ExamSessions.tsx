"use client";

/** tExamSession — proto/part28.html: the container everything hangs in, and the sheets it is waiting on. Set up, edited and
 *  opened by the Director of ICT alone, from Portal Management; every office that reads results reads it and its monitor. */
import { reasonHeader } from "@/lib/reason";
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import type { Scope } from "@/lib/scope";
import { chaseWords, streamWords, type ExamSession, type Monitor } from "@/lib/results";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Bar, day, Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify , notifyProblem } from "@/components/proto/Toast";

export function ExamSessions({ sessions, scope, list, monitor, actingOffice }: { sessions: string[]; scope: Scope; list: ExamSession[]; monitor: Monitor | null; actingOffice: string | null }) {
  const router = useRouter();
  // creating, editing and opening an examination session is the Director of ICT's (the API refuses every other office)
  const canEdit = actingOffice === "ict";
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [said, setSaid] = useState<string | null>(null);
  const [f, setF] = useState({ session: scope.session, semester: "1", kind: "MAIN", stream: "REGULAR", examsFrom: "", examsTo: "", sheetsDue: "" });
  const [today] = useState(() => Date.now());
  const [edit, setEdit] = useState<ExamSession | null>(null);
  const [ed, setEd] = useState({ session: "", semester: "1", kind: "MAIN", stream: "REGULAR", examsFrom: "", examsTo: "", sheetsDue: "" });

  function openEdit(e: ExamSession) {
    setEdit(e);
    setEd({ session: e.session, semester: String(e.semester), kind: e.kind, stream: e.stream ?? "REGULAR", examsFrom: (e.examsFrom ?? "").slice(0, 10), examsTo: (e.examsTo ?? "").slice(0, 10), sheetsDue: (e.sheetsDue ?? "").slice(0, 10) });
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
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
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
        setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText });
        return null;
      }
      notify(reason);
      /* V359: a reminder or an escalation says what was sent, and to whom */
      if (j && typeof j.said === "string") setSaid(j.said);
      router.refresh();
      return j;
    } finally {
      setBusy(null);
    }
  }

  async function create(open: boolean) {
    const made = await post("/api/bff/api/v1/results/exam-sessions", { ...f, semester: Number(f.semester) }, `Examination session ${f.session} semester ${f.semester}${f.stream === "CCE" ? " (CCE)" : ""} ${open ? "opened" : "saved as a draft"}`, "create");
    if (made && open && made.id) {
      const r = await post(`/api/bff/api/v1/results/exam-sessions/${made.id}/open`, {}, `Examination session opened`, "open");
      if (r) setSaid(`The session is open; ${r.offeringsWithoutLecturer} courses have no lecturer yet.`);
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

      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="info" title="Done">{said}</Note> : null}
      <Tiles items={[
        ["Open sessions", String(open.length), open.length ? "var(--green-ink)" : null, open.length ? `${open[0].session} ${open[0].semester === 1 ? "First" : open[0].semester === 2 ? "Second" : "Third"} semester` : "None open"],
        ["Courses examined", String(courses), null, "Sheets generated over the register"],
        ["Candidates", candidates.toLocaleString(), null, "Registered for an examined course"],
        ["Sheets due", due ? day(due, false) : "—", "var(--red-ink)", due ? `${Math.max(0, Math.round((new Date(due).getTime() - today) / 86400000))} days from today` : "No session open"],
      ]} />

      {canEdit ? (
      <Panel title="Create an examination session">
        <PBody>
          <div className="grid grid--3">
            <Field id="es-s" label="Academic session"><select id="es-s" className="ctl" value={f.session} onChange={(e) => setF({ ...f, session: e.target.value })}>{sessions.map((s) => <option key={s}>{s}</option>)}</select></Field>
            <Field id="es-m" label="Semester"><select id="es-m" className="ctl" value={f.semester} onChange={(e) => setF({ ...f, semester: e.target.value })}><option value="1">First</option><option value="2">Second</option><option value="3">Third</option></select></Field>
            <Field id="es-t" label="Type"><select id="es-t" className="ctl" value={f.kind} onChange={(e) => setF({ ...f, kind: e.target.value })}><option value="MAIN">Main examination</option><option value="RESIT">Re-sit</option><option value="SPECIAL">Special</option></select></Field>
            <Field id="es-w" label="Students" hint="A CCE session examines the Centre's evening classes only"><select id="es-w" className="ctl" value={f.stream} onChange={(e) => setF({ ...f, stream: e.target.value })}><option value="REGULAR">Full-time</option><option value="CCE">CCE (part-time)</option></select></Field>
            <Field id="es-f" label="Examinations begin"><input id="es-f" className="ctl" type="date" value={f.examsFrom} onChange={(e) => setF({ ...f, examsFrom: e.target.value })} /></Field>
            <Field id="es-e" label="Examinations end"><input id="es-e" className="ctl" type="date" value={f.examsTo} onChange={(e) => setF({ ...f, examsTo: e.target.value })} /></Field>
            <Field id="es-d" label="Score sheets due"><input id="es-d" className="ctl" type="date" value={f.sheetsDue} onChange={(e) => setF({ ...f, sheetsDue: e.target.value })} /></Field>
          </div>
          <Note kind="info" title="Opening a session releases nothing by itself">
            Examination cards and score sheets are released separately, with <b>Release examination cards</b> and <b>Release score sheets</b> below.
          </Note>
          <Note kind="info" title="Releasing the score sheets generates every sheet at once">
            One sheet per course offered, in the allocated lecturer&rsquo;s name; a course without a lecturer gets none. A full-time session makes sheets for full-time classes only, a CCE session for the Centre&rsquo;s evening classes only.
          </Note>
          <div className="row">
            <Btn kind="primary" disabled={busy !== null || !f.examsFrom || !f.examsTo || !f.sheetsDue} onClick={() => void create(true)}>Open the session</Btn>
            <Btn kind="ghost" disabled={busy !== null || !f.examsFrom || !f.examsTo || !f.sheetsDue} onClick={() => void create(false)}>Save as a draft</Btn>
          </div>
        </PBody>
      </Panel>
      ) : (
        <Note kind="info" title="Set up by the Director of ICT">
          Examination sessions are created and opened by the Director of ICT, from Portal Management.
        </Note>
      )}

      {list.length ? (
        <Panel title="Examination sessions" right={`${list.length} on record`}>
          <DTable
            cols={["Session|mid", "Semester|mid", "Type|mid", "Examinations|mid", "Sheets due|mid", "Sheets|mid", "Outstanding|mid", "State|mid", "Examination cards|mid", "Score sheets|mid", "|num"]}
            rows={list.map((e) => [
              <b className="tnum" key="s">{e.session}</b>, <span className="tnum" key="m">{e.semester === 1 ? "First" : e.semester === 2 ? "Second" : "Third"}</span>,
              <span className="sub2" key="k">{e.kind === "MAIN" ? "Main" : e.kind === "RESIT" ? "Re-sit" : "Special"}{e.stream === "CCE" ? <> <Pil kind="info">CCE</Pil></> : null}</span>,
              <span className="tnum" key="x">{day(e.examsFrom, false)} – {day(e.examsTo, false)}</span>,
              <span className="tnum" key="d">{day(e.sheetsDue)}</span>, <span className="tnum" key="n">{e.sheets}</span>,
              <span className={`tnum${e.outstanding ? " ink-red b700" : ""}`} key="o">{e.outstanding}</span>,
              e.state === "OPEN" ? <Pil kind="ok" key="st">Open</Pil> : e.state === "DRAFT" ? <Pil kind="info" key="st">Draft</Pil> : <Pil kind="grey" key="st">Closed</Pil>,
              <span key="cards" className="row row--inline row--tight">
                {e.cardsReleasedAt ? <Pil kind="ok">Released {day(e.cardsReleasedAt, false)}</Pil> : <Pil kind="grey">Not released</Pil>}
                {canEdit && e.state === "OPEN" && !e.cardsReleasedAt ? <Btn kind="primary" size="sm" disabled={busy !== null} onClick={() => { if (window.confirm(`Release the examination cards for ${e.session} ${e.semester === 1 ? "first" : e.semester === 2 ? "second" : "third"} semester? Students see their papers at once, and a student the Bursary has cleared can download the card.`)) void post(`/api/bff/api/v1/results/exam-sessions/${e.id}/release-cards`, {}, "Examination cards released", `cards-${e.id}`).then((r) => { if (r) { setSaid("The examination cards are released: students see their papers, and a cleared student can download the card."); router.refresh(); } }); }}>Release examination cards</Btn> : null}
                {canEdit && e.cardsReleasedAt ? <Btn kind="ghost" size="sm" disabled={busy !== null} onClick={() => { if (window.confirm("Withdraw the examination cards? Students stop seeing their papers and cannot download the card until you release them again.")) void post(`/api/bff/api/v1/results/exam-sessions/${e.id}/withdraw-cards`, {}, "Examination cards withdrawn", `cards-${e.id}`).then((r) => { if (r) { setSaid("The examination cards are withdrawn."); router.refresh(); } }); }}>Withdraw</Btn> : null}
              </span>,
              <span key="sheets" className="row row--inline row--tight">
                {e.sheetsReleasedAt ? <Pil kind="ok">Released {day(e.sheetsReleasedAt, false)}</Pil> : <Pil kind="grey">Not released</Pil>}
                {canEdit && e.state === "OPEN" && !e.sheetsReleasedAt ? <Btn kind="primary" size="sm" disabled={busy !== null} onClick={() => { if (window.confirm(`Release the score sheets for ${e.session} ${e.semester === 1 ? "first" : e.semester === 2 ? "second" : "third"} semester to the lecturers? One sheet is made for every course with a lecturer, and lecturers can enter marks at once. This is not undone.`)) void post(`/api/bff/api/v1/results/exam-sessions/${e.id}/release-sheets`, {}, "Score sheets released", `sheets-${e.id}`).then((r) => { if (r) { setSaid(`${r.sheetsMade} score sheets released to the lecturers; ${r.offeringsWithoutLecturer} courses have no lecturer and get their sheet when one is allocated.`); router.refresh(); } }); }}>Release score sheets</Btn> : null}
              </span>,
              <span key="a" className="row row--inline row--tight row--right">
                {canEdit && e.state !== "CLOSED" ? <Btn kind="ghost" disabled={busy !== null} onClick={() => openEdit(e)}>Edit</Btn> : null}
                {e.state === "DRAFT" ? (canEdit ? <Btn kind="primary" disabled={busy !== null} onClick={() => void post(`/api/bff/api/v1/results/exam-sessions/${e.id}/open`, {}, "Examination session opened", e.id).then((r) => { if (r) { setSaid(`The session is open; ${r.offeringsWithoutLecturer} courses have no lecturer yet.`); router.refresh(); } })}>Open</Btn> : null) : <LinkBtn href={`/examinations/sessions?exam=${e.id}`} kind="ghost">Monitor</LinkBtn>}
              </span>,
            ])}
          />
        </Panel>
      ) : null}

      {edit ? (
        <Modal title="Edit the examination session" sub={`${edit.session} · ${edit.semester === 1 ? "First" : edit.semester === 2 ? "Second" : "Third"} semester · ${edit.kind === "MAIN" ? "Main" : edit.kind === "RESIT" ? "Re-sit" : "Special"} · ${streamWords(edit.stream)}`} onClose={() => setEdit(null)}
          foot={<><Btn kind="ghost" onClick={() => setEdit(null)}>Cancel</Btn><span className="grow" />
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
            <Field id="ee-w" label="Students"><select id="ee-w" className="ctl" value={ed.stream} disabled={edit.sheets > 0} onChange={(e) => setEd({ ...ed, stream: e.target.value })}><option value="REGULAR">Full-time</option><option value="CCE">CCE (part-time)</option></select></Field>
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
            <span className={`tnum${x.outstanding ? " ink-red b700" : ""}`} key="o">{x.outstanding}</span>,
            <Bar key="p" pct={x.progress} colour={x.outstanding ? (x.progress < 50 ? "var(--red)" : "var(--chrome)") : "var(--green)"} />,
          ])}
        />
        {!faculties.length ? <PBody><div className="sub2">{monitor ? "No sheets were generated in this session yet." : canEdit ? "No examination session is open. Open one above and the monitor fills from the register." : "No examination session is open. When the Director of ICT opens one, the monitor fills from the register."}</div></PBody> : null}
      </Panel>

      {holding && outstanding.length ? (
        <Panel title={`The ${outstanding.length} sheet${outstanding.length === 1 ? "" : "s"} holding the Faculty of ${holding.facultyName}`} right="Named, with the person and the days">
          <DTable
            cols={["Course", "Department", "Lecturer", "Candidates|mid", "Days late|mid", "Chased", "Action|num"]}
            rows={outstanding.map((o) => [
              <b className="tnum" key="c">{o.courseCode}</b>, <span className="sub2" key="d">{o.deptName}</span>, <span key="l">{o.lecturer ?? "—"}</span>,
              <span className="tnum" key="n">{o.candidates}</span>,
              <span className="tnum ink-red b700" key="x">{o.daysLate ?? "—"}</span>,
              <span className="sub2" key="e">{chaseWords(o.chase) ?? "Not yet"}{o.daysLate ? <div>Next escalation: {o.escalatedTo}</div> : null}</span>,
              <span key="a"><Btn kind="ghost" disabled={busy !== null} onClick={() => void post(`/api/bff/api/v1/results/sheets/${o.id}/remind`, {}, `Reminder for ${o.courseCode}`, o.id)}>Remind</Btn> <Btn kind="urgent" disabled={busy !== null || !o.daysLate} title={o.daysLate ? undefined : "A sheet is escalated once it is past its due date"} onClick={() => void post(`/api/bff/api/v1/results/sheets/${o.id}/escalate`, {}, `Escalation for ${o.courseCode}`, o.id)}>Escalate</Btn></span>,
            ])}
          />
        </Panel>
      ) : null}
    </>
  );
}
