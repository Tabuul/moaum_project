"use client";

/**
 * JUPEB practice tests (V347): a test of one subject, its question bank uploaded from Excel or CSV, opened to the students
 * of that subject. Each attempt draws its questions at random from the bank, is timed and marked by the server; the answer
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
import { jcall, readSheet, when } from "@/lib/jupeb";

interface Test {
  id: string; subject_id: string; code: string; subject: string; title: string; instructions: string | null; duration_minutes: number; questions_per_attempt: number;
  attempts_allowed: number; show_answers: boolean; open: boolean; updated_at: string; questions: number; attempts: number; students: number; average: number | null;
}
interface Question { id: string; ordinal: number; stem: string; option_a: string; option_b: string; option_c: string | null; option_d: string | null; option_e: string | null; answer: string; explanation: string | null; answered: number; right_answers: number }
interface Form { id: string | null; subjectId: string; title: string; instructions: string; durationMinutes: string; questionsPerAttempt: string; attemptsAllowed: string; showAnswers: boolean; open: boolean }

const ALIASES: Record<string, string> = {
  "question": "question", "questions": "question", "stem": "question", "question text": "question",
  "a": "a", "option a": "a", "b": "b", "option b": "b", "c": "c", "option c": "c", "d": "d", "option d": "d", "e": "e", "option e": "e",
  "answer": "answer", "correct answer": "answer", "correct option": "answer", "key": "answer", "explanation": "explanation", "solution": "explanation",
};
const EMPTY: Form = { id: null, subjectId: "", title: "", instructions: "", durationMinutes: "30", questionsPerAttempt: "20", attemptsAllowed: "3", showAnswers: true, open: false };

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
    questionsPerAttempt: Number(f.questionsPerAttempt), attemptsAllowed: Number(f.attemptsAllowed), showAnswers: f.showAnswers, open: f.open });
  const formOf = (t: Test, patch: Partial<Form> = {}): Form => ({ id: t.id, subjectId: t.subject_id, title: t.title, instructions: t.instructions ?? "", durationMinutes: String(t.duration_minutes),
    questionsPerAttempt: String(t.questions_per_attempt), attemptsAllowed: String(t.attempts_allowed), showAnswers: t.show_answers, open: t.open, ...patch });
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
  const formOk = form && form.subjectId && form.title.trim().length >= 3 && n(form.durationMinutes, 5, 240) && n(form.questionsPerAttempt, 1, 200) && n(form.attemptsAllowed, 1, 20);

  return (
    <>
      <PageHead title="JUPEB practice tests" description="Timed practice in each subject, marked at once. Questions are drawn at random from the test's bank; the answer key reaches a student only after they submit. Never part of a result."
        actions={canWrite ? <Btn kind="primary" disabled={!subjects.length} onClick={() => setForm({ ...EMPTY })}>New practice test</Btn> : null} />
      <Panel title="Tests">
        <PBody>
          {!tests ? <p className="sub2">Loading…</p> : !tests.length ? <Note kind="info" title="No practice test yet">{canWrite ? "Create a test for a subject, upload its questions, then open it to the students." : "The JUPEB Office has not created any."}</Note> : (
            <DTable pageSize={0} cols={["Subject", "Test", "Bank|num", "Per attempt|num", "Time", "Attempts allowed|num", "Students|num", "Attempts|num", "Average|num", "Status", ""]} rows={tests.map((t) => [
              `${t.code} · ${t.subject}`, t.title, t.questions, t.questions_per_attempt, `${t.duration_minutes} min`, t.attempts_allowed, t.students, t.attempts, t.average == null ? "—" : `${Number(t.average)}%`,
              t.open ? <Pil key="s" kind="ok">Open</Pil> : <Pil key="s" kind="grey">Closed</Pil>,
              <span key="a" className="row">
                <Btn kind="ghost" onClick={() => setOpen(t)}>Questions</Btn>
                {canWrite ? <Btn kind="ghost" onClick={() => setForm(formOf(t))}>Edit</Btn> : null}
                {canWrite ? <Btn kind={t.open ? "ghost" : "secondary"} disabled={busy} onClick={() => void save(formOf(t, { open: !t.open }))}>{t.open ? "Close" : "Open"}</Btn> : null}
              </span>,
            ])} />
          )}
        </PBody>
      </Panel>
      {open ? <QuestionBank test={open} canWrite={canWrite} onChanged={reload} onClose={() => setOpen(null)} /> : null}
      {form ? (
        <Modal title={form.id ? "Edit the practice test" : "New practice test"} onClose={() => setForm(null)}
          foot={<><Btn kind="ghost" onClick={() => setForm(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || !formOk} onClick={() => void save(form)}>{busy ? "Saving…" : "Save"}</Btn></>}>
          <div className="grid grid--2">
            <Field id="pt-sub" label="Subject" required><select id="pt-sub" className="ctl" value={form.subjectId} onChange={(e) => setForm({ ...form, subjectId: e.target.value })}>
              <option value="">— Choose —</option>{subjects.map((x) => <option key={x.id} value={x.id}>{x.code} — {x.title}</option>)}</select></Field>
            <Field id="pt-title" label="Title" required><input id="pt-title" className="ctl" maxLength={160} value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} /></Field>
            <Field id="pt-dur" label="Time allowed (minutes)" required hint="5 to 240"><input id="pt-dur" className="ctl" type="number" min={5} max={240} value={form.durationMinutes} onChange={(e) => setForm({ ...form, durationMinutes: e.target.value })} /></Field>
            <Field id="pt-q" label="Questions per attempt" required hint="Drawn at random from the bank"><input id="pt-q" className="ctl" type="number" min={1} max={200} value={form.questionsPerAttempt} onChange={(e) => setForm({ ...form, questionsPerAttempt: e.target.value })} /></Field>
            <Field id="pt-att" label="Attempts allowed per student" required hint="1 to 20"><input id="pt-att" className="ctl" type="number" min={1} max={20} value={form.attemptsAllowed} onChange={(e) => setForm({ ...form, attemptsAllowed: e.target.value })} /></Field>
            <Field id="pt-show" label="After submission"><label className="row" style={{ gap: "var(--s-1)" }}><input id="pt-show" type="checkbox" checked={form.showAnswers} onChange={(e) => setForm({ ...form, showAnswers: e.target.checked })} /> show the answers and explanations</label></Field>
          </div>
          <Field id="pt-ins" label="Instructions"><textarea id="pt-ins" className="ctl" rows={3} maxLength={2000} value={form.instructions} onChange={(e) => setForm({ ...form, instructions: e.target.value })} /></Field>
          {form.id ? <Field id="pt-open" label="Open to the students"><label className="row" style={{ gap: "var(--s-1)" }}><input id="pt-open" type="checkbox" checked={form.open} onChange={(e) => setForm({ ...form, open: e.target.checked })} /> open (needs questions)</label></Field> : null}
        </Modal>
      ) : null}
    </>
  );
}

function QuestionBank({ test, canWrite, onChanged, onClose }: { test: Test; canWrite: boolean; onChanged: () => void; onClose: () => void }) {
  const [rows, setRows] = useState<Question[] | null>(null);
  const [replace, setReplace] = useState(false);
  const [refused, setRefused] = useState<{ row: number; reason: string }[]>([]);
  const [busy, setBusy] = useState(false);
  const [tick, setTick] = useState(0);
  useEffect(() => {
    let live = true;
    void jcall<{ questions: Question[] }>(`/api/v1/jupeb/office/practice-tests/${test.id}`).then((r) => { if (!live) return; if (r.ok) setRows(r.data.questions); else notifyProblem(r.problem); });
    return () => { live = false; };
  }, [test.id, tick]);
  const changed = () => { setTick((t) => t + 1); onChanged(); };
  async function upload(file: File | undefined) {
    if (!file) return;
    const list = await readSheet(file, ALIASES);
    if (!list.length) { notifyProblem({ status: 400, title: "No questions found. The file needs a header row with Question, A, B (C, D, E), Answer and Explanation." }); return; }
    if (replace && !window.confirm(`Replace the ${rows?.length ?? 0} questions in the bank with the ${list.length} in ${file.name}? Past attempts keep their questions.`)) return;
    setBusy(true);
    try {
      const r = await jcall<{ added: number; refused: { row: number; reason: string }[]; active: number }>(`/api/v1/jupeb/office/practice-tests/${test.id}/questions`, "POST", { rows: list, replace });
      if (!r.ok) { notifyProblem(r.problem); return; }
      setRefused(r.data.refused);
      notify(`${r.data.added} question${r.data.added === 1 ? "" : "s"} added; the bank holds ${r.data.active}.`);
      changed();
    } finally { setBusy(false); }
  }
  async function remove(q: Question) {
    if (!window.confirm(`Remove question ${q.ordinal} from the bank? Past attempts keep it.`)) return;
    const r = await jcall(`/api/v1/jupeb/office/practice-tests/${test.id}/questions/${q.id}/remove`, "POST", {});
    if (r.ok) changed(); else notifyProblem(r.problem);
  }
  function template() {
    downloadBlob(buildXlsx(["Question", "A", "B", "C", "D", "E", "Answer", "Explanation"], [["The SI unit of force is", "Newton", "Joule", "Watt", "Pascal", "", "A", "F = ma, measured in newtons"]], "Questions"),
      "jupeb-practice-questions-template.xlsx");
  }
  async function exportBank() {
    if (!rows) return;
    downloadBlob(await brandedXlsx(`JUPEB practice questions — ${test.code} ${test.title}`, ["No.", "Question", "A", "B", "C", "D", "E", "Answer", "Explanation", "Answered", "Right"],
      rows.map((q) => [q.ordinal, q.stem, q.option_a, q.option_b, q.option_c, q.option_d, q.option_e, q.answer, q.explanation, Number(q.answered), Number(q.right_answers)]),
      { sheetName: "Questions", serial: docSerial("JUPEBPQ"), noSerialColumn: true, meta: [["Confidential", "The answer key: keep it within the JUPEB Office"]] }), `jupeb-practice-${test.code}.xlsx`);
  }
  return (
    <Panel title={`${test.code} · ${test.title} — question bank`} right={<span className="row">
      {rows?.length ? <Btn kind="ghost" onClick={() => void exportBank()}>Export (Excel)</Btn> : null}
      <Btn kind="ghost" onClick={onClose}>Close</Btn>
    </span>}>
      <PBody>
        <KvGrid cls="grid--4" pairs={[["Questions in the bank", String(rows?.length ?? "…")], ["Per attempt", String(test.questions_per_attempt)], ["Time", `${test.duration_minutes} min`], ["Last changed", when(test.updated_at)]]} />
        {canWrite ? (
          <div className="row mt-2" style={{ flexWrap: "wrap" }}>
            <label className="btn btn--primary btn--sm" style={{ cursor: busy ? "wait" : "pointer" }}>Upload questions (Excel or CSV)
              <input type="file" hidden accept=".xlsx,.csv" disabled={busy} onChange={(e) => { void upload(e.target.files?.[0]); e.target.value = ""; }} /></label>
            <label className="row" style={{ gap: "var(--s-1)" }}><input type="checkbox" checked={replace} onChange={(e) => setReplace(e.target.checked)} /> replace the bank (otherwise added to it)</label>
            <Btn kind="ghost" onClick={template}>Template</Btn>
            {busy ? <span className="sub2">Uploading…</span> : null}
          </div>
        ) : null}
        {refused.length ? <Note kind="bad" title={`${refused.length} row${refused.length === 1 ? "" : "s"} not added`}>{refused.map((x) => `Row ${x.row}: ${x.reason}`).join(" · ")}</Note> : null}
        {rows && rows.length ? (
          <DTable pageSize={25} cols={["No.|num", "Question", "Options", "Answer|mid", "Answered|num", "Right|num", ...(canWrite ? [""] : [])]}
            texts={rows.map((q) => `${q.stem} ${q.option_a} ${q.option_b} ${q.option_c ?? ""} ${q.option_d ?? ""} ${q.option_e ?? ""}`)}
            rows={rows.map((q) => [q.ordinal, <span key="q" style={{ whiteSpace: "pre-line" }}>{q.stem}</span>,
              <span key="o" className="sub2">{[["A", q.option_a], ["B", q.option_b], ["C", q.option_c], ["D", q.option_d], ["E", q.option_e]].filter(([, v]) => v).map(([k, v]) => `${k}. ${v}`).join("  ·  ")}</span>,
              q.answer, Number(q.answered), Number(q.answered) ? `${Number(q.right_answers)} (${Math.round((100 * Number(q.right_answers)) / Number(q.answered))}%)` : "—",
              ...(canWrite ? [<Btn key="r" kind="ghost" onClick={() => void remove(q)}>Remove</Btn>] : [])])} />
        ) : rows ? <p className="sub2 mt-2">The bank is empty.</p> : null}
      </PBody>
    </Panel>
  );
}
