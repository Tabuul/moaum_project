"use client";

/** tCbtBank — the CBT question bank (V077, extended by V322 and V364): pick a course, see its questions and the blueprint (how many there
 *  are by topic and difficulty), author in three kinds — one correct option, true/false, several correct options — with an explanation for
 *  the marker, search on the server, edit, retire, archive, read a question's history, export. A question is never deleted; from V364 every
 *  change is a new version, and each attempt keeps the version it was examined on — so a question is corrected after it is sat, but not
 *  while an examination drawing it is open. From V374 a question written or changed waits for moderation: someone other than the person
 *  who set it approves it, or returns it with a note, and only approved questions go on a paper — the server's rule; this page asks. */
import { useState } from "react";
import { useQueryNav } from "@/lib/query-nav";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { QuestionImport } from "@/components/cbt/QuestionImport";
import { ModerationSample } from "@/components/cbt/ModerationSample";

export interface Course { code: string; title: string; questions: number; total?: number; awaiting?: number; general_office?: string | null; kind?: string }
export type Moderation = "PENDING" | "APPROVED" | "RETURNED";
export interface Question { id: string; course_code: string; topic: string | null; stem: string; options: string[]; answer: number; answers: number[] | null; kind: string; difficulty: string; marks: number; active: boolean; explanation?: string | null; authored_by?: string | null; authored_at?: string; updated_at?: string | null; on_papers?: number; version?: number; archived_at?: string | null; sat?: number;
  /** V374: the moderation of the question's current version, who decided and with what note, who set the version, and whether that was the signed-in person */
  moderation?: Moderation; moderated_by?: string | null; moderated_at?: string | null; moderation_note?: string | null; set_by?: string | null; mine?: boolean }
interface Version { version: number; kind: string; stem: string; options: string[]; answers: number[]; explanation: string | null; marks: number; topic: string | null; difficulty: string; created_at: string; created_by: string | null; attempts: number }
interface Decision { version: number; decision: "APPROVED" | "RETURNED"; note: string | null; decided_at: string; decided_by: string | null; decided_office: string | null }
const MOD_WORD: Record<Moderation, [string, "ok" | "warn" | "bad"]> = { APPROVED: ["Approved", "ok"], PENDING: ["Awaiting moderation", "warn"], RETURNED: ["Returned", "bad"] };
const MODERATORS = ["hod", "exams", "facultyexams", "dean", "gst", "eps", "super", "jupeb"];
export interface BlueprintRow { topic: string; easy: number; medium: number; hard: number; total: number; marks?: number }

const DIFF: Record<string, ["ok" | "info" | "bad" | "grey", string]> = { EASY: ["ok", "Easy"], MEDIUM: ["info", "Medium"], HARD: ["bad", "Hard"] };
const KIND_WORD: Record<string, string> = { MCQ: "Multiple choice", TRUE_FALSE: "True / false", MULTI: "Multiple select" };
interface Draft { topic: string; stem: string; kind: string; options: string[]; answers: number[]; difficulty: string; marks: string; explanation: string }
const EMPTY: Draft = { topic: "", stem: "", kind: "MCQ", options: ["", "", "", ""], answers: [0], difficulty: "MEDIUM", marks: "1", explanation: "" };

export function QuestionBank({ courses, course, questions, blueprint, actingOffice, base = "/exams/question-bank", search = "", status = "" }: { courses: Course[]; course: string | null; questions: Question[]; blueprint: BlueprintRow[]; actingOffice: string | null; base?: string; search?: string; status?: string }) {
  const router = useRouter();
  const go = useQueryNav();
  const [text, setText] = useState(search);
  const [history, setHistory] = useState<{ q: Question; versions: Version[] | null; decisions?: Decision[]; problem: Problem | null } | null>(null);
  const [modFilter, setModFilter] = useState("");
  const [returning, setReturning] = useState<Question | null>(null);
  const [returnNote, setReturnNote] = useState("");
  const where = (patch: Record<string, string>) => {
    const p = new URLSearchParams();
    const all = { course: course ?? "", q: search, status, ...patch };
    for (const [k, v] of Object.entries(all)) if (v) p.set(k, v);
    return `${base}?${p.toString()}`;
  };
  async function openHistory(x: Question) {
    setHistory({ q: x, versions: null, problem: null });
    const [r, d] = await Promise.all([fetch(`/api/bff/api/v1/cbt/questions/${x.id}/versions`), fetch(`/api/bff/api/v1/cbt/questions/${x.id}/moderation`)]);
    const j = await r.json().catch(() => null);
    const decisions = d.ok ? ((await d.json().catch(() => [])) as Decision[]) : [];
    setHistory({ q: x, versions: r.ok ? (j as Version[]) : null, decisions, problem: r.ok ? null : ((j as Problem) ?? { status: r.status, title: r.statusText }) });
  }
  async function exportBank() {
    const head = ["Course Code", "Question Type", "Question", "Option A", "Option B", "Option C", "Option D", "Option E", "Correct Answer", "Marks", "Topic", "Difficulty", "Explanation", "Status", "Version", "Moderation"];
    const body = questions.map((x) => [x.course_code, x.kind, x.stem, ...[0, 1, 2, 3, 4].map((i) => x.options[i] ?? ""), (x.answers ?? [x.answer]).map((i) => String.fromCharCode(65 + i)).join(", "),
      x.marks, x.topic ?? "", x.difficulty, x.explanation ?? "", x.archived_at ? "ARCHIVED" : x.active ? "ACTIVE" : "INACTIVE", x.version ?? 1, x.moderation ?? ""]);
    downloadBlob(await brandedXlsx(`${course} question bank`, head, body, { sheetName: "Questions", serial: docSerial("QBK"), sub: `${questions.length} questions · keys included: keep this file within the office`, noSerialColumn: true }), `${(course ?? "bank").replace(/\s+/g, "-")}-question-bank.xlsx`);
  }
  const may = ["lecturer", "hod", "exams", "dean", "gst", "eps", "super", "jupeb"].includes(actingOffice ?? "");
  const mayModerate = MODERATORS.includes(actingOffice ?? "");
  const [q, setQ] = useState<Draft>({ ...EMPTY, options: [...EMPTY.options] });
  const [editing, setEditing] = useState<Question | null>(null);
  const [e, setE] = useState<Draft>({ ...EMPTY });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  async function send(path: string, method: "POST" | "PUT", body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/cbt${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return null; }
      notify(reason);
      router.refresh();
      return j as Record<string, unknown>;
    } finally {
      setBusy(false);
    }
  }

  const body = (d: Draft) => {
    const options = d.kind === "TRUE_FALSE" ? ["True", "False"] : d.options.map((o) => o.trim()).filter(Boolean);
    const answers = d.answers.filter((a) => a < options.length);
    return { topic: d.topic || null, stem: d.stem.trim(), kind: d.kind, options, answer: d.kind === "MULTI" ? null : answers[0] ?? 0, answers: d.kind === "MULTI" ? answers : [answers[0] ?? 0], difficulty: d.difficulty, marks: d.marks ? Number(d.marks) : 1, explanation: d.explanation.trim() || null };
  };
  const valid = (d: Draft) => d.stem.trim() && (d.kind === "TRUE_FALSE" || d.options.filter((o) => o.trim()).length >= 2) && d.answers.length > 0;
  const pickAnswer = (d: Draft, set: (x: Draft) => void, i: number) => set({ ...d, answers: d.kind === "MULTI" ? (d.answers.includes(i) ? d.answers.filter((x) => x !== i) : [...d.answers, i].sort((a, b) => a - b)) : [i] });
  const setKind = (d: Draft, set: (x: Draft) => void, kind: string) => set({ ...d, kind, options: kind === "TRUE_FALSE" ? ["True", "False"] : d.options.length >= 2 ? d.options : ["", "", "", ""], answers: kind === "MULTI" ? d.answers : [d.answers[0] ?? 0] });

  const form = (d: Draft, set: (x: Draft) => void, prefix: string, locked?: boolean) => (
    <>
      <div className="grid grid--3">
        <Field id={`${prefix}-kind`} label="Kind" hint={locked ? "Fixed" : undefined}><select id={`${prefix}-kind`} className="ctl" disabled={locked} value={d.kind} onChange={(ev) => setKind(d, set, ev.target.value)}>{Object.entries(KIND_WORD).map(([k, w]) => <option key={k} value={k}>{w}</option>)}</select></Field>
        <Field id={`${prefix}-topic`} label="Topic" hint="Optional"><input id={`${prefix}-topic`} className="ctl" value={d.topic} onChange={(ev) => set({ ...d, topic: ev.target.value })} /></Field>
        <Field id={`${prefix}-diff`} label="Difficulty"><select id={`${prefix}-diff`} className="ctl" value={d.difficulty} onChange={(ev) => set({ ...d, difficulty: ev.target.value })}>{["EASY", "MEDIUM", "HARD"].map((x) => <option key={x} value={x}>{x.charAt(0) + x.slice(1).toLowerCase()}</option>)}</select></Field>
      </div>
      <Field id={`${prefix}-stem`} label="Question" required><textarea id={`${prefix}-stem`} className="ctl" rows={3} value={d.stem} onChange={(ev) => set({ ...d, stem: ev.target.value })} /></Field>
      {d.options.map((opt, i) => (
        <div key={i} className="row mb-2">
          <input type={d.kind === "MULTI" ? "checkbox" : "radio"} name={`${prefix}-answer`} checked={d.answers.includes(i)} onChange={() => pickAnswer(d, set, i)} title="Correct option" aria-label={`Option ${String.fromCharCode(65 + i)} is correct`} />
          <input className="ctl grow" placeholder={`Option ${String.fromCharCode(65 + i)}`} disabled={locked || d.kind === "TRUE_FALSE"} value={opt} onChange={(ev) => { const options = [...d.options]; options[i] = ev.target.value; set({ ...d, options }); }} />
          {!locked && d.kind !== "TRUE_FALSE" && d.options.length > 2 ? <Btn kind="ghost" size="sm" onClick={() => set({ ...d, options: d.options.filter((_, k) => k !== i), answers: d.answers.filter((a) => a !== i).map((a) => (a > i ? a - 1 : a)) })}>Remove</Btn> : null}
        </div>
      ))}
      <div className="row row--inline row--tight mb-2">
        {!locked && d.kind !== "TRUE_FALSE" && d.options.length < 8 ? <Btn kind="ghost" size="sm" onClick={() => set({ ...d, options: [...d.options, ""] })}>Add an option</Btn> : null}
        <span className="sub2">{d.kind === "MULTI" ? "Tick every correct option; a candidate earns the marks only with exactly those." : "Select the radio beside the correct option."}</span>
      </div>
      <div className="grid grid--3">
        <Field id={`${prefix}-marks`} label="Marks"><input id={`${prefix}-marks`} className="ctl tnum" inputMode="numeric" value={d.marks} onChange={(ev) => set({ ...d, marks: ev.target.value.replace(/[^0-9]/g, "") })} /></Field>
        <Field id={`${prefix}-expl`} label="Explanation" hint="For the marker and the review; never shown during the examination" className="rf--full"><textarea id={`${prefix}-expl`} className="ctl" rows={2} value={d.explanation} onChange={(ev) => set({ ...d, explanation: ev.target.value })} /></Field>
      </div>
    </>
  );

  if (!course) {
    return (
      <>
        <Note kind="info" title="A paper is assembled to a blueprint, not picked by hand">
          Each course has a bank of questions tagged by topic and difficulty, so an examination can be drawn to a specification — so many easy, so many hard, spread across the topics — and be comparable from one sitting to the next. The correct options never leave the server.
        </Note>
        <Panel title="Courses" right="Pick one to open its question bank">
          {courses.length ? (
            <DTable cols={["Code", "Title", "Office|mid", "Active questions|num", "Awaiting moderation|num", "|num"]} rows={courses.map((c) => [
              <span className="tnum" key="c">{c.code}</span>,
              <span key="t">{c.title}</span>,
              <span key="o" className="sub2">{c.general_office ?? (c.kind === "GST" ? "GST" : "—")}</span>,
              <span className="tnum" key="q">{c.questions}{c.total != null && c.total !== c.questions ? <span className="sub2"> of {c.total}</span> : null}</span>,
              c.awaiting ? <Pil kind="warn" key="w">{c.awaiting}</Pil> : <span key="w" className="sub2">—</span>,
              <LinkBtn key="o" href={`${base}?course=${encodeURIComponent(c.code)}`} kind="primary">Open</LinkBtn>,
            ])} texts={courses.map((c) => `${c.code} ${c.title}`)} />
          ) : <PBody><div className="sub2">No course is on the catalogue yet.</div></PBody>}
        </Panel>
      </>
    );
  }

  const active = questions.filter((x) => x.active).length;
  const keyOf = (x: Question) => (x.answers ?? [x.answer]).map((i) => x.options[i]).join(" · ");
  // V374: what waits for moderation, and what the signed-in moderator may decide (never a version they set)
  const waiting = questions.filter((x) => x.moderation && x.moderation !== "APPROVED" && !x.archived_at);
  const decidable = waiting.filter((x) => x.moderation === "PENDING" && !x.mine);
  const shown = modFilter === "AWAITING" ? waiting : modFilter ? questions.filter((x) => x.moderation === modFilter) : questions;
  const moderate = (x: Question, decision: "APPROVE" | "RETURN", note?: string) =>
    send(`/questions/${x.id}/moderation`, "POST", { decision, note: note ?? null }, `${decision === "APPROVE" ? "Approve" : "Return"} a question in ${course}${note ? `: ${note}` : ""}`);
  async function approveAll() {
    if (!window.confirm(`Approve the ${decidable.length} question${decidable.length === 1 ? "" : "s"} awaiting moderation that you did not set? Read each first: an approved question may go on a paper.`)) return;
    const j = await send("/questions/moderation", "POST", { ids: decidable.map((x) => x.id), decision: "APPROVE" }, `Approve ${decidable.length} questions in ${course}`);
    if (j) setSaid(`${j.decided} approved${Array.isArray(j.left) && j.left.length ? ` · ${j.left.length} left as they were` : ""}`);
  }
  return (
    <>
      {said ? <Note kind="ok" title={said}>On the record.</Note> : null}
      {err ? <ProblemNotice problem={err} /> : null}
      <div className="mb-3"><LinkBtn href={base} kind="ghost">← All courses</LinkBtn></div>
      <Tiles items={[
        ["Course", course, null, courses.find((c) => c.code === course)?.title ?? ""],
        ["Active questions", String(active), null, `${questions.length - active} retired`],
        ["Topics", String(blueprint.length), null, "Distinct"],
        ["Marks available", String(questions.filter((x) => x.active).reduce((n, x) => n + Number(x.marks), 0)), null, "Sum of active questions"],
        ["Awaiting moderation", String(waiting.length), waiting.length ? "var(--amber-ink)" : null, `${waiting.filter((x) => x.moderation === "RETURNED").length} returned`],
      ]} cls="grid--5" />
      {waiting.length ? (
        <Note kind="info" title={`${waiting.length} question${waiting.length === 1 ? " waits" : "s wait"} for moderation`}>
          A question goes on a paper once someone other than the person who set it — a Head of Department, an Examinations Officer, a Dean, or the course&rsquo;s own office — approves it.
          A returned question carries the moderator&rsquo;s note; correcting it sends it back for moderation. Every change of wording, options, key or marks waits again.
          {mayModerate ? (decidable.length ? <> You may decide {decidable.length} of them.</> : <> None of them is yours to decide: you set them (another moderator approves those), or they were returned to their setter.</>)
            : <> Your office ({actingOffice ?? "none"}) does not approve questions; switch to a moderating office in the bar if you hold one.</>}
        </Note>
      ) : null}

      <Panel title="Blueprint" right="Active questions by topic and difficulty">
        {blueprint.length ? (
          <DTable cols={["Topic", "Easy|num", "Medium|num", "Hard|num", "Total|num", "Marks|num"]} rows={blueprint.map((b) => [
            <span key="t">{b.topic}</span>,
            <span className="tnum sub2" key="e">{b.easy}</span>,
            <span className="tnum sub2" key="m">{b.medium}</span>,
            <span className="tnum sub2" key="h">{b.hard}</span>,
            <b className="tnum" key="tot">{b.total}</b>,
            <span className="tnum" key="mk">{b.marks ?? "—"}</span>,
          ])} />
        ) : <PBody><div className="sub2">No questions yet — author the first below.</div></PBody>}
      </Panel>

      <Panel title="Questions" right={<span className="row row--inline row--tight">
          <form className="row row--inline row--tight" onSubmit={(ev) => { ev.preventDefault(); go(where({ q: text.trim() })); }}>
            <input className="ctl" aria-label="Search the bank" placeholder="Search the text or topic" value={text} onChange={(ev) => setText(ev.target.value)} />
            <select className="ctl" aria-label="Status" value={status} onChange={(ev) => go(where({ status: ev.target.value }))}><option value="">Active and retired</option><option value="ACTIVE">Active</option><option value="INACTIVE">Retired</option><option value="ARCHIVED">Archived</option><option value="ALL">Everything</option></select>
            <select className="ctl" aria-label="Moderation" value={modFilter} onChange={(ev) => setModFilter(ev.target.value)}><option value="">Any moderation</option><option value="AWAITING">Awaiting moderation</option><option value="PENDING">Not yet decided</option><option value="RETURNED">Returned</option><option value="APPROVED">Approved</option></select>
            <Btn kind="secondary" size="sm" type="submit">Search</Btn>
          </form>
          {mayModerate && decidable.length ? <Btn kind="primary" size="sm" disabled={busy} onClick={() => void approveAll()}>Approve {decidable.length} awaiting</Btn> : null}
          {questions.length ? <Btn kind="ghost" size="sm" onClick={() => void exportBank()}>Export</Btn> : null}
        </span>}>
        {shown.length ? (
          <DTable pageSize={25} cols={["Question", "Kind|mid", "Topic|mid", "Difficulty|mid", "Marks|num", "Moderation|mid", "Action|num"]} rows={shown.map((x) => [
            <span key="s">{x.stem}<div className="sub2">Key: {keyOf(x)}{x.on_papers ? ` · on ${x.on_papers} paper${x.on_papers === 1 ? "" : "s"}` : ""}{x.sat ? ` · sat ${x.sat} time${x.sat === 1 ? "" : "s"}` : ""}{(x.version ?? 1) > 1 ? ` · version ${x.version}` : ""}{x.authored_by ? ` · ${x.authored_by}` : ""}</div></span>,
            <span className="sub2" key="k">{KIND_WORD[x.kind] ?? x.kind}</span>,
            <span className="sub2" key="t">{x.topic ?? "—"}</span>,
            <Pil kind={DIFF[x.difficulty]?.[0] ?? "grey"} key="d">{DIFF[x.difficulty]?.[1] ?? x.difficulty}</Pil>,
            <span className="tnum" key="m">{x.marks}</span>,
            <span key="mod" style={{ display: "grid", gap: 4, justifyItems: "center" }}>
              {x.moderation ? <Pil kind={MOD_WORD[x.moderation][1]}>{MOD_WORD[x.moderation][0]}</Pil> : null}
              <span className="sub2">{x.moderation === "APPROVED" ? (x.moderated_by ? x.moderated_by : "in the bank before moderation") : x.moderation === "RETURNED" ? `“${x.moderation_note ?? ""}”` : x.mine ? "set by you — another moderator approves it" : x.set_by ?? ""}</span>
              {mayModerate && !x.archived_at && !x.mine && x.moderation !== "APPROVED" ? <Btn kind="secondary" size="sm" disabled={busy} onClick={() => void moderate(x, "APPROVE")}>Approve</Btn> : null}
              {mayModerate && !x.archived_at && !x.mine && x.moderation !== "RETURNED" ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => { setReturning(x); setReturnNote(""); }}>Return</Btn> : null}
            </span>,
            <span key="ac" className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>{x.archived_at ? <Pil kind="grey" key="p">Archived</Pil> : x.active ? <Pil kind="ok" key="p">Active</Pil> : <Pil kind="grey" key="p">Retired</Pil>}
              {may && !x.archived_at ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => { setEditing(x); setE({ topic: x.topic ?? "", stem: x.stem, kind: x.kind ?? "MCQ", options: [...x.options], answers: x.answers ?? [x.answer], difficulty: x.difficulty, marks: String(x.marks), explanation: x.explanation ?? "" }); }}>Edit</Btn> : null}
              {may && !x.archived_at ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => void send(`/questions/${x.id}/active`, "POST", { active: !x.active }, `${x.active ? "Retire" : "Restore"} a question in ${course}`)}>{x.active ? "Retire" : "Restore"}</Btn> : null}
              {may ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => void send(`/questions/${x.id}/archive`, "POST", { archived: !x.archived_at }, `${x.archived_at ? "Restore from the archive" : "Archive"} a question in ${course}`)}>{x.archived_at ? "Unarchive" : "Archive"}</Btn> : null}
              <Btn kind="ghost" size="sm" onClick={() => void openHistory(x)}>History</Btn></span>,
          ])} texts={shown.map((x) => `${x.stem} ${x.topic ?? ""} ${x.difficulty} ${x.kind} ${x.moderation ?? ""}`)} />
        ) : <PBody><div className="sub2">{questions.length ? "No question here is in that state of moderation." : <>No question in this course&rsquo;s bank yet.</>}</div></PBody>}
      </Panel>

      {/* V375: a sample read, the rest approved with it */}
      {mayModerate ? <ModerationSample course={course} /> : null}
      {may ? <QuestionImport course={course} courseTitle={courses.find((c) => c.code === course)?.title} /> : null}
      {may ? (
        <Panel title="Author a question" right={`Added to ${course}`}>
          <PBody>
            {form(q, setQ, "q")}
            <div><Btn kind="primary" disabled={busy || !valid(q)} onClick={async () => { const j = await send("/questions", "POST", { course, ...body(q) }, `Author a question in ${course}`); if (j) { setSaid("Question added to the bank: it waits for moderation before it goes on a paper"); setQ({ ...EMPTY, topic: q.topic, kind: q.kind, difficulty: q.difficulty, options: q.kind === "TRUE_FALSE" ? ["True", "False"] : ["", "", "", ""], answers: [0] }); } }}>Add to the bank</Btn></div>
          </PBody>
        </Panel>
      ) : null}

      {editing ? (
        <Modal title="Edit the question" sub={editing.sat ? `Sat ${editing.sat} time${editing.sat === 1 ? "" : "s"} · version ${editing.version ?? 1}` : course} wide onClose={() => setEditing(null)}
          foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setEditing(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || !valid(e)} onClick={async () => { const j = await send(`/questions/${editing.id}`, "PUT", body(e), `Edit a question in ${course}`); if (j) setEditing(null); }}>Save</Btn></span>}>
          {form(e, setE, "e")}
          {editing.sat ? <div className="sub2">This question has been sat. Saving makes version {(editing.version ?? 1) + 1}; every candidate who sat version {editing.version ?? 1} keeps it — their paper, their answers and their marks do not change. A change that should alter results already given is made by amending those results with a reason. The edit is refused while an examination drawing the question is open.</div> : null}
        </Modal>
      ) : null}
      {history ? (
        <Modal title="The question's history" sub={`${course} · now version ${history.q.version ?? 1}`} wide onClose={() => setHistory(null)} foot={<Btn kind="ghost" onClick={() => setHistory(null)}>Close</Btn>}>
          {history.problem ? <ProblemNotice problem={history.problem} /> : !history.versions ? <div className="sub2">Loading…</div> : (
            <DTable cols={["Version|mid", "Question", "Key", "Marks|num", "Examined|num", "Made"]} rows={history.versions.map((v) => [
              <b key="v" className="tnum">{v.version}</b>,
              <span key="s">{v.stem}<div className="sub2">{v.options.map((o, i) => `${String.fromCharCode(65 + i)}. ${o}`).join(" · ")}</div></span>,
              <span key="k" className="tnum">{v.answers.map((i) => String.fromCharCode(65 + i)).join(", ")}</span>,
              <span key="m" className="tnum">{v.marks}</span>,
              <span key="a" className="tnum">{v.attempts}</span>,
              <span key="c" className="sub2">{new Date(v.created_at).toLocaleString("en-GB")}{v.created_by ? ` · ${v.created_by}` : ""}</span>,
            ])} />
          )}
          <div className="sub2 mt-2">Each attempt is marked on the version it was drawn; &ldquo;Examined&rdquo; counts the attempts that drew each version.</div>
          {history.decisions && history.decisions.length ? (
            <>
              <h4 className="mt-3 mb-1">Moderation</h4>
              <DTable cols={["Version|mid", "Decision|mid", "Note", "By", "When"]} rows={history.decisions.map((d, i) => [
                <b key="v" className="tnum">{d.version}</b>,
                <Pil key="d" kind={MOD_WORD[d.decision][1]}>{MOD_WORD[d.decision][0]}</Pil>,
                <span key="n">{d.note ?? "—"}</span>,
                <span key="b" className="sub2">{d.decided_by ?? "—"}{d.decided_office ? ` · ${d.decided_office.toUpperCase()}` : ""}</span>,
                <span key={`w${i}`} className="sub2">{new Date(d.decided_at).toLocaleString("en-GB")}</span>,
              ])} />
            </>
          ) : history.versions ? <div className="sub2 mt-2">{history.q.moderation === "APPROVED" && !history.q.moderated_by ? "In the bank before moderation began: taken as approved." : "No moderation decision yet."}</div> : null}
        </Modal>
      ) : null}
      {returning ? (
        <Modal title="Return the question" sub={course} onClose={() => setReturning(null)}
          foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setReturning(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || !returnNote.trim()} onClick={async () => { const j = await moderate(returning, "RETURN", returnNote.trim()); if (j) setReturning(null); }}>Return with this note</Btn></span>}>
          <p className="mb-2">{returning.stem}</p>
          <div className="sub2 mb-2">Key: {keyOf(returning)}{returning.set_by ? ` · set by ${returning.set_by}` : ""}</div>
          <Field id="ret-note" label="What should change" required hint="The setter reads this; correcting the question sends it back for moderation"><textarea id="ret-note" className="ctl" rows={3} value={returnNote} onChange={(ev) => setReturnNote(ev.target.value)} /></Field>
        </Modal>
      ) : null}
    </>
  );
}
