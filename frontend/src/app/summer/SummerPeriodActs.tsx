"use client";

/** V735, V779 · the Academic Office's period and acts: the period of a session's Summer (its window, the examination and results
 *  dates, who it is for, the most courses a student may hold), identifying the eligible in tranches, telling the students in
 *  tranches, authorising a student for an approved academic reason, the examination acts — which the database holds back while
 *  paid Summer courses are unverified, until the Office verifies them or records why they may go ahead — the paid courses the
 *  registration could not take, and the authorisations to look at again. */
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import type { Problem } from "@/lib/api";
import { Btn, KvGrid, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { day } from "@/lib/format";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { sessionSlug } from "@/lib/report";
import {
  CATEGORY_BOXES, boxesOf, categoriesOf, categoryWord, notEligibleWord, periodForWord, periodWords, plural, reasonOk, sessionPath, type SummerIssue, type SummerPeriod,
} from "@/lib/summer";
import { call, type DeskResult } from "./deskApi";

/** V754: a Summer authorisation to look at again (registration.summer_authorisations_to_review) */
export interface SummerAuthorisationToReview {
  kind: "DEAD_CODE" | "REWRITTEN"; session: string; student_id: string; number: string | null; name: string; course_named: string | null;
  courses_now: string[] | null; trail_gives: string | null; rewritten_by: string | null; at: string | null;
}

const list = (s: string) => s.split(/[\s,;]+/).map((x) => x.trim()).filter(Boolean);
/** course codes carry a space ("CSC 401"): split on commas and semicolons only */
const codes = (s: string) => s.split(/[,;\n]+/).map((x) => x.trim().toUpperCase().replace(/\s+/g, " ")).filter(Boolean);

/** the period's form: the window, the examination and results dates, who it is for */
function PeriodForm({ session, period, onDone }: { session: string; period: SummerPeriod | null; onDone: () => void }) {
  const [state, setState] = useState<string>(period?.state ?? "PLANNED");
  const [opens, setOpens] = useState(period?.registration_opens ?? "");
  const [closes, setCloses] = useState(period?.registration_closes ?? "");
  const [examsFrom, setExamsFrom] = useState(period?.exams_from ?? "");
  const [examsTo, setExamsTo] = useState(period?.exams_to ?? "");
  const [results, setResults] = useState(period?.results_due ?? "");
  const [boxes, setBoxes] = useState<Set<string>>(boxesOf(period?.categories));
  const [programmes, setProgrammes] = useState((period?.programmes ?? []).join(", "));
  const [levels, setLevels] = useState((period?.levels ?? []).join(", "));
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  async function save() {
    setBusy(true);
    setProblem(null);
    try {
      const r = await call("PUT", `/summer/${sessionPath(session)}`, {
        state, registrationOpens: opens || null, registrationCloses: closes || null, examsFrom: examsFrom || null, examsTo: examsTo || null,
        resultsDue: results || null, categories: categoriesOf(boxes), programmes: list(programmes), levels: list(levels).map(Number).filter((n) => Number.isInteger(n) && n > 0),
        reason: reason.trim() || null,
      }, `Summer Semester ${session} set ${state.toLowerCase()}`);
      if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
      notify(`The Summer Semester of ${session} is ${state.toLowerCase()}`);
      setReason("");
      onDone();
    } finally {
      setBusy(false);
    }
  }
  return (
    <Panel title={period ? "The period" : `Set the Summer Semester of ${session}`} right={period?.set_at ? `Last set ${day(period.set_at)}` : undefined}>
      <PBody>
        <div className="grid grid--3">
          <Field id="sm-state" label="State" hint="Students register only while it is open and within its dates.">
            <select id="sm-state" className="ctl" value={state} onChange={(e) => setState(e.target.value)}>
              <option value="PLANNED">Planned</option><option value="OPEN">Open</option><option value="CLOSED">Closed</option>
            </select>
          </Field>
          <Field id="sm-opens" label="Registration opens"><input id="sm-opens" type="date" className="ctl" value={opens} onChange={(e) => setOpens(e.target.value)} /></Field>
          <Field id="sm-closes" label="Registration closes"><input id="sm-closes" type="date" className="ctl" value={closes} onChange={(e) => setCloses(e.target.value)} /></Field>
          <Field id="sm-ef" label="Examinations from"><input id="sm-ef" type="date" className="ctl" value={examsFrom} onChange={(e) => setExamsFrom(e.target.value)} /></Field>
          <Field id="sm-et" label="Examinations to"><input id="sm-et" type="date" className="ctl" value={examsTo} onChange={(e) => setExamsTo(e.target.value)} /></Field>
          <Field id="sm-rd" label="Results expected"><input id="sm-rd" type="date" className="ctl" value={results} onChange={(e) => setResults(e.target.value)} /></Field>
        </div>
        <fieldset className="mt-2" style={{ border: 0, padding: 0, margin: 0 }}>
          <legend className="sub2 mb-1">Who it is for</legend>
          <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-4)" }}>
            {CATEGORY_BOXES.map((b) => (
              <label key={b.id} className="row" style={{ gap: "var(--s-1)" }}>
                <input type="checkbox" checked={boxes.has(b.id)} onChange={() => setBoxes((x) => { const n = new Set(x); if (n.has(b.id)) n.delete(b.id); else n.add(b.id); return n; })} />
                {b.label}
              </label>
            ))}
          </div>
          <div className="sub2 mt-1">Every final-year and spillover student of the programmes below, whatever the level on their record; the Academic Office may also authorise a student for an approved academic reason.</div>
        </fieldset>
        <div className="grid grid--3 mt-2">
          <Field id="sm-prog" label="Programmes" hint="Codes, separated by commas. Empty: every undergraduate programme."><input id="sm-prog" className="ctl" value={programmes} onChange={(e) => setProgrammes(e.target.value)} /></Field>
          <Field id="sm-lv" label="Levels" hint="e.g. 400, 500: the student's Summer level, the higher of the level on record and the level the engine reads. Empty: every level."><input id="sm-lv" className="ctl tnum" value={levels} onChange={(e) => setLevels(e.target.value)} /></Field>
          <Field id="sm-why" label="Reason" hint="Kept with the change."><input id="sm-why" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
        </div>
        <div className="mt-2"><Btn kind="primary" size="md" busy={busy} busyLabel="Saving…" disabled={busy || boxes.size === 0} onClick={() => void save()}>Save the period</Btn></div>
        {problem ? <ProblemNotice problem={problem} /> : null}
      </PBody>
    </Panel>
  );
}

/** the most courses a student may hold in this Summer, optional; it stops further selecting and never removes a course */
function Ceiling({ session, period, onDone }: { session: string; period: SummerPeriod; onDone: () => void }) {
  const [max, setMax] = useState(period.max_courses != null ? String(period.max_courses) : "");
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const n = max.trim() === "" ? null : Number(max);
  const valid = n === null || (Number.isInteger(n) && n >= 1 && n <= 60);
  async function save() {
    setBusy(true);
    setProblem(null);
    try {
      const r = await call("PUT", `/summer/${sessionPath(session)}/ceiling`, { maxCourses: n, reason: reason.trim() }, `Summer Semester ${session}: course ceiling ${n === null ? "removed" : `set to ${n}`}`);
      if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
      notify(n === null ? "No ceiling on the courses a student may hold" : `A student may hold at most ${plural(n, "course")}`);
      setReason("");
      onDone();
    } finally {
      setBusy(false);
    }
  }
  return (
    <Panel title="Course ceiling" right={period.max_courses ? `At most ${plural(period.max_courses, "course")} a student` : "No ceiling"}>
      <PBody>
        <div className="row row--end" style={{ gap: "var(--s-3)" }}>
          <Field id="sc-max" label="Most courses a student may hold" hint="1 to 60, or empty for none. Counted over the whole Summer; a student selects at most 30 in one go."><input id="sc-max" className="ctl tnum" inputMode="numeric" value={max} onChange={(e) => setMax(e.target.value.replace(/[^0-9]/g, ""))} /></Field>
          <Field id="sc-why" label="Reason" hint="At least ten characters; kept with the change." style={{ flex: "1 1 260px" }}><input id="sc-why" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
          <Btn kind="primary" size="md" busy={busy} busyLabel="Saving…" disabled={busy || !valid || !reasonOk(reason)} onClick={() => void save()}>Set the ceiling</Btn>
        </div>
        <div className="sub2 mt-1">A ceiling below what a student already holds never removes a course; it only stops further selecting.</div>
        {problem ? <ProblemNotice problem={problem} /> : null}
      </PBody>
    </Panel>
  );
}

type Act = "open" | "release-sheets";

/** the examination acts, with the count the database holds them on and the override the Office may record */
function Examinations({ session, period, maySet, onDone }: { session: string; period: SummerPeriod; maySet: boolean; onDone: () => void }) {
  const [busy, setBusy] = useState<Act | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [override, setOverride] = useState<{ act: Act; problem: Problem } | null>(null);
  const [reason, setReason] = useState("");
  const unverified = period.unverified ?? null;
  const examsOpen = period.exam_state === "OPEN";
  const overrides = period.overrides ?? [];
  async function act(a: Act) {
    setBusy(a);
    setProblem(null);
    try {
      const r = await call("POST", `/summer/${sessionPath(session)}/exams/${a}`, {}, `Summer Semester ${session}: examinations ${a === "open" ? "opened" : "score sheets released"}`);
      if (!r.ok) {
        // the database holds the act while paid courses are unverified: the Office may record why it goes ahead
        if (r.problem.code === "SUMMER_VERIFICATION_PENDING") { setOverride({ act: a, problem: r.problem }); return; }
        setProblem(r.problem); notifyProblem(r.problem); return;
      }
      notify(a === "open" ? "The Summer examinations are open" : "The score sheets are released to the lecturers");
      onDone();
    } finally {
      setBusy(null);
    }
  }
  async function goAhead() {
    if (!override) return;
    setBusy(override.act);
    try {
      const o = await call("POST", `/summer/${sessionPath(session)}/exams/${override.act}/override`, { reason: reason.trim() }, `Summer Semester ${session}: why the ${override.act === "open" ? "examinations open" : "score sheets are released"} with courses unverified`);
      if (!o.ok) { setOverride({ act: override.act, problem: o.problem }); notifyProblem(o.problem); return; }
      const r = await call("POST", `/summer/${sessionPath(session)}/exams/${override.act}`, {}, `Summer Semester ${session}: examinations ${override.act === "open" ? "opened" : "score sheets released"}`);
      if (!r.ok) { setOverride({ act: override.act, problem: r.problem }); notifyProblem(r.problem); return; }
      notify(override.act === "open" ? "The Summer examinations are open" : "The score sheets are released to the lecturers");
      setOverride(null);
      setReason("");
      onDone();
    } finally {
      setBusy(null);
    }
  }
  return (
    <Panel title="Examinations" right={`Examinations: ${period.exam_state ? period.exam_state.toLowerCase() : "not dated"}`}>
      <PBody>
        <KvGrid cls="grid--3" pairs={[
          ["Paid courses not verified", <b key="u" className="tnum" style={{ color: unverified ? "var(--red-ink)" : undefined }}>{unverified === null ? "Read when a course is paid" : unverified.toLocaleString()}</b>],
          ["Examination dates", period.exams_from ? `${day(period.exams_from)} – ${day(period.exams_to)}` : "Not dated"],
          ["Overrides on record", overrides.length ? plural(overrides.length, "override") : "None"],
        ]} />
        {examsOpen && (unverified ?? 0) > 0 ? (
          <Note kind="bad" title={`The examinations are open and ${plural(unverified ?? 0, "paid course")} not verified`}>A student who sits a course they already passed gets a lower new attempt, and every attempt counts in the CGPA. Verify them on the Verification tab; each is on the score sheets of its class while its entry stands.</Note>
        ) : null}
        {overrides.length ? (
          <ul className="list mt-1">
            {overrides.map((o) => <li key={o.act}><b>{o.act === "OPEN" ? "Opening the examinations" : "Releasing the score sheets"}</b> went ahead with {o.unverified} unverified on {day(o.set_at)}: <span className="sub2">{o.reason}</span></li>)}
          </ul>
        ) : null}
        <div className="sub2 mt-1">The database counts the paid courses not yet verified, from the results as they stand, at the moment of the act. Press Reconcile with results on the Verification tab first, so what the results settle is already confirmed or taken back; the examinations cannot be opened while registration is still open.</div>
        {maySet ? (
          <div className="row mt-2" style={{ gap: "var(--s-2)" }}>
            <Btn kind="ghost" size="md" busy={busy === "open"} busyLabel="Opening…" disabled={busy !== null || !period.exam_session_id || period.exam_state !== "DRAFT"} onClick={() => void act("open")}>Open the examinations</Btn>
            <Btn kind="ghost" size="md" busy={busy === "release-sheets"} busyLabel="Releasing…" disabled={busy !== null || period.exam_state !== "OPEN"} onClick={() => void act("release-sheets")}>Release the score sheets</Btn>
          </div>
        ) : null}
        {problem ? <ProblemNotice problem={problem} /> : null}
      </PBody>
      {override ? (
        <Modal title="Paid Summer courses are not verified" sub={override.act === "open" ? "Opening the examinations" : "Releasing the score sheets"} onClose={() => { setOverride(null); setReason(""); }}
          foot={<>
            <Btn kind="ghost" size="md" disabled={busy !== null} onClick={() => { setOverride(null); setReason(""); }}>Verify them first</Btn>
            <Btn kind="urgent" size="md" busy={busy !== null} busyLabel="Recording…" disabled={busy !== null || !reasonOk(reason)} onClick={() => void goAhead()}>Record the reason and go ahead</Btn>
          </>}>
          <ProblemNotice problem={override.problem} />
          <p className="sub2">An override holds only while the number of unverified courses has not grown: a course paid after it stops the act again. The reason is kept on the record.</p>
          <Field id="ov-why" label="Why the examinations may go ahead" hint={`At least ten characters. ${reason.trim().length} so far.`} required>
            <textarea id="ov-why" className="ctl" rows={3} maxLength={500} value={reason} onChange={(e) => setReason(e.target.value)} />
          </Field>
        </Modal>
      ) : null}
    </Panel>
  );
}

/** the Academic Office's acts on a set Summer: identify, tell, authorise */
function Acts({ session, period, onDone }: { session: string; period: SummerPeriod; onDone: () => void }) {
  const [busy, setBusy] = useState<string | null>(null);
  const [progress, setProgress] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [number, setNumber] = useState("");
  const [courses, setCourses] = useState("");
  const [why, setWhy] = useState("");
  async function identify() {
    setBusy("identify");
    setProblem(null);
    try {
      let since: string | null = null;
      let read = 0;
      let withResults = 0;
      for (let i = 0; i < 200; i++) {
        const r: DeskResult<Record<string, unknown>> = await call("POST", `/summer/${sessionPath(session)}/identify`, { since, limit: 2000 }, `Summer Semester ${session}: eligible students identified`);
        if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
        since = String(r.data.since);
        read += Number(r.data.read ?? 0);
        withResults += Number(r.data.results ?? 0);
        setProgress(`${read.toLocaleString()} read · ${Number(r.data.left ?? 0).toLocaleString()} left · ${Number(r.data.eligible ?? 0).toLocaleString()} eligible · ${withResults.toLocaleString()} with results counted`);
        if (Number(r.data.left ?? 0) === 0 || Number(r.data.read ?? 0) === 0) break;
      }
      notify("The eligible students are identified");
      onDone();
    } finally {
      setBusy(null);
    }
  }
  /** the students are told in tranches walked by a cursor, so the request is never held for minutes and a repeat tells no one twice */
  async function tell(kind: "OPEN" | "CLOSING" | "TIMETABLE") {
    setBusy(kind);
    setProblem(null);
    try {
      let after: string | null = null;
      let told = 0;
      let visited = 0;
      for (let i = 0; i < 400; i++) {
        const r: DeskResult<Record<string, unknown>> = await call("POST", `/summer/${sessionPath(session)}/tell`, { kind, limit: 500, after }, `Summer Semester ${session}: students told (${kind.toLowerCase()})`);
        if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
        told += Number(r.data.told ?? 0);
        visited += Number(r.data.visited ?? 0);
        after = r.data.next ? String(r.data.next) : null;
        setProgress(`${plural(told, "student")} told · ${visited.toLocaleString()} visited · ${Number(r.data.remaining ?? 0).toLocaleString()} still to visit`);
        if (!after) break;
      }
      notify(`${plural(told, "student")} told`);
    } finally {
      setBusy(null);
    }
  }
  async function authorise(revoke: boolean) {
    setBusy(revoke ? "revoke" : "authorise");
    setProblem(null);
    try {
      const r = await call("POST", `/summer/${sessionPath(session)}/authorise`, { number: number.trim(), courses: codes(courses).length ? codes(courses) : null, reason: why.trim(), revoke },
        `Summer Semester ${session}: ${number.trim()} ${revoke ? "authorisation withdrawn" : "authorised"}`);
      if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
      const e = r.data.eligibility as { eligible: boolean; category: string | null; reason: string | null } | undefined;
      notify(e?.eligible ? `${number.trim()} may take the Summer (${categoryWord(e.category)})` : `${number.trim()}: ${notEligibleWord(e?.reason)}`);
      setNumber(""); setCourses(""); setWhy("");
      onDone();
    } finally {
      setBusy(null);
    }
  }
  return (
    <Panel title="Acts" right={`${periodWords(period)[0]} · for ${periodForWord(period.categories)}`}>
      <PBody>
        <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)" }}>
          <Btn kind="primary" size="md" busy={busy === "identify"} busyLabel="Identifying…" disabled={busy !== null} onClick={() => void identify()}>Identify the eligible</Btn>
          <Btn kind="ghost" size="md" busy={busy === "OPEN"} busyLabel="Telling…" disabled={busy !== null || period.state === "CLOSED" || !period.registration_opens || !period.registration_closes} onClick={() => void tell("OPEN")}>Tell the eligible it is open</Btn>
          <Btn kind="ghost" size="md" busy={busy === "CLOSING"} busyLabel="Telling…" disabled={busy !== null || period.state !== "OPEN" || !period.registration_closes} onClick={() => void tell("CLOSING")}>Remind those not registered</Btn>
          <Btn kind="ghost" size="md" busy={busy === "TIMETABLE"} busyLabel="Telling…" disabled={busy !== null || !period.exams_from || !period.exams_to} onClick={() => void tell("TIMETABLE")}>Tell the registered the examination dates</Btn>
        </div>
        {progress ? <div className="sub2 mt-1" role="status">{progress}</div> : null}
        <div className="sub2 mt-1">Identifying reads every undergraduate who is final-year or in spillover, or authorised, and how many results each has on the portal, two thousand at a time; the figures are as last identified. A student’s own page always reads their eligibility afresh. Notices go in groups of five hundred; a notice already sent is never sent twice, and the e-mail pace of the portal means a very large audience is reached over more than a day.</div>
        <div className="grid grid--4 mt-2">
          <Field id="sm-num" label="Authorise a student" hint="Matriculation or admission number."><input id="sm-num" className="ctl tnum" value={number} onChange={(e) => setNumber(e.target.value)} /></Field>
          <Field id="sm-crs" label="Courses (optional)" hint="Codes, separated by commas, beside the courses they select."><input id="sm-crs" className="ctl" value={courses} onChange={(e) => setCourses(e.target.value)} /></Field>
          <Field id="sm-aw" label="Approved academic reason"><input id="sm-aw" className="ctl" value={why} onChange={(e) => setWhy(e.target.value)} /></Field>
          <div className="row" style={{ alignItems: "flex-end", gap: "var(--s-2)" }}>
            <Btn kind="primary" size="md" disabled={busy !== null || !number.trim() || why.trim().length < 10} onClick={() => void authorise(false)}>Authorise</Btn>
            <Btn kind="ghost" size="md" disabled={busy !== null || !number.trim() || why.trim().length < 10} onClick={() => void authorise(true)}>Withdraw</Btn>
          </div>
        </div>
        {problem ? <ProblemNotice problem={problem} /> : null}
      </PBody>
    </Panel>
  );
}

/** V739: paid Summer courses the registration could not take, retried once what stopped it is put right; decided by the Office
 *  (not outstanding or rejected, which credits the fee) when they cannot be taken at all */
function Issues({ issues, maySet, onDone }: { issues: SummerIssue[]; maySet: boolean; onDone: () => void }) {
  const [busy, setBusy] = useState<string | null>(null);
  async function retry(id: string, name: string) {
    setBusy(id);
    try {
      const r = await call("POST", `/summer/issues/${id}/retry`, {}, `Summer registration retried for ${name}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      const left = Number(r.data.stillRefused ?? 0);
      notify(left ? `${left} course${left === 1 ? " is" : "s are"} still refused` : `${name} is registered`);
      onDone();
    } finally {
      setBusy(null);
    }
  }
  return (
    <Panel title="Paid, not yet registered" right={String(issues.length)}>
      <PBody><div className="sub2">The payment stands; the registration could not take these courses. Put right what stopped it (for example a course ended since it was chosen), then retry. A course the student may not take at all is decided on the Verification tab (not outstanding or rejected), and its fee is held as a Summer credit.</div></PBody>
      <DTable cols={["Number", "Name", "Course", "Why", "Reference", "|mid"]} rows={issues.map((i) => [
        <span key="n" className="tnum">{i.number ?? "—"}</span>,
        <Link key="nm" className="lnk" href={`/students/${i.student_id}`}>{i.name}</Link>,
        <span key="c" className="tnum">{i.course_code ?? "—"}</span>,
        <span key="w" className="sub2">{i.error}</span>,
        <span key="r" className="tnum t-xs">{i.reference ?? "—"}</span>,
        maySet ? <Btn key="x" kind="ghost" size="sm" busy={busy === i.id} disabled={busy !== null} onClick={() => void retry(i.id, i.name)}>Retry</Btn> : <span key="x" />,
      ])} />
    </Panel>
  );
}

/** V754: why an authorisation is to be looked at again */
function reviewWhy(a: SummerAuthorisationToReview): string {
  return a.kind === "DEAD_CODE" ? "names a course no longer on the catalogue" : `rewritten by ${a.rewritten_by ?? "a one-off repair"}`;
}

/** V754: the Summer authorisations naming a course no longer on the catalogue, or rewritten by a one-off repair to another course
 *  than the trail from the grant gives; nothing is changed (the Office re-authorises) */
function ToReview({ session, items }: { session: string; items: SummerAuthorisationToReview[] }) {
  // V756: one row per course to look at; a student's authorisation is counted once
  const students = new Set(items.map((a) => `${a.session} ${a.student_id}`)).size;
  async function exportReview() {
    const head = ["Number", "Name", "Course named", "Now names", "The trail from the grant gives", "Why", "Granted or rewritten"];
    const rows = items.map((a) => [a.number ?? "", a.name, a.course_named ?? "", (a.courses_now ?? []).join(", "), a.trail_gives ?? "", reviewWhy(a), a.at ? day(a.at) : ""]);
    const blob = await brandedXlsx(`Summer authorisations to look at again, ${session}`, head, rows, {
      sheetName: "Authorisations", serial: docSerial("SAR"), meta: [["Session", session], ["Authorisations", String(students)], ["Courses to look at", String(rows.length)]],
    });
    downloadBlob(blob, `summer-semester-${sessionSlug(session)}-authorisations.xlsx`);
    notify(`${students} authorisation${students === 1 ? "" : "s"} exported`);
  }
  return (
    <Panel title="Authorisations to look at again" right={`${students} authorisation${students === 1 ? "" : "s"}`}>
      <PBody>
        <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)", alignItems: "center" }}>
          <span className="sub2" style={{ flex: "1 1 40ch" }}>Re-authorise the student with the right course using the Authorise form on this page; nothing is changed automatically.</span>
          <Btn kind="ghost" size="sm" busyLabel="Preparing…" onClick={() => exportReview()}>Download Excel</Btn>
        </div>
      </PBody>
      <DTable cols={["Number", "Name", "Course named", "Now names", "The trail from the grant gives", "Why"]} rows={items.map((a) => [
        <span key="n" className="tnum">{a.number ?? "—"}</span>,
        <Link key="nm" className="lnk" href={`/students/${a.student_id}`}>{a.name}</Link>,
        <span key="c" className="tnum">{a.course_named ?? "—"}</span>,
        <span key="w" className="tnum">{a.courses_now?.length ? a.courses_now.join(", ") : "—"}</span>,
        <span key="t" className="tnum">{a.trail_gives ?? "—"}</span>,
        <span key="y" className="sub2">{reviewWhy(a)}</span>,
      ])} texts={items.map((a) => `${a.number ?? ""} ${a.name} ${a.course_named ?? ""} ${(a.courses_now ?? []).join(" ")} ${a.trail_gives ?? ""}`)} />
    </Panel>
  );
}

export function SummerPeriodActs({ session, period, maySet, issues, toReview }: {
  session: string; period: SummerPeriod | null; maySet: boolean; issues: SummerIssue[]; toReview: SummerAuthorisationToReview[];
}) {
  const router = useRouter();
  const refresh = () => router.refresh();
  return (
    <>
      {period ? (
        <Panel title={`Summer Semester ${session}`} right={<Pil kind={periodWords(period)[1]}>{periodWords(period)[0].toUpperCase()}</Pil>}>
          <PBody>
            <KvGrid pairs={[
              ["Registration", period.registration_opens ? `${day(period.registration_opens)} – ${day(period.registration_closes)}` : "Not dated"],
              ["Examinations", period.exams_from ? `${day(period.exams_from)} – ${day(period.exams_to)}` : "Not dated"],
              ["Results expected", period.results_due ? day(period.results_due) : "—"],
              ["For", periodForWord(period.categories) + (period.programmes?.length ? ` · ${period.programmes.join(", ")}` : "") + (period.levels?.length ? ` · ${period.levels.join(", ")} Level` : "") + (period.max_courses ? ` · at most ${period.max_courses} courses` : "")],
            ]} />
          </PBody>
        </Panel>
      ) : null}
      {maySet ? <PeriodForm key={`${session}-${period?.set_at ?? "new"}`} session={session} period={period} onDone={refresh} /> : null}
      {maySet && period ? <Ceiling key={`c-${session}-${period.max_courses ?? "none"}`} session={session} period={period} onDone={refresh} /> : null}
      {period ? <Examinations session={session} period={period} maySet={maySet} onDone={refresh} /> : null}
      {maySet && period ? <Acts session={session} period={period} onDone={refresh} /> : null}
      {issues.length ? <Issues issues={issues} maySet={maySet} onDone={refresh} /> : null}
      {maySet && toReview.length ? <ToReview session={session} items={toReview} /> : null}
    </>
  );
}
