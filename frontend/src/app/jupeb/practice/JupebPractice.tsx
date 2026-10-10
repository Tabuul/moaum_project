"use client";

/**
 * JUPEB practice tests (V347): a test of one subject, its question bank uploaded from Excel or CSV, opened to the students
 * of that subject. V349: a question is also typed one at a time, with formulas ($x^2$, $H_2O$, $\frac{1}{2}mv^2$) drawn as it is
 * typed and an image (a diagram, a graph) attached; a question already answered is never rewritten — editing it makes a new version. Each attempt draws its questions at random from the bank, is timed and marked by the server; the answer
 * key never reaches a student before they submit. Practice is never part of a result.
 *
 * This is the JUPEB module's own engine: the University's CBT engine (V322) is bound to the main register's students and
 * the course offerings, which a JUPEB candidate does not have.
 */
import { useEffect, useState } from "react";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { buildXlsx } from "@/lib/xlsx";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { fileBase64, jcall, readSheet, when } from "@/lib/jupeb";
import { MathText } from "@/components/proto/MathText";
import { plainMath } from "@/lib/mathtext";

interface Test {
  id: string; subject_id: string; code: string; subject: string; title: string; instructions: string | null; duration_minutes: number; questions_per_attempt: number;
  attempts_allowed: number; show_answers: boolean; open: boolean; updated_at: string; questions: number; attempts: number; students: number; average: number | null;
  /** V355: a mock examination — one attempt in its window, results held until released; questions tagged to the syllabus */
  kind?: "PRACTICE" | "MOCK"; opens_at?: string | null; closes_at?: string | null; results_released_at?: string | null; tagged?: number;
}
interface Question {
  id: string; ordinal: number; stem: string; option_a: string; option_b: string; option_c: string | null; option_d: string | null; option_e: string | null; answer: string;
  explanation: string | null; answered: number; right_answers: number; has_image: boolean; course?: string | null; topic?: string | null; topic_label?: string | null;
}
interface QForm { id: string | null; question: string; a: string; b: string; c: string; d: string; e: string; answer: string; explanation: string; image: File | null; course: string; topic: string }
const BLANK_Q: QForm = { id: null, question: "", a: "", b: "", c: "", d: "", e: "", answer: "A", explanation: "", image: null, course: "", topic: "" };
interface Form { id: string | null; subjectId: string; title: string; instructions: string; durationMinutes: string; questionsPerAttempt: string; attemptsAllowed: string; showAnswers: boolean; open: boolean;
  kind: "PRACTICE" | "MOCK"; opensAt: string; closesAt: string }
interface TopicChoice { course: string; course_title: string; semester: number | null; sn: string; topic: string }
/** a local date-time for an input, and back to an instant */
const localInput = (iso: string | null | undefined) => { if (!iso) return ""; const d = new Date(iso); const z = new Date(d.getTime() - d.getTimezoneOffset() * 60000); return z.toISOString().slice(0, 16); };
const instant = (v: string) => (v ? new Date(v).toISOString() : null);

const ALIASES: Record<string, string> = {
  "question": "question", "questions": "question", "stem": "question", "question text": "question",
  "a": "a", "option a": "a", "b": "b", "option b": "b", "c": "c", "option c": "c", "d": "d", "option d": "d", "e": "e", "option e": "e",
  "answer": "answer", "correct answer": "answer", "correct option": "answer", "key": "answer", "explanation": "explanation", "solution": "explanation",
  "course": "course", "course code": "course", "unit": "course", "topic": "topic", "topic no": "topic", "topic s n": "topic", "s n": "topic",
};
const EMPTY: Form = { id: null, subjectId: "", title: "", instructions: "", durationMinutes: "30", questionsPerAttempt: "20", attemptsAllowed: "3", showAnswers: true, open: false,
  kind: "PRACTICE", opensAt: "", closesAt: "" };

export function JupebPractice({ canWrite }: { canWrite: boolean }) {
  const [tests, setTests] = useState<Test[] | null>(null);
  const [subjects, setSubjects] = useState<{ id: string; code: string; title: string }[]>([]);
  const [form, setForm] = useState<Form | null>(null);
  const [open, setOpen] = useState<Test | null>(null);
  const [busy, setBusy] = useState(false);
  const [tick, setTick] = useState(0);
  useEffect(() => {
    let live = true;
    void jcall<{ tests: Test[]; subjects: { id: string; code: string; title: string }[] }>("/api/v1/jupeb/office/practice-tests").then((r) => {
      if (!live) return;
      if (!r.ok) { notifyProblem(r.problem); return; }
      setTests(r.data.tests); setSubjects(r.data.subjects);
      setOpen((o) => (o ? r.data.tests.find((t) => t.id === o.id) ?? null : null));
    });
    return () => { live = false; };
  }, [tick]);
  const reload = () => setTick((t) => t + 1);

  const bodyOf = (f: Form) => ({ subjectId: f.subjectId, title: f.title.trim(), instructions: f.instructions.trim() || null, durationMinutes: Number(f.durationMinutes),
    questionsPerAttempt: Number(f.questionsPerAttempt), attemptsAllowed: f.kind === "MOCK" ? 1 : Number(f.attemptsAllowed), showAnswers: f.showAnswers, open: f.open,
    kind: f.kind, opensAt: f.kind === "MOCK" ? instant(f.opensAt) : null, closesAt: f.kind === "MOCK" ? instant(f.closesAt) : null });
  const formOf = (t: Test, patch: Partial<Form> = {}): Form => ({ id: t.id, subjectId: t.subject_id, title: t.title, instructions: t.instructions ?? "", durationMinutes: String(t.duration_minutes),
    questionsPerAttempt: String(t.questions_per_attempt), attemptsAllowed: String(t.attempts_allowed), showAnswers: t.show_answers, open: t.open,
    kind: t.kind ?? "PRACTICE", opensAt: localInput(t.opens_at), closesAt: localInput(t.closes_at), ...patch });
  async function release(t: Test) {
    if (!window.confirm(`Release the results of "${t.title}" to the students who sat it?`)) return;
    const r = await jcall(`/api/v1/jupeb/office/practice-tests/${t.id}/release`, "POST", {}, `JUPEB mock results released: ${t.title}`);
    if (r.ok) { notify("The results are released."); reload(); } else notifyProblem(r.problem);
  }
  async function save(f: Form) {
    setBusy(true);
    try {
      const r = f.id ? await jcall(`/api/v1/jupeb/office/practice-tests/${f.id}`, "PUT", bodyOf(f)) : await jcall("/api/v1/jupeb/office/practice-tests", "POST", bodyOf(f));
      if (!r.ok) { notifyProblem(r.problem); return false; }
      notify(f.id ? "The test is saved." : "The test is created. Upload its questions, then open it.");
      setForm(null);
      reload();
      return true;
    } finally { setBusy(false); }
  }
  const n = (v: string, lo: number, hi: number) => { const x = Number(v); return Number.isInteger(x) && x >= lo && x <= hi; };
  const formOk = form && form.subjectId && form.title.trim().length >= 3 && n(form.durationMinutes, 5, 240) && n(form.questionsPerAttempt, 1, 200) && n(form.attemptsAllowed, 1, 20)
    && (form.kind !== "MOCK" || (form.opensAt && form.closesAt && form.closesAt > form.opensAt));

  return (
    <>
      <PageHead title="JUPEB practice tests" description="Timed practice, marked at once; the key is shown only after submission. Never part of a result."
        actions={canWrite ? <span className="row"><Btn kind="secondary" disabled={!subjects.length} onClick={() => setForm({ ...EMPTY, kind: "MOCK", attemptsAllowed: "1", showAnswers: false })}>New mock examination</Btn>
          <Btn kind="primary" disabled={!subjects.length} onClick={() => setForm({ ...EMPTY })}>New practice test</Btn></span> : null} />
      <Panel title="Tests">
        <PBody>
          {!tests ? <p className="sub2">Loading…</p> : !tests.length ? <Note kind="info" title="No practice test yet">{canWrite ? "Create a test for a subject, upload its questions, then open it to the students." : "The JUPEB Office has not created any."}</Note> : (
            <DTable pageSize={0} cols={["Subject", "Test", "Bank|num", "Per attempt|num", "Time", "Attempts allowed|num", "Students|num", "Attempts|num", "Average|num", "Status", ""]} rows={tests.map((t) => [
              `${t.code} · ${t.subject}`, <span key="t">{t.title}{t.kind === "MOCK" ? <span className="sub2">{` · mock, ${when(t.opens_at ?? "")} – ${when(t.closes_at ?? "")}`}</span> : null}</span>,
              `${t.questions}${t.tagged ? ` (${t.tagged} by topic)` : ""}`, t.questions_per_attempt, `${t.duration_minutes} min`, t.attempts_allowed, t.students, t.attempts, t.average == null ? "—" : `${Number(t.average)}%`,
              <span key="s" className="row" style={{ gap: 4 }}>{t.open ? <Pil kind="ok">Open</Pil> : <Pil kind="grey">Closed</Pil>}
                {t.kind === "MOCK" ? (t.results_released_at ? <Pil kind="info">Results released</Pil> : <Pil kind="warn">Results held</Pil>) : null}</span>,
              <span key="a" className="row">
                <Btn kind="ghost" onClick={() => setOpen(t)}>Questions</Btn>
                {canWrite ? <Btn kind="ghost" onClick={() => setForm(formOf(t))}>Edit</Btn> : null}
                {canWrite ? <Btn kind={t.open ? "ghost" : "secondary"} disabled={busy} onClick={() => void save(formOf(t, { open: !t.open }))}>{t.open ? "Close" : "Open"}</Btn> : null}
                {canWrite && t.kind === "MOCK" && !t.results_released_at && t.attempts ? <Btn kind="secondary" onClick={() => void release(t)}>Release results</Btn> : null}
              </span>,
            ])} />
          )}
        </PBody>
      </Panel>
      {open ? <QuestionBank test={open} canWrite={canWrite} onChanged={reload} onClose={() => setOpen(null)} /> : null}
      {subjects.length ? <TopicStanding subjects={subjects} /> : null}
      {form ? (
        <Modal title={form.id ? (form.kind === "MOCK" ? "Edit the mock examination" : "Edit the practice test") : form.kind === "MOCK" ? "New mock examination" : "New practice test"} onClose={() => setForm(null)}
          foot={<><Btn kind="ghost" onClick={() => setForm(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || !formOk} onClick={() => void save(form)}>{busy ? "Saving…" : "Save"}</Btn></>}>
          <div className="grid grid--2">
            <Field id="pt-sub" label="Subject" required><select id="pt-sub" className="ctl" value={form.subjectId} onChange={(e) => setForm({ ...form, subjectId: e.target.value })}>
              <option value="">— Choose —</option>{subjects.map((x) => <option key={x.id} value={x.id}>{x.code} — {x.title}</option>)}</select></Field>
            <Field id="pt-title" label="Title" required><input id="pt-title" className="ctl" maxLength={160} value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} /></Field>
            <Field id="pt-dur" label="Time allowed (minutes)" required hint="5 to 240"><input id="pt-dur" className="ctl" type="number" min={5} max={240} value={form.durationMinutes} onChange={(e) => setForm({ ...form, durationMinutes: e.target.value })} /></Field>
            <Field id="pt-q" label="Questions per attempt" required hint="Drawn at random from the bank"><input id="pt-q" className="ctl" type="number" min={1} max={200} value={form.questionsPerAttempt} onChange={(e) => setForm({ ...form, questionsPerAttempt: e.target.value })} /></Field>
            {form.kind === "MOCK" ? <>
              <Field id="pt-from" label="Sat from" required><input id="pt-from" className="ctl" type="datetime-local" value={form.opensAt} onChange={(e) => setForm({ ...form, opensAt: e.target.value })} /></Field>
              <Field id="pt-to" label="Until" required error={form.closesAt && form.opensAt && form.closesAt <= form.opensAt ? "After it opens" : undefined}><input id="pt-to" className="ctl" type="datetime-local" value={form.closesAt} onChange={(e) => setForm({ ...form, closesAt: e.target.value })} /></Field>
            </> : <Field id="pt-att" label="Attempts allowed per student" required hint="1 to 20"><input id="pt-att" className="ctl" type="number" min={1} max={20} value={form.attemptsAllowed} onChange={(e) => setForm({ ...form, attemptsAllowed: e.target.value })} /></Field>}
            <Field id="pt-show" label="After submission"><label className="row" style={{ gap: "var(--s-1)" }}><input id="pt-show" type="checkbox" checked={form.showAnswers} onChange={(e) => setForm({ ...form, showAnswers: e.target.checked })} /> show the answers and explanations</label></Field>
          </div>
          {form.kind === "MOCK" ? <p className="sub2">A mock examination is sat once, within its window; the students see their results only when you release them.</p> : null}
          <Field id="pt-ins" label="Instructions"><textarea id="pt-ins" className="ctl" rows={3} maxLength={2000} value={form.instructions} onChange={(e) => setForm({ ...form, instructions: e.target.value })} /></Field>
          {form.id ? <Field id="pt-open" label="Open to the students"><label className="row" style={{ gap: "var(--s-1)" }}><input id="pt-open" type="checkbox" checked={form.open} onChange={(e) => setForm({ ...form, open: e.target.checked })} /> open (needs questions)</label></Field> : null}
        </Modal>
      ) : null}
    </>
  );
}

/** V355: a subject's practice by syllabus topic across the current session's students, weakest first (mocks included) */
function TopicStanding({ subjects }: { subjects: { id: string; code: string; title: string }[] }) {
  const [subject, setSubject] = useState("");
  const [rows, setRows] = useState<{ topic_id: string; label: string; students: number; answered: number; percentage: number }[] | null>(null);
  useEffect(() => {
    let live = true;
    if (subject) void jcall<NonNullable<typeof rows>>(`/api/v1/jupeb/office/practice-topics?subject=${subject}`).then((r) => { if (!live) return; if (r.ok) setRows(r.data); else notifyProblem(r.problem); });
    return () => { live = false; };
  }, [subject]);
  return (
    <Panel title="Topics, weakest first" right={<select className="ctl" style={{ width: 220 }} aria-label="Subject" value={subject} onChange={(e) => { setRows(null); setSubject(e.target.value); }}>
      <option value="">— Choose a subject —</option>{subjects.map((x) => <option key={x.id} value={x.id}>{`${x.code} — ${x.title}`}</option>)}</select>}>
      <PBody>
        <p className="sub2">Answers by syllabus topic, mocks included. Untagged questions are not counted.</p>
        {!subject ? null : !rows ? <p className="sub2">Loading…</p> : !rows.length ? <p className="sub2">No question tagged to a topic has been answered in this subject yet.</p> : (
          <DTable pageSize={20} cols={["Topic", "Students|num", "Answers|num", "Right|num"]} rows={rows.map((x) => [x.label, x.students, x.answered,
            <Pil key="p" kind={Number(x.percentage) >= 70 ? "ok" : Number(x.percentage) >= 50 ? "info" : "warn"}>{`${Number(x.percentage)}%`}</Pil>])} />
        )}
      </PBody>
    </Panel>
  );
}

function QuestionBank({ test, canWrite, onChanged, onClose }: { test: Test; canWrite: boolean; onChanged: () => void; onClose: () => void }) {
  const [rows, setRows] = useState<Question[] | null>(null);
  const [replace, setReplace] = useState(false);
  const [refused, setRefused] = useState<{ row: number; reason: string }[]>([]);
  const [busy, setBusy] = useState(false);
  const [tick, setTick] = useState(0);
  const [edit, setEdit] = useState<QForm | null>(null);
  const [choices, setChoices] = useState<TopicChoice[]>([]);
  useEffect(() => {
    let live = true;
    void jcall<{ questions: Question[] }>(`/api/v1/jupeb/office/practice-tests/${test.id}`).then((r) => { if (!live) return; if (r.ok) setRows(r.data.questions); else notifyProblem(r.problem); });
    return () => { live = false; };
  }, [test.id, tick]);
  useEffect(() => {
    let live = true;
    void jcall<TopicChoice[]>(`/api/v1/jupeb/office/practice-tests/${test.id}/topics`).then((r) => { if (live && r.ok) setChoices(r.data); });
    return () => { live = false; };
  }, [test.id]);
  const courses = [...new Map(choices.map((c) => [c.course, c])).values()];
  const changed = () => { setTick((t) => t + 1); onChanged(); };
  const base = `/api/v1/jupeb/office/practice-tests/${test.id}/questions`;
  async function upload(file: File | undefined) {
    if (!file) return;
    const list = await readSheet(file, ALIASES);
    if (!list.length) { notifyProblem({ status: 400, title: "No questions found. The file needs a header row with Question, A, B (C, D, E), Answer and Explanation." }); return; }
    if (replace && !window.confirm(`Replace the ${rows?.length ?? 0} questions in the bank with the ${list.length} in ${file.name}? Past attempts keep their questions.`)) return;
    setBusy(true);
    try {
      const r = await jcall<{ added: number; refused: { row: number; reason: string }[]; active: number }>(base, "POST", { rows: list, replace });
      if (!r.ok) { notifyProblem(r.problem); return; }
      setRefused(r.data.refused);
      notify(`${r.data.added} question${r.data.added === 1 ? "" : "s"} added; the bank holds ${r.data.active}.`);
      changed();
    } finally { setBusy(false); }
  }
  async function remove(q: Question) {
    if (!window.confirm(`Remove question ${q.ordinal} from the bank? Past attempts keep it.`)) return;
    const r = await jcall(`${base}/${q.id}/remove`, "POST", {});
    if (r.ok) changed(); else notifyProblem(r.problem);
  }
  /** an image put on a question: PNG or JPEG, at most 1 MB */
  async function putImage(question: string, file: File): Promise<boolean> {
    if (!/^image\/(png|jpeg)$/.test(file.type)) { notifyProblem({ status: 400, title: "A question's image is a PNG or a JPEG." }); return false; }
    if (file.size > 1024 * 1024) { notifyProblem({ status: 400, title: `A question's image is at most 1 MB; this one is ${Math.round(file.size / 1024)} KB.` }); return false; }
    const r = await jcall(`${base}/${question}/image`, "POST", { filename: file.name, contentType: file.type, base64: await fileBase64(file) });
    if (!r.ok) { notifyProblem(r.problem); return false; }
    return true;
  }
  async function image(q: Question, file: File | undefined) {
    if (!file) return;
    setBusy(true);
    try { if (await putImage(q.id, file)) { notify(`Image put on question ${q.ordinal}.`); changed(); } } finally { setBusy(false); }
  }
  async function dropImage(q: Question) {
    if (!window.confirm(`Take the image off question ${q.ordinal}?`)) return;
    const r = await jcall(`${base}/${q.id}/image/remove`, "POST", {});
    if (r.ok) changed(); else notifyProblem(r.problem);
  }
  async function save() {
    if (!edit) return;
    setBusy(true);
    try {
      const row = { question: edit.question, a: edit.a, b: edit.b, c: edit.c, d: edit.d, e: edit.e, answer: edit.answer, explanation: edit.explanation, course: edit.course, topic: edit.course ? edit.topic : "" };
      const r = edit.id ? await jcall<{ id: string; newVersion?: boolean }>(`${base}/${edit.id}`, "PUT", { row }) : await jcall<{ id: string }>(`${base}/add`, "POST", { row });
      if (!r.ok) { notifyProblem(r.problem); return; }
      if (edit.image && !(await putImage(r.data.id, edit.image))) { changed(); return; }
      notify(edit.id ? ("newVersion" in r.data && r.data.newVersion ? "Saved as a new version; the attempts that used the old one keep it." : "The question is corrected.") : "The question is added.");
      setEdit(null);
      changed();
    } finally { setBusy(false); }
  }
  function template() {
    downloadBlob(buildXlsx(["Question", "A", "B", "C", "D", "E", "Answer", "Explanation", "Course", "Topic"], [
      ["The SI unit of force is", "Newton", "Joule", "Watt", "Pascal", "", "A", "F = ma, measured in newtons", "PHY 001", "1"],
      ["The kinetic energy of a body is", "$mv$", "$\\frac{1}{2}mv^2$", "$mgh$", "$\\frac{1}{2}kx^2$", "", "B", "$E_k = \\frac{1}{2}mv^2$", "PHY 001", "2"],
    ], "Questions"), "jupeb-practice-questions-template.xlsx");
  }
  async function exportBank() {
    if (!rows) return;
    downloadBlob(await brandedXlsx(`JUPEB practice questions — ${test.code} ${test.title}`, ["No.", "Question", "A", "B", "C", "D", "E", "Answer", "Explanation", "Image", "Answered", "Right"],
      rows.map((q) => [q.ordinal, plainMath(q.stem), plainMath(q.option_a), plainMath(q.option_b), plainMath(q.option_c), plainMath(q.option_d), plainMath(q.option_e), q.answer,
        plainMath(q.explanation), q.has_image ? "Yes" : "", Number(q.answered), Number(q.right_answers)]),
      { sheetName: "Questions", serial: docSerial("JUPEBPQ"), noSerialColumn: true, meta: [["Confidential", "The answer key: keep it within the JUPEB Office"]] }), `jupeb-practice-${test.code}.xlsx`);
  }
  const options = (q: Question) => ([["A", q.option_a], ["B", q.option_b], ["C", q.option_c], ["D", q.option_d], ["E", q.option_e]] as [string, string | null][]).filter(([, v]) => v);
  const formOf = (q: Question): QForm => ({ id: q.id, question: q.stem, a: q.option_a, b: q.option_b, c: q.option_c ?? "", d: q.option_d ?? "", e: q.option_e ?? "", answer: q.answer,
    explanation: q.explanation ?? "", image: null, course: q.course ?? "", topic: q.topic ?? "" });
  const letters = edit ? (["A", "B", "C", "D", "E"] as const).filter((l) => (edit[l.toLowerCase() as "a"] ?? "").trim()) : [];
  return (
    <Panel title={`${test.code} · ${test.title} — question bank`} right={<span className="row">
      {rows?.length ? <Btn kind="ghost" onClick={() => void exportBank()}>Export (Excel)</Btn> : null}
      <Btn kind="ghost" onClick={onClose}>Close</Btn>
    </span>}>
      <PBody>
        <KvGrid cls="grid--4" pairs={[["Questions in the bank", String(rows?.length ?? "…")], ["Per attempt", String(test.questions_per_attempt)], ["Time", `${test.duration_minutes} min`], ["Last changed", when(test.updated_at)]]} />
        {canWrite ? (
          <div className="row mt-2" style={{ flexWrap: "wrap" }}>
            <Btn kind="primary" disabled={busy} onClick={() => setEdit({ ...BLANK_Q })}>Add a question</Btn>
            <label className="btn btn--secondary btn--sm" style={{ cursor: busy ? "wait" : "pointer" }}>Upload questions (Excel or CSV)
              <input type="file" hidden accept=".xlsx,.csv" disabled={busy} onChange={(e) => { void upload(e.target.files?.[0]); e.target.value = ""; }} /></label>
            <label className="row row--inline row--tight"><input type="checkbox" checked={replace} onChange={(e) => setReplace(e.target.checked)} /> replace the bank (otherwise added to it)</label>
            <Btn kind="ghost" onClick={template}>Template</Btn>
            {busy ? <span className="sub2">Working…</span> : null}
          </div>
        ) : null}
        {canWrite ? <p className="sub2 mt-1">Upload columns Course (such as PHY 001) and Topic (the topic&rsquo;s S/N in the syllabus) tag each question.</p> : null}
        {canWrite ? <p className="sub2 mt-1">Formulas go between dollar signs: <code>$x^2$</code>, <code>$H_2O$</code>, <code>$\frac{"{1}{2}"}mv^2$</code>, <code>$\sqrt{"{b^2-4ac}"}$</code>, <code>$\alpha$</code>, <code>$\to$</code>, <code>$30^\circ$</code>. A diagram is attached to a question as a PNG or JPEG of up to 1 MB.</p> : null}
        {refused.length ? <Note kind="bad" title={`${refused.length} row${refused.length === 1 ? "" : "s"} not added`}>{refused.map((x) => `Row ${x.row}: ${x.reason}`).join(" · ")}</Note> : null}
        {rows && rows.length ? (
          <DTable pageSize={25} cols={["No.|num", "Question", "Options", "Answer|mid", "Answered|num", "Right|num", ...(canWrite ? [""] : [])]}
            texts={rows.map((q) => `${q.stem} ${q.option_a} ${q.option_b} ${q.option_c ?? ""} ${q.option_d ?? ""} ${q.option_e ?? ""}`)}
            rows={rows.map((q) => [q.ordinal,
              <span key="q"><MathText text={q.stem} />{q.has_image ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={`/api/bff${base}/${q.id}/image`} alt={`Diagram of question ${q.ordinal}`} style={{ display: "block", maxWidth: 220, maxHeight: 140, objectFit: "contain", marginTop: 6, border: "1px solid var(--line)", background: "#fff" }} />
              ) : null}{q.explanation ? <div className="sub2 mt-1">Explanation: <MathText text={q.explanation} /></div> : null}</span>,
              <span key="o" className="sub2">{options(q).map(([k, v]) => <span key={k} style={{ display: "block" }}><b>{k}.</b> <MathText text={v} /></span>)}{q.topic_label ? <span style={{ display: "block", marginTop: 4 }}>{`Topic: ${q.topic_label}`}</span> : null}</span>,
              q.answer, Number(q.answered), Number(q.answered) ? `${Number(q.right_answers)} (${Math.round((100 * Number(q.right_answers)) / Number(q.answered))}%)` : "—",
              ...(canWrite ? [<span key="a" className="stack" style={{ gap: 4 }}>
                <Btn kind="ghost" onClick={() => setEdit(formOf(q))}>Edit</Btn>
                <label className="btn btn--ghost btn--sm" style={{ cursor: "pointer" }}>{q.has_image ? "Replace image" : "Add image"}
                  <input type="file" hidden accept="image/png,image/jpeg" onChange={(e) => { void image(q, e.target.files?.[0]); e.target.value = ""; }} /></label>
                {q.has_image ? <Btn kind="ghost" onClick={() => void dropImage(q)}>Remove image</Btn> : null}
                <Btn kind="ghost" onClick={() => void remove(q)}>Remove</Btn>
              </span>] : [])])} />
        ) : rows ? <p className="sub2 mt-2">The bank is empty.</p> : null}
      </PBody>
      {edit ? (
        <Modal wide title={edit.id ? "Edit the question" : "Add a question"} onClose={() => setEdit(null)}
          foot={<><Btn kind="ghost" onClick={() => setEdit(null)}>Cancel</Btn>
            <Btn kind="primary" disabled={busy || !edit.question.trim() || !edit.a.trim() || !edit.b.trim() || !letters.includes(edit.answer as "A")} onClick={() => void save()}>{busy ? "Saving…" : "Save"}</Btn></>}>
          <div className="grid grid--2">
            <div>
              <Field id="pq-q" label="Question" required><textarea id="pq-q" className="ctl" rows={4} maxLength={4000} value={edit.question} onChange={(e) => setEdit({ ...edit, question: e.target.value })} /></Field>
              {(["a", "b", "c", "d", "e"] as const).map((k) => (
                <Field key={k} id={`pq-${k}`} label={`Option ${k.toUpperCase()}`} required={k === "a" || k === "b"}><input id={`pq-${k}`} className="ctl" maxLength={1000} value={edit[k]} onChange={(e) => setEdit({ ...edit, [k]: e.target.value })} /></Field>
              ))}
              <div className="grid grid--2">
                <Field id="pq-ans" label="Answer" required><select id="pq-ans" className="ctl" value={edit.answer} onChange={(e) => setEdit({ ...edit, answer: e.target.value })}>
                  {(["A", "B", "C", "D", "E"] as const).map((l) => <option key={l} value={l} disabled={!letters.includes(l)}>{l}</option>)}</select></Field>
                <Field id="pq-img" label={edit.id ? "Replace the image" : "Image"} hint="PNG or JPEG, up to 1 MB"><input id="pq-img" type="file" accept="image/png,image/jpeg" onChange={(e) => setEdit({ ...edit, image: e.target.files?.[0] ?? null })} /></Field>
              </div>
              <div className="grid grid--2">
                <Field id="pq-course" label="Course" hint="Of the syllabus — so the weakest topics are seen"><select id="pq-course" className="ctl" value={edit.course} onChange={(e) => setEdit({ ...edit, course: e.target.value, topic: "" })}>
                  <option value="">— Not tagged —</option>{courses.map((c) => <option key={c.course} value={c.course}>{`${c.course} ${c.course_title}`}</option>)}</select></Field>
                <Field id="pq-topic" label="Topic"><select id="pq-topic" className="ctl" value={edit.topic} disabled={!edit.course} onChange={(e) => setEdit({ ...edit, topic: e.target.value })}>
                  <option value="">— The course only —</option>{choices.filter((c) => c.course === edit.course).map((c) => <option key={c.sn} value={c.sn}>{`${c.sn}. ${c.topic}`}</option>)}</select></Field>
              </div>
              <Field id="pq-x" label="Explanation" hint="Shown after submission where the test shows answers"><textarea id="pq-x" className="ctl" rows={3} maxLength={4000} value={edit.explanation} onChange={(e) => setEdit({ ...edit, explanation: e.target.value })} /></Field>
            </div>
            <div>
              <div className="eyebrow">As the student sees it</div>
              <div className="card"><div className="card__body">
                <div className="b600"><MathText text={edit.question || "—"} /></div>
                {edit.id && rows?.find((r) => r.id === edit.id)?.has_image && !edit.image ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={`/api/bff${base}/${edit.id}/image`} alt="The question's image" style={{ display: "block", maxWidth: "100%", maxHeight: 200, objectFit: "contain", marginTop: 6, background: "#fff" }} />
                ) : edit.image ? <p className="sub2 mt-1">{`New image: ${edit.image.name}`}</p> : null}
                <div className="stack mt-2" style={{ gap: 6 }}>
                  {letters.map((l) => (
                    <div key={l} style={{ padding: "6px 8px", border: `1px solid ${l === edit.answer ? "var(--green)" : "var(--line)"}`, borderRadius: "var(--r-sm)" }}>
                      <b>{l}.</b> <MathText text={edit[l.toLowerCase() as "a"]} />
                    </div>
                  ))}
                </div>
                {edit.explanation ? <p className="sub2 mt-2">Explanation: <MathText text={edit.explanation} /></p> : null}
              </div></div>
              {edit.id ? <p className="sub2 mt-2">Saving makes a new version; past attempts keep theirs.</p> : null}
            </div>
          </div>
        </Modal>
      ) : null}
    </Panel>
  );
}
