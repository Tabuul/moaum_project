"use client";

/**
 * Course registration correction: the Director of ICT finds the student by matriculation number (by admission number while the
 * student has none), chooses a session and semester
 * from the student's registrations and takes a wrongly counted course off it with a reason — the course, the curriculum and every
 * other student's registration untouched. A course without a result is withdrawn at once; one with a result (any mark, F or ABS)
 * keeps counting until the Registrar or the Deputy Registrar (never the officer who asked) confirms it under Waiting for the
 * Registry, or declines it with a note. The same course on the student's other registrations (a carry-over the result gave rise to)
 * may be named in the same request. Every correction of the student is listed; the Director cancels a held one or puts an applied
 * one back. The active office decides what is offered here, and the database checks it again.
 */
import { useState } from "react";
import { useJson } from "@/lib/use-json";
import { Field, Modal } from "@/components/proto/blocks";
import { Btn, KvGrid, Note, Panel, PBody, Pil, Tabs, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { reasonHeader } from "@/lib/reason";
import { roleLabel } from "@/lib/offices";
import { shownCode } from "@/lib/course-code";
import { CATEGORY_LABEL, courseCategory } from "@/lib/course-order";
import type { Problem } from "@/lib/api";
import {
  answerLines, cameWord, choiceKey, codeTaken, counted, decideProblem, heldCount, heldWords, includable, mayDecide, mayRequest, notIncludable, reasonProblem, removable,
  removalBody, semesterChoices, semesterWord, stateWord, studentNumber, undoable,
  type CorrectionEntry, type CorrectionStudent, type Elsewhere, type Removal, type RequestAnswer,
} from "@/lib/registration-corrections";

const BASE = "/api/bff/api/v1/registration/corrections";
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
const statusWord = (s: string | null | undefined) => (s ? s.charAt(0) + s.slice(1).toLowerCase() : "—");
const keyOf = (x: { registrationId: string; offeringId: string }) => `${x.registrationId}|${x.offeringId}`;

async function post<T>(path: string, body: unknown, why: string): Promise<T> {
  const r = await fetch(`${BASE}${path}`, {
    method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(why) }, body: JSON.stringify(body),
  });
  const j = await r.json().catch(() => null);
  if (!r.ok) throw j ?? { status: r.status, title: "Not done" };
  return j as T;
}

type Which = "student" | "waiting";

export function Corrections({ office, initialMatric }: { office: string | null; initialMatric: string }) {
  const asks = mayRequest(office);
  const decides = mayDecide(office);
  // the Registry opens on what waits for it; the Director (and the Super Administrator) on the student
  const [tab, setTab] = useState<Which>(decides && !asks ? "waiting" : "student");
  const [tick, setTick] = useState(0);
  const [typed, setTyped] = useState(initialMatric);
  const [sought, setSought] = useState(initialMatric);
  // the student is read again on a search, never after a change below (the panel stays while its courses are read again)
  const [look, setLook] = useState(0);
  const { data: student, failed: notFound, loading: finding } = useJson<CorrectionStudent>(sought ? `${BASE}/student?matric=${encodeURIComponent(sought)}` : null, look);
  // the session and semester chosen, for the student it was chosen for; the newest registration until one is chosen
  const choices = semesterChoices(student?.registrations ?? []);
  const [picked, setPicked] = useState<{ student: string; key: string } | null>(null);
  const key = student && picked && picked.student === student.id && choices.some((c) => choiceKey(c.session, c.semester) === picked.key) ? picked.key
    : choices[0] ? choiceKey(choices[0].session, choices[0].semester) : "";
  const chosen = choices.find((c) => choiceKey(c.session, c.semester) === key) ?? null;
  const { data: entries, failed: entriesFailed, loading: entriesLoading } = useJson<CorrectionEntry[]>(student && chosen
    ? `${BASE}/entries?student=${student.id}&session=${encodeURIComponent(chosen.session)}&semester=${chosen.semester}` : null, tick);
  const { data: history, failed: historyFailed } = useJson<Removal[]>(student ? `${BASE}?student=${student.id}` : null, tick);
  const { data: waiting, failed: waitingFailed, loading: waitingLoading } = useJson<Removal[]>(`${BASE}?state=PENDING`, tick);

  const [ask, setAsk] = useState<{ e: CorrectionEntry; also: string[]; reason: string } | null>(null);
  const [done, setDone] = useState<{ student: string; answer: RequestAnswer } | null>(null);
  const [undo, setUndo] = useState<{ r: Removal; reason: string } | null>(null);
  const [decide, setDecide] = useState<{ r: Removal; confirm: boolean; note: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const refresh = () => setTick((x) => x + 1);

  function find(m: string) {
    const n = m.trim().toUpperCase();
    setTyped(n);
    setDone(null);
    if (n === sought) setLook((x) => x + 1); else setSought(n);
  }

  async function request() {
    if (!ask || !student || !chosen) return;
    const also = ask.e.elsewhere.filter((x) => ask.also.includes(keyOf(x)));
    const codes = [codeTaken(ask.e.courseCode, ask.e.codeAsTaken), ...also.map((x) => `${shownCode(x.courseCode)} (${x.session} semester ${x.semester})`)].join(", ");
    setBusy(true);
    try {
      const a = await post<RequestAnswer>("", removalBody(student.id, ask.e, also, ask.reason),
        `${student.matric ?? student.name}: ${codes} taken off the ${chosen.session} ${semesterWord(chosen.semester).toLowerCase()} registration - ${ask.reason.trim()}`);
      setDone({ student: student.id, answer: a });
      setAsk(null);
      const held = a.removals.filter((r) => r.state === "PENDING").length;
      notify(held ? `${a.groupRef}: ${held === a.removals.length ? "held" : `${held} of ${a.removals.length} held`} for the Registrar or the Deputy Registrar.` : `${a.groupRef}: taken off ${student.name}'s registration.`);
      refresh();
    } catch (e) {
      notifyProblem(e as Problem, "The course was not taken off");
      refresh();
    } finally { setBusy(false); }
  }

  async function putBack() {
    if (!undo) return;
    const r = undo.r;
    setBusy(true);
    try {
      await post<{ state: string }>(`/${r.id}/undo`, { reason: undo.reason.trim() },
        `${r.matric ?? r.name}: ${r.ref} ${r.state === "PENDING" ? "cancelled" : "undone"} - ${undo.reason.trim()}`);
      notify(r.state === "PENDING" ? `${r.ref} cancelled: ${codeTaken(r.courseCode, r.codeAsTaken)} keeps counting.`
        : `${r.ref} undone: ${codeTaken(r.courseCode, r.codeAsTaken)} is back on the registration as it stood.`);
      setUndo(null);
      refresh();
    } catch (e) {
      notifyProblem(e as Problem, "The correction was not undone");
    } finally { setBusy(false); }
  }

  async function decideIt() {
    if (!decide) return;
    const { r, confirm, note } = decide;
    setBusy(true);
    try {
      await post<{ state: string }>(`/${r.id}/decide`, { confirm, note: note.trim() || null },
        `${r.matric ?? r.name}: ${r.ref} ${confirm ? "confirmed" : "declined"} by the Registry${note.trim() ? ` - ${note.trim()}` : ""}`);
      notify(confirm ? `${r.ref} confirmed: ${codeTaken(r.courseCode, r.codeAsTaken)} is withdrawn from ${r.name}'s registration; the mark stays on its sheet.`
        : `${r.ref} declined: ${codeTaken(r.courseCode, r.codeAsTaken)} keeps counting.`);
      setDecide(null);
      refresh();
    } catch (e) {
      notifyProblem(e as Problem, "The removal was not decided");
      refresh();
    } finally { setBusy(false); }
  }

  const askProblem = ask ? reasonProblem(ask.reason) : null;
  const undoProblem = undo ? reasonProblem(undo.reason, "why the correction is undone") : null;
  const decideNote = decide ? decideProblem(decide.confirm, decide.note) : null;
  const answer = done && student && done.student === student.id ? done.answer : null;
  // the number the student is known by: the matriculation number, else the admission number while there is none
  const [numLabel, numValue]: [string, string] = student ? studentNumber(student) : ["Matriculation number", "—"];

  const historyTable = (rows: Removal[]) => (
    <DTable cols={["Reference", "Course", "Session", "Was", "How it came", "Result", "State", "Asked", "Decided or undone", "Reason", "|num"]}
      rows={rows.map((r) => {
        const [word, tone] = stateWord(r.state);
        return [
          <span key="r"><span className="tnum b600">{r.ref}</span>{r.groupRef !== r.ref ? <div className="sub2 tnum">with {r.groupRef}</div> : null}</span>,
          <Two key="c" a={<span className="tnum">{codeTaken(r.courseCode, r.codeAsTaken)}</span>} b={r.title ?? ""} />,
          <span key="s" className="tnum">{r.session} · {semesterWord(r.semester)}{r.level ? <div className="sub2">{r.level} Level</div> : null}</span>,
          <span key="w" className="sub2">{statusWord(r.wasStatus)} · {r.wasUnits} unit{r.wasUnits === 1 ? "" : "s"}</span>,
          <span key="h" className="sub2">{cameWord(r.wasAdded)}</span>,
          <span key="m" className="sub2">{r.hadResult ? r.resultWords ?? "A mark is on record" : "No result"}</span>,
          <Pil key="st" kind={tone}>{word}</Pil>,
          <span key="a" className="sub2">{when(r.requestedAt)}<div>{r.requestedByName ?? "—"}{r.requestedOffice ? ` (${roleLabel(r.requestedOffice)})` : ""}</div></span>,
          <span key="d" className="sub2">{r.decidedAt ? <>{when(r.decidedAt)}<div>{r.decidedByName ?? "—"}{r.decidedOffice ? ` (${roleLabel(r.decidedOffice)})` : ""}</div>{r.decisionNote ? <div>{r.decisionNote}</div> : null}</>
            : null}{r.undoneAt ? <div>{r.state === "CANCELLED" ? "Cancelled" : "Put back"} {when(r.undoneAt)} · {r.undoneByName ?? "—"}{r.undoReason ? <div>{r.undoReason}</div> : null}</div> : null}{!r.decidedAt && !r.undoneAt ? "—" : null}</span>,
          <span key="why">{r.reason}</span>,
          asks && undoable(r.state) ? <Btn key="u" kind="ghost" onClick={() => setUndo({ r, reason: "" })}>Undo</Btn> : "",
        ];
      })}
      texts={rows.map((r) => `${r.ref} ${r.groupRef} ${r.name} ${r.matric ?? ""} ${r.courseCode} ${r.codeAsTaken ?? ""} ${r.session} ${r.reason}`)} />
  );

  return (
    <>
      <Note kind="info" title="One student's course, taken off one registration">
        The course, the curriculum and every other student&rsquo;s registration stay as they are. A course without a result is withdrawn at once. A course
        with a result (any mark, F or ABS included) keeps counting until the Registrar or the Deputy Registrar confirms its removal; the mark then stays on
        its sheet as history. A removal sticks: the student&rsquo;s own save or an old-portal upload does not bring the course back; only its undo here does.
        Issued transcripts are flagged for review, and the student&rsquo;s change history lists every removal.
      </Note>
      <Tabs<Which> label="Course registration correction" value={tab} onChange={setTab} items={[
        { id: "student", label: "Find a student" },
        { id: "waiting", label: "Waiting for the Registry", count: waiting ? waiting.length.toLocaleString() : undefined },
      ]} />

      {tab === "student" ? (
        <>
          <Panel title="Find the student">
            <PBody>
              <form className="row row--tight" style={{ flexWrap: "wrap", gap: 8, alignItems: "flex-end" }} onSubmit={(e) => { e.preventDefault(); if (typed.trim()) find(typed); }}>
                <Field id="rcr-matric" label="Matriculation or admission number" hint="The student's matriculation number as it is on the record; the admission number while the student has none">
                  <input id="rcr-matric" className="ctl tnum" value={typed} onChange={(e) => setTyped(e.target.value)} style={{ minWidth: 280 }} autoComplete="off" placeholder="MOAU/SC/CSC/24/12345" />
                </Field>
                <Btn kind="primary" type="submit" disabled={!typed.trim()} busy={finding} busyLabel="Searching…">Search</Btn>
              </form>
            </PBody>
          </Panel>
          {notFound && !finding ? <Note kind="bad" title="No student found">{notFound}</Note> : null}

          {student && !finding ? (
            <>
              <Panel title={student.name} right={<Pil kind="grey">{statusWord(student.status)}</Pil>}>
                <PBody>
                  <KvGrid pairs={[
                    [numLabel, <span key="m" className="tnum">{numValue}</span>], ["Programme", student.programme ?? student.programmeCode ?? "—"],
                    ["Level", student.level ? `${student.level} Level` : "—"], ["Status", statusWord(student.status)],
                  ]} />
                  {student.graduate ? (
                    <Note kind="info" title="Senate-approved graduate — the approved CGPA stays">
                      A course taken off this student&rsquo;s registration does not change the CGPA, the class or the award the Senate approved; each correction says
                      the student is a graduate, for the Registry.
                    </Note>
                  ) : null}
                  {choices.length ? (
                    <Field id="rcr-sem" label="Session and semester" hint="The student's registrations, newest first">
                      <select id="rcr-sem" className="ctl" value={key} onChange={(e) => setPicked({ student: student.id, key: e.target.value })} style={{ maxWidth: 520 }}>
                        {choices.map((c) => (
                          <option key={choiceKey(c.session, c.semester)} value={choiceKey(c.session, c.semester)}>
                            {`${c.session} · ${semesterWord(c.semester)}${c.level ? ` · ${c.level} Level` : ""} · ${statusWord(c.status)} · ${c.courses} course${c.courses === 1 ? "" : "s"}`}
                          </option>
                        ))}
                      </select>
                    </Field>
                  ) : <div className="sub2">The student has no course registration on record.</div>}
                </PBody>
              </Panel>

              {answer ? (
                <Note kind="ok" title={`Correction ${answer.groupRef} recorded`}>
                  {answerLines(answer).map((l) => <div key={l}>{l}</div>)}
                  {answer.graduate ? <div>The student is a Senate-approved graduate: the approved CGPA stays.</div> : null}
                </Note>
              ) : null}

              {chosen ? (
                <Panel title={`Courses on the registration · ${chosen.session} · ${semesterWord(chosen.semester)}`} right={entriesLoading ? "Loading…" : entries ? `${entries.filter((e) => counted(e.status)).length} counted of ${entries.length}` : undefined}>
                  {entriesFailed ? <PBody><Note kind="bad" title="Unable to load the registration">{entriesFailed}</Note></PBody> : null}
                  {entries ? (entries.length ? (
                    <DTable pageSize={0} cols={["Course", "Title", "Units|num", "Status", "Category", "How it came", "Result", "Removal", "|num"]}
                      rows={entries.map((e) => {
                        const code = codeTaken(e.courseCode, e.codeAsTaken);
                        const [word, tone] = stateWord(e.removalState);
                        return [
                          <span key="c"><b className="tnum">{code}</b>{e.codeAsTaken && code !== shownCode(e.courseCode) ? <div className="sub2 tnum">now {shownCode(e.courseCode)}</div> : null}</span>,
                          <span key="t">{e.title}</span>,
                          <span key="u" className="tnum">{e.units}</span>,
                          <Pil key="s" kind={counted(e.status) ? "ok" : "grey"}>{statusWord(e.status)}</Pil>,
                          <span key="k">{CATEGORY_LABEL[courseCategory({ category: e.category, entryType: e.entryType, basis: e.basis })]}{e.isElective ? <> <Pil kind="info">Elective</Pil></> : null}</span>,
                          <span key="h" className="sub2">{cameWord(e.came)}</span>,
                          <span key="r" className="sub2">{e.hasResult ? e.resultWords ?? "A mark is on record" : "No result"}</span>,
                          e.removalRef ? <span key="x"><span className="tnum">{e.removalRef}</span> <Pil kind={tone}>{word}</Pil></span> : <span key="x" className="sub2">—</span>,
                          asks && removable(e) ? <Btn key="a" kind="ghost" onClick={() => setAsk({ e, also: [], reason: "" })}>Remove</Btn> : "",
                        ];
                      })} />
                  ) : <PBody><div className="sub2">No course is on this registration.</div></PBody>) : null}
                  {!asks ? <PBody><div className="sub2">The Director of ICT takes a course off; the Registrar or the Deputy Registrar decides one held for a result under Waiting for the Registry.</div></PBody> : null}
                </Panel>
              ) : null}

              <Panel title="Corrections of this student" right={history ? `${history.length} on record` : undefined}>
                {historyFailed ? <PBody><Note kind="bad" title="Unable to load the corrections">{historyFailed}</Note></PBody> : null}
                {history ? (history.length ? historyTable(history) : <PBody><div className="sub2">No course has been taken off this student&rsquo;s registrations.</div></PBody>) : null}
              </Panel>
            </>
          ) : null}
        </>
      ) : (
        <Panel title="Waiting for the Registry" right={waitingLoading ? "Loading…" : waiting ? `${waiting.length} held for a decision` : undefined}>
          {waitingFailed ? <PBody><Note kind="bad" title="Unable to load what waits">{waitingFailed}</Note></PBody> : null}
          {waiting ? (waiting.length ? (
            <DTable cols={["Reference", "Student", "Course", "Session", "Result", "Reason", "Asked", "|num"]}
              rows={waiting.map((r) => [
                <span key="r" className="tnum b600">{r.ref}</span>,
                <span key="s"><Two a={r.name} b={<span className="tnum">{r.matric ?? "—"}</span>} />{r.graduate ? <Pil kind="info">Senate-approved graduate</Pil> : null}</span>,
                <Two key="c" a={<span className="tnum">{codeTaken(r.courseCode, r.codeAsTaken)}</span>} b={`${r.title ?? ""}${r.title ? " · " : ""}${r.wasUnits} unit${r.wasUnits === 1 ? "" : "s"} · ${cameWord(r.wasAdded).toLowerCase()}`} />,
                <span key="se" className="tnum">{r.session} · {semesterWord(r.semester)}</span>,
                <span key="m" className="sub2">{r.resultWords ?? "A mark is on record"}</span>,
                <span key="why">{r.reason}</span>,
                <span key="a" className="sub2">{when(r.requestedAt)}<div>{r.requestedByName ?? "—"}{r.requestedOffice ? ` (${roleLabel(r.requestedOffice)})` : ""}</div></span>,
                <span key="act" className="row row--inline row--tight">
                  {decides ? <>
                    <Btn kind="primary" onClick={() => setDecide({ r, confirm: true, note: "" })}>Confirm</Btn>
                    <Btn kind="ghost" onClick={() => setDecide({ r, confirm: false, note: "" })}>Decline</Btn>
                  </> : null}
                  {r.matric ? <Btn kind="ghost" onClick={() => { setTab("student"); find(r.matric!); }}>Open</Btn> : null}
                  {asks ? <Btn kind="ghost" onClick={() => setUndo({ r, reason: "" })}>Undo</Btn> : null}
                </span>,
              ])}
              texts={waiting.map((r) => `${r.ref} ${r.name} ${r.matric ?? ""} ${r.courseCode} ${r.codeAsTaken ?? ""} ${r.session} ${r.reason}`)} />
          ) : <PBody><div className="sub2">No removal waits for the Registry.</div></PBody>) : null}
          <PBody><div className="sub2">A removal with a result waits here for the Registrar or the Deputy Registrar, never the officer who asked for it. Confirmed, the course is withdrawn from the registration and its mark kept on its sheet as history; declined (with a note), it keeps counting.</div></PBody>
        </Panel>
      )}

      {ask && student && chosen ? (() => {
        const e = ask.e;
        const code = codeTaken(e.courseCode, e.codeAsTaken);
        const also = e.elsewhere.filter((x) => ask.also.includes(keyOf(x)));
        const held = heldCount(e, also);
        const named = 1 + also.length;
        const toggle = (x: Elsewhere, on: boolean) => setAsk({ ...ask, also: on ? [...ask.also, keyOf(x)] : ask.also.filter((k) => k !== keyOf(x)) });
        return (
          <Modal wide title={`Take ${code} off — ${student.name}`} sub={`${chosen.session} · ${semesterWord(chosen.semester)}`} onClose={() => setAsk(null)}
            foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn><span className="grow" />
              <Btn kind="urgent" disabled={!!askProblem || busy} busy={busy} busyLabel="Taking it off…" onClick={() => void request()}>{held === named ? "Ask the Registry" : named > 1 ? "Take them off" : "Take it off"}</Btn></>}>
            <KvGrid cls="grid--3" pairs={[
              ["Student Name", student.name], [numLabel === "Admission number" ? "Admission Number" : "Matriculation Number", <span key="m" className="tnum">{numValue}</span>],
              ["Programme", student.programme ?? student.programmeCode ?? "—"], ["Level", (e.level ?? chosen.level) ? `${e.level ?? chosen.level} Level` : "—"],
              ["Academic Session", <span key="s" className="tnum">{chosen.session}</span>], ["Semester", semesterWord(chosen.semester)],
              ["Course Code", <b key="c" className="tnum">{code}</b>], ["Course Title", e.title], ["Course Unit", String(e.units)],
              ["Registration Status", `${statusWord(e.registrationStatus)} · course ${statusWord(e.status).toLowerCase()}`], ["How it came", cameWord(e.came)],
              ["Result", e.hasResult ? e.resultWords ?? "A mark is on record" : "No result"],
            ]} />
            {e.hasResult ? (
              <Note kind="info" title="Held for the Registrar or the Deputy Registrar">
                {code} carries a result. It keeps counting until the Registrar or the Deputy Registrar (another officer than you) confirms the removal; the mark
                then stays on its sheet as history.
              </Note>
            ) : <p className="sub2">Without a result, {code} is withdrawn from this registration at once.</p>}
            {student.graduate ? <Note kind="info" title="Senate-approved graduate">The CGPA the Senate approved stays; the correction says the student is a graduate, for the Registry.</Note> : null}
            {e.elsewhere.length ? (
              <div className="mt-2">
                <div className="eyebrow mb-1">The same course on the student&rsquo;s other registrations</div>
                <div className="sub2 mb-1">Tick one to take it off under the same reason — a carry-over this course&rsquo;s result gave rise to, say. One with a result is held for the Registry too.</div>
                {e.elsewhere.map((x) => {
                  const why = notIncludable(x);
                  return (
                    <label key={keyOf(x)} className="row row--tight" style={{ gap: 8, padding: "4px 0", alignItems: "flex-start", opacity: why ? 0.7 : 1 }}>
                      <input type="checkbox" className="pchk" disabled={!includable(x)} checked={ask.also.includes(keyOf(x))} onChange={(ev) => toggle(x, ev.target.checked)} />
                      <span>
                        <b className="tnum">{shownCode(x.courseCode)}</b> · <span className="tnum">{x.session}</span> · {semesterWord(x.semester)} · {x.units} unit{x.units === 1 ? "" : "s"}
                        {x.entryType ? ` · ${statusWord(x.entryType)}` : ""} · {statusWord(x.status)}
                        <span className="sub2"> · {x.hasResult ? x.result ?? "a mark is on record" : "no result"}</span>
                        {why ? <span className="sub2"> · {why}</span> : null}
                      </span>
                    </label>
                  );
                })}
              </div>
            ) : null}
            {named > 1 ? <p className="sub2">{heldWords(held, named)}</p> : null}
            <Field id="rcr-why" label="Why the course is taken off" required hint="Ten characters or more; it goes on the record with your name">
              <textarea id="rcr-why" className="ctl" rows={3} maxLength={2000} value={ask.reason} onChange={(ev) => setAsk({ ...ask, reason: ev.target.value })}
                placeholder="e.g. An elective the student never chose, registered by the old-portal upload" />
            </Field>
            {askProblem && ask.reason.trim().length ? <p className="sub2">{askProblem}</p> : null}
          </Modal>
        );
      })() : null}

      {undo ? (
        <Modal title={`${undo.r.state === "PENDING" ? "Cancel" : "Undo"} ${undo.r.ref} — ${undo.r.name}`}
          sub={undo.r.state === "PENDING" ? `${codeTaken(undo.r.courseCode, undo.r.codeAsTaken)} keeps counting; the request stays on the record as cancelled`
            : `${codeTaken(undo.r.courseCode, undo.r.codeAsTaken)} comes back on the ${undo.r.session} registration as it stood; the removal stays on the record`}
          onClose={() => setUndo(null)}
          foot={<><Btn kind="ghost" onClick={() => setUndo(null)}>Close</Btn><span className="grow" />
            <Btn kind="urgent" disabled={!!undoProblem || busy} busy={busy} busyLabel="Undoing…" onClick={() => void putBack()}>{undo.r.state === "PENDING" ? "Cancel it" : "Put it back"}</Btn></>}>
          <Field id="rcr-undo" label="Why it is undone" required hint="Ten characters or more">
            <textarea id="rcr-undo" className="ctl" rows={3} maxLength={2000} value={undo.reason} onChange={(ev) => setUndo({ ...undo, reason: ev.target.value })} />
          </Field>
          {undoProblem && undo.reason.trim().length ? <p className="sub2">{undoProblem}</p> : null}
        </Modal>
      ) : null}

      {decide ? (
        <Modal title={`${decide.confirm ? "Confirm" : "Decline"} ${decide.r.ref} — ${decide.r.name}`}
          sub={`${codeTaken(decide.r.courseCode, decide.r.codeAsTaken)} · ${decide.r.session} · ${semesterWord(decide.r.semester)}`} onClose={() => setDecide(null)}
          foot={<><Btn kind="ghost" onClick={() => setDecide(null)}>Close</Btn><span className="grow" />
            <Btn kind={decide.confirm ? "primary" : "urgent"} disabled={!!decideNote || busy} busy={busy} busyLabel={decide.confirm ? "Confirming…" : "Declining…"}
              onClick={() => void decideIt()}>{decide.confirm ? "Confirm the removal" : "Decline it"}</Btn></>}>
          <KvGrid cls="grid--2" pairs={[
            ["Student", `${decide.r.name}${decide.r.matric ? ` · ${decide.r.matric}` : ""}`], ["Course", `${codeTaken(decide.r.courseCode, decide.r.codeAsTaken)}${decide.r.title ? ` — ${decide.r.title}` : ""}`],
            ["Result", decide.r.resultWords ?? "A mark is on record"], ["Was", `${statusWord(decide.r.wasStatus)} · ${decide.r.wasUnits} units · ${cameWord(decide.r.wasAdded).toLowerCase()}`],
            ["Asked by", `${decide.r.requestedByName ?? "—"}${decide.r.requestedOffice ? ` (${roleLabel(decide.r.requestedOffice)})` : ""} · ${when(decide.r.requestedAt)}`], ["Reason", decide.r.reason],
          ]} />
          <p className="sub2">{decide.confirm
            ? "Confirmed, the course is withdrawn from the registration; its mark stays on its sheet as history, and issued transcripts are flagged for review."
            : "Declined, the course keeps counting on the registration; the request stays on the record with your note."}
          {decide.r.graduate ? " The student is a Senate-approved graduate: the approved CGPA stays." : ""}</p>
          <Field id="rcr-note" label={decide.confirm ? "Note on the decision" : "Why it is declined"} required={!decide.confirm}
            hint={decide.confirm ? "Optional; kept with the decision" : "Ten characters or more; kept with the decision"}>
            <textarea id="rcr-note" className="ctl" rows={3} maxLength={2000} value={decide.note} onChange={(ev) => setDecide({ ...decide, note: ev.target.value })} />
          </Field>
          {decideNote && decide.note.trim().length ? <p className="sub2">{decideNote}</p> : null}
        </Modal>
      ) : null}
    </>
  );
}
