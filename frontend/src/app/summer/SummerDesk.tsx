"use client";
/** V735 · the Summer Semester desk — the University's master prompt of 12 November 2026. The Academic Office (and the Registrar, the
 *  Deputy Registrar, the Super Administrator) set the Summer of a session — a third period of its own: the registration window, the
 *  examination dates, the results date, the categories, programmes and levels it runs for — identify the eligible (in tranches: each
 *  student's eligibility reads every result they hold), authorise a student for an approved academic reason, tell the students, and
 *  open the examinations. Everyone who reads it sees the students (a Head of Department their department's, a Dean their faculty's),
 *  the classes, and the figures: eligible, begun, registered, the programme and course fees paid apart, the results. */
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, KvGrid, Note, Panel, PBody, Pil, Tabs, Tiles } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { day } from "@/lib/format";
import { toCsv, sessionSlug } from "@/lib/report";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { classListHref } from "@/lib/lecturer";
import Link from "next/link";
import {
  CATEGORIES, categoryWord, naira, notEligibleWord, paymentStateWords, periodWords, semesterWord, sessionPath, type Money, type SummerPeriod,
} from "@/lib/summer";

export interface SummerStudentRow {
  student_id: string; matric_no: string | null; name: string; programme_code: string | null; programme: string | null; dept_code: string | null;
  department: string | null; faculty_code: string | null; faculty: string | null; level: number | null; eligible: boolean | null;
  category: string | null; outstanding: number | null; reason: string | null; courses_selected: number; courses_paid: number;
  programme_fee_due: Money; programme_fee_paid: Money; course_fees_due: Money; course_fees_paid: Money; payment_state: string;
  registration_status: string | null; courses_registered: number; results_published: number; results_passed: number; results_failed: number;
  cleared_all: boolean;
}
type Group = { name: string; eligible: number; commenced: number; registered: number; courses: number };
export interface SummerStudents {
  session: string; period: SummerPeriod | null; identifiedAt: string | null; rows: SummerStudentRow[];
  /** V739: paid courses the registration could not take (a course ended since it was chosen, a gate on the registration) */
  issues?: { id: string; student_id: string; number: string | null; name: string; course_code: string | null; error: string; raised_at: string; reference: string | null }[];
  summary: {
    eligible: number; commenced: number; completed: number; registeredCourses: number; owing: number; paid: number;
    programmeFeesPaid: Money; courseFeesPaid: Money; feesOutstanding: Money; resultsPublished: number; resultsPassed: number; resultsFailed: number;
    clearedAll: number; byFaculty: Group[]; byDepartment: Group[]; byProgramme: Group[]; byLevel: Group[];
  };
}
export interface SummerCourseRow {
  offering_id: string; course_code: string; title: string | null; units: number | null; course_semester: number | null; dept_code: string | null;
  department: string | null; lecturer: string | null; registered: number; failed_in_first: number; failed_in_second: number; sheets: number;
  sheet_stage: string | null;
}
/** V754: a Summer authorisation to look at again (registration.summer_authorisations_to_review) */
export interface SummerAuthorisationToReview {
  kind: "DEAD_CODE" | "REWRITTEN"; session: string; student_id: string; number: string | null; name: string; course_named: string | null;
  courses_now: string[] | null; trail_gives: string | null; rewritten_by: string | null; at: string | null;
}

const SETTERS = ["academic", "registrar", "dregistrar", "super"];
/** V741: the offices that may open a class list (the API's /registration/class-list readers) */
const CLASS_LIST = ["academic", "registrar", "dregistrar", "dvc", "vc", "records", "dean", "hod", "exams", "facultyexams", "facultyofficer", "lecturer", "ict", "admin", "super"];
type View = "students" | "courses" | "groups";
type Show = "all" | "eligible" | "commenced" | "owing" | "paid" | "notstarted";

async function call(method: "POST" | "PUT", path: string, body: unknown, reason: string): Promise<{ ok: true; data: Record<string, unknown> } | { ok: false; problem: Problem }> {
  const r = await fetch(`/api/bff/api/v1${path}`, {
    method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}),
  });
  const j = await r.json().catch(() => null);
  if (!r.ok) return { ok: false, problem: j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText } };
  return { ok: true, data: (j ?? {}) as Record<string, unknown> };
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
  const [cats, setCats] = useState<Set<string>>(new Set(period?.categories ?? CATEGORIES));
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
        resultsDue: results || null, categories: [...cats], programmes: list(programmes), levels: list(levels).map(Number).filter((n) => Number.isInteger(n) && n > 0),
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
        <div className="mt-2">
          <div className="sub2 mb-1">Who it is for</div>
          <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-4)" }}>
            {CATEGORIES.map((c) => (
              <label key={c} className="row" style={{ gap: "var(--s-1)" }}>
                <input type="checkbox" aria-label={categoryWord(c)} checked={cats.has(c)} onChange={() => setCats((x) => { const n = new Set(x); if (n.has(c)) n.delete(c); else n.add(c); return n; })} />
                {categoryWord(c)}
              </label>
            ))}
          </div>
        </div>
        <div className="grid grid--3 mt-2">
          <Field id="sm-prog" label="Programmes" hint="Codes, separated by commas. Empty: every undergraduate programme."><input id="sm-prog" className="ctl" value={programmes} onChange={(e) => setProgrammes(e.target.value)} /></Field>
          <Field id="sm-lv" label="Levels" hint="e.g. 400, 500. Empty: every level."><input id="sm-lv" className="ctl tnum" value={levels} onChange={(e) => setLevels(e.target.value)} /></Field>
          <Field id="sm-why" label="Reason" hint="Kept with the change."><input id="sm-why" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
        </div>
        <div className="mt-2"><Btn kind="primary" size="md" busy={busy} busyLabel="Saving…" disabled={busy || cats.size === 0} onClick={() => void save()}>Save the period</Btn></div>
        {problem ? <ProblemNotice problem={problem} /> : null}
      </PBody>
    </Panel>
  );
}

/** the Academic Office's acts on a set Summer: identify, authorise, tell, examinations */
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
      for (let i = 0; i < 200; i++) {
        const r: Awaited<ReturnType<typeof call>> = await call("POST", `/summer/${sessionPath(session)}/identify`, { since, limit: 400 }, `Summer Semester ${session}: eligible students identified`);
        if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
        since = String(r.data.since);
        read += Number(r.data.read ?? 0);
        setProgress(`${read} read · ${r.data.left} left · ${r.data.eligible} eligible`);
        if (Number(r.data.left ?? 0) === 0 || Number(r.data.read ?? 0) === 0) break;
      }
      notify("The eligible students are identified");
      onDone();
    } finally {
      setBusy(null);
    }
  }
  async function tell(kind: "OPEN" | "CLOSING" | "TIMETABLE") {
    setBusy(kind);
    setProblem(null);
    try {
      const r = await call("POST", `/summer/${sessionPath(session)}/tell`, { kind }, `Summer Semester ${session}: students told (${kind.toLowerCase()})`);
      if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
      notify(`${r.data.told} student${r.data.told === 1 ? "" : "s"} told`);
    } finally {
      setBusy(null);
    }
  }
  async function exams(act: "open" | "release-sheets") {
    setBusy(act);
    setProblem(null);
    try {
      const r = await call("POST", `/summer/${sessionPath(session)}/exams/${act}`, {}, `Summer Semester ${session}: examinations ${act === "open" ? "opened" : "score sheets released"}`);
      if (!r.ok) { setProblem(r.problem); notifyProblem(r.problem); return; }
      notify(act === "open" ? "The Summer examinations are open" : "The score sheets are released to the lecturers");
      onDone();
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
    <Panel title="Acts" right={`Examinations: ${period.exam_state ? period.exam_state.toLowerCase() : "not dated"}`}>
      <PBody>
        <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)" }}>
          <Btn kind="primary" size="md" busy={busy === "identify"} busyLabel="Identifying…" disabled={busy !== null} onClick={() => void identify()}>Identify the eligible</Btn>
          <Btn kind="ghost" size="md" disabled={busy !== null || period.state === "CLOSED" || !period.registration_opens || !period.registration_closes} onClick={() => void tell("OPEN")}>Tell the eligible it is open</Btn>
          <Btn kind="ghost" size="md" disabled={busy !== null || period.state !== "OPEN" || !period.registration_closes} onClick={() => void tell("CLOSING")}>Remind those not registered</Btn>
          <Btn kind="ghost" size="md" disabled={busy !== null || !period.exams_from || !period.exams_to} onClick={() => void tell("TIMETABLE")}>Tell the registered the examination dates</Btn>
          <Btn kind="ghost" size="md" disabled={busy !== null || !period.exam_session_id || period.exam_state !== "DRAFT"} onClick={() => void exams("open")}>Open the examinations</Btn>
          <Btn kind="ghost" size="md" disabled={busy !== null || period.exam_state !== "OPEN"} onClick={() => void exams("release-sheets")}>Release the score sheets</Btn>
        </div>
        {progress ? <div className="sub2 mt-1">{progress}</div> : null}
        <div className="sub2 mt-1">Identifying reads every undergraduate at or past the final level, in spillover, or authorised, a few hundred at a time; the figures below are as last identified. A student’s own page always reads their eligibility afresh.</div>
        <div className="grid grid--4 mt-2">
          <Field id="sm-num" label="Authorise a student" hint="Matriculation or admission number."><input id="sm-num" className="ctl tnum" value={number} onChange={(e) => setNumber(e.target.value)} /></Field>
          <Field id="sm-crs" label="Courses (optional)" hint="Codes, separated by commas, beside the outstanding ones."><input id="sm-crs" className="ctl" value={courses} onChange={(e) => setCourses(e.target.value)} /></Field>
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

/** V739: paid Summer courses the registration could not take, retried once what stopped it is put right */
function Issues({ issues, maySet, onDone }: { issues: NonNullable<SummerStudents["issues"]>; maySet: boolean; onDone: () => void }) {
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
      <PBody><div className="sub2">The payment stands; the registration could not take these courses. Put right what stopped it (for example a course ended since it was chosen), then retry.</div></PBody>
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

function download(name: string, text: string) {
  const url = URL.createObjectURL(new Blob([text], { type: "text/csv;charset=utf-8" }));
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export function SummerDesk({ periods, session, sessions, students, courses, actingOffice, toReview = [] }: {
  periods: SummerPeriod[]; session: string | null; sessions: string[]; students: SummerStudents | null; courses: SummerCourseRow[]; actingOffice: string | null;
  /** V754: the authorisations to look at again (read only where the office may set) */
  toReview?: SummerAuthorisationToReview[];
}) {
  const router = useRouter();
  const maySet = SETTERS.includes(actingOffice ?? "");
  const [view, setView] = useState<View>("students");
  const [show, setShow] = useState<Show>("all");
  const [q, setQ] = useState("");
  const [newSession, setNewSession] = useState("");
  const period = students?.period ?? periods.find((p) => p.session === session) ?? null;
  const rows = useMemo(() => {
    const all = students?.rows ?? [];
    const term = q.trim().toLowerCase();
    return all.filter((r) => {
      if (show === "eligible" && !r.eligible) return false;
      if (show === "commenced" && r.payment_state === "NOT_STARTED") return false;
      if (show === "owing" && !["UNPAID", "PART_PAID"].includes(r.payment_state)) return false;
      if (show === "paid" && r.payment_state !== "PAID") return false;
      if (show === "notstarted" && (r.payment_state !== "NOT_STARTED" || !r.eligible)) return false;
      return !term || [r.matric_no, r.name, r.programme, r.department, r.faculty].some((x) => (x ?? "").toLowerCase().includes(term));
    });
  }, [students, show, q]);
  const unset = sessions.filter((s) => !periods.some((p) => p.session === s));
  const s = students?.summary;

  function exportRows() {
    if (!students) return;
    download(`summer-semester-${sessionSlug(students.session)}-students.csv`, toCsv(
      ["Matriculation number", "Name", "Faculty", "Department", "Programme", "Level", "Eligible", "Category", "Outstanding", "Why not",
        "Courses selected", "Courses paid", "Programme fee paid", "Course fees paid", "Owed", "Payment", "Registration", "Courses registered",
        "Results published", "Passed", "Failed", "Cleared every outstanding course"],
      rows.map((r) => [r.matric_no, r.name, r.faculty, r.department, r.programme, r.level, r.eligible ? "Yes" : "No", categoryWord(r.category), r.outstanding,
        r.eligible ? "" : notEligibleWord(r.reason), r.courses_selected, r.courses_paid, String(r.programme_fee_paid ?? 0), String(r.course_fees_paid ?? 0),
        String(Number(r.programme_fee_due ?? 0) + Number(r.course_fees_due ?? 0)), paymentStateWords(r.payment_state)[0], r.registration_status ?? "",
        r.courses_registered, r.results_published, r.results_passed, r.results_failed, r.cleared_all ? "Yes" : "No"])));
  }

  return (
    <>
      <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)", alignItems: "center" }}>
        <span className="sub2">Session</span>
        {periods.map((p) => (
          <Btn key={p.session} kind={p.session === session ? "primary" : "ghost"} size="sm" onClick={() => router.push(`/summer?session=${encodeURIComponent(p.session)}`)}>{p.session}</Btn>
        ))}
        {maySet && unset.length ? (
          <>
            <select aria-label="A session without a Summer" className="ctl" style={{ width: "auto" }} value={newSession} onChange={(e) => setNewSession(e.target.value)}>
              <option value="">Set a new Summer…</option>
              {unset.map((x) => <option key={x} value={x}>{x}</option>)}
            </select>
            <Btn kind="ghost" size="sm" disabled={!newSession} onClick={() => router.push(`/summer?session=${encodeURIComponent(newSession)}`)}>Open</Btn>
          </>
        ) : null}
      </div>

      {!session ? (
        <Note kind="info" title="No Summer Semester is set">{maySet ? "Choose a session above to set its Summer Semester." : "The Academic Office sets the Summer Semester of a session."}</Note>
      ) : (
        <>
          {period ? (
            <Panel title={`Summer Semester ${session}`} right={<Pil kind={periodWords(period)[1]}>{periodWords(period)[0].toUpperCase()}</Pil>}>
              <PBody>
                <KvGrid pairs={[
                  ["Registration", period.registration_opens ? `${day(period.registration_opens)} – ${day(period.registration_closes)}` : "Not dated"],
                  ["Examinations", period.exams_from ? `${day(period.exams_from)} – ${day(period.exams_to)}` : "Not dated"],
                  ["Results expected", period.results_due ? day(period.results_due) : "—"],
                  ["For", (period.categories ?? []).map(categoryWord).join(", ") + (period.programmes?.length ? ` · ${period.programmes.join(", ")}` : "") + (period.levels?.length ? ` · ${period.levels.join(", ")} Level` : "")],
                ]} />
              </PBody>
            </Panel>
          ) : null}
          {maySet ? <PeriodForm key={`${session}-${period?.set_at ?? "new"}`} session={session} period={period} onDone={() => router.refresh()} /> : null}
          {maySet && period ? <Acts session={session} period={period} onDone={() => router.refresh()} /> : null}
          {maySet && toReview.length ? <ToReview session={session} items={toReview} /> : null}
          {students?.issues?.length ? <Issues issues={students.issues} maySet={maySet} onDone={() => router.refresh()} /> : null}

          {s ? (
            <>
              <Tiles items={[
                ["Eligible", String(s.eligible), null, students?.identifiedAt ? `As identified ${day(students.identifiedAt)}` : "Not yet identified"],
                ["Begun", String(s.commenced), null, `${s.owing} owing · ${s.paid} paid in full`],
                ["Registered", String(s.completed), null, `${s.registeredCourses} course registrations`],
                ["Results", String(s.resultsPublished), null, `${s.resultsPassed} passed · ${s.resultsFailed} failed · ${s.clearedAll} cleared all`],
              ]} />
              <Tiles cls="grid--3" items={[
                ["Programme fees paid", naira(s.programmeFeesPaid), null, "Charged once a student a Summer"],
                ["Course fees paid", naira(s.courseFeesPaid), null, "A fee a course registered"],
                ["Owed, not yet paid", naira(s.feesOutstanding), null, "Selected and unpaid"],
              ]} />
              <Tabs label="What to show" value={view} onChange={setView} items={[
                { id: "students", label: "Students", count: s ? String(students?.rows.length ?? 0) : undefined },
                { id: "courses", label: "Courses", count: String(courses.length) },
                { id: "groups", label: "By unit" },
              ]} />
              {view === "students" ? (
                <Panel title="Students" right={<Btn kind="ghost" size="sm" disabled={!rows.length} onClick={exportRows}>Export CSV</Btn>}>
                  <PBody>
                    <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)" }}>
                      <select aria-label="Which students" className="ctl" style={{ width: "auto" }} value={show} onChange={(e) => setShow(e.target.value as Show)}>
                        <option value="all">Every student</option><option value="eligible">Eligible</option><option value="notstarted">Eligible, not begun</option>
                        <option value="commenced">Begun</option><option value="owing">Owing</option><option value="paid">Paid in full</option>
                      </select>
                      <input aria-label="Search" className="ctl" style={{ maxWidth: "28ch" }} placeholder="Number, name, programme…" value={q} onChange={(e) => setQ(e.target.value)} />
                      <span className="sub2">{rows.length} shown</span>
                    </div>
                  </PBody>
                  <DTable pageSize={50} cols={["Number", "Name", "Programme", "Level|num", "Eligible", "Outstanding|num", "Selected · paid", "Paid|num", "Owed|num", "Payment", "Results"]} rows={rows.map((r) => {
                    const [pw, pt] = paymentStateWords(r.payment_state);
                    return [
                      <span key="n" className="tnum">{r.matric_no ?? "—"}</span>,
                      <Link key="nm" className="lnk" href={`/students/${r.student_id}`}>{r.name}</Link>,
                      <span key="p" className="sub2">{r.programme ?? "—"}</span>,
                      <span key="l" className="tnum">{r.level ?? "—"}</span>,
                      r.eligible ? <Pil key="e" kind="ok">{categoryWord(r.category).toUpperCase()}</Pil> : <span key="e" className="sub2" title={notEligibleWord(r.reason)}>{r.reason ? r.reason.replaceAll("_", " ").toLowerCase() : "—"}</span>,
                      <span key="o" className="tnum">{r.outstanding ?? "—"}</span>,
                      <span key="s" className="tnum">{r.courses_selected} · {r.courses_paid}</span>,
                      <span key="pd" className="tnum">{naira(Number(r.programme_fee_paid ?? 0) + Number(r.course_fees_paid ?? 0))}</span>,
                      <span key="ow" className="tnum">{naira(Number(r.programme_fee_due ?? 0) + Number(r.course_fees_due ?? 0))}</span>,
                      <Pil key="ps" kind={pt}>{pw.toUpperCase()}</Pil>,
                      <span key="r" className="sub2">{r.results_published ? `${r.results_passed} passed · ${r.results_failed} failed` : "—"}</span>,
                    ];
                  })} />
                </Panel>
              ) : view === "courses" ? (
                <Panel title="The Summer's classes" right="Allocate lecturers on Teaching Allocation (semester: Summer)">
                  <DTable pageSize={50} cols={["Course", "Title", "Units|num", "Course's semester", "Department", "Lecturer", "Registered|num", "Failed in the first · second", "Score sheet"]} rows={courses.map((c) => [
                    CLASS_LIST.includes(actingOffice ?? "")
                      ? <Link key="c" className="lnk tnum b700" href={classListHref(c.course_code, session, 3)} title="The students registered in this Summer class">{c.course_code}</Link>
                      : <b key="c" className="tnum">{c.course_code}</b>,
                    <span key="t">{c.title ?? "—"}</span>,
                    <span key="u" className="tnum">{c.units ?? "—"}</span>,
                    <span key="s">{semesterWord(c.course_semester)}</span>,
                    <span key="d" className="sub2">{c.department ?? c.dept_code ?? "—"}</span>,
                    c.lecturer ? <span key="l">{c.lecturer}</span> : <Pil key="l" kind="warn">NOT ALLOCATED</Pil>,
                    <span key="r" className="tnum">{c.registered}</span>,
                    <span key="f" className="tnum">{c.failed_in_first} · {c.failed_in_second}</span>,
                    <span key="sh" className="sub2">{c.sheets ? (c.sheet_stage ?? "made").toLowerCase() : "—"}</span>,
                  ])} />
                </Panel>
              ) : (
                <>
                  {([["Faculty", s.byFaculty], ["Department", s.byDepartment], ["Programme", s.byProgramme], ["Level", s.byLevel]] as [string, Group[]][]).map(([t, g]) => (
                    <Panel key={t} title={`By ${t.toLowerCase()}`} right={String(g.length)}>
                      <DTable cols={[t, "Eligible|num", "Begun|num", "Registered|num", "Course registrations|num"]} rows={g.map((x) => [
                        <span key="n">{x.name}</span>, <span key="e" className="tnum">{x.eligible}</span>, <span key="c" className="tnum">{x.commenced}</span>,
                        <span key="r" className="tnum">{x.registered}</span>, <span key="k" className="tnum">{x.courses}</span>,
                      ])} />
                    </Panel>
                  ))}
                </>
              )}
            </>
          ) : null}
        </>
      )}
    </>
  );
}
