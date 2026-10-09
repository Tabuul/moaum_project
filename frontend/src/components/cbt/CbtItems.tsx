"use client";
/** V372: each question of an ended examination as its scored candidates met it — how many got it right (the facility), whether it
 *  separated the stronger candidates from the weaker (the discrimination: the top 27% by score against the bottom 27%), which options
 *  were chosen, overall and by the top group — and flags where the strongest mostly chose another option than the key. It shows the
 *  keys, so it opens to the office that manages the examination once the examination has ended. Nothing is re-marked here. */
import { useEffect, useState } from "react";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";

export interface ItemRow {
  question_id: string; n: number; stem: string; kind: string; options: { i: number; text: string }[]; key: number[];
  seen: number; answered: number; correct: number; facility: number | null; discrimination: number | null; upper_n: number; lower_n: number;
  choices: Record<string, number>; upper_choices: Record<string, number>; flags: string[];
}
export interface ItemAnalysis { questions: ItemRow[]; candidates: number; flagged: number }

export const FLAG_WORD: Record<string, [string, "bad" | "warn" | "grey"]> = {
  POSSIBLE_WRONG_KEY: ["Possible wrong key", "bad"], NEGATIVE_DISCRIMINATION: ["Weaker candidates did better", "bad"], WEAK_DISCRIMINATION: ["Separates weakly", "warn"],
  VERY_HARD: ["Very hard", "warn"], VERY_EASY: ["Very easy", "grey"], NOBODY_ANSWERED: ["Nobody answered", "warn"],
};
const letter = (i: number) => String.fromCharCode(65 + i);
const two = (x: number | null) => (x == null ? "—" : Number(x).toFixed(2));

export function useItemAnalysis(examId: string, open: boolean, reload = 0): { data: ItemAnalysis | null; problem: Problem | null } {
  const [data, setData] = useState<ItemAnalysis | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  useEffect(() => {
    if (!open) return;
    let gone = false;
    fetch(`/api/bff/api/v1/cbt/exams/${encodeURIComponent(examId)}/items`).then(async (r) => {
      const j = await r.json().catch(() => null);
      if (gone) return;
      if (r.ok) setData(j as ItemAnalysis); else setProblem((j as Problem) ?? { status: r.status, title: r.statusText });
    }).catch(() => { if (!gone) setProblem({ status: 0, title: "The analysis could not be read." }); });
    return () => { gone = true; };
  }, [examId, open, reload]);
  return { data, problem };
}

/** V373: a key correction already made on the examination */
interface KeyCorrection { id: string; question_id: string; stem: string; old_key: string; new_key: string; reason: string; corrected_by: string | null; corrected_office: string | null; corrected_at: string; attempts_seen: number; scores_changed: number; bank_fixed: boolean }
interface PreviewRow { attempt_id: string; number: string; name: string; outcome: string; max_marks: number; old_score: number; new_score: number; old_percentage: number; new_percentage: number; old_grade: string | null; new_grade: string | null; old_passed: boolean; new_passed: boolean }
const keyWord = (k: string) => k.split(",").filter(Boolean).map((x) => letter(Number(x))).join(", ");

export function CbtItems({ examId, ended, canCorrect = false }: { examId: string; ended: boolean; canCorrect?: boolean }) {
  const [reload, setReload] = useState(0);
  const { data, problem } = useItemAnalysis(examId, ended, reload);
  const [onlyFlagged, setOnlyFlagged] = useState(false);
  const [fix, setFix] = useState<ItemRow | null>(null);
  const [history, setHistory] = useState<KeyCorrection[]>([]);
  useEffect(() => {
    if (!ended || !canCorrect) return;
    let gone = false;
    fetch(`/api/bff/api/v1/cbt/exams/${encodeURIComponent(examId)}/key-corrections`).then(async (r) => { if (!gone && r.ok) setHistory((await r.json()) as KeyCorrection[]); }).catch(() => undefined);
    return () => { gone = true; };
  }, [examId, ended, canCorrect, reload]);
  if (!ended) return <Note kind="info" title="The question analysis opens once the examination has ended">It shows each question&rsquo;s key and how the candidates answered it, so it waits until nobody is still writing.</Note>;
  if (problem) return <Note kind="bad" title="The analysis could not be read">{problem.title}</Note>;
  if (!data) return <div className="sub2">Reading the answers…</div>;
  const rows = onlyFlagged ? data.questions.filter((q) => q.flags.length) : data.questions;
  const flaggedAny = data.questions.filter((q) => q.flags.length).length;
  const avg = data.questions.length ? data.questions.reduce((s, q) => s + Number(q.facility ?? 0), 0) / data.questions.length : null;
  return (
    <>
      <Tiles items={[
        ["SCORED CANDIDATES", String(data.candidates), null, data.candidates >= 10 ? "Top and bottom 27% compared" : "Under ten: no groups to compare"],
        ["QUESTIONS", String(data.questions.length), null, `${flaggedAny} with something to look at`],
        ["POSSIBLE WRONG KEYS", String(data.flagged), data.flagged ? "var(--red-ink)" : null, "The strongest mostly chose another option"],
        ["AVERAGE FACILITY", avg == null ? "—" : avg.toFixed(2), null, "Share who got a question right"],
      ]} />
      {data.flagged ? (
        <Note kind="bad" title={`${data.flagged} question${data.flagged === 1 ? "" : "s"} may carry a wrong key`}>
          More of the strongest candidates chose one other option than the option marked correct. Check the key in the bank before the results are approved; correcting a key and marking again is the office&rsquo;s decision, made on the results.
        </Note>
      ) : null}
      <Panel title="Question by question" right={<label className="row row--inline row--tight sub2"><input type="checkbox" checked={onlyFlagged} onChange={(e) => setOnlyFlagged(e.target.checked)} /> Only those with something to look at</label>}>
        <PBody>
          <div className="sub2">Facility is the share of candidates who got the question right — the usual guide is 0.20 to 0.90. Discrimination is that share in the top 27% of candidates by score minus that share in the bottom 27% — 0.20 or more separates well, below 0 means the weaker did better. Option counts show every candidate&rsquo;s choice, with the top group&rsquo;s in brackets; the key is in bold.</div>
        </PBody>
        <DTable pageSize={25} cols={["#|mid", "Question", "Facility|num", "Discrimination|num", "Options chosen", "To look at", ...(canCorrect ? ["|mid"] : [])]} rows={rows.map((q) => [
          <span key="n" className="tnum">{q.n}</span>,
          <span key="q">{q.stem.length > 160 ? q.stem.slice(0, 160) + "…" : q.stem}<div className="sub2">{q.kind === "MULTI" ? "Multiple select" : q.kind === "TRUE_FALSE" ? "True / false" : "Multiple choice"} · key {q.key.map(letter).join(", ")} · {q.answered} of {q.seen} answered</div></span>,
          <span key="f" className="tnum">{two(q.facility)}</span>,
          <span key="d" className="tnum">{two(q.discrimination)}</span>,
          <span key="o" className="sub2">{q.options.map((o) => {
            const all = q.choices[String(o.i)] ?? 0, top = q.upper_choices[String(o.i)] ?? 0, isKey = q.key.includes(o.i);
            return <span key={o.i} style={{ marginRight: 10, whiteSpace: "nowrap" }}>{isKey ? <b>{letter(o.i)} {all}</b> : <>{letter(o.i)} {all}</>}{q.upper_n ? ` (${top})` : ""}</span>;
          })}</span>,
          <span key="x" className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>{q.flags.length ? q.flags.map((f) => <Pil key={f} kind={(FLAG_WORD[f] ?? [f, "grey"])[1]}>{(FLAG_WORD[f] ?? [f])[0]}</Pil>) : <span className="sub2">—</span>}</span>,
          ...(canCorrect ? [<Btn key="k" kind={q.flags.includes("POSSIBLE_WRONG_KEY") ? "secondary" : "ghost"} size="sm" onClick={() => setFix(q)}>Correct the key</Btn>] : []),
        ])} texts={rows.map((q) => `${q.n} ${q.stem} ${q.flags.join(" ")}`)} />
      </Panel>
      {history.length ? (
        <Panel title="Keys corrected on this examination">
          <DTable cols={["Question", "Key", "Reason", "Scores changed|num", "Bank|mid", "By"]} rows={history.map((h) => [
            <span key="q" className="sub2">{h.stem}</span>,
            <span key="k" className="tnum">{keyWord(h.old_key)} → <b>{keyWord(h.new_key)}</b></span>,
            <span key="r" className="sub2">{h.reason}</span>,
            <span key="c" className="tnum">{h.scores_changed} of {h.attempts_seen}</span>,
            <span key="b" className="sub2">{h.bank_fixed ? "Corrected" : "Unchanged"}</span>,
            <span key="w" className="sub2">{h.corrected_by ?? h.corrected_office ?? "—"}<div>{new Date(h.corrected_at).toLocaleString("en-GB", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" })}</div></span>,
          ])} />
        </Panel>
      ) : null}
      {fix ? <KeyFix examId={examId} q={fix} onClose={() => setFix(null)} onDone={() => { setFix(null); setReload((n) => n + 1); }} /> : null}
    </>
  );
}

/** V373: the key of one question corrected — the correct option(s) and the reason, the effect on every candidate read first, then applied */
function KeyFix({ examId, q, onClose, onDone }: { examId: string; q: ItemRow; onClose: () => void; onDone: () => void }) {
  const [key, setKey] = useState<number[]>(q.key);
  const [reason, setReason] = useState("");
  const [fixBank, setFixBank] = useState(true);
  const [preview, setPreview] = useState<{ rows: PreviewRow[]; changed: number; passChanged: number } | null>(null);
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState<{ scores_changed: number; bank_fixed: boolean; sentToSheet: boolean } | null>(null);
  const multi = q.kind === "MULTI";
  const same = [...key].sort().join(",") === [...q.key].sort().join(",");
  const choose = (i: number) => { setPreview(null); setKey(multi ? (key.includes(i) ? key.filter((x) => x !== i) : [...key, i].sort((a, b) => a - b)) : [i]); };

  async function read() {
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/cbt/exams/${examId}/questions/${q.question_id}/key-correction?key=${key.join(",")}`);
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      setPreview(j as { rows: PreviewRow[]; changed: number; passChanged: number });
    } finally { setBusy(false); }
  }
  async function apply() {
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/cbt/exams/${examId}/questions/${q.question_id}/key-correction`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Key of question ${q.n} corrected: ${reason.trim()}`) }, body: JSON.stringify({ key, reason: reason.trim(), fixBank }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      notify(`Key of question ${q.n} corrected`);
      setDone(j as { scores_changed: number; bank_fixed: boolean; sentToSheet: boolean });
    } finally { setBusy(false); }
  }

  if (done) {
    return (
      <Modal title={`Question ${q.n}: key corrected`} onClose={onDone} foot={<Btn kind="primary" onClick={onDone}>Done</Btn>}>
        <p>{done.scores_changed} score{done.scores_changed === 1 ? "" : "s"} changed, each as a new version of the result naming this correction. {done.bank_fixed ? "The question in the bank is corrected too." : "The question in the bank is unchanged."}</p>
        {done.sentToSheet ? <Note kind="info" title="The results were already sent to the score sheet">Send them again from Results &amp; analytics so the sheet carries the corrected scores (while the sheet is still at entry).</Note> : null}
      </Modal>
    );
  }
  return (
    <Modal title={`Correct the key · question ${q.n}`} sub={q.stem.length > 120 ? q.stem.slice(0, 120) + "…" : q.stem} wide onClose={onClose}
      foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={onClose}>Back</Btn>
        <Btn kind="secondary" disabled={busy || same || !key.length} onClick={() => void read()}>{busy && !preview ? "Reading…" : "See the effect"}</Btn>
        <Btn kind="primary" disabled={busy || !preview || same || !reason.trim()} onClick={() => void apply()}>{busy && preview ? "Correcting…" : "Correct the key and re-mark"}</Btn></span>}>
      <div className="sub2 mb-2">Choose the right option{multi ? "s" : ""}. Every candidate who sat the question is re-marked: their score moves by the difference the key makes, so an amendment made by hand stays. Each changed score is a new version of the result, with your reason; nothing is overwritten.</div>
      <div style={{ display: "grid", gap: 6 }}>
        {q.options.map((o) => (
          <label key={o.i} className="row row--inline row--tight" style={{ alignItems: "flex-start" }}>
            <input type={multi ? "checkbox" : "radio"} name="kf-key" checked={key.includes(o.i)} onChange={() => choose(o.i)} />
            <span><b>{letter(o.i)}.</b> {o.text} {q.key.includes(o.i) ? <Pil kind="grey">key now</Pil> : null} <span className="sub2">· chosen by {q.choices[String(o.i)] ?? 0}</span></span>
          </label>
        ))}
      </div>
      <Field id="kf-reason" label="Reason" required><textarea id="kf-reason" className="ctl" rows={2} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. B is the right answer; the key was entered wrongly" /></Field>
      <label className="row row--inline row--tight sub2"><input type="checkbox" checked={fixBank} onChange={(e) => setFixBank(e.target.checked)} /> Correct the question in the bank too, for later papers (skipped if the bank has changed it since, or a running examination uses it)</label>
      {preview ? (
        <div className="mt-2">
          <Note kind={preview.changed ? "info" : "ok"} title={`${preview.changed} of ${preview.rows.length} candidates' scores change${preview.passChanged ? ` · ${preview.passChanged} pass or fail` : ""}`}>Read the changes before you apply them.</Note>
          <DTable pageSize={20} cols={["Matric No.", "Name", "Score now|num", "After|num", "Grade|mid", "Pass|mid"]} rows={preview.rows.map((r) => {
            const moved = Number(r.old_score) !== Number(r.new_score);
            return [
              <span key="n" className="tnum">{r.number}</span>, <span key="m">{r.name}{r.outcome === "VOID" ? <Pil kind="grey" className="ml-1">void</Pil> : null}</span>,
              <span key="o" className="tnum">{Number(r.old_score)} / {r.max_marks}</span>,
              <span key="a" className={`tnum${moved ? " b600" : ""}`}>{Number(r.new_score)} / {r.max_marks}</span>,
              <span key="g" className="tnum">{r.old_grade ?? "—"}{r.new_grade !== r.old_grade ? <> → <b>{r.new_grade ?? "—"}</b></> : null}</span>,
              <span key="p">{r.old_passed === r.new_passed ? (r.new_passed ? "Pass" : "Fail") : <b>{r.old_passed ? "Pass → Fail" : "Fail → Pass"}</b>}</span>,
            ];
          })} />
        </div>
      ) : null}
    </Modal>
  );
}
