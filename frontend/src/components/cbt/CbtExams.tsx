"use client";
/** The office's CBT examinations (V322): the sitting's figures, every examination of the session with its state and counts, and the
 *  form that creates one over an offering of the office's own courses. A click opens the examination; an open one has its live monitor. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import type { PutmeSession } from "@/lib/cbt";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import type { Problem } from "@/lib/api";
import { COUNTABLE, DETECTOR_WORD, EXAM_TYPE_WORD, EXAM_WORD, PUTME_VERIFY_WORD, RESULTS_WORD, num, whenAt, type CaComponent, type CbtExamList, type CbtOffice, type Detector, type ExamType, type JupebSubject, type PutmeVerify } from "@/lib/cbt";

/** the office's name in a heading: the University's examinations office reads as the University's CBT; V385: the Directorate's as Post-UTME */
export const officeWord = (o: CbtOffice) => (o === "EXAMS" ? "University" : o === "POST_UTME" ? "Post-UTME" : o);
const SUBJECT_REQUIRED = "Choose the subject";

const SEM = (n: number | null | undefined) => (n == null ? "Whole session" : n === 1 ? "First semester" : n === 2 ? "Second semester" : "Third semester");

/** a datetime-local value from an ISO instant, in the browser's zone */
export const localInput = (iso: string | null | undefined) => {
  if (!iso) return "";
  const d = new Date(iso);
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
};
export const isoOf = (local: string) => (local ? new Date(local).toISOString() : null);

export interface ExamForm {
  title: string; instructions: string; durationMinutes: string; selection: "FIXED" | "RANDOM"; totalQuestions: string; randomizeQuestions: boolean; randomizeOptions: boolean;
  passMark: string; attemptLimit: string; securityMode: "STANDARD" | "SECURE"; venue: "REMOTE" | "LAB"; violationLimit: string; violationAction: "WARN" | "SUBMIT" | "TERMINATE";
  secondSession: "CONTINUE" | "DENY" | "MONITOR"; startsAt: string; endsAt: string; partialCredit: boolean;
  /* V364 */
  examType: ExamType; negativeMarks: string; allowBack: boolean; allowReview: boolean; fullscreenRequired: boolean; detectors: Detector[]; countedEvents: string[];
  warnAt: string; finalWarnAt: string; disconnectMinutes: string; proctoring: "NONE" | "CAMERA"; scoreOnSubmit: boolean; sheetComponent: "EXAM" | "CA" | "NONE";
  /** V365: the part of the JUPEB continuous assessment a JUPEB examination counts towards */
  jupebCaComponentId: string;
  /** V385: the second factor at a Post-UTME examination's door */
  putmeVerify: PutmeVerify;
}
export const EMPTY_FORM: ExamForm = {
  title: "", instructions: "", durationMinutes: "60", selection: "FIXED", totalQuestions: "0", randomizeQuestions: true, randomizeOptions: false, passMark: "40", attemptLimit: "1",
  securityMode: "STANDARD", venue: "REMOTE", violationLimit: "2", violationAction: "WARN", secondSession: "CONTINUE", startsAt: "", endsAt: "", partialCredit: false,
  examType: "EXAMINATION", negativeMarks: "0", allowBack: true, allowReview: true, fullscreenRequired: true, detectors: ["TAB", "BLUR", "FULLSCREEN", "COPY", "PASTE", "RIGHT_CLICK", "NETWORK"],
  countedEvents: ["TAB_SWITCH", "WINDOW_BLUR", "FULLSCREEN_EXIT"], warnAt: "", finalWarnAt: "", disconnectMinutes: "", proctoring: "NONE", scoreOnSubmit: false, sheetComponent: "EXAM",
  jupebCaComponentId: "", putmeVerify: "APPLICATION_NO",
};
/** V385: a Post-UTME examination starts from the settings a hall examination of thousands wants: random paper, shuffled options, lab, one screen */
export const PUTME_FORM: ExamForm = { ...EMPTY_FORM, selection: "RANDOM", totalQuestions: "50", randomizeOptions: true, passMark: "0", venue: "LAB", violationLimit: "3", secondSession: "DENY", sheetComponent: "NONE", scoreOnSubmit: false };
export const formBody = (f: ExamForm, office?: CbtOffice) => ({
  title: f.title.trim(), instructions: f.instructions.trim() || null, durationMinutes: Number(f.durationMinutes) || 60, totalQuestions: Number(f.totalQuestions) || 0,
  selection: f.selection, randomizeQuestions: f.randomizeQuestions, randomizeOptions: f.randomizeOptions, passMark: Number(f.passMark) || 0, attemptLimit: Number(f.attemptLimit) || 1,
  securityMode: f.securityMode, venue: f.venue, violationLimit: Number(f.violationLimit) || 0, violationAction: f.violationAction, secondSession: f.secondSession,
  startsAt: isoOf(f.startsAt), endsAt: isoOf(f.endsAt), partialCredit: f.partialCredit,
  settings: {
    examType: f.examType, negativeMarks: Number(f.negativeMarks) || 0, allowBack: f.allowBack, allowReview: f.allowBack && f.allowReview, fullscreenRequired: f.fullscreenRequired,
    detectors: f.detectors, countedEvents: f.countedEvents, warnAt: f.warnAt ? Number(f.warnAt) : null, finalWarnAt: f.finalWarnAt ? Number(f.finalWarnAt) : null,
    disconnectMinutes: f.disconnectMinutes ? Number(f.disconnectMinutes) : null, proctoring: f.proctoring,
    scoreOnSubmit: office === "POST_UTME" ? false : f.scoreOnSubmit, sheetComponent: office === "POST_UTME" ? "NONE" : f.sheetComponent,
    ...(f.jupebCaComponentId ? { jupebCaComponentId: f.jupebCaComponentId } : {}),
    ...(office === "POST_UTME" ? { putmeVerify: f.putmeVerify } : {}),
  },
});

const toggle = <T,>(list: T[], x: T) => (list.includes(x) ? list.filter((y) => y !== x) : [...list, x]);

/** the configuration fields, shared by the create form and the setup tab */
export function ExamFields({ f, set, locked, jupeb, putme }: { f: ExamForm; set: (patch: Partial<ExamForm>) => void; locked?: boolean; jupeb?: { components: CaComponent[] }; putme?: boolean }) {
  const dis = !!locked;
  return (
    <>
      <div className="grid grid--2">
        <Field id="x-title" label="Examination title" required><input id="x-title" className="ctl" value={f.title} onChange={(e) => set({ title: e.target.value })} placeholder="e.g. GST 101 First Semester CBT" /></Field>
        <Field id="x-dur" label="Duration (minutes)" required><input id="x-dur" className="ctl tnum" inputMode="numeric" disabled={dis} value={f.durationMinutes} onChange={(e) => set({ durationMinutes: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
      </div>
      <div className="grid grid--2">
        <Field id="x-start" label="Opens" required hint="Candidates may start from this moment"><input id="x-start" type="datetime-local" className="ctl" value={f.startsAt} onChange={(e) => set({ startsAt: e.target.value })} /></Field>
        <Field id="x-end" label="Closes" required hint="No start after this; an attempt still running ends here"><input id="x-end" type="datetime-local" className="ctl" value={f.endsAt} onChange={(e) => set({ endsAt: e.target.value })} /></Field>
      </div>
      <div className="grid grid--4">
        <Field id="x-sel" label="Question selection"><select id="x-sel" className="ctl" disabled={dis} value={f.selection} onChange={(e) => set({ selection: e.target.value as ExamForm["selection"] })}><option value="FIXED">Fixed paper (the questions chosen)</option><option value="RANDOM">Random: N drawn from the pool</option></select></Field>
        <Field id="x-n" label="Questions drawn" hint={f.selection === "RANDOM" ? "Per candidate, from the pool" : "Set by the paper"}><input id="x-n" className="ctl tnum" inputMode="numeric" disabled={dis || f.selection !== "RANDOM"} value={f.totalQuestions} onChange={(e) => set({ totalQuestions: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
        <Field id="x-pass" label="Pass mark (%)"><input id="x-pass" className="ctl tnum" inputMode="numeric" disabled={dis} value={f.passMark} onChange={(e) => set({ passMark: e.target.value.replace(/[^0-9.]/g, "") })} /></Field>
        <Field id="x-att" label="Attempts allowed"><input id="x-att" className="ctl tnum" inputMode="numeric" disabled={dis} value={f.attemptLimit} onChange={(e) => set({ attemptLimit: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
      </div>
      <div className="grid grid--5">
        <Field id="x-rq" label="Question order"><select id="x-rq" className="ctl" disabled={dis} value={f.randomizeQuestions ? "1" : "0"} onChange={(e) => set({ randomizeQuestions: e.target.value === "1" })}><option value="1">Shuffled per candidate</option><option value="0">As the paper lists them</option></select></Field>
        <Field id="x-pc" label="Multiple-select marking" hint={f.partialCredit ? "Each right option earns a share, each wrong one costs a share, never below zero" : "The marks only for exactly the right options"}><select id="x-pc" className="ctl" disabled={dis} value={f.partialCredit ? "1" : "0"} onChange={(e) => set({ partialCredit: e.target.value === "1" })}><option value="0">All or nothing</option><option value="1">Partial credit</option></select></Field>
        <Field id="x-ro" label="Option order"><select id="x-ro" className="ctl" disabled={dis} value={f.randomizeOptions ? "1" : "0"} onChange={(e) => set({ randomizeOptions: e.target.value === "1" })}><option value="0">As authored</option><option value="1">Shuffled per candidate</option></select></Field>
        <Field id="x-sec" label="Security mode" hint={f.securityMode === "SECURE" ? "Requires the approved secure/kiosk CBT environment" : "Browser monitoring: tabs, focus, fullscreen, network"}><select id="x-sec" className="ctl" disabled={dis} value={f.securityMode} onChange={(e) => set({ securityMode: e.target.value as ExamForm["securityMode"] })}><option value="STANDARD">Standard web CBT</option><option value="SECURE">Secure CBT / kiosk</option></select></Field>
        <Field id="x-venue" label="Venue"><select id="x-venue" className="ctl" disabled={dis} value={f.venue} onChange={(e) => set({ venue: e.target.value as ExamForm["venue"] })}><option value="REMOTE">Remote CBT</option><option value="LAB">CBT laboratory</option></select></Field>
      </div>
      <div className="grid grid--3">
        <Field id="x-vl" label="Violations allowed" hint="Tab switches, focus losses, fullscreen exits, a second sign-in"><input id="x-vl" className="ctl tnum" inputMode="numeric" disabled={dis} value={f.violationLimit} onChange={(e) => set({ violationLimit: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
        <Field id="x-va" label="Over the limit"><select id="x-va" className="ctl" disabled={dis} value={f.violationAction} onChange={(e) => set({ violationAction: e.target.value as ExamForm["violationAction"] })}><option value="WARN">Final warning only; the record stands</option><option value="SUBMIT">Submit the attempt automatically</option><option value="TERMINATE">Terminate the attempt</option></select></Field>
        <Field id="x-ss" label="A second sign-in"><select id="x-ss" className="ctl" disabled={dis} value={f.secondSession} onChange={(e) => set({ secondSession: e.target.value as ExamForm["secondSession"] })}><option value="CONTINUE">Continue the attempt there; the first screen is replaced</option><option value="DENY">Refuse the second screen</option><option value="MONITOR">Allow both screens; record it</option></select></Field>
      </div>
      <div className="grid grid--4">
        <Field id="x-type" label="Kind of examination"><select id="x-type" className="ctl" disabled={dis} value={f.examType} onChange={(e) => set({ examType: e.target.value as ExamType })}>{(Object.keys(EXAM_TYPE_WORD) as ExamType[]).map((k) => <option key={k} value={k}>{EXAM_TYPE_WORD[k]}</option>)}</select></Field>
        <Field id="x-neg" label="Negative marking" hint="Marks deducted for each wrong answer; 0 = none. Never below nought overall"><input id="x-neg" className="ctl tnum" inputMode="decimal" disabled={dis} value={f.negativeMarks} onChange={(e) => set({ negativeMarks: e.target.value.replace(/[^0-9.]/g, "") })} /></Field>
        <Field id="x-back" label="Navigation"><select id="x-back" className="ctl" disabled={dis} value={f.allowBack ? "1" : "0"} onChange={(e) => set({ allowBack: e.target.value === "1", allowReview: e.target.value === "1" && f.allowReview })}><option value="1">Back and forward</option><option value="0">Forward only</option></select></Field>
        <Field id="x-rev" label="Mark for review" hint={f.allowBack ? "Candidates may flag questions to revisit" : "Not on a forward-only paper"}><select id="x-rev" className="ctl" disabled={dis || !f.allowBack} value={f.allowBack && f.allowReview ? "1" : "0"} onChange={(e) => set({ allowReview: e.target.value === "1" })}><option value="1">Allowed</option><option value="0">Not allowed</option></select></Field>
      </div>
      <div className="grid grid--4">
        <Field id="x-fs" label="Fullscreen"><select id="x-fs" className="ctl" disabled={dis} value={f.fullscreenRequired ? "1" : "0"} onChange={(e) => set({ fullscreenRequired: e.target.value === "1" })}><option value="1">Required</option><option value="0">Not required</option></select></Field>
        <Field id="x-warn" label="First warning at" hint="Violations before the first warning; blank = 1"><input id="x-warn" className="ctl tnum" inputMode="numeric" disabled={dis} value={f.warnAt} onChange={(e) => set({ warnAt: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
        <Field id="x-fwarn" label="Final warning at" hint="Blank = at the number allowed"><input id="x-fwarn" className="ctl tnum" inputMode="numeric" disabled={dis} value={f.finalWarnAt} onChange={(e) => set({ finalWarnAt: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
        <Field id="x-disc" label="Out of contact" hint="Minutes without contact before the attempt is submitted with what was saved; blank = wait to the end of time"><input id="x-disc" className="ctl tnum" inputMode="numeric" disabled={dis} value={f.disconnectMinutes} onChange={(e) => set({ disconnectMinutes: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
      </div>
      <Field id="x-det" label="What the examination screen watches" hint="Reported to the office as evidence; a browser cannot stop a switch to another app or device">
        <div className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>{(Object.keys(DETECTOR_WORD) as Detector[]).map((d) => <label key={d} className="row row--inline row--tight" style={{ marginRight: 12 }}><input type="checkbox" disabled={dis} checked={f.detectors.includes(d)} onChange={() => set({ detectors: toggle(f.detectors, d) })} /> {DETECTOR_WORD[d]}</label>)}</div>
      </Field>
      <Field id="x-cnt" label="Counted as violations" hint="The rest are recorded without counting towards the thresholds">
        <div className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>{COUNTABLE.filter(([k]) => f.proctoring === "CAMERA" || !["FACE_NOT_DETECTED", "MULTIPLE_FACES", "FACE_OUT_OF_FRAME", "PROLONGED_LOOK_AWAY", "CAMERA_STOPPED"].includes(k)).map(([k, w]) => <label key={k} className="row row--inline row--tight" style={{ marginRight: 12 }}><input type="checkbox" disabled={dis} checked={f.countedEvents.includes(k)} onChange={() => set({ countedEvents: toggle(f.countedEvents, k) })} /> {w}</label>)}</div>
      </Field>
      <div className="grid grid--3">
        <Field id="x-proc" label="Camera proctoring" hint={f.proctoring === "CAMERA" ? "By the candidate's consent; face signals only, no video kept, no microphone" : "No camera"}><select id="x-proc" className="ctl" disabled={dis} value={f.proctoring} onChange={(e) => set({ proctoring: e.target.value as ExamForm["proctoring"] })}><option value="NONE">None</option><option value="CAMERA">Camera, by consent</option></select></Field>
        {putme ? (
          <Field id="x-sos" label="The candidate's score" hint="Never shown on submission; the Academic Office releases Post-UTME scores and the result-checking page shows them"><input id="x-sos" className="ctl" disabled value="Released by the Academic Office" readOnly /></Field>
        ) : (
          <Field id="x-sos" label="The candidate's score" hint="By default the result is seen only once published"><select id="x-sos" className="ctl" disabled={dis} value={f.scoreOnSubmit ? "1" : "0"} onChange={(e) => set({ scoreOnSubmit: e.target.value === "1" })}><option value="0">Once the results are published</option><option value="1">On submission</option></select></Field>
        )}
        {putme ? (
          <Field id="x-verify" label="Verification at the door" hint="Beside the JAMB registration number, which alone never opens the examination">
            <select id="x-verify" className="ctl" disabled={dis} value={f.putmeVerify} onChange={(e) => set({ putmeVerify: e.target.value as PutmeVerify })}>
              {(Object.keys(PUTME_VERIFY_WORD) as PutmeVerify[]).map((k) => <option key={k} value={k}>{PUTME_VERIFY_WORD[k]}</option>)}
            </select>
          </Field>
        ) : jupeb ? (
          <Field id="x-sheet" label="Into the JUPEB continuous assessment" hint="The Board examines JUPEB; a CBT result counts only towards the assessment part the office set">
            <select id="x-sheet" className="ctl" disabled={dis} value={f.sheetComponent === "CA" ? f.jupebCaComponentId || "CA" : "NONE"}
              onChange={(e) => set(e.target.value === "NONE" ? { sheetComponent: "NONE", jupebCaComponentId: "" } : { sheetComponent: "CA", jupebCaComponentId: e.target.value === "CA" ? "" : e.target.value })}>
              <option value="NONE">Not at all (practice, a mock)</option>
              {jupeb.components.map((c) => <option key={c.id} value={c.id}>{c.title} (out of {Number(c.max_score)})</option>)}
            </select>
          </Field>
        ) : (
          <Field id="x-sheet" label="On the score sheet"><select id="x-sheet" className="ctl" disabled={dis} value={f.sheetComponent} onChange={(e) => set({ sheetComponent: e.target.value as ExamForm["sheetComponent"] })}><option value="EXAM">As the examination</option><option value="CA">As continuous assessment</option><option value="NONE">Not at all (a quiz or mock)</option></select></Field>
        )}
      </div>
      {jupeb && !jupeb.components.length ? <div className="sub2">No JUPEB continuous-assessment part is set for this session yet.</div> : null}
      <Field id="x-instr" label="Instructions to candidates" hint="Shown before the start, under the University's standard instructions"><textarea id="x-instr" className="ctl" rows={3} value={f.instructions} onChange={(e) => set({ instructions: e.target.value })} /></Field>
    </>
  );
}

export function CbtExams({ data, base, office, canManage }: { data: CbtExamList; base: string; office: CbtOffice; canManage: boolean }) {
  const word = officeWord(office);
  const go = useQueryNav();
  const router = useRouter();
  const [creating, setCreating] = useState(false);
  const [offering, setOffering] = useState("");
  const [f, setF] = useState<ExamForm>(EMPTY_FORM);
  const [busy, setBusy] = useState(false);
  const jupeb = office === "JUPEB";
  /* V385: a Post-UTME examination is made for an admission session, on the Directorate's bank for it */
  const putme = office === "POST_UTME";
  const putmeSessions = data.putmeSessions ?? [];
  const [putmeSession, setPutmeSession] = useState(data.session);
  const [subjectId, setSubjectId] = useState("");
  const [semester, setSemester] = useState("1");
  const subjects: JupebSubject[] = data.subjects ?? [];
  const cbtSubjects = subjects.filter((x) => x.cbt_enabled);
  const rows = data.rows;
  const open = rows.filter((r) => r.live_state === "OPEN").length;
  const upcoming = rows.filter((r) => r.live_state === "UPCOMING" || r.live_state === "SCHEDULED").length;
  const completed = rows.filter((r) => r.live_state === "COMPLETED").length;
  const writing = rows.reduce((n, r) => n + Number(r.writing), 0);
  const q = (patch: Record<string, string>) => {
    const p = new URLSearchParams();
    const session = patch.session ?? data.session;
    const semester = "semester" in patch ? patch.semester : data.semester == null ? "" : String(data.semester);
    if (session) p.set("session", session);
    if (semester) p.set("semester", semester);
    if ((patch.archived ?? (data.archived ? "true" : "")) === "true") p.set("archived", "true");
    return `${base}/cbt?${p.toString()}`;
  };

  async function create() {
    setBusy(true);
    try {
      const target = putme ? { session: putmeSession } : jupeb ? { jupebSubjectId: subjectId, session: data.session, semester: Number(semester) } : { offeringId: offering };
      const r = await fetch("/api/bff/api/v1/cbt/exams", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Create the CBT examination ${f.title}`) }, body: JSON.stringify({ office, ...target, ...formBody(f, office) }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      notify(`${j.reference} created as a draft`);
      router.push(`${base}/cbt/${j.id}`);
    } finally { setBusy(false); }
  }

  async function setSubject(x: JupebSubject, on: boolean) {
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/cbt/catalogue/jupeb/${x.id}`, { method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${on ? "Allow" : "Withdraw"} CBT for the JUPEB subject ${x.code}`) }, body: JSON.stringify({ enabled: on }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      notify(`${x.title} ${on ? "may now be examined by CBT" : "is no longer examined by CBT"}`);
      router.refresh();
    } finally { setBusy(false); }
  }

  return (
    <>
      <PageHead title={`${word} CBT examinations`} description={`${office === "EXAMS" ? "CBT-enabled courses within your scope" : putme ? "The Directorate of ICT's examinations of the session's Post-UTME applicants" : `The ${office} office`} · ${data.session}${data.archived ? " · archived examinations" : ""}`}
        actions={<span className="row row--inline row--tight">
          {/* V375: every sitting's report, filed or due, in one place */}
          <LinkBtn kind="secondary" size="sm" href={`/cbt/reports?office=${office}&session=${encodeURIComponent(data.session)}`}>Sitting reports</LinkBtn>
          <label htmlFor="cx-session" className="sub2">Session</label>
          <select id="cx-session" className="ctl" value={data.session} onChange={(e) => go(q({ session: e.target.value }))}>{data.sessions.map((x) => <option key={x.name} value={x.name}>{x.name}</option>)}</select>
          <label htmlFor="cx-sem" className="sub2">Semester</label>
          <select id="cx-sem" className="ctl" value={data.semester == null ? "" : String(data.semester)} onChange={(e) => go(q({ semester: e.target.value }))}><option value="">Whole session</option><option value="1">First</option><option value="2">Second</option><option value="3">Third</option></select>
          <Btn kind="ghost" onClick={() => go(q({ archived: data.archived ? "" : "true" }))}>{data.archived ? "Current examinations" : "Archived"}</Btn>
          {canManage ? <Btn kind="primary" onClick={() => { setF(putme ? PUTME_FORM : { ...EMPTY_FORM, sheetComponent: jupeb ? "NONE" : "EXAM" }); setOffering(data.offerings[0]?.id ?? ""); setSubjectId(cbtSubjects[0]?.id ?? ""); setPutmeSession(data.session); setCreating(true); }}>Create examination</Btn> : null}
        </span>} />
      <Tiles items={[
        ["EXAMINATIONS", num(rows.length), null, `${data.session} · ${SEM(data.semester).toLowerCase()}`],
        ["OPEN NOW", num(open), open ? "var(--green-ink)" : null, `${num(writing)} candidate${writing === 1 ? "" : "s"} writing`],
        ["UPCOMING", num(upcoming), null, "Scheduled or published, not yet open"],
        ["COMPLETED", num(completed), null, `${num(rows.filter((r) => r.results_state === "PUBLISHED").length)} with results published`],
      ]} />
      <Panel title={`${word} examinations · ${data.session}`} right={<span className="sub2">{rows.length} examination{rows.length === 1 ? "" : "s"}</span>}>
        {rows.length ? (
          <DTable pageSize={25} cols={["Reference", "Examination", "Course", "Window", "State|mid", "Candidates|num", "Started|num", "Writing|num", "Scored|num", "Results|mid", "|num"]} rows={rows.map((r) => [
            <span key="r" className="tnum">{r.reference}</span>,
            <span key="t"><b>{r.title}</b><div className="sub2">{r.duration_minutes} min · {r.selection === "RANDOM" ? `${r.total_questions} of ${r.pool_size} drawn` : `${r.pool_size} questions`} · {r.security_mode === "SECURE" ? "secure/kiosk" : "standard web"} · {r.venue === "LAB" ? "CBT lab" : "remote"}</div></span>,
            <span key="c"><b className="tnum">{r.course_code}</b><div className="sub2">{r.course_title}</div></span>,
            <span key="w" className="sub2 tnum">{r.starts_at ? `${whenAt(r.starts_at)} → ${whenAt(r.ends_at)}` : "Not yet dated"}</span>,
            <Pil key="s" kind={(EXAM_WORD[r.live_state] ?? ["", "grey"])[1]}>{(EXAM_WORD[r.live_state] ?? [r.live_state])[0]}</Pil>,
            <span key="n" className="tnum">{num(r.candidates)}</span>, <span key="st" className="tnum">{num(r.started)}</span>,
            <span key="wr" className={`tnum${Number(r.writing) ? " b600" : ""}`}>{num(r.writing)}</span>, <span key="sc" className="tnum">{num(r.scored)}</span>,
            <Pil key="rs" kind={(RESULTS_WORD[r.results_state] ?? ["", "grey"])[1]}>{(RESULTS_WORD[r.results_state] ?? [r.results_state])[0]}</Pil>,
            <span key="a" className="row row--inline row--tight">{r.live_state === "OPEN" ? <LinkBtn kind="go" size="sm" href={`${base}/cbt/${r.id}/monitor`}>Monitor</LinkBtn> : null}<LinkBtn kind="primary" size="sm" href={`${base}/cbt/${r.id}`}>Open</LinkBtn></span>,
          ])} texts={rows.map((r) => `${r.reference} ${r.title} ${r.course_code} ${r.live_state}`)} />
        ) : <PBody><div className="sub2">No examination for {data.session}{data.semester ? ` ${SEM(data.semester).toLowerCase()}` : ""} yet.{canManage ? " Create one over an offering of the office's courses." : ""}</div></PBody>}
      </Panel>
      {jupeb ? (
        <Panel title="JUPEB subjects examined by CBT" right={<span className="sub2">{cbtSubjects.length} of {subjects.length} allowed</span>}>
          {subjects.length ? (
            <DTable pageSize={25} cols={["Subject", "Registered|num", "Questions|num", "CBT|mid", "|num"]} rows={subjects.map((x) => [
              <span key="s"><b className="tnum">{x.code}</b><div className="sub2">{x.title}</div></span>,
              <span key="r" className="tnum">{num(x.registered)}</span>, <span key="q" className="tnum">{num(x.questions)}</span>,
              x.cbt_enabled ? <Pil key="c" kind="ok">CBT</Pil> : <Pil key="c" kind="grey">Not CBT</Pil>,
              canManage ? (x.cbt_enabled ? <Btn key="a" kind="ghost" size="sm" disabled={busy} onClick={() => void setSubject(x, false)}>Withdraw</Btn> : <Btn key="a" kind="primary" size="sm" disabled={busy} onClick={() => void setSubject(x, true)}>Allow CBT</Btn>) : <span key="a" />,
            ])} texts={subjects.map((x) => `${x.code} ${x.title}`)} />
          ) : <PBody><div className="sub2">No active JUPEB subject.</div></PBody>}
        </Panel>
      ) : null}
      {putme ? (
        <Panel title="Admission sessions" right={<span className="sub2">{putmeSessions.length} with applicants, questions or applications open</span>}>
          {putmeSessions.length ? (
            <DTable pageSize={10} cols={["Session", "Applicants|num", "Screened programmes|num", "Questions|num", "CBT door|mid", "Result checking|mid"]} rows={putmeSessions.map((x) => [
              <span key="s"><b className="tnum">{x.name}</b><div className="sub2">{x.state}</div></span>,
              <span key="a" className="tnum">{num(x.applicants)}</span>,
              <span key="p" className={`tnum${Number(x.screened_programmes) ? "" : " b600"}`}>{num(x.screened_programmes)}</span>,
              <span key="q" className="tnum">{num(x.questions)}</span>,
              <Pil key="w" kind={x.cbt_window === "OPEN" ? "ok" : "grey"}>{x.cbt_window}</Pil>,
              <Pil key="r" kind={x.results_window === "OPEN" ? "ok" : "grey"}>{x.results_window}</Pil>,
            ])} texts={putmeSessions.map((x) => x.name)} />
          ) : <PBody><div className="sub2">No admission session with Post-UTME applicants yet.</div></PBody>}
          <PBody><div className="sub2">The paper is drawn from the session&rsquo;s Post-UTME question bank. A session&rsquo;s examination is published only once the admission settings name the programmes screened by examination; candidates sit it only while the Post-UTME CBT door (Application Registration Control) is open.</div></PBody>
        </Panel>
      ) : null}
      {!jupeb && !putme && !data.offerings.length ? <Note kind="info" title={office === "EXAMS" ? `No CBT course of yours is offered in ${data.session}` : `No ${office} course is offered in ${data.session}`}>{office === "EXAMS" ? "An examination is created over an offering of a course the University allows to be examined by CBT (CBT courses), within your department or faculty." : `An examination is created over an offering; offer the course for the session on ${office} Courses first.`}</Note> : null}

      {creating ? (
        <Modal title="Create a CBT examination" sub={`${word} · ${data.session}`} wide onClose={() => setCreating(false)}
          foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setCreating(false)}>Cancel</Btn><Btn kind="primary" disabled={busy || (putme ? !putmeSession : jupeb ? !subjectId : !offering) || !f.title.trim()} onClick={() => void create()}>{busy ? "Creating…" : "Create as draft"}</Btn></span>}>
          {putme ? (
            <Field id="x-psession" label="Admission session" required hint="The session's submitted Post-UTME applicants are the candidates; the paper is drawn from the session's Post-UTME bank">
              <select id="x-psession" className="ctl" value={putmeSession} onChange={(e) => setPutmeSession(e.target.value)}>
                {(putmeSessions.length ? putmeSessions : [{ name: data.session, applicants: 0, questions: 0 } as PutmeSession]).map((x) => <option key={x.name} value={x.name}>{x.name} · {num(x.applicants)} applicant{Number(x.applicants) === 1 ? "" : "s"} · {num(x.questions)} active question{Number(x.questions) === 1 ? "" : "s"}</option>)}
              </select>
            </Field>
          ) : jupeb ? (
            <div className="grid grid--2">
              <Field id="x-subject" label="Subject" required hint={cbtSubjects.length ? "A subject the JUPEB Office has allowed CBT; the paper is drawn from its own bank" : "Allow a subject CBT first, in the panel below"}>
                <select id="x-subject" className="ctl" value={subjectId} onChange={(e) => setSubjectId(e.target.value)}>
                  {!cbtSubjects.length ? <option value="">{SUBJECT_REQUIRED}</option> : null}
                  {cbtSubjects.map((x) => <option key={x.id} value={x.id}>{x.code} — {x.title} · {x.questions} active question{x.questions === 1 ? "" : "s"}</option>)}
                </select>
              </Field>
              <Field id="x-jsem" label="Semester"><select id="x-jsem" className="ctl" value={semester} onChange={(e) => setSemester(e.target.value)}><option value="1">First semester</option><option value="2">Second semester</option></select></Field>
            </div>
          ) : (
          <Field id="x-off" label="Course offering" required hint="A CBT course of the office offered this session; the paper is drawn from that course's question bank">
            <select id="x-off" className="ctl" value={offering} onChange={(e) => setOffering(e.target.value)}>
              {data.offerings.map((o) => <option key={o.id} value={o.id}>{o.course_code} — {o.title} · semester {o.semester} · {o.questions} active question{o.questions === 1 ? "" : "s"}</option>)}
            </select>
          </Field>
          )}
          <ExamFields f={f} set={(p) => setF({ ...f, ...p })} jupeb={jupeb ? { components: [] } : undefined} putme={putme} />
          <div className="sub2 mt-2">Created as a draft. Only {putme ? "the session's applicants who submitted with the screening fee confirmed, of a programme screened by examination, not disqualified and not yet scored" : jupeb ? "JUPEB students registered for the subject whose share of the semester’s school fee is paid" : `students registered on the offering whose ${office === "EXAMS" ? "school fees are cleared for examinations" : "GST fee is paid (where the Bursar’s rule requires it)"}`} can sit it.</div>
        </Modal>
      ) : null}
    </>
  );
}
