"use client";
/** V372: each question of an ended examination as its scored candidates met it — how many got it right (the facility), whether it
 *  separated the stronger candidates from the weaker (the discrimination: the top 27% by score against the bottom 27%), which options
 *  were chosen, overall and by the top group — and flags where the strongest mostly chose another option than the key. It shows the
 *  keys, so it opens to the office that manages the examination once the examination has ended. Nothing is re-marked here. */
import { useEffect, useState } from "react";
import { Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
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

export function useItemAnalysis(examId: string, open: boolean): { data: ItemAnalysis | null; problem: Problem | null } {
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
  }, [examId, open]);
  return { data, problem };
}

export function CbtItems({ examId, ended }: { examId: string; ended: boolean }) {
  const { data, problem } = useItemAnalysis(examId, ended);
  const [onlyFlagged, setOnlyFlagged] = useState(false);
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
        <DTable pageSize={25} cols={["#|mid", "Question", "Facility|num", "Discrimination|num", "Options chosen", "To look at"]} rows={rows.map((q) => [
          <span key="n" className="tnum">{q.n}</span>,
          <span key="q">{q.stem.length > 160 ? q.stem.slice(0, 160) + "…" : q.stem}<div className="sub2">{q.kind === "MULTI" ? "Multiple select" : q.kind === "TRUE_FALSE" ? "True / false" : "Multiple choice"} · key {q.key.map(letter).join(", ")} · {q.answered} of {q.seen} answered</div></span>,
          <span key="f" className="tnum">{two(q.facility)}</span>,
          <span key="d" className="tnum">{two(q.discrimination)}</span>,
          <span key="o" className="sub2">{q.options.map((o) => {
            const all = q.choices[String(o.i)] ?? 0, top = q.upper_choices[String(o.i)] ?? 0, isKey = q.key.includes(o.i);
            return <span key={o.i} style={{ marginRight: 10, whiteSpace: "nowrap" }}>{isKey ? <b>{letter(o.i)} {all}</b> : <>{letter(o.i)} {all}</>}{q.upper_n ? ` (${top})` : ""}</span>;
          })}</span>,
          <span key="x" className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>{q.flags.length ? q.flags.map((f) => <Pil key={f} kind={(FLAG_WORD[f] ?? [f, "grey"])[1]}>{(FLAG_WORD[f] ?? [f])[0]}</Pil>) : <span className="sub2">—</span>}</span>,
        ])} texts={rows.map((q) => `${q.n} ${q.stem} ${q.flags.join(" ")}`)} />
      </Panel>
    </>
  );
}
