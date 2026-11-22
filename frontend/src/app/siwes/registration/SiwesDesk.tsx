"use client";
/** V752 · the SIWES registration desk — the University's master prompt of 12 November 2026. One desk, three tabs, each shown when the API
 *  answers it for the acting office:
 *  - Configuration: the session's SIWES period (registration opens and closes, training starts and its expected completion, the length
 *    in months, DRAFT until opened), the programmes taking SIWES that session and each programme's SIWES course per curriculum — a course
 *    of the catalogue named by its code, never a new course and never tied to a session. The Academic Office, the Registrar, the Deputy
 *    Registrar and the Super Administrator set it (the database checks again); everyone else reads it.
 *    V776 (the user's word of 22 November 2026): a programme is added before its SIWES course is known — each row says how the course is
 *    known (set here, or written down from the programme's own structure when it was added or a course was added to the SIWES courses
 *    — only where its Second Semester is the SIWES semester — standing until another is set) or that there is none yet, with what the
 *    catalogue offers now: one course found ("Use it" sets it; where the programme's Second Semester also carries required courses it
 *    asks first what that binds), several (the office sets the one), a SIWES course the programme carries where SIWES registration does
 *    not reach (a First Semester or 400 Level course: said plainly, nothing to set), or nothing; where a course is found the row says
 *    what the programme's Second Semester is (the SIWES semester, or one that also carries required courses); a note names the cohorts
 *    no course reaches yet, those of them who have paid or registered and so stay held to SIWES, and the same offer; the SIWES courses
 *    of the catalogue are listed, each department's under its own code and title, with the programmes each is set or written down for
 *    and the attachment semesters that rest on it, a course added to them by its code (a waiting programme whose own structure carries
 *    it is given it where its Second Semester is the SIWES semester) or taken off them.
 *  - Students: the eligible students of the session (300 Level, a programme taking SIWES), paid or not, registered or not, filtered by
 *    faculty, department, programme and status, searched and paged on the server, each one's detail, and the whole list as a branded
 *    Excel workbook or a printed list.
 *  - Statistics: eligible, paid (and the SIWES fees received), yet to pay, registered, yet to register — in all and by faculty,
 *    department and programme.
 *  The SIWES registration fee is the Bursary's (Fee Setup); it is never a school fee and never counted with one. */
import { useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, KvGrid, Note, Panel, PBody, Pil, Tabs, Tiles } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify, notifyProblem } from "@/components/proto/Toast";
import type { ScopeStructure } from "@/components/proto/ScopeBar";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { day } from "@/lib/format";
import {
  GROUP_HEAD, HISTORY_HEAD, NO_COURSE_300, NO_COURSE_FOUND, NO_COURSE_YET, PROGRAMMES_HINT, SIWES_COURSE_ADD_HINT, SIWES_COURSE_LEVEL_HINT, SIWES_SETTERS, STATUSES, STATUS_WORD,
  STUDENT_HEAD, apiStatus, attachmentForWords, byWords, carriedByWords, configWarnings, confirmUseItWords, courseCodeTyped, courseHint, courseHintWords, courseStateWarning,
  courseStateWord, courseWords, dateWord, emptyPeriodForm, foundInsteadWords, groupLine, historyLine, levelSemesterWords, naira, notRecognisedWords, num, onSiwesCourses,
  otherCoursesOf, periodProblems, periodWords, programmeAddedWords, programmeCourseLines, programmeNames, reasonWords, recognisedForWords, rowState, scopeWords,
  secondSemesterWords, sessionNames, setForWords, shownStatus, siwesCourseAddedWords, siwesCourseKnownWords, siwesCourseOf, siwesCourseOffWords, siwesCourseSetHereWords, siwesCoursesHint,
  siwesQuery, sourceWord, studentLine, trainingWords, unitName, unitOptions, unreachedLines,
  type MySiwes, type Opt, type PeriodForm, type SiwesCatalogueCourse, type SiwesConfig, type SiwesConfigProgramme, type SiwesCourse, type SiwesCourseLine,
  type SiwesFilters, type SiwesGroup, type SiwesHistoryRow, type SiwesStats, type SiwesStudentPage, type SiwesStudentRow,
} from "@/lib/siwes";

export type SiwesTab = "config" | "students" | "stats";

type Answer = { ok: true; data: Record<string, unknown> } | { ok: false; problem: Problem };

async function call(method: "POST" | "PUT" | "DELETE", path: string, body: unknown, reason: string): Promise<Answer> {
  const r = await fetch(`/api/bff/api/v1/siwes/admin${path}`, {
    method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) },
    body: method === "DELETE" ? undefined : JSON.stringify(body ?? {}),
  });
  const j = await r.json().catch(() => null);
  if (!r.ok) return { ok: false, problem: j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText } };
  return { ok: true, data: (j ?? {}) as Record<string, unknown> };
}

/** the session's SIWES period: its form, for the offices that set it */
function PeriodEditor({ session, config, onDone }: { session: string; config: SiwesConfig; onDone: () => void }) {
  const [f, setF] = useState<PeriodForm>(() => emptyPeriodForm(config.period));
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const problems = periodProblems(f);
  // who last set it: the person's name (the desk's config adds it) and the office, never a person's id
  const setter = byWords(config.period?.setByName, config.period?.setOffice);
  const set = (k: keyof PeriodForm) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value });
  async function save() {
    setBusy(true);
    setProblem(null);
    try {
      const r = await call("PUT", "/period", {
        session, state: f.state, registrationOpens: f.registrationOpens || null, registrationCloses: f.registrationCloses || null,
        trainingStarts: f.trainingStarts || null, trainingEnds: f.trainingEnds || null, durationMonths: Number(f.durationMonths), note: f.note.trim() || null,
      }, `SIWES period ${session} set ${f.state.toLowerCase()}`);
      if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
      notify(`SIWES ${session}: the period is saved (${f.state.toLowerCase()})`);
      onDone();
    } finally {
      setBusy(false);
    }
  }
  return (
    <Panel title={config.period ? "Change the period" : `Set SIWES for ${session}`} right={config.period?.setAt ? `Last set ${day(config.period.setAt)}${setter ? ` by ${setter}` : ""}` : undefined}>
      <PBody>
        <div className="grid grid--4">
          <Field id="sw-state" label="State" hint="Draft: not shown to students. Open: students pay and register within the dates. Closed: nothing more is taken.">
            <select id="sw-state" className="ctl" value={f.state} onChange={set("state")}>
              <option value="DRAFT">Draft</option><option value="OPEN">Open</option><option value="CLOSED">Closed</option>
            </select>
          </Field>
          <Field id="sw-opens" label="Registration opens"><input id="sw-opens" type="date" className="ctl" value={f.registrationOpens} onChange={set("registrationOpens")} /></Field>
          <Field id="sw-closes" label="Registration closes" hint="The students' deadline."><input id="sw-closes" type="date" className="ctl" value={f.registrationCloses} onChange={set("registrationCloses")} /></Field>
          <Field id="sw-months" label="Duration (months)"><input id="sw-months" type="number" min={1} max={12} step={1} className="ctl tnum" value={f.durationMonths} onChange={set("durationMonths")} /></Field>
          <Field id="sw-starts" label="Training starts"><input id="sw-starts" type="date" className="ctl" value={f.trainingStarts} onChange={set("trainingStarts")} /></Field>
          <Field id="sw-ends" label="Expected completion"><input id="sw-ends" type="date" className="ctl" value={f.trainingEnds} onChange={set("trainingEnds")} /></Field>
          <Field id="sw-note" label="Note" hint="Kept with the change." full><input id="sw-note" className="ctl" value={f.note} onChange={set("note")} /></Field>
        </div>
        {problems.length ? <ul className="sub2 mt-1" style={{ color: "var(--red-ink)", margin: 0, paddingLeft: "1.2em" }}>{problems.map((p) => <li key={p}>{p}</li>)}</ul> : null}
        <div className="mt-2"><Btn kind="primary" size="md" busy={busy} busyLabel="Saving…" disabled={busy || problems.length > 0} onClick={() => void save()}>Save the period</Btn></div>
        {problem ? <ProblemNotice problem={problem} /> : null}
      </PBody>
    </Panel>
  );
}

/** a programme's SIWES course for one curriculum (or every curriculum of the programme): a catalogue course named by its code */
function CourseModal({ programme, onClose, onDone }: { programme: SiwesConfigProgramme; onClose: () => void; onDone: () => void }) {
  const curricula = (programme.curricula ?? []).map((c) => c.curriculum).filter((c): c is string => !!c);
  const [curriculum, setCurriculum] = useState<string>("");
  const [code, setCode] = useState(programme.course?.code ?? "");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  async function save() {
    const courseCode = code.trim().toUpperCase().replace(/\s+/g, " ");
    if (!courseCode) { notifyProblem({ status: 422, title: "Give the course code, as the catalogue holds it." }); return; }
    setBusy(true);
    setProblem(null);
    try {
      const r = await call("PUT", "/courses", { programmeCode: programme.code, curriculum: curriculum || null, courseCode },
        `SIWES course of ${programme.code}${curriculum ? ` (${curriculum})` : ""} set to ${courseCode}`);
      if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
      notify(`${programme.code}${curriculum ? ` (${curriculum})` : ""}: SIWES course ${courseCode}`);
      // K25: a course not LIVE in the catalogue is mapped as asked, and said so at once
      const warning = courseStateWarning((r.data.course ?? null) as SiwesCourse | null);
      if (warning) notify(warning, "warn", 12000);
      onDone();
      onClose();
    } finally {
      setBusy(false);
    }
  }
  return (
    <Modal title={`SIWES course of ${programme.name}`} sub={`${programme.code} · the course stands for every session; it is a course already in the catalogue`} onClose={() => { if (!busy) onClose(); }}
      foot={<><Btn kind="ghost" disabled={busy} onClick={onClose}>Cancel</Btn><Btn kind="primary" busy={busy} busyLabel="Saving…" onClick={() => void save()}>Save the course</Btn></>}>
      <div className="grid grid--2">
        <Field id="swc-cur" label="Curriculum" hint="Where the programme's curricula carry different SIWES courses, set each.">
          <select id="swc-cur" className="ctl" value={curriculum} onChange={(e) => setCurriculum(e.target.value)}>
            <option value="">Every curriculum of the programme</option>
            {curricula.map((c) => <option key={c} value={c}>{c}</option>)}
          </select>
        </Field>
        <Field id="swc-code" label="Course code" required hint="e.g. CSC 399. A course the catalogue does not hold is refused; none is created here.">
          <input id="swc-code" className="ctl tnum" value={code} onChange={(e) => setCode(e.target.value)} placeholder="CSC 399" />
        </Field>
      </div>
      {/* SIWES_COURSE_LEVEL: a course the programme carries only at another level is refused (shown by notifyProblem above) */}
      <div className="sub2 mt-1">{SIWES_COURSE_LEVEL_HINT}</div>
      {problem ? <ProblemNotice problem={problem} /> : null}
    </Modal>
  );
}

/** V776 · the SIWES courses of the catalogue: each department carries SIWES under its own code and title. A course whose title reads
 *  SIWES or Industrial Training is listed as the catalogue takes it; the offices that set SIWES add any other by its code (a waiting
 *  programme whose own structure carries it is given it where its Second Semester is the SIWES semester), or take one off ("Not a
 *  SIWES course": refused by the database while it is set for a programme, reaches students who have paid or registered, or makes an
 *  attachment semester students are registered in; the programmes it was only written down for wait again). A course set as a
 *  programme's SIWES course without being on the SIWES courses is listed too, and said so: there is nothing to take off */
function SiwesCoursesPanel({ config, maySet, onDone }: { config: SiwesConfig; maySet: boolean; onDone: () => void }) {
  const courses = config.siwesCourses ?? [];
  const names = programmeNames(config);
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  async function add() {
    const courseCode = courseCodeTyped(code);
    if (!courseCode) { notifyProblem({ status: 422, title: "Give the course code, as the catalogue holds it." }); return; }
    setBusy("add");
    setProblem(null);
    try {
      const r = await call("PUT", "/siwes-courses", { courseCode, siwes: true }, `SIWES courses: ${courseCode} added`);
      if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
      // a course no programme comes by on its own (not 300 Level, say) is added as asked, and said so at once; the programmes still
      // waiting are given it by the act where their structure carries it and their Second Semester is the SIWES semester — those that
      // came by their course are named (the list before it is the configuration's)
      const said = siwesCourseAddedWords((r.data.siwesCourses ?? null) as SiwesCatalogueCourse[] | null, courseCode, config.siwesCourses, names);
      // a notice that says more than the bare success stays long enough to be read
      notify(said.words, said.tone, said.tone === "warn" || said.words.length > 80 ? 12000 : undefined);
      setCode("");
      onDone();
    } finally {
      setBusy(null);
    }
  }
  async function takeOff(c: SiwesCatalogueCourse) {
    // set here as a programme's SIWES course: the database refuses it, so the officer is told which programme instead of being asked
    const setHere = siwesCourseSetHereWords(c, names);
    if (setHere) { notify(setHere, "warn", 12000); return; }
    if (!window.confirm(siwesCourseOffWords(c, names))) return;
    setBusy(c.code);
    setProblem(null);
    try {
      const r = await call("PUT", "/siwes-courses", { courseCode: c.code, siwes: false }, `SIWES courses: ${c.code} taken off`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(`${c.code} is no longer a SIWES course`);
      onDone();
    } finally {
      setBusy(null);
    }
  }
  return (
    <Panel title="SIWES courses" right={`${courses.length} course${courses.length === 1 ? "" : "s"}`}>
      {courses.length ? (
        <DTable cols={["Course", "Department", "Level and semester", "Catalogue", "How it is known", "Programmes", "|mid"]}
          texts={courses.map((c) => [c.code, c.title, c.department, carriedByWords(c, Infinity), setForWords(c, names), recognisedForWords(c, names), attachmentForWords(c, Infinity)].filter(Boolean).join(" "))}
          rows={courses.map((c) => {
            const st = courseStateWord(c);
            const carried = carriedByWords(c);
            // whose SIWES course it is: set here, or written down from the programme's structure
            const setFor = setForWords(c, names);
            const recognisedFor = recognisedForWords(c, names);
            // the attachment semesters that rest on it: taking it off the SIWES courses ends them
            const attachment = attachmentForWords(c);
            const why = notRecognisedWords(c);
            return [
              <span key="c"><b className="tnum">{c.code}</b> {c.title ?? ""}{c.units != null ? <span className="sub2"> · {c.units} unit{c.units === 1 ? "" : "s"}</span> : null}</span>,
              <span key="d" className="sub2">{c.department || "—"}</span>,
              <span key="l">{levelSemesterWords(c)}</span>,
              <span key="s">{st ? <Pil kind={st[1]}>{st[0].toUpperCase()}</Pil> : "—"}</span>,
              <span key="k" className="sub2">{siwesCourseKnownWords(c)}</span>,
              <span key="p">
                <span className="blk">{carried ? <><span className="sub2">In the structure of</span> {carried}</> : <span className="sub2">In no programme&rsquo;s structure</span>}</span>
                {setFor ? <span className="blk"><span className="sub2">Set here for</span> {setFor}</span> : null}
                {recognisedFor ? <span className="blk"><span className="sub2">Written down for</span> {recognisedFor}</span> : null}
                {attachment ? <span className="blk sub2">Attachment semester of {attachment}</span> : null}
                {why ? <span className="blk sub2">{why}</span> : null}
              </span>,
              // a course listed only because it is set as a programme's SIWES course is not on the SIWES courses: nothing to take off
              maySet && onSiwesCourses(c) ? (
                <Btn key="a" kind="ghost" size="sm" busy={busy === c.code} disabled={busy !== null} onClick={() => void takeOff(c)}>Not a SIWES course</Btn>
              ) : <span key="a" />,
            ];
          })} />
      ) : (
        <PBody><div className="sub2">No course of the catalogue is listed as SIWES yet{maySet ? "; add each department's SIWES course below, by its code" : ""}.</div></PBody>
      )}
      {maySet ? (
        <PBody>
          <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)", alignItems: "flex-end" }}>
            <Field id="sw-siwes-course" label="Add a course" hint="A course code as the catalogue holds it, e.g. CSC 399. A course the catalogue does not hold is refused; none is created here.">
              <input id="sw-siwes-course" className="ctl tnum" value={code} onChange={(e) => setCode(e.target.value)} placeholder="CSC 399"
                onKeyDown={(e) => { if (e.key === "Enter" && busy === null && code.trim()) void add(); }} />
            </Field>
            <Btn kind="secondary" size="sm" busy={busy === "add"} busyLabel="Adding…" disabled={busy !== null || !code.trim()} onClick={() => void add()}>Add course</Btn>
          </div>
          {problem ? <ProblemNotice problem={problem} /> : null}
        </PBody>
      ) : null}
      <PBody><div className="sub2">{siwesCoursesHint(config.fee)} {SIWES_COURSE_ADD_HINT}</div></PBody>
    </Panel>
  );
}

function ConfigTab({ session, config, maySet, onDone }: { session: string; config: SiwesConfig; maySet: boolean; onDone: () => void }) {
  const [adding, setAdding] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [course, setCourse] = useState<SiwesConfigProgramme | null>(null);
  const p = config.period;
  const [pw, pt] = periodWords(p);
  async function add() {
    if (!adding) return;
    setBusy("add");
    try {
      const r = await call("POST", "/programmes", { session, programmeCode: adding }, `SIWES ${session}: programme ${adding} added`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      // V776: the programme is added whether or not its SIWES course is known; one with no course found is said so, never a bare success
      const said = programmeAddedWords(r.data as { programmes?: SiwesConfigProgramme[] | null }, adding, session);
      notify(said.words, said.tone, said.tone === "warn" ? 12000 : undefined);
      setAdding("");
      onDone();
    } finally {
      setBusy(null);
    }
  }
  async function remove(x: SiwesConfigProgramme) {
    if (!window.confirm(`Take ${x.name} (${x.code}) out of SIWES for ${session}? Its 300 Level students then register the Second Semester as before.`)) return;
    setBusy(x.code);
    try {
      const r = await call("DELETE", `/programmes?${siwesQuery({ session, programme: undefined }, { programmeCode: x.code })}`, null, `SIWES ${session}: programme ${x.code} removed`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(`${x.code} no longer takes SIWES in ${session}`);
      onDone();
    } finally {
      setBusy(null);
    }
  }
  // V776: the one course the catalogue now gives a programme (or one curriculum of it) with no course written down, set as its course
  // in one press: the same call "Set course" makes, with that course and that curriculum
  const foundKey = (x: SiwesConfigProgramme, l: SiwesCourseLine) => `found|${x.code}|${l.curriculum ?? ""}`;
  async function takeFound(x: SiwesConfigProgramme, l: SiwesCourseLine) {
    const found = l.found;
    if (!found) return;
    // a programme whose Second Semester is not the SIWES semester: what taking the course binds is told first, in the officer's words
    // (the published fee when there is one); where the semester is the SIWES semester, or the answer does not say, nothing is asked
    const ask = confirmUseItWords(x, found, config.fee);
    if (ask && !window.confirm(ask)) return;
    const whose = `${x.code}${l.curriculum ? ` (${l.curriculum})` : ""}`;
    setBusy(foundKey(x, l));
    try {
      const r = await call("PUT", "/courses", { programmeCode: x.code, curriculum: l.curriculum || null, courseCode: found.code }, `SIWES course of ${whose} set to ${found.code}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(`${whose}: SIWES course ${found.code}`);
      // K25: a course not LIVE in the catalogue is set as asked, and said so at once
      const warning = courseStateWarning((r.data.course ?? null) as SiwesCourse | null);
      if (warning) notify(warning, "warn", 12000);
      onDone();
    } finally {
      setBusy(null);
    }
  }
  const eligibleWord = (e: SiwesConfigProgramme["eligible"]) => (typeof e === "number" ? String(e) : typeof e === "boolean" ? (e ? "Yes" : "No") : "—");
  const foundButton = (x: SiwesConfigProgramme, l: SiwesCourseLine) => (
    <> <Btn kind="secondary" size="sm" busy={busy === foundKey(x, l)} busyLabel="Setting…" disabled={busy !== null} onClick={() => void takeFound(x, l)}>Use it</Btn></>
  );
  // K25: a programme's course with its catalogue state — a course not LIVE is warned of, under the table. V776: and how the course is
  // known (set here, or written down from the programme's structure); where there is none the row says what the catalogue offers
  // now — one course found (the offices that set take it with "Use it"), several (the one is set), a SIWES course carried where SIWES
  // registration does not reach (said plainly: nothing to set), or nothing — and what is done. Where a course is found and not yet
  // taken the row says what the programme's Second Semester is; beside a course written down from the catalogue, "the catalogue now
  // offers X instead" (or the course has ended), with the same press
  const courseCell = (x: SiwesConfigProgramme, l: SiwesCourseLine) => {
    if (!l.course) {
      const h = courseHint(l, maySet);
      if (h.kind === "NONE") return <><Pil kind="warn">{NO_COURSE_FOUND.toUpperCase()}</Pil> <span className="sub2">{h.action}</span></>;
      if (h.kind === "ELSEWHERE") return <><Pil kind="grey">{NO_COURSE_300.toUpperCase()}</Pil> <span className="sub2">{courseHintWords(h)}.</span></>;
      const st = h.found && h.found.state !== "LIVE" ? courseStateWord(h.found) : null;
      const load = secondSemesterWords(x);
      return (
        <>
          <Pil kind="warn">{NO_COURSE_YET.toUpperCase()}</Pil> <span className="sub2">{h.words}</span>{st ? <> <Pil kind={st[1]}>{st[0].toUpperCase()}</Pil></> : null}
          {h.kind === "FOUND" && maySet ? foundButton(x, l) : <span className="sub2"> — {h.action}</span>}
          {load ? <span className="blk sub2">{load}.</span> : null}
        </>
      );
    }
    const st = courseStateWord(l.course);
    const load = l.found ? secondSemesterWords(x) : "";
    return (
      <>
        {courseWords(l.course)}{st ? <> <Pil kind={st[1]}>{st[0].toUpperCase()}</Pil></> : null}{l.known ? <span className="sub2"> · {l.known}</span> : null}
        {l.found ? <span className="blk"><span className="sub2">{foundInsteadWords(l.course, l.found)}.</span>{maySet ? foundButton(x, l) : null}</span> : null}
        {load ? <span className="blk sub2">{load}.</span> : null}
      </>
    );
  };
  const warnings = configWarnings(config);
  // V776: the cohorts of the programmes taking SIWES that no SIWES course reaches yet, those of them who have paid or registered (held
  // to SIWES, waiting for the course), and what the catalogue offers each
  const unreached = unreachedLines(config, maySet);
  return (
    <>
      <Panel title={`SIWES ${session}`} right={<Pil kind={pt}>{pw.toUpperCase()}</Pil>}>
        <PBody>
          <KvGrid pairs={[
            ["For", "300 Level · Second Semester"],
            ["Registration", p?.registrationOpens ? `${dateWord(p.registrationOpens)} – ${dateWord(p.registrationCloses)}` : "Not dated"],
            ["Training", trainingWords(p)],
            ["SIWES registration fee", config.fee ? `${naira(config.fee.amount)} · ${String(config.fee.state ?? "").toLowerCase() || "not stated"}` : "Not stated (Fee Setup)"],
          ]} />
          {p?.note ? <div className="sub2 mt-1">{p.note}</div> : null}
          {!p ? <div className="sub2 mt-1">{maySet ? "Set the period below; programmes are added once it is saved." : "The Academic Office has not set SIWES for this session."}</div> : null}
          {config.fee && config.fee.state !== "PUBLISHED" ? <div className="sub2 mt-1">The Bursary publishes the SIWES registration fee on Fee Setup; until then no student can pay it.</div> : null}
        </PBody>
      </Panel>
      {maySet ? <PeriodEditor key={`${session}|${p?.setAt ?? "new"}`} session={session} config={config} onDone={onDone} /> : null}
      <Panel title="Programmes taking SIWES" right={`${config.programmes.length} programme${config.programmes.length === 1 ? "" : "s"}`}>
        {config.programmes.length ? (
          <DTable cols={["Programme", "Department", "Faculty", "Eligible|num", "SIWES course", "|mid"]} rows={config.programmes.map((x) => {
            // one line for each curriculum the programme's students hold, where it has any
            const lines = programmeCourseLines(x);
            return [
              <span key="p"><b className="tnum">{x.code}</b> {x.name}</span>,
              <span key="d" className="sub2">{unitName(x.department) || "—"}</span>,
              <span key="f" className="sub2">{unitName(x.faculty) || "—"}</span>,
              <span key="e" className="tnum">{eligibleWord(x.eligible)}</span>,
              <span key="c">{lines.map((l) => (l.curriculum
                ? <span key={l.curriculum} className="blk"><span className="sub2">{l.curriculum}:</span> {courseCell(x, l)}</span>
                : <span key="programme">{courseCell(x, l)}</span>))}</span>,
              maySet ? (
                <span key="a" className="row row--inline row--tight">
                  <Btn kind="ghost" size="sm" disabled={busy !== null} onClick={() => setCourse(x)}>Set course</Btn>
                  <Btn kind="ghost" size="sm" busy={busy === x.code} disabled={busy !== null} onClick={() => void remove(x)}>Remove</Btn>
                </span>
              ) : <span key="a" />,
            ];
          })} />
        ) : <PBody><div className="sub2">No programme takes SIWES in {session} yet.</div></PBody>}
        {unreached.lines.length ? (
          <PBody>
            <Note kind={unreached.paid ? "bad" : "info"} title={unreached.title}>
              {unreached.words}
              <ul style={{ margin: 0, paddingLeft: "1.2em" }}>
                {unreached.lines.map((u) => <li key={u.key}><b>{u.name}:</b> {u.words}. {u.course}.{u.semester ? ` ${u.semester}.` : ""}</li>)}
              </ul>
            </Note>
          </PBody>
        ) : null}
        {warnings.length ? (
          <PBody>
            <Note kind={warnings.some((w) => w.ended) ? "bad" : "info"} title={`${warnings.length} SIWES course${warnings.length === 1 ? " is" : "s are"} not live in the catalogue`}>
              <ul style={{ margin: 0, paddingLeft: "1.2em" }}>
                {warnings.map((w) => <li key={`${w.programme}|${w.curriculum ?? ""}`}><b>{w.programme}{w.curriculum ? ` (${w.curriculum})` : ""}:</b> {w.words}</li>)}
              </ul>
            </Note>
          </PBody>
        ) : null}
        {maySet && p ? (
          <PBody>
            <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)", alignItems: "flex-end" }}>
              <Field id="sw-add" label="Add a programme" hint="Undergraduate programmes not yet taking SIWES this session. A programme whose students are on SIWES is added whether or not its SIWES course is known yet.">
                <select id="sw-add" className="ctl" value={adding} onChange={(e) => setAdding(e.target.value)}>
                  <option value="">Choose a programme…</option>
                  {config.candidates.map((c) => <option key={c.code} value={c.code}>{c.name} ({c.code})</option>)}
                </select>
              </Field>
              <Btn kind="secondary" size="sm" busy={busy === "add"} busyLabel="Adding…" disabled={busy !== null || !adding} onClick={() => void add()}>Add programme</Btn>
            </div>
          </PBody>
        ) : null}
        <PBody><div className="sub2">{PROGRAMMES_HINT}</div></PBody>
      </Panel>
      <SiwesCoursesPanel config={config} maySet={maySet} onDone={onDone} />
      {course ? <CourseModal programme={course} onClose={() => setCourse(null)} onDone={onDone} /> : null}
    </>
  );
}

type Detail = MySiwes & { matricNo?: string | null; name?: string | null; history?: SiwesHistoryRow[] | null };

/** one student's SIWES: what the eligibility says, the payment, the registration, and the earlier rows of the record */
function StudentDetail({ row, session, d, problem, onClose }: { row: SiwesStudentRow; session: string; d: Detail | null; problem: Problem | null; onClose: () => void }) {
  const history = d?.history ?? [];
  return (
    <Modal wide title={`${d?.name ?? row.name} · SIWES ${session}`} sub={`${d?.matricNo ?? row.matricNo ?? ""} · ${row.programme ?? row.programmeCode ?? ""}`} onClose={onClose}>
      {problem ? <ProblemNotice problem={problem} /> : !d ? <div className="sub2">Reading…</div> : (
        <>
          <KvGrid pairs={[
            ["Eligible", d.eligible ? "Yes" : "No"],
            ["Level", d.level != null ? `${d.level} Level` : "—"],
            ["Department", unitName(d.department) || row.department || "—"],
            ["Faculty", unitName(d.faculty) || row.faculty || "—"],
            // once registered, the course the registration was made on, whatever the programme is mapped to since
            ["SIWES course", courseWords(siwesCourseOf(d))],
            ["Training", trainingWords(d.period)],
            ["Fee", d.paid ? `${naira(d.paid.amount)} paid ${dateWord(d.paid.at)} · ${sourceWord(d.paid.source)}` : d.openReference ? `Reference ${d.openReference.reference} drawn, not paid` : "Not paid"],
            ["Payment reference", d.paid?.reference ?? "—"],
            ["Receipt number", d.paid?.receiptNo ?? "—"],
            ["Registration", d.registration ? `${d.registration.status.toLowerCase()} · ${dateWord(d.registration.at)}` : "Not registered"],
            ["Other Second Semester courses", otherCoursesOf(d).join(", ") || "None"],
          ]} />
          {!d.eligible && d.reasons?.length ? <Note kind="bad" title="Why not eligible">{reasonWords(d.reasons).join(" ")}</Note> : null}
          {history.length ? (
            <div className="mt-2">
              <div className="sub2 mb-1">The student&rsquo;s SIWES record</div>
              <DTable cols={HISTORY_HEAD} rows={history.map((h) => historyLine(h).map((w, i) => <span key={i} className={i ? "sub2" : "tnum"}>{w}</span>))} />
            </div>
          ) : null}
        </>
      )}
    </Modal>
  );
}

export function SiwesDesk({ session, filters, tab, config, configProblem, students, studentsProblem, stats, statsProblem, structure, actingOffice }: {
  session: string | null; filters: SiwesFilters; tab: SiwesTab | null;
  config: SiwesConfig | null; configProblem: Problem | null;
  students: SiwesStudentPage | null; studentsProblem: Problem | null;
  stats: SiwesStats | null; statsProblem: Problem | null;
  structure: ScopeStructure; actingOffice: string | null;
}) {
  const go = useQueryNav();
  const maySet = SIWES_SETTERS.includes(actingOffice ?? "") && config?.access?.set !== false;
  // a tab is shown when the API answers it for the acting office
  const tabs: { id: SiwesTab; label: string; count?: string }[] = [
    ...(config ? [{ id: "config" as const, label: "Configuration", count: String(config.programmes.length) }] : []),
    ...(students ? [{ id: "students" as const, label: "Students", count: String(students.total) }] : []),
    ...(stats ? [{ id: "stats" as const, label: "Statistics" }] : []),
  ];
  const view: SiwesTab = tab && tabs.some((t) => t.id === tab) ? tab : (maySet && config ? "config" : tabs.find((t) => t.id === "students")?.id ?? tabs[0]?.id ?? "config");
  const [q, setQ] = useState(filters.q ?? "");
  const [busy, setBusy] = useState(false);
  const [detail, setDetail] = useState<{ row: SiwesStudentRow; data: Detail | null; problem: Problem | null } | null>(null);
  async function openDetail(row: SiwesStudentRow) {
    if (!session) return;
    setDetail({ row, data: null, problem: null });
    const r = await fetch(`/api/bff/api/v1/siwes/admin/students/${encodeURIComponent(row.studentId)}?session=${encodeURIComponent(session)}`, { cache: "no-store" }).catch(() => null);
    const j = r ? await r.json().catch(() => null) : null;
    if (!r || !r.ok) { setDetail({ row, data: null, problem: (j as Problem) ?? { status: 503, title: "The student's SIWES could not be read just now." } }); return; }
    setDetail({ row, data: j as Detail, problem: null });
  }
  const href = (patch: SiwesFilters & { tab?: string; page?: number }) => {
    const n: SiwesFilters & { tab?: string; page?: number } = { ...filters, tab: view, ...patch };
    if ("faculty" in patch) { delete n.department; delete n.programme; }
    if ("department" in patch) delete n.programme;
    if (!("page" in patch)) delete n.page;
    return `/siwes/registration?${siwesQuery(n)}`;
  };
  const opts = unitOptions(structure, filters, (config?.programmes ?? []).map((p) => p.code));
  const sessions = sessionNames(config?.sessions);
  // the list shown: the eligible students unless the address asks for another (ALL: every student of the programmes, the API sent no status)
  const status = shownStatus(filters.status);
  const scope = scopeWords({ ...filters, session: session ?? undefined }, opts, [
    view === "students" ? STATUS_WORD[status] : null, view === "students" && filters.q ? `search “${filters.q}”` : null]);

  async function allRows(): Promise<SiwesStudentRow[]> {
    const out: SiwesStudentRow[] = [];
    const total = students?.total ?? 0;
    for (let page = 0; page * 500 < total && page < 200; page++) {
      const r = await fetch(`/api/bff/api/v1/siwes/admin/students?${siwesQuery({ ...filters, status: apiStatus(filters.status) }, { page, size: 500 })}`, { cache: "no-store" });
      if (!r.ok) throw (await r.json().catch(() => ({ status: r.status, title: r.statusText })));
      const j = (await r.json()) as SiwesStudentPage;
      out.push(...j.rows);
      if (j.rows.length < 500) break;
    }
    return out;
  }
  async function exportStudents(kind: "xlsx" | "pdf") {
    if (!session) return;
    setBusy(true);
    try {
      const body = (await allRows()).map((r) => studentLine(r, session));
      const title = `SIWES Students — ${STATUS_WORD[status]}`;
      if (kind === "xlsx") downloadBlob(await brandedXlsx(title, STUDENT_HEAD, body, { sheetName: "SIWES students", serial: docSerial("SIW"), sub: scope }), `siwes-students-${session.replace("/", "-")}.xlsx`);
      else brandedPrint(title, scope, STUDENT_HEAD, body, docSerial("SIW"));
    } catch (e) {
      notifyProblem((e as { status?: number }).status ? (e as Problem) : { status: 500, title: "The export could not be built" });
    } finally {
      setBusy(false);
    }
  }
  async function exportGroups(kind: "xlsx" | "pdf", t: string, g: SiwesGroup[]) {
    if (!session) return;
    setBusy(true);
    try {
      const head = [t, ...GROUP_HEAD.slice(1)];
      const body = g.map(groupLine);
      const title = `SIWES ${t} Summary`;
      if (kind === "xlsx") downloadBlob(await brandedXlsx(title, head, body, { sheetName: `By ${t.toLowerCase()}`, serial: docSerial("SIW"), sub: scope }), `siwes-${t.toLowerCase()}-summary-${session.replace("/", "-")}.xlsx`);
      else brandedPrint(title, scope, head, body, docSerial("SIW"));
    } catch (e) {
      notifyProblem({ status: 500, title: "The export could not be built", detail: e instanceof Error ? e.message : String(e) });
    } finally {
      setBusy(false);
    }
  }

  const sel = (id: string, label: string, k: keyof SiwesFilters, options: Opt[], all: string) => (
    <Field id={id} label={label}>
      <select id={id} className="ctl" value={filters[k] ?? ""} onChange={(e) => go(href({ [k]: e.target.value || undefined }))}>
        <option value="">{all}</option>
        {options.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
      </select>
    </Field>
  );
  const pages = students ? Math.max(1, Math.ceil(students.total / Math.max(1, students.size))) : 1;
  const s = stats;

  return (
    <>
      <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)", alignItems: "flex-end" }}>
        {sessions.length ? (
          <Field id="sw-session" label="Session">
            <select id="sw-session" className="ctl" value={session ?? ""} onChange={(e) => go(`/siwes/registration?${siwesQuery({ session: e.target.value }, { tab: view })}`)}>
              {!session || sessions.includes(session) ? null : <option value={session}>{session}</option>}
              {sessions.map((x) => <option key={x} value={x}>{x}</option>)}
            </select>
          </Field>
        ) : null}
        <span className="grow" />
        {tabs.length > 1 ? <Tabs label="What to show" value={view} onChange={(t) => go(href({ tab: t }))} items={tabs} /> : null}
      </div>
      {configProblem && view === "config" ? <ProblemNotice problem={configProblem} /> : null}

      {view === "config" && config && session ? (
        <ConfigTab session={session} config={config} maySet={maySet} onDone={() => go(href({}))} />
      ) : null}

      {view !== "config" ? (
        <Panel title="Filters" right={scope}>
          <PBody>
            <form className="row row--inline row--tight" style={{ flexWrap: "wrap" }} onSubmit={(e) => { e.preventDefault(); go(href({ q: q.trim() || undefined, page: 0 })); }}>
              {sel("sw-fac", "Faculty", "faculty", opts.faculties, "All faculties")}
              {sel("sw-dept", "Department", "department", opts.departments, "All departments")}
              {sel("sw-prog", "Programme", "programme", opts.programmes, "All programmes")}
              {view === "students" ? (
                <>
                  <Field id="sw-status" label="Students">
                    <select id="sw-status" className="ctl" value={status} onChange={(e) => go(href({ status: e.target.value === "ELIGIBLE" ? undefined : e.target.value, page: 0 }))}>
                      {STATUSES.map((x) => <option key={x} value={x}>{STATUS_WORD[x]}</option>)}
                    </select>
                  </Field>
                  <Field id="sw-q" label="Search"><input id="sw-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Matric number, name" /></Field>
                  <Btn kind="secondary" size="sm" type="submit">Search</Btn>
                  {filters.q ? <Btn kind="ghost" size="sm" onClick={() => { setQ(""); go(href({ q: undefined, page: 0 })); }}>Clear</Btn> : null}
                </>
              ) : null}
            </form>
          </PBody>
        </Panel>
      ) : null}

      {view === "students" ? (
        studentsProblem ? <ProblemNotice problem={studentsProblem} /> : students && session ? (
          <Panel title={`${num(students.total).toLocaleString("en-NG")} student${students.total === 1 ? "" : "s"}`} right={
            <span className="row row--inline row--tight">
              <span className="sub2">page {students.page + 1} of {pages}</span>
              <Btn kind="ghost" size="sm" disabled={students.page === 0} onClick={() => go(href({ page: students.page - 1 }))}>Previous</Btn>
              <Btn kind="ghost" size="sm" disabled={students.page + 1 >= pages} onClick={() => go(href({ page: students.page + 1 }))}>Next</Btn>
              <Btn kind="secondary" size="sm" disabled={busy || !students.total} onClick={() => void exportStudents("xlsx")}>Excel</Btn>
              <Btn kind="ghost" size="sm" disabled={busy || !students.total} onClick={() => void exportStudents("pdf")}>Print</Btn>
            </span>}>
            {students.rows.length ? (
              <DTable cols={["S/N|num", "Student", "Programme", "Level|num", "SIWES fee", "Registration", "|mid"]} rows={students.rows.map((r, i) => {
                const [w, t] = rowState(r);
                return [
                  <span key="n" className="tnum sub2">{students.page * students.size + i + 1}</span>,
                  <span key="s"><b>{r.name}</b><div className="sub2 tnum">{r.matricNo ?? "—"}</div></span>,
                  <span key="p">{r.programme ?? r.programmeCode ?? "—"}<div className="sub2">{[r.department, r.faculty].filter(Boolean).join(" · ")}</div></span>,
                  <span key="l" className="tnum">{r.level ?? "—"}</span>,
                  <span key="f">{r.paid ? <Pil kind="ok">PAID</Pil> : <Pil kind={r.eligible === false ? "grey" : "bad"}>NOT PAID</Pil>}
                    {r.paid ? <div className="sub2 tnum">{naira(r.amount)}{r.paidAt ? ` · ${dateWord(r.paidAt)}` : ""}{r.paymentSource ? ` · ${sourceWord(r.paymentSource)}` : ""}</div> : null}</span>,
                  <span key="r"><Pil kind={t}>{t === "grey" ? w : w.toUpperCase()}</Pil>{r.registered ? <div className="sub2 tnum">{r.courseCode ?? ""}{r.registeredAt ? ` · ${dateWord(r.registeredAt)}` : ""}</div> : null}</span>,
                  <Btn key="v" kind="ghost" size="sm" onClick={() => void openDetail(r)}>View</Btn>,
                ];
              })} />
            ) : <PBody><Note kind="info" title="No student matches">Widen the filters or clear the search.</Note></PBody>}
          </Panel>
        ) : null
      ) : null}

      {view === "stats" ? (
        statsProblem ? <ProblemNotice problem={statsProblem} /> : s ? (
          <>
            <Tiles cls="grid--3" items={[
              ["Eligible", num(s.eligible).toLocaleString("en-NG"), null, "300 Level, a programme taking SIWES"],
              ["Paid", num(s.paid).toLocaleString("en-NG"), "var(--green-ink)", `${naira(s.amountPaid)} received`],
              ["Yet to pay", num(s.unpaid).toLocaleString("en-NG"), s.unpaid ? "var(--red-ink)" : null, `${naira(s.amountOutstanding)} at the published fee`],
              ["Registered", num(s.registered).toLocaleString("en-NG"), "var(--green-ink)", "SIWES course registered"],
              ["Yet to register", num(s.notRegistered).toLocaleString("en-NG"), s.notRegistered ? "var(--red-ink)" : null, "Eligible, not yet registered"],
            ]} />
            {([["Faculty", s.byFaculty], ["Department", s.byDepartment], ["Programme", s.byProgramme]] as [string, SiwesGroup[]][]).map(([t, g]) => (
              <Panel key={t} title={`By ${t.toLowerCase()}`} right={
                <span className="row row--inline row--tight">
                  <span className="sub2">{g.length}</span>
                  <Btn kind="secondary" size="sm" disabled={busy || !g.length} onClick={() => void exportGroups("xlsx", t, g)}>Excel</Btn>
                  <Btn kind="ghost" size="sm" disabled={busy || !g.length} onClick={() => void exportGroups("pdf", t, g)}>Print</Btn>
                </span>}>
                <DTable cols={[t, "Eligible|num", "Paid|num", "Yet to pay|num", "Registered|num", "Yet to register|num"]} rows={g.map((x) => {
                  const line = groupLine(x);
                  return [<span key="n">{line[0]}</span>, ...line.slice(2).map((v, i) => <span key={i} className="tnum">{v}</span>)];
                })} />
              </Panel>
            ))}
          </>
        ) : null
      ) : null}

      {!session ? <Note kind="info" title="No session">The University&rsquo;s current session could not be read.</Note> : null}
      {detail && session ? <StudentDetail row={detail.row} session={session} d={detail.data} problem={detail.problem} onClose={() => setDetail(null)} /> : null}
    </>
  );
}
