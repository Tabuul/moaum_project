"use client";
/** One CBT examination from the office's side (V322): its setup and lifecycle, its paper, its candidates, its results and analytics.
 *  Every action goes to the API, where the rules and the office's authority are judged; the screen only asks. */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tabs, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Problem } from "@/lib/api";
import { EXAM_WORD, RESULTS_WORD, num, pct1, textOf, whenAt, type CbtExam as Exam } from "@/lib/cbt";
import { EMPTY_FORM, ExamFields, formBody, localInput, type ExamForm } from "./CbtExams";
import { CbtCandidates } from "./CbtCandidates";
import { CbtResults } from "./CbtResults";

type Tab = "setup" | "paper" | "candidates" | "results";
interface BankQuestion { id: string; topic: string | null; stem: string; kind: string; difficulty: string; marks: number; active: boolean; on_papers: number; options: string[] }

export async function cbtSend(path: string, method: "POST" | "PUT", body: unknown, reason: string): Promise<Record<string, unknown> | null> {
  const r = await fetch(`/api/bff/api/v1/cbt${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
  const j = await r.json().catch(() => null);
  if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return null; }
  notify(reason);
  return j as Record<string, unknown>;
}

export function CbtExam({ exam, base, canManage, stronger, initialTab }: { exam: Exam; base: string; canManage: boolean; stronger: boolean; initialTab?: Tab }) {
  const router = useRouter();
  const [tab, setTab] = useState<Tab>(initialTab ?? "setup");
  const [busy, setBusy] = useState(false);
  const [f, setF] = useState<ExamForm>(() => ({
    ...EMPTY_FORM, title: exam.title, instructions: exam.instructions ?? "", durationMinutes: String(exam.duration_minutes), selection: exam.selection, totalQuestions: String(exam.total_questions),
    randomizeQuestions: exam.randomize_questions, randomizeOptions: exam.randomize_options, passMark: String(exam.pass_mark), attemptLimit: String(exam.attempt_limit),
    securityMode: exam.security_mode, venue: exam.venue, violationLimit: String(exam.violation_limit), violationAction: exam.violation_action, secondSession: exam.second_session,
    startsAt: localInput(exam.starts_at), endsAt: localInput(exam.ends_at),
  }));
  const [ask, setAsk] = useState<{ action: string; title: string; text: string; reason: boolean } | null>(null);
  const [reason, setReason] = useState("");
  const [bank, setBank] = useState<BankQuestion[] | null>(null);
  const [bankProblem, setBankProblem] = useState<Problem | null>(null);
  const [picked, setPicked] = useState<string[]>(() => exam.paper.map((p) => p.id));
  const [marks, setMarks] = useState<Record<string, string>>(() => Object.fromEntries(exam.paper.filter((p) => p.paper_marks != null).map((p) => [p.id, String(p.paper_marks)])));
  const editable = canManage && (exam.state === "DRAFT" || exam.state === "SCHEDULED");
  const live = exam.live_state;
  const counts = exam.counts;
  const stats = exam.stats;

  useEffect(() => {
    if (tab !== "paper" || bank) return;
    fetch(`/api/bff/api/v1/cbt/questions?course=${encodeURIComponent(exam.course_code)}`).then(async (r) => {
      const j = await r.json().catch(() => null);
      if (!r.ok) { setBankProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      setBank(j.rows as BankQuestion[]);
    }).catch((e) => setBankProblem({ status: 500, title: String(e) }));
  }, [tab, bank, exam.course_code]);

  async function run(work: () => Promise<Record<string, unknown> | null>) {
    setBusy(true);
    try { const j = await work(); if (j) router.refresh(); } finally { setBusy(false); }
  }
  const act = (action: string, why?: string) => run(() => cbtSend(`/exams/${exam.id}/${action}`, "POST", { reason: why ?? null }, `${action.charAt(0).toUpperCase() + action.slice(1)} ${exam.reference}`));
  const save = () => run(() => cbtSend(`/exams/${exam.id}`, "PUT", formBody(f), `Edit ${exam.reference}`));
  const savePaper = () => run(() => cbtSend(`/exams/${exam.id}/paper`, "PUT", { questions: picked.map((id) => ({ id, marks: marks[id] ? Number(marks[id]) : null })) }, `Set the paper of ${exam.reference}: ${picked.length} question${picked.length === 1 ? "" : "s"}`));
  const toggle = (id: string) => setPicked((p) => (p.includes(id) ? p.filter((x) => x !== id) : [...p, id]));
  const move = (id: string, by: number) => setPicked((p) => { const i = p.indexOf(id); const j = i + by; if (i < 0 || j < 0 || j >= p.length) return p; const n = [...p]; n.splice(i, 1); n.splice(j, 0, id); return n; });

  const actions: { action: string; label: string; kind: "primary" | "secondary" | "ghost" | "go" | "urgent"; when: boolean; confirm: string; reason?: boolean }[] = [
    { action: "schedule", label: "Schedule", kind: "secondary", when: exam.state === "DRAFT", confirm: "Mark the examination as scheduled for its window. Candidates are not yet told; publishing tells them." },
    { action: "publish", label: "Publish to candidates", kind: "go", when: exam.state === "DRAFT" || exam.state === "SCHEDULED", confirm: "Every student registered on the offering is told by e-mail of the date, time and duration. The paper and the rules are then fixed; only the closing time and the instructions can still change." },
    { action: "unpublish", label: "Withdraw", kind: "ghost", when: exam.state === "PUBLISHED" && counts.candidates - counts.not_started === 0, confirm: "Withdraw the examination to scheduled. Possible only while nobody has started." },
    { action: "close", label: "Close now", kind: "urgent", when: exam.state === "PUBLISHED" && (live === "OPEN" || live === "ENDED"), confirm: "Close the window now: no further start, and every attempt still running is submitted as it stands and scored." },
    { action: "complete", label: "Complete", kind: "primary", when: exam.state === "CLOSED" || (exam.state === "PUBLISHED" && live === "ENDED"), confirm: "Complete the examination: any attempt still open is finalised at time expired, and the results move to auto-scored for review." },
    { action: "cancel", label: "Cancel examination", kind: "urgent", when: exam.state !== "COMPLETED" && exam.state !== "CANCELLED", confirm: "Cancel the examination. Attempts in progress are terminated and candidates who were told of it are told of the cancellation. Give the reason.", reason: true },
  ];

  return (
    <>
      <PageHead eyebrow={<span className="tnum">{exam.reference} · {exam.session} · semester {exam.semester}</span>} title={exam.title}
        description={<span><b className="tnum">{exam.course_code}</b> {exam.course_title} · {exam.duration_minutes} minutes · {exam.selection === "RANDOM" ? `${exam.total_questions} questions drawn from ${num(exam.pool_size)}` : `${num(exam.pool_size)} questions`} · {num(exam.pool_marks)} marks · pass mark {pct1(exam.pass_mark)} · {exam.security_mode === "SECURE" ? "secure/kiosk CBT" : "standard web CBT"} · {exam.venue === "LAB" ? "CBT laboratory" : "remote"}</span>}
        actions={<span className="row row--inline row--tight">
          <Pil kind={(EXAM_WORD[live] ?? ["", "grey"])[1]}>{(EXAM_WORD[live] ?? [live])[0]}</Pil>
          <Pil kind={(RESULTS_WORD[exam.results_state] ?? ["", "grey"])[1]}>Results: {(RESULTS_WORD[exam.results_state] ?? [exam.results_state])[0].toLowerCase()}</Pil>
          {live === "OPEN" || counts.in_progress > 0 ? <LinkBtn kind="go" href={`${base}/cbt/${exam.id}/monitor`}>Live monitor</LinkBtn> : null}
          <LinkBtn kind="ghost" href={`${base}/cbt?session=${encodeURIComponent(exam.session)}`}>All examinations</LinkBtn>
        </span>} />
      {exam.paper_problem && exam.state !== "COMPLETED" && exam.state !== "CANCELLED" ? <Note kind="bad" title="The paper is not ready">{textOf(exam.paper_problem)}. Set the paper before publishing.</Note> : null}
      {exam.state === "CANCELLED" ? <Note kind="bad" title={`Cancelled ${whenAt(exam.cancelled_at)}`}>{exam.cancel_reason}</Note> : null}
      {exam.security_mode === "SECURE" ? <Note kind="info" title="Secure / kiosk mode">Candidates sit this examination in the approved secure examination environment (a secure exam browser, a kiosk, a managed CBT laboratory). A standard browser cannot guarantee that a candidate does not switch to another application or device; the secure environment does.</Note> : null}
      <Tiles items={[
        ["CANDIDATES", num(counts.candidates), null, `${num(counts.eligible)} eligible now`],
        ["WRITING", num(counts.in_progress), counts.in_progress ? "var(--green-ink)" : null, `${num(counts.disconnected)} disconnected`],
        ["COMPLETED", num(stats.completed), null, `${num(counts.submitted)} submitted · ${num(counts.time_expired)} time expired · ${num(counts.terminated)} terminated`],
        ["NOT STARTED", num(counts.not_started), null, "Registered, no attempt yet"],
        ["SCORES", num(counts.scored), null, stats.average != null ? `Average ${pct1(stats.average)}` : "None yet"],
        ["PASSED", num(stats.passed), stats.passed ? "var(--green-ink)" : null, `${num(stats.failed)} failed · ${num(stats.void)} void`],
        ["VIOLATIONS", num(counts.warned), counts.critical ? "var(--red-ink)" : null, `${num(counts.critical)} at or over the limit of ${exam.violation_limit}`],
        ["WINDOW", exam.starts_at ? whenAt(exam.starts_at) : "Not dated", null, exam.ends_at ? `to ${whenAt(exam.ends_at)}` : "Set the opening and closing time"],
      ]} />
      <Tabs label="Examination" value={tab} onChange={setTab} items={[
        { id: "setup", label: "Setup & lifecycle" }, { id: "paper", label: "Paper", count: exam.paper.length || undefined },
        { id: "candidates", label: "Candidates", count: num(counts.candidates) }, { id: "results", label: "Results & analytics", count: num(counts.scored) },
      ]} />

      {tab === "setup" ? (
        <>
          <Panel title="Configuration" right={editable ? <Btn kind="primary" disabled={busy || !f.title.trim()} onClick={() => void save()}>{busy ? "Saving…" : "Save changes"}</Btn> : exam.state === "PUBLISHED" && canManage ? <Btn kind="secondary" disabled={busy} onClick={() => void save()}>Save closing time & instructions</Btn> : <span className="sub2">Read only</span>}>
            <PBody>
              {exam.state === "PUBLISHED" ? <div className="sub2 mb-2">The examination is published: its paper and rules are fixed. The title, the instructions and the closing time may still change.</div> : null}
              <ExamFields f={f} set={(p) => setF({ ...f, ...p })} locked={!editable} />
            </PBody>
          </Panel>
          <Panel title="Lifecycle" right={<span className="sub2">Created {whenAt(exam.created_at)}{exam.created_by_name ? ` by ${exam.created_by_name}` : ""}{exam.created_office ? ` (${exam.created_office})` : ""}</span>}>
            <PBody>
              <KvGrid cls="grid--4" pairs={[["State", (EXAM_WORD[exam.state] ?? [exam.state])[0]], ["Published", whenAt(exam.published_at)], ["Closed", whenAt(exam.closed_at)], ["Completed", whenAt(exam.completed_at)]]} />
              {canManage ? (
                <div className="row row--inline row--tight mt-2" style={{ flexWrap: "wrap" }}>
                  {actions.filter((a) => a.when).map((a) => <Btn key={a.action} kind={a.kind} disabled={busy} onClick={() => { setReason(""); setAsk({ action: a.action, title: a.label, text: a.confirm, reason: !!a.reason }); }}>{a.label}</Btn>)}
                </div>
              ) : null}
              <div className="sub2 mt-2">Draft → scheduled → published (candidates told) → open by the clock → closed → completed (results auto-scored, then reviewed, approved and published). The clock opens and ends the window; the office closes early and completes.</div>
            </PBody>
          </Panel>
        </>
      ) : null}

      {tab === "paper" ? (
        <Panel title={exam.selection === "RANDOM" ? `The pool · ${picked.length ? `${picked.length} chosen` : `the course's whole active bank (${num(exam.pool_size)})`}` : `The paper · ${picked.length} question${picked.length === 1 ? "" : "s"}`}
          right={editable ? <span className="row row--inline row--tight"><Btn kind="ghost" disabled={busy || !bank} onClick={() => setPicked(bank ? bank.filter((q) => q.active).map((q) => q.id) : picked)}>Pick every active question</Btn><Btn kind="ghost" disabled={busy || !picked.length} onClick={() => setPicked([])}>Clear</Btn><Btn kind="primary" disabled={busy} onClick={() => void savePaper()}>{busy ? "Saving…" : "Save the paper"}</Btn></span> : <span className="sub2">Fixed{exam.state === "PUBLISHED" ? " since publication" : ""}</span>}>
          <PBody>
            {bankProblem ? <ProblemNotice problem={bankProblem} /> : null}
            <div className="sub2 mb-2">
              {exam.selection === "RANDOM"
                ? `Each candidate draws ${exam.total_questions} questions from the pool by their own seed. Leave the pool empty to draw from the course's whole active bank, or pick the questions it draws from. `
                : "The questions in the order listed; shuffled per candidate when the question order says so. "}
              Marks come from the bank unless overridden on the paper. The correct options never leave the server. <LinkBtn kind="ghost" size="sm" href={`${base}/question-bank?course=${encodeURIComponent(exam.course_code)}`}>Open the {exam.course_code} bank</LinkBtn>
            </div>
            {!bank ? <div className="sub2">Loading the bank…</div> : (
              <DTable pageSize={50} cols={["On paper|mid", "#|mid", "Question", "Topic|mid", "Kind|mid", "Difficulty|mid", "Marks|num", "Order|mid"]} rows={[...bank].sort((a, b) => (picked.indexOf(a.id) === -1 ? 1e9 : picked.indexOf(a.id)) - (picked.indexOf(b.id) === -1 ? 1e9 : picked.indexOf(b.id))).map((q) => {
                const on = picked.includes(q.id);
                return [
                  <input key="c" type="checkbox" checked={on} disabled={!editable || (!q.active && !on)} onChange={() => toggle(q.id)} aria-label={`Include ${q.stem}`} />,
                  <span key="n" className="tnum sub2">{on ? picked.indexOf(q.id) + 1 : "—"}</span>,
                  <span key="s">{q.stem}{!q.active ? <Pil kind="grey" className="ml-1">retired</Pil> : null}<div className="sub2">{q.options.length} options{q.on_papers ? ` · on ${q.on_papers} paper${q.on_papers === 1 ? "" : "s"}` : ""}</div></span>,
                  <span key="t" className="sub2">{q.topic ?? "—"}</span>,
                  <span key="k" className="sub2">{q.kind === "MULTI" ? "Multiple select" : q.kind === "TRUE_FALSE" ? "True / false" : "Multiple choice"}</span>,
                  <span key="d" className="sub2">{q.difficulty.charAt(0) + q.difficulty.slice(1).toLowerCase()}</span>,
                  editable && on ? <input key="m" className="ctl tnum" style={{ width: 64 }} inputMode="numeric" placeholder={String(q.marks)} value={marks[q.id] ?? ""} onChange={(e) => setMarks({ ...marks, [q.id]: e.target.value.replace(/[^0-9]/g, "") })} aria-label="Marks on this paper" /> : <span key="m" className="tnum">{marks[q.id] || q.marks}</span>,
                  editable && on && exam.selection === "FIXED" ? <span key="o" className="row row--inline row--tight"><Btn kind="ghost" size="sm" onClick={() => move(q.id, -1)}>↑</Btn><Btn kind="ghost" size="sm" onClick={() => move(q.id, 1)}>↓</Btn></span> : <span key="o" />,
                ];
              })} texts={bank.map((q) => `${q.stem} ${q.topic ?? ""} ${q.kind}`)} />
            )}
          </PBody>
        </Panel>
      ) : null}

      {tab === "candidates" ? <CbtCandidates exam={exam} base={base} canManage={canManage} /> : null}
      {tab === "results" ? <CbtResults exam={exam} base={base} canManage={canManage} stronger={stronger} /> : null}

      {ask ? (
        <Modal title={ask.title} sub={exam.reference} onClose={() => setAsk(null)}
          foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setAsk(null)}>Back</Btn><Btn kind={ask.action === "cancel" || ask.action === "close" ? "urgent" : "primary"} disabled={busy || (ask.reason && !reason.trim())} onClick={() => { const a = ask; setAsk(null); void act(a.action, a.reason ? reason.trim() : undefined); }}>{ask.title}</Btn></span>}>
          <p>{ask.text}</p>
          {ask.reason ? <Field id="x-reason" label="Reason" required><textarea id="x-reason" className="ctl" rows={2} value={reason} onChange={(e) => setReason(e.target.value)} /></Field> : null}
        </Modal>
      ) : null}
    </>
  );
}
