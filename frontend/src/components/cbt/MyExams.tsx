"use client";
/** s/cbt — the student's CBT examinations (V322; every CBT course from V364): the examinations on their registered CBT courses with the clock's word, whether
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
import { printSlips, type Slip } from "@/lib/cbt-slip";
import { ATTEMPT_WORD, ELIGIBILITY_WORD, EXAM_TYPE_WORD, EXAM_WORD, codeOf, num, pct1, textOf, whenAt, type MyExam, type MyExams as Data } from "@/lib/cbt";

export const tokenKey = (attemptId: string) => `cbt-token:${attemptId}`;

/** the candidate who acknowledges the instructions: a University student (s) or, from V365, a JUPEB student (who) — and the door their examinations are behind */
export function MyExams({ data, s, who, apiBase = "/api/bff/api/v1/me/cbt", roomBase = "/student/cbt/room", feesHref = "/student/fees" }: {
  data: Data; s?: Me; who?: { name: string; number: string }; apiBase?: string; roomBase?: string; feesHref?: string;
}) {
  const person = who ?? { name: s ? `${s.surname} ${s.otherNames}` : "", number: s ? s.matricNo ?? s.admissionNo ?? "" : "" };
  const router = useRouter();
  const [open, setOpen] = useState<MyExam | null>(null);
  const [agreed, setAgreed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const rows = data.rows;
  const openNow = rows.filter((r) => r.live_state === "OPEN").length;
  const upcoming = rows.filter((r) => r.live_state === "UPCOMING").length;
  const published = rows.filter((r) => r.result_published && r.attempt_id).length;

  /* V375: the slip shown at the door of the sitting, its QR signed by the portal */
  async function printSlip(x: MyExam) {
    const r = await fetch(`${apiBase}/exams/${x.exam_id}/slip`);
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
    await printSlips("CBT slip", `${x.course_code} · ${x.title}`, [j as Slip]);
  }

  async function start(x: MyExam) {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`${apiBase}/exams/${x.exam_id}/start`, { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return; }
      try { sessionStorage.setItem(tokenKey(j.attemptId), j.token); } catch { /* the room asks again if the key is not kept */ }
      router.push(`${roomBase}/${j.attemptId}`);
    } finally { setBusy(false); }
  }

  const eligibilityPill = (x: MyExam) => {
    if (x.attempt_status === "IN_PROGRESS") return <Pil kind="info">Attempt in progress</Pil>;
    if (!x.eligibility) return <Pil kind="ok">Eligible — you may start</Pil>;
    const code = codeOf(x.eligibility) ?? "";
    const kind = code === "GST_PAYMENT_REQUIRED" || code === "CBT_FEES_NOT_CLEARED" || code === "CBT_JUPEB_FEES" || code === "CBT_COURSE_NOT_REGISTERED" || code === "CBT_JUPEB_SUBJECT_NOT_REGISTERED" || code === "CBT_STUDENT_INACTIVE" || code === "CBT_JUPEB_NOT_STUDENT" ? "bad" : code === "CBT_EXAM_NOT_STARTED" ? "info" : "grey";
    return <Pil kind={kind}>{ELIGIBILITY_WORD[code] ?? textOf(x.eligibility)}</Pil>;
  };

  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Tiles items={[
        ["CBT EXAMINATIONS", num(rows.length), null, `${data.session} · your CBT courses`],
        ["OPEN NOW", num(openNow), openNow ? "var(--green-ink)" : null, "Within the window"],
        ["UPCOMING", num(upcoming), null, "Published, not yet open"],
        ["RESULTS PUBLISHED", num(published), published ? "var(--green-ink)" : null, "Visible once the office publishes"],
      ]} />
      {rows.some((r) => codeOf(r.eligibility) === "GST_PAYMENT_REQUIRED") ? (
        <Note kind="bad" title="GST PAYMENT REQUIRED" action={<LinkBtn kind="primary" href="/student/gst">GST &amp; EPS</LinkBtn>}>You cannot start a GST CBT examination until your GST fee for the session is paid and confirmed. One payment covers both GST and EPS.</Note>
      ) : null}
      {rows.some((r) => codeOf(r.eligibility) === "CBT_FEES_NOT_CLEARED") ? (
        <Note kind="bad" title="SCHOOL FEES NOT CLEARED" action={<LinkBtn kind="primary" href={feesHref}>Fees &amp; payments</LinkBtn>}>A CBT examination of a University course is sat once the session&rsquo;s school fees are cleared for examinations.</Note>
      ) : null}
      {rows.some((r) => codeOf(r.eligibility) === "CBT_JUPEB_FEES") ? (
        <Note kind="bad" title="JUPEB SCHOOL FEE NOT PAID" action={<LinkBtn kind="primary" href={feesHref}>Payments</LinkBtn>}>A JUPEB CBT examination is sat once the semester&rsquo;s share of your JUPEB school fee is paid.</Note>
      ) : null}
      {!rows.length ? <Note kind="info" title="No CBT examination on your courses yet">An examination appears here once the examining office publishes it for a course on your submitted registration.</Note> : null}
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
                ["Course", x.course_title], ["Mode", x.security_mode === "SECURE" ? "Secure CBT / kiosk" : x.proctoring === "CAMERA" ? "Web CBT, camera by consent" : "Standard web CBT"], ["Venue", x.venue === "LAB" ? "CBT laboratory" : "Remote"], ["Standing", eligibilityPill(x)],
              ]} />
              {/* V373: the candidate's own sitting — the examination opens to them only then — and any extra time */}
              {x.sitting ? (
                <Note kind="info" title={`Your sitting: ${x.sitting}${x.seat_no ? ` · seat ${x.seat_no}` : ""}`}>
                  {x.sitting_venue} · {whenAt(x.sitting_starts_at)}{x.sitting_ends_at ? ` to ${new Date(x.sitting_ends_at).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" })}` : ""}. The examination opens to you only in your sitting; come to the venue in good time.
                  {/* V374: the office's late-entry limit, when it set one */}
                  {x.late_entry_until && x.attendance !== "LATE" ? <> You may start on your own until <b>{new Date(x.late_entry_until).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" })}</b>; after that, only once the invigilator admits you.</> : null}
                  <div className="mt-1"><Btn kind="secondary" size="sm" onClick={() => void printSlip(x)}>Print your CBT slip</Btn> <span className="sub2">Bring it to the door: the invigilator scans it and checks your face against your photograph.</span></div>
                </Note>
              ) : null}
              {x.attendance === "ABSENT" ? <Note kind="bad" title="Marked absent">The invigilator marked you absent from your sitting, so the examination does not open to you. If you are in the hall, ask the invigilator to admit you.</Note> : null}
              {x.attendance === "LATE" ? <div className="sub2 mt-1">The invigilator admitted you late{x.late_minutes_given ? <>, with <b>{x.late_minutes_given} minutes</b> given back</> : null}.</div> : null}
              {x.extra_minutes ? <div className="sub2 mt-1">You have <b>{x.extra_minutes} minutes&rsquo; extra time</b> on this paper; your clock includes it.</div> : null}
              {x.security_mode === "SECURE" ? <div className="sub2 mt-1">This examination is sat in the University&rsquo;s secure examination environment{x.venue === "LAB" ? " at the CBT laboratory" : ""}; it does not open in an ordinary browser.</div> : null}
              {x.eligibility && x.attempt_status !== "IN_PROGRESS" && codeOf(x.eligibility) !== "CBT_EXAM_NOT_OPEN" ? <div className="sub2 mt-1">{textOf(x.eligibility)}</div> : null}
              {x.result_published && x.attempt_id ? (
                <Note kind={x.outcome === "VOID" ? "bad" : x.passed ? "ok" : "info"} title={x.outcome === "VOID" ? "Result void" : `Result: ${pct1(x.percentage)} · grade ${x.grade ?? "—"} · ${x.passed ? "PASS" : "FAIL"}`}>
                  {x.score} of {x.max_marks} marks · pass mark {pct1(x.pass_mark)} · submitted {whenAt(x.submitted_at)}.
                </Note>
              ) : x.attempt_id && x.attempt_status !== "IN_PROGRESS" && x.score != null ? (
                <Note kind={x.outcome === "VOID" ? "bad" : "info"} title={`Score: ${x.score} of ${x.max_marks} · ${pct1(x.percentage)}`}>Released on submission by this examination&rsquo;s rules. The result is final once the office publishes it.</Note>
              ) : x.attempt_id && x.attempt_status !== "IN_PROGRESS" ? <div className="sub2 mt-1">Submitted {whenAt(x.submitted_at)}. Your result has been recorded and will be released according to University examination policy.</div> : null}
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
          <p>You are about to begin your <b>{open.course_code}</b> computer-based {EXAM_TYPE_WORD[open.exam_type ?? "EXAMINATION"].toLowerCase()}, <b>{open.title}</b>.</p>
          <KvGrid cls="grid--3" pairs={[["Duration", `${open.duration_minutes} minutes`], ["Questions", String(open.questions)], ["Attempts allowed", String(open.attempt_limit)]]} />
          <p className="mt-2"><b>Once the examination starts:</b></p>
          <ul>
            <li>Do not leave the examination screen.</li>
            <li>Do not switch browser tabs.</li>
            {open.fullscreen_required !== false ? <li>Do not exit fullscreen mode.</li> : null}
            <li>Do not attempt to open another window.</li>
            <li>Your activity is monitored.</li>
            <li>Violations are recorded. {open.violation_limit} {open.violation_limit === 1 ? "is" : "are"} allowed; beyond that {open.violation_action === "TERMINATE" ? "your examination is terminated" : open.violation_action === "SUBMIT" ? "your examination is submitted automatically" : "a final warning is issued and the record stands"} according to University policy.</li>
            <li>{open.partial_credit ? "On a multiple-select question each correct option you choose earns a share of the marks and each wrong one costs a share; a question never scores below zero." : "A multiple-select question earns its marks only when exactly the correct options are chosen."}</li>
            {Number(open.negative_marks ?? 0) > 0 ? <li>Negative marking: a wrong answer costs {open.negative_marks} mark{Number(open.negative_marks) === 1 ? "" : "s"}; a question left unanswered costs nothing. Your total never falls below nought.</li> : null}
            {open.allow_back === false ? <li>This paper moves forward only: once you move to the next question you cannot return to an earlier one.</li> : open.allow_review !== false ? <li>You may mark questions for review and return to them before you submit.</li> : null}
            {open.proctoring === "CAMERA" ? <li>This examination uses your camera, with your consent asked first, to report face signals to the office. No video or picture is kept; the microphone is not used.</li> : null}
            <li>{open.score_on_submit ? "Your score is shown when you submit; the result is final once the office publishes it." : "Your score is not shown when you submit; your result is released according to University examination policy."}</li>
            <li>Your answers are saved as you go. If your connection drops, remain on the screen while it reconnects; the clock keeps running on the server.</li>
            <li>The examination ends at the end of your time, or at the close of the window, whichever is earlier; whatever you have answered is submitted and scored.</li>
          </ul>
          {open.instructions ? <Note kind="info" title={open.office === "EXAMS" ? "From the examining office" : open.office === "JUPEB" ? "From the JUPEB Office" : `From the ${open.office} office`}>{open.instructions}</Note> : null}
          <label className="row row--inline row--tight mt-2"><input type="checkbox" checked={agreed} onChange={(e) => setAgreed(e.target.checked)} /> I have read the instructions and I am {person.name} ({person.number}).</label>
        </Modal>
      ) : null}
    </>
  );
}
