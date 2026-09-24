"use client";

/** tCbtBank — the CBT question bank: pick a course, see its questions and the blueprint
 *  (how many questions there are by topic and difficulty), and author new ones. A question
 *  is retired, not deleted, so a paper that used it can still be explained. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface Course { code: string; title: string; questions: number }
export interface Question { id: string; course_code: string; topic: string | null; stem: string; options: string[]; answer: number; difficulty: string; marks: number; active: boolean }
export interface BlueprintRow { topic: string; easy: number; medium: number; hard: number; total: number }

const DIFF: Record<string, ["ok" | "info" | "bad" | "grey", string]> = { EASY: ["ok", "Easy"], MEDIUM: ["info", "Medium"], HARD: ["bad", "Hard"] };

export function QuestionBank({ courses, course, questions, blueprint, actingOffice }: { courses: Course[]; course: string | null; questions: Question[]; blueprint: BlueprintRow[]; actingOffice: string | null }) {
  const router = useRouter();
  const may = ["lecturer", "hod", "exams", "dean", "super"].includes(actingOffice ?? "");
  const [q, setQ] = useState({ topic: "", stem: "", options: ["", "", "", ""], answer: 0, difficulty: "MEDIUM", marks: "1" });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  async function send(path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/cbt${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j ?? { status: r.status, title: r.statusText }); return null; }
      notify(reason);
      router.refresh();
      return j as Record<string, unknown>;
    } finally {
      setBusy(false);
    }
  }

  if (!course) {
    return (
      <>
        <Note kind="info" title="A paper is assembled to a blueprint, not picked by hand">
          Each course has a bank of questions tagged by topic and difficulty, so an examination can be drawn to a specification — so many easy, so many hard, spread across the topics — and be comparable from one sitting to the next.
        </Note>
        <Panel title="Courses" right="Pick one to open its question bank">
          {courses.length ? (
            <DTable cols={["Code", "Title", "Questions|num", "|num"]} rows={courses.map((c) => [
              <span className="tnum" key="c">{c.code}</span>,
              <span key="t">{c.title}</span>,
              <span className="tnum" key="q">{c.questions}</span>,
              <LinkBtn key="o" href={`/exams/question-bank?course=${encodeURIComponent(c.code)}`} kind="primary">Open</LinkBtn>,
            ])} texts={courses.map((c) => `${c.code} ${c.title}`)} />
          ) : <PBody><div className="sub2">No course is on the catalogue yet.</div></PBody>}
        </Panel>
      </>
    );
  }

  const active = questions.filter((x) => x.active).length;
  return (
    <>
      {said ? <Note kind="ok" title={said}>On the record.</Note> : null}
      {err ? <ProblemNotice problem={err} /> : null}
      <div className="mb-3"><LinkBtn href="/exams/question-bank" kind="ghost">← All courses</LinkBtn></div>
      <Tiles items={[
        ["Course", course, null, courses.find((c) => c.code === course)?.title ?? ""],
        ["Active questions", String(active), null, `${questions.length - active} retired`],
        ["Topics", String(blueprint.length), null, "Distinct"],
        ["Marks available", String(questions.filter((x) => x.active).reduce((n, x) => n + Number(x.marks), 0)), null, "Sum of active questions"],
      ]} />

      <Panel title="Blueprint" right="Active questions by topic and difficulty">
        {blueprint.length ? (
          <DTable cols={["Topic", "Easy|num", "Medium|num", "Hard|num", "Total|num"]} rows={blueprint.map((b) => [
            <span key="t">{b.topic}</span>,
            <span className="tnum sub2" key="e">{b.easy}</span>,
            <span className="tnum sub2" key="m">{b.medium}</span>,
            <span className="tnum sub2" key="h">{b.hard}</span>,
            <b className="tnum" key="tot">{b.total}</b>,
          ])} />
        ) : <PBody><div className="sub2">No questions yet — author the first below.</div></PBody>}
      </Panel>

      <Panel title="Questions">
        {questions.length ? (
          <DTable cols={["Question", "Topic|mid", "Difficulty|mid", "Marks|num", "Action|num"]} rows={questions.map((x) => [
            <span key="s">{x.stem}<div className="sub2">Answer: {x.options[x.answer]}</div></span>,
            <span className="sub2" key="t">{x.topic ?? "—"}</span>,
            <Pil kind={DIFF[x.difficulty]?.[0] ?? "grey"} key="d">{DIFF[x.difficulty]?.[1] ?? x.difficulty}</Pil>,
            <span className="tnum" key="m">{x.marks}</span>,
            <span key="ac">{x.active ? <Pil kind="ok" key="p">Active</Pil> : <Pil kind="grey" key="p">Retired</Pil>}{may ? <Btn kind="ghost" disabled={busy} onClick={() => void send(`/questions/${x.id}/active`, { active: !x.active }, `${x.active ? "Retire" : "Restore"} a question in ${course}`)}>{x.active ? "Retire" : "Restore"}</Btn> : null}</span>,
          ])} texts={questions.map((x) => `${x.stem} ${x.topic ?? ""} ${x.difficulty}`)} />
        ) : <PBody><div className="sub2">No question in this course&rsquo;s bank yet.</div></PBody>}
      </Panel>

      {may ? (
        <Panel title="Author a question" right={`Added to ${course}`}>
          <PBody>
            <Field id="q-stem" label="Question"><textarea id="q-stem" className="ctl" rows={2} value={q.stem} onChange={(e) => setQ({ ...q, stem: e.target.value })} /></Field>
            {q.options.map((opt, i) => (
              <div key={i} className="row mb-2">
                <input type="radio" name="answer" checked={q.answer === i} onChange={() => setQ({ ...q, answer: i })} title="Correct answer" />
                <input className="ctl grow" placeholder={`Option ${String.fromCharCode(65 + i)}`} value={opt} onChange={(e) => { const options = [...q.options]; options[i] = e.target.value; setQ({ ...q, options }); }} />
              </div>
            ))}
            <div className="sub2 mb-2">Select the radio beside the correct option.</div>
            <div className="grid grid--3">
              <Field id="q-topic" label="Topic" hint="Optional"><input id="q-topic" className="ctl" value={q.topic} onChange={(e) => setQ({ ...q, topic: e.target.value })} /></Field>
              <Field id="q-diff" label="Difficulty"><select id="q-diff" className="ctl" value={q.difficulty} onChange={(e) => setQ({ ...q, difficulty: e.target.value })}>{["EASY", "MEDIUM", "HARD"].map((d) => <option key={d} value={d}>{d.charAt(0) + d.slice(1).toLowerCase()}</option>)}</select></Field>
              <Field id="q-marks" label="Marks"><input id="q-marks" className="ctl tnum" inputMode="numeric" value={q.marks} onChange={(e) => setQ({ ...q, marks: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
            </div>
            <div><Btn kind="primary" disabled={busy || !q.stem.trim() || q.options.filter((o) => o.trim()).length < 2} onClick={async () => { const options = q.options.map((o) => o.trim()).filter(Boolean); const answer = Math.min(q.answer, options.length - 1); const j = await send("/questions", { course, topic: q.topic || null, stem: q.stem.trim(), options, answer, difficulty: q.difficulty, marks: q.marks ? Number(q.marks) : 1 }, `Author a question in ${course}`); if (j) { setSaid("Question added to the bank"); setQ({ topic: q.topic, stem: "", options: ["", "", "", ""], answer: 0, difficulty: "MEDIUM", marks: "1" }); } }}>Add to the bank</Btn></div>
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
