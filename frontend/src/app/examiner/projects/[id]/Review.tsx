"use client";
/** The examiner's review (V254): the candidate and the project, the documents released for external examination, and
 *  the assessment form the University configured — a score and a comment on each line, the totals computed, the general
 *  comments and the recommendation. Saved as a draft as often as wanted; submitted once, on a confirmation; read-only
 *  after that unless the University reopens it. */
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Documents, History, RECOMMENDATION, RecommendationPil, StatusPil, daysWords, dayOf, when, type Assessment, type Doc, type Event, type Line, type MyAssignment } from "@/lib/examiners";

export interface ReviewData extends Omit<MyAssignment, "documents"> {
  abstract: string | null; keywords: string | null; documents: Doc[]; rubric: { id: string; name: string; kind: string; has_defence: boolean; note: string | null };
  assessment: Assessment | null; lines: Line[]; history: Event[];
}
type Draft = { scores: Record<string, { score: string; comment: string }>; general: string; strengths: string; weaknesses: string; recommendations: string; corrections: string; final: string };

export function Review({ d }: { d: ReviewData }) {
  const router = useRouter();
  const a = d.assessment;
  const readOnly = a?.state === "SUBMITTED" || a?.state === "LOCKED";
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [confirm, setConfirm] = useState(false);
  const [dirty, setDirty] = useState(false);
  const [f, setF] = useState<Draft>(() => ({
    scores: Object.fromEntries(d.lines.map((l) => [l.criterion_id, { score: l.score == null ? "" : String(l.score), comment: l.comment ?? "" }])),
    general: a?.general_comments ?? "", strengths: a?.strengths ?? "", weaknesses: a?.weaknesses ?? "", recommendations: a?.recommendations ?? "", corrections: a?.corrections ?? "", final: a?.final_recommendation ?? "",
  }));

  const sections = useMemo(() => {
    const by: Record<string, Line[]> = { WRITTEN: [], DEFENCE: [] };
    for (const l of d.lines) (by[l.section] ??= []).push(l);
    return by;
  }, [d.lines]);
  const totals = useMemo(() => {
    const over: string[] = [];
    let sum = 0, max = 0, missing = 0;
    for (const l of d.lines) {
      max += Number(l.max_score);
      const v = f.scores[l.criterion_id]?.score ?? "";
      if (v === "") missing++; else { const n = Number(v); if (n > Number(l.max_score) || n < 0) over.push(l.name); else sum += n; }
    }
    const section = (s: string) => d.lines.filter((l) => l.section === s).reduce((acc, l) => { const v = f.scores[l.criterion_id]?.score ?? ""; return { sum: acc.sum + (v === "" || Number(v) > Number(l.max_score) ? 0 : Number(v)), max: acc.max + Number(l.max_score) }; }, { sum: 0, max: 0 });
    return { sum, max, missing, over, written: section("WRITTEN"), defence: section("DEFENCE"), pct: max ? Math.round((1000 * sum) / max) / 10 : 0 };
  }, [d.lines, f.scores]);
  const complete = totals.missing === 0 && totals.over.length === 0 && !!f.final && f.general.trim().length >= 20;

  const setScore = (id: string, patch: Partial<{ score: string; comment: string }>) => { setDirty(true); setF({ ...f, scores: { ...f.scores, [id]: { ...(f.scores[id] ?? { score: "", comment: "" }), ...patch } } }); };
  const set = (patch: Partial<Draft>) => { setDirty(true); setF({ ...f, ...patch }); };

  async function call(path: string, method: "POST" | "PUT", body: unknown, reason: string, key: string): Promise<boolean> {
    setBusy(key); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/examiners/me/projects/${d.id}${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      if (!r.ok) { const p = (await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return false; }
      notify(reason);
      router.refresh();
      return true;
    } finally { setBusy(null); }
  }
  const payload = () => ({
    scores: d.lines.map((l) => ({ criterionId: l.criterion_id, score: (f.scores[l.criterion_id]?.score ?? "") === "" ? null : Number(f.scores[l.criterion_id].score), comment: f.scores[l.criterion_id]?.comment || null })),
    generalComments: f.general || null, strengths: f.strengths || null, weaknesses: f.weaknesses || null, recommendations: f.recommendations || null, corrections: f.corrections || null, finalRecommendation: f.final || null,
  });
  async function saveDraft() { if (await call("/assessment", "PUT", payload(), "Draft saved", "save")) setDirty(false); }
  async function submit() {
    setConfirm(false);
    if (!(await call("/assessment", "PUT", payload(), "Draft saved", "save"))) return;
    await call("/assessment/submit", "POST", {}, "Assessment submitted", "submit");
  }

  return (
    <>
      <PageHead eyebrow={`${d.kind === "POSTGRADUATE" ? "Postgraduate" : "Undergraduate"} project · ${d.session}`} title={d.title} description={`${d.student} (${d.number}) · ${d.programme}, ${d.department}`}
        actions={<><StatusPil status={d.status} />{d.overdue ? <Pil kind="bad">Overdue</Pil> : null}<LinkBtn href="/examiner/projects">My Projects</LinkBtn></>} />
      {problem ? <ProblemNotice problem={problem} /> : null}

      {readOnly ? (
        <Note kind={a?.state === "LOCKED" ? "ok" : "info"} title={a?.state === "LOCKED" ? "Your assessment has been approved and locked by the University" : "Your assessment has been submitted and is read-only"}>
          Submitted {when(a?.submitted_at)}. {a?.state === "LOCKED" ? "Thank you for your service as External Examiner." : "If the University needs a correction, the desk will reopen it and you will be told by email."}
        </Note>
      ) : a?.state === "REOPENED" ? (
        <Note kind="bad" title={`Reopened by the University on ${dayOf(a.reopened_at)}`}>{a.reopen_reason}<span className="blk sub2 mt-2">Your earlier scores and comments are kept. Revise what is needed and submit again.</span></Note>
      ) : (
        <Note kind="info" title={`Review deadline ${dayOf(d.deadline)} · ${daysWords(d.days_left, d.status)}`}>
          Score each line out of its maximum, add a comment where it helps, write your general comments and give a recommendation. Save the draft as often as you like; submit once when it is complete.
        </Note>
      )}

      <div className="grid grid--2">
        <Panel title="The candidate" right={d.faculty}>
          <PBody><KvGrid cls="grid--2" pairs={[["Name", <strong key="n">{d.student}</strong>], ["Student ID", <span key="m" className="tnum">{d.number}</span>], ["Programme", d.programme], ["Department", d.department], ["Faculty", d.faculty], ["Academic session", d.session]]} /></PBody>
        </Panel>
        <Panel title="The project" right={d.project_type ?? (d.kind === "POSTGRADUATE" ? "Postgraduate research" : "Final-year project")}>
          <PBody>
            <KvGrid cls="grid--2" pairs={[["Supervisor", d.supervisor ?? "—"], ["Co-supervisor", d.co_supervisor ?? "—"], ["Submitted", dayOf(d.submitted_on)], ["Examination date", d.exam_date ? dayOf(d.exam_date) : "—"], ["Keywords", d.keywords ?? "—"]]} />
            {d.abstract ? <><div className="hr" /><div className="eyebrow mb-1">Abstract</div><div style={{ whiteSpace: "pre-wrap" }}>{d.abstract}</div></> : null}
          </PBody>
        </Panel>
      </div>

      <Panel title="Documents" right={`${d.documents.length} released for external examination`}>
        <PBody><Documents items={d.documents} href={(x) => `/api/bff/api/v1/examiners/me/projects/${d.id}/documents/${x.id}/content`} /></PBody>
      </Panel>

      <Panel title={`Assessment · ${d.rubric.name}`} right={<span className="row row--inline row--tight"><span className="sub2">Total</span><strong className="tnum">{totals.sum} / {totals.max}</strong><span className="sub2 tnum">{totals.pct}%</span>{a?.grade && totals.missing === 0 ? <Pil kind="info">{a.grade}</Pil> : null}</span>}>
        {d.rubric.note ? <PBody><div className="sub2">{d.rubric.note}</div></PBody> : null}
        {(["WRITTEN", "DEFENCE"] as const).filter((s) => sections[s]?.length).map((s) => (
          <div key={s} className="tablewrap">
            <table className="tbl--data">
              <thead><tr><th>{s === "WRITTEN" ? "The written work" : "The defence"}</th><th className="mid">Maximum</th><th className="mid">Score</th><th>Comment</th></tr></thead>
              <tbody>
                {sections[s].map((l) => {
                  const v = f.scores[l.criterion_id] ?? { score: "", comment: "" };
                  const bad = v.score !== "" && (Number(v.score) > Number(l.max_score) || Number(v.score) < 0);
                  return (
                    <tr key={l.criterion_id}>
                      <td><strong>{l.name}</strong>{l.guidance ? <div className="sub2">{l.guidance}</div> : null}</td>
                      <td className="mid tnum">{Number(l.max_score)}</td>
                      <td className="mid">{readOnly ? <b className="tnum">{l.score ?? "—"}</b> : <input className={`ctl tnum${bad ? " is-error" : ""}`} style={{ width: 80, textAlign: "center" }} inputMode="decimal" value={v.score} onChange={(e) => setScore(l.criterion_id, { score: e.target.value.replace(/[^0-9.]/g, "") })} aria-label={`${l.name} score out of ${Number(l.max_score)}`} />}{bad ? <div className="ink-red t-xs">Over {Number(l.max_score)}</div> : null}</td>
                      <td>{readOnly ? <span className="sub2" style={{ whiteSpace: "pre-wrap" }}>{l.comment ?? "—"}</span> : <input className="ctl" value={v.comment} onChange={(e) => setScore(l.criterion_id, { comment: e.target.value })} placeholder="Optional" aria-label={`${l.name} comment`} />}</td>
                    </tr>
                  );
                })}
                <tr><td className="b600">{s === "WRITTEN" ? "Written work" : "Defence"} subtotal</td><td className="mid tnum b600">{s === "WRITTEN" ? totals.written.max : totals.defence.max}</td><td className="mid tnum b600">{s === "WRITTEN" ? totals.written.sum : totals.defence.sum}</td><td /></tr>
              </tbody>
            </table>
          </div>
        ))}
        <PBody>
          <div className="row row--base">
            <strong>Total</strong><span className="tnum b700">{totals.sum} of {totals.max}</span><span className="sub2 tnum">{totals.pct}%</span>
            {a?.grade && totals.missing === 0 && !dirty ? <span className="sub2">Grade {a.grade} on the University&rsquo;s scheme in force</span> : null}
            <span className="sub2">Computed from the scores; it is not typed.</span>
          </div>
        </PBody>
      </Panel>

      <Panel title="Comments and recommendation" right={f.final ? <RecommendationPil value={f.final} /> : "A recommendation is required"}>
        <PBody>
          <div className="stack">
            <Field id="rv-general" label="General comments" required hint="At least a sentence or two on the work as a whole">
              {readOnly ? <div style={{ whiteSpace: "pre-wrap" }}>{f.general || "—"}</div> : <textarea id="rv-general" className="ctl" rows={5} value={f.general} onChange={(e) => set({ general: e.target.value })} maxLength={8000} />}
            </Field>
            <div className="grid grid--2">
              <Field id="rv-str" label="Strengths">{readOnly ? <div style={{ whiteSpace: "pre-wrap" }}>{f.strengths || "—"}</div> : <textarea id="rv-str" className="ctl" rows={4} value={f.strengths} onChange={(e) => set({ strengths: e.target.value })} maxLength={4000} />}</Field>
              <Field id="rv-weak" label="Weaknesses">{readOnly ? <div style={{ whiteSpace: "pre-wrap" }}>{f.weaknesses || "—"}</div> : <textarea id="rv-weak" className="ctl" rows={4} value={f.weaknesses} onChange={(e) => set({ weaknesses: e.target.value })} maxLength={4000} />}</Field>
              <Field id="rv-rec" label="Recommendations">{readOnly ? <div style={{ whiteSpace: "pre-wrap" }}>{f.recommendations || "—"}</div> : <textarea id="rv-rec" className="ctl" rows={4} value={f.recommendations} onChange={(e) => set({ recommendations: e.target.value })} maxLength={4000} />}</Field>
              <Field id="rv-corr" label="Required corrections">{readOnly ? <div style={{ whiteSpace: "pre-wrap" }}>{f.corrections || "—"}</div> : <textarea id="rv-corr" className="ctl" rows={4} value={f.corrections} onChange={(e) => set({ corrections: e.target.value })} maxLength={4000} />}</Field>
            </div>
            <Field id="rv-final" label="Final recommendation" required>
              {readOnly ? <RecommendationPil value={f.final} /> : (
                <select id="rv-final" className="ctl" value={f.final} onChange={(e) => set({ final: e.target.value })} style={{ maxWidth: 360 }}>
                  <option value="">Choose…</option>
                  {Object.entries(RECOMMENDATION).map(([k, v]) => <option key={k} value={k}>{v[0]}</option>)}
                </select>
              )}
            </Field>
            {!readOnly ? (
              <div className="row row--base">
                <Btn kind="secondary" disabled={!!busy} onClick={() => void saveDraft()}>{busy === "save" ? "Saving…" : "Save Draft"}</Btn>
                <Btn kind="primary" disabled={!!busy || !complete} onClick={() => setConfirm(true)}>{a?.state === "REOPENED" ? "Resubmit Assessment" : "Submit Assessment"}</Btn>
                <span className="sub2">{!complete ? (totals.missing ? `${totals.missing} line${totals.missing === 1 ? "" : "s"} unscored. ` : "") + (totals.over.length ? `Over the maximum: ${totals.over.join(", ")}. ` : "") + (!f.final ? "Choose a recommendation. " : "") + (f.general.trim().length < 20 ? "Write general comments." : "") : dirty ? "Unsaved changes." : a ? `Draft saved ${when(a.saved_at)}.` : ""}</span>
              </div>
            ) : null}
          </div>
        </PBody>
      </Panel>

      <Panel title="History" right="What the University and you have done on this assignment">
        <PBody><History events={d.history} /></PBody>
      </Panel>

      {confirm ? (
        <Modal title="Submit this assessment?" sub={`${d.title} — ${d.student}`} onClose={() => setConfirm(false)}
          foot={<><Btn kind="ghost" onClick={() => setConfirm(false)}>Not Yet</Btn><Btn kind="go" disabled={!!busy} onClick={() => void submit()}>Yes, Submit</Btn></>}>
          <p className="m-0">Are you sure you want to submit this assessment?</p>
          <p className="m-0 mt-2">Once submitted, you may not be able to change your scores unless the authorised administrator reopens the assessment.</p>
          <p className="m-0 mt-2 sub2">Total {totals.sum} of {totals.max} ({totals.pct}%) · {RECOMMENDATION[f.final]?.[0] ?? f.final}</p>
        </Modal>
      ) : null}
    </>
  );
}
