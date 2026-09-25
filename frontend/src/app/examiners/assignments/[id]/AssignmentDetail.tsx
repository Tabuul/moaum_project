"use client";
/** One assignment on the desk (V254): the examiner's assessment read in full, approved and locked, or reopened on a
 *  reason; the documents the examiner was given; the whole history. The desk never types a score. */
import Link from "next/link";
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Documents, History, RecommendationPil, StatusPil, dayOf, daysWords, when, type Assessment, type AssignmentRow, type Doc, type Event, type Line } from "@/lib/examiners";

export interface AssignmentFull extends AssignmentRow { assessment: { assessment: Assessment | null; lines: Line[] }; documents: Doc[]; history: Event[] }

export function AssignmentDetail({ a }: { a: AssignmentFull }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [reopen, setReopen] = useState<string | null>(null);
  const s = a.assessment.assessment;
  const lines = a.assessment.lines;
  const written = lines.filter((l) => l.section === "WRITTEN"); const defence = lines.filter((l) => l.section === "DEFENCE");
  const sum = (ls: Line[]) => ls.reduce((acc, l) => acc + Number(l.score ?? 0), 0);
  const max = (ls: Line[]) => ls.reduce((acc, l) => acc + Number(l.max_score), 0);

  async function post(path: string, body: unknown, reason: string): Promise<boolean> {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/examiners${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      if (!r.ok) { const p = (await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return false; }
      notify(reason); router.refresh(); return true;
    } finally { setBusy(false); }
  }

  return (
    <>
      <PageHead eyebrow={`${a.kind === "POSTGRADUATE" ? "Postgraduate" : "Undergraduate"} project · ${a.session}`} title={a.title} description={`${a.student} (${a.number}) · ${a.programme}, ${a.department} · examiner ${a.examiner}, ${a.institution}`}
        actions={<><StatusPil status={a.status} />{a.overdue ? <Pil kind="bad">Overdue</Pil> : null}<LinkBtn href={`/examiners/projects/${a.project_id}`}>The Project</LinkBtn><LinkBtn href="/examiners/assignments">All Assignments</LinkBtn></>} />
      {problem && reopen === null ? <ProblemNotice problem={problem} /> : null}

      {s?.state === "SUBMITTED" ? (
        <Note kind="ok" title={`Submitted ${when(s.submitted_at)}${s.version > 1 ? ` (version ${s.version})` : ""}`} action={<span className="row row--tight"><Btn kind="go" disabled={busy} onClick={() => { if (window.confirm("Approve and lock this assessment? The examiner can no longer change it.")) void post(`/assessments/${s.id}/lock`, {}, "Assessment approved and locked"); }}>Approve and Lock</Btn><Btn kind="ghost" disabled={busy} onClick={() => setReopen("")}>Reopen</Btn></span>}>
          The assessment is read-only to the examiner. Lock it once the department has read it; reopen it on a reason if the examiner must revise it.
        </Note>
      ) : s?.state === "LOCKED" ? (
        <Note kind="ok" title={`Locked ${when(s.locked_at)}`} action={<Btn kind="ghost" disabled={busy} onClick={() => setReopen("")}>Reopen</Btn>}>Approved by the University. It feeds moderation under the results workflow; it does not itself change a result.</Note>
      ) : s?.state === "REOPENED" ? (
        <Note kind="bad" title={`Reopened ${when(s.reopened_at)} for revision`}>{s.reopen_reason}<span className="blk sub2 mt-2">The examiner has been told and can revise and resubmit.</span></Note>
      ) : (
        <Note kind="info" title={a.status === "ASSIGNED" ? "The examiner has not started" : "In review"}>
          {a.first_viewed_at ? `The examiner first opened the project ${when(a.first_viewed_at)}. ` : "The examiner has not opened the project yet. "}Deadline {dayOf(a.deadline)}, {daysWords(a.days_left, a.status).toLowerCase()}.{s ? ` Draft last saved ${when(s.saved_at)}.` : ""}
        </Note>
      )}

      <div className="grid grid--2">
        <Panel title="The assignment" right={a.rubric}>
          <PBody><KvGrid cls="grid--2" pairs={[["Examiner", <Link key="e" className="lnk" href={`/examiners/${a.examiner_id}`}>{a.examiner}</Link>], ["Institution", a.institution], ["Assigned", `${dayOf(a.assigned_at)}${a.assigned_by ? ` by ${a.assigned_by}` : ""}`], ["Review deadline", dayOf(a.deadline)], ["Examination date", a.exam_date ? dayOf(a.exam_date) : "—"], ["Supervisor", a.supervisor ?? "—"], ["Project submitted", dayOf(a.submitted_on)], ["Faculty", a.faculty]]} /></PBody>
        </Panel>
        <Panel title="Documents the examiner was given" right={`${a.documents.filter((d) => d.released !== false).length} released`}>
          <PBody><Documents items={a.documents} href={(d) => `/api/bff/api/v1/examiners/projects/${a.project_id}/documents/${d.id}/content`} /></PBody>
        </Panel>
      </div>

      <Panel title="The assessment" right={s?.total != null ? <span className="row row--inline row--tight"><strong className="tnum">{s.total} / {s.max_total}</strong><span className="sub2 tnum">{s.percentage}%</span>{s.grade ? <Pil kind="info">Grade {s.grade}</Pil> : null}<RecommendationPil value={s.final_recommendation} /></span> : "Nothing submitted yet"}>
        {s ? (
          <>
            {[["The written work", written], ["The defence", defence]].filter(([, ls]) => (ls as Line[]).length).map(([title, ls]) => (
              <div key={String(title)} className="tablewrap">
                <table className="tbl--data">
                  <thead><tr><th>{String(title)}</th><th className="mid">Maximum</th><th className="mid">Score</th><th>Examiner&rsquo;s comment</th></tr></thead>
                  <tbody>
                    {(ls as Line[]).map((l) => <tr key={l.criterion_id}><td><strong>{l.name}</strong>{l.guidance ? <div className="sub2">{l.guidance}</div> : null}</td><td className="mid tnum">{Number(l.max_score)}</td><td className="mid tnum b600">{l.score ?? "—"}</td><td className="sub2" style={{ whiteSpace: "pre-wrap" }}>{l.comment ?? "—"}</td></tr>)}
                    <tr><td className="b600">Subtotal</td><td className="mid tnum b600">{max(ls as Line[])}</td><td className="mid tnum b600">{sum(ls as Line[])}</td><td /></tr>
                  </tbody>
                </table>
              </div>
            ))}
            <PBody>
              <KvGrid cls="grid--2" pairs={[["General comments", <span key="g" style={{ whiteSpace: "pre-wrap" }}>{s.general_comments ?? "—"}</span>], ["Strengths", <span key="s" style={{ whiteSpace: "pre-wrap" }}>{s.strengths ?? "—"}</span>], ["Weaknesses", <span key="w" style={{ whiteSpace: "pre-wrap" }}>{s.weaknesses ?? "—"}</span>], ["Recommendations", <span key="r" style={{ whiteSpace: "pre-wrap" }}>{s.recommendations ?? "—"}</span>], ["Required corrections", <span key="c" style={{ whiteSpace: "pre-wrap" }}>{s.corrections ?? "—"}</span>], ["Final recommendation", <RecommendationPil key="f" value={s.final_recommendation} />]]} />
            </PBody>
          </>
        ) : <PBody><div className="sub2">The examiner has not started the assessment. Its lines follow the form {a.rubric}.</div></PBody>}
      </Panel>

      <Panel title="History" right="Every act on this assignment, written once"><PBody><History events={a.history} /></PBody></Panel>

      {reopen !== null && s ? (
        <Modal title="Reopen the assessment" sub={`${a.examiner} is told and may revise; the earlier version stays on the history`} onClose={() => setReopen(null)}
          foot={<><Btn kind="ghost" onClick={() => setReopen(null)}>Cancel</Btn><Btn kind="urgent" disabled={busy || reopen.trim().length < 5} onClick={async () => { if (await post(`/assessments/${s.id}/reopen`, { reason: reopen.trim() }, "Assessment reopened")) setReopen(null); }}>Reopen</Btn></>}>
          {problem ? <ProblemNotice problem={problem} /> : null}
          <Field id="ro-reason" label="Reason" required><textarea id="ro-reason" className="ctl" rows={3} value={reopen} onChange={(e) => setReopen(e.target.value)} /></Field>
        </Modal>
      ) : null}
    </>
  );
}
