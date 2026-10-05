"use client";
/** s/cbt — the student's CBT examinations (V322): the examinations on their registered GST and EPS courses with the clock's word, whether
 *  they may sit now and why not otherwise, the instructions acknowledged before the start, the attempt continued where it was, and the
 *  result once the office publishes it. The server judges eligibility at the start; the button only asks. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import type { Me } from "@/lib/student-portal";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notifyProblem } from "@/components/proto/Toast";
import { ATTEMPT_WORD, ELIGIBILITY_WORD, EXAM_WORD, codeOf, num, pct1, textOf, whenAt, type MyExam, type MyExams as Data } from "@/lib/cbt";

export const tokenKey = (attemptId: string) => `cbt-token:${attemptId}`;

export function MyExams({ data, s }: { data: Data; s: Me }) {
  const router = useRouter();
  const [open, setOpen] = useState<MyExam | null>(null);
  const [agreed, setAgreed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const rows = data.rows;
  const openNow = rows.filter((r) => r.live_state === "OPEN").length;
  const upcoming = rows.filter((r) => r.live_state === "UPCOMING").length;
  const published = rows.filter((r) => r.result_published && r.attempt_id).length;

  async function start(x: MyExam) {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/me/cbt/exams/${x.exam_id}/start`, { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return; }
      try { sessionStorage.setItem(tokenKey(j.attemptId), j.token); } catch { /* the room asks again if the key is not kept */ }
      router.push(`/student/cbt/room/${j.attemptId}`);
    } finally { setBusy(false); }
  }

  const eligibilityPill = (x: MyExam) => {
    if (x.attempt_status === "IN_PROGRESS") return <Pil kind="info">Attempt in progress</Pil>;
    if (!x.eligibility) return <Pil kind="ok">Eligible — you may start</Pil>;
    const code = codeOf(x.eligibility) ?? "";
    const kind = code === "GST_PAYMENT_REQUIRED" || code === "CBT_COURSE_NOT_REGISTERED" || code === "CBT_STUDENT_INACTIVE" ? "bad" : code === "CBT_EXAM_NOT_STARTED" ? "info" : "grey";
    return <Pil kind={kind}>{ELIGIBILITY_WORD[code] ?? textOf(x.eligibility)}</Pil>;
  };

  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Tiles items={[
        ["CBT EXAMINATIONS", num(rows.length), null, `${data.session} · your GST and EPS courses`],
        ["OPEN NOW", num(openNow), openNow ? "var(--green-ink)" : null, "Within the window"],
        ["UPCOMING", num(upcoming), null, "Published, not yet open"],
        ["RESULTS PUBLISHED", num(published), published ? "var(--green-ink)" : null, "Visible once the office publishes"],
      ]} />
      {rows.some((r) => codeOf(r.eligibility) === "GST_PAYMENT_REQUIRED") ? (
        <Note kind="bad" title="GST PAYMENT REQUIRED" action={<LinkBtn kind="primary" href="/student/gst">GST &amp; EPS</LinkBtn>}>You cannot start a GST CBT examination until your GST fee for the session is paid and confirmed. One payment covers both GST and EPS.</Note>
      ) : null}
      {!rows.length ? <Note kind="info" title="No CBT examination on your courses yet">A GST or EPS examination appears here once the office publishes it for a course on your submitted registration.</Note> : null}
      {rows.map((x) => {
        const live = x.live_state;
        const word = EXAM_WORD[live] ?? [live, "grey"];
        const canStart = !x.eligibility && live === "OPEN" && x.attempt_status !== "IN_PROGRESS";
        const canContinue = x.attempt_status === "IN_PROGRESS";
        return (
          <Panel key={x.exam_id} title={<span><b className="tnum">{x.course_code}</b> · {x.title}</span>} right={<span className="row row--inline row--tight"><Pil kind={word[1]}>{live === "OPEN" ? "NOW OPEN" : word[0]}</Pil>{x.attempt_status && x.attempt_status !== "IN_PROGRESS" ? <Pil kind={(ATTEMPT_WORD[x.attempt_status] ?? ["", "grey"])[1]}>{(ATTEMPT_WORD[x.attempt_status] ?? [x.attempt_status])[0]}</Pil> : null}</span>}>
            <PBody>
              <KvGrid cls="grid--4" pairs={[
                ["Date", whenAt(x.starts_at)], ["Closes", whenAt(x.ends_at)], ["Duration", `${x.duration_minutes} minutes`], ["Questions", `${x.questions}`],
                ["Course", x.course_title], ["Mode", x.security_mode === "SECURE" ? "Secure CBT / kiosk" : "Standard web CBT"], ["Venue", x.venue === "LAB" ? "CBT laboratory" : "Remote"], ["Standing", eligibilityPill(x)],
              ]} />
              {x.security_mode === "SECURE" ? <div className="sub2 mt-1">This examination is sat in the University&rsquo;s secure examination environment{x.venue === "LAB" ? " at the CBT laboratory" : ""}; it does not open in an ordinary browser.</div> : null}
              {x.eligibility && x.attempt_status !== "IN_PROGRESS" && codeOf(x.eligibility) !== "CBT_EXAM_NOT_OPEN" ? <div className="sub2 mt-1">{textOf(x.eligibility)}</div> : null}
              {x.result_published && x.attempt_id ? (
                <Note kind={x.outcome === "VOID" ? "bad" : x.passed ? "ok" : "info"} title={x.outcome === "VOID" ? "Result void" : `Result: ${pct1(x.percentage)} · grade ${x.grade ?? "—"} · ${x.passed ? "PASS" : "FAIL"}`}>
                  {x.score} of {x.max_marks} marks · pass mark {pct1(x.pass_mark)} · submitted {whenAt(x.submitted_at)}.
                </Note>
              ) : x.attempt_id && x.attempt_status !== "IN_PROGRESS" ? <div className="sub2 mt-1">Submitted {whenAt(x.submitted_at)}. Your result is published by the {x.office} office; you will be told.</div> : null}
              <div className="row row--inline row--tight mt-2">
                {canStart || canContinue ? <Btn kind="primary" disabled={busy} onClick={() => { setAgreed(false); setOpen(x); }}>{canContinue ? "CONTINUE EXAMINATION" : "VIEW INSTRUCTIONS & START"}</Btn> : <Btn kind="ghost" onClick={() => { setAgreed(false); setOpen(x); }}>View instructions</Btn>}
                {codeOf(x.eligibility) === "GST_PAYMENT_REQUIRED" ? <LinkBtn kind="go" href="/student/gst">PAY GST FEE</LinkBtn> : null}
                {codeOf(x.eligibility) === "CBT_COURSE_NOT_REGISTERED" ? <LinkBtn kind="secondary" href="/student/register">Course registration</LinkBtn> : null}
              </div>
            </PBody>
          </Panel>
        );
      })}

      {open ? (
        <Modal title="EXAM INSTRUCTIONS" sub={`${open.course_code} · ${open.title}`} wide onClose={() => setOpen(null)}
          foot={<span className="row row--inline row--tight">
            <Btn kind="ghost" onClick={() => setOpen(null)}>Close</Btn>
            {open.attempt_status === "IN_PROGRESS" || (!open.eligibility && open.live_state === "OPEN") ? (
              <Btn kind="go" disabled={busy || !agreed} onClick={() => { const x = open; setOpen(null); void start(x); }}>{busy ? "Opening…" : open.attempt_status === "IN_PROGRESS" ? "CONTINUE EXAM" : "START EXAM"}</Btn>
            ) : null}
          </span>}>
          <p>You are about to begin your <b>{open.course_code}</b> computer-based examination, <b>{open.title}</b>.</p>
          <KvGrid cls="grid--3" pairs={[["Duration", `${open.duration_minutes} minutes`], ["Questions", String(open.questions)], ["Attempts allowed", String(open.attempt_limit)]]} />
          <p className="mt-2"><b>Once the examination starts:</b></p>
          <ul>
            <li>Do not leave the examination screen.</li>
            <li>Do not switch browser tabs.</li>
            <li>Do not exit fullscreen mode.</li>
            <li>Do not attempt to open another window.</li>
            <li>Your activity is monitored.</li>
            <li>Violations are recorded. {open.violation_limit} {open.violation_limit === 1 ? "is" : "are"} allowed; beyond that {open.violation_action === "TERMINATE" ? "your examination is terminated" : open.violation_action === "SUBMIT" ? "your examination is submitted automatically" : "a final warning is issued and the record stands"} according to University policy.</li>
            <li>{open.partial_credit ? "On a multiple-select question each correct option you choose earns a share of the marks and each wrong one costs a share; a question never scores below zero." : "A multiple-select question earns its marks only when exactly the correct options are chosen."}</li>
            <li>Your answers are saved as you go. If your connection drops, remain on the screen while it reconnects; the clock keeps running on the server.</li>
            <li>The examination ends at the end of your time, or at the close of the window, whichever is earlier; whatever you have answered is submitted and scored.</li>
          </ul>
          {open.instructions ? <Note kind="info" title={`From the ${open.office} office`}>{open.instructions}</Note> : null}
          <label className="row row--inline row--tight mt-2"><input type="checkbox" checked={agreed} onChange={(e) => setAgreed(e.target.checked)} /> I have read the instructions and I am {s.surname} {s.otherNames} ({s.matricNo ?? s.admissionNo}).</label>
        </Modal>
      ) : null}
    </>
  );
}
