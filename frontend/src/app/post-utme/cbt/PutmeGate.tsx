"use client";
/** V385: the Post-UTME CBT door. The candidate gives the JAMB registration number and the verification the examination names; the
 *  server answers yes or no and never which part was wrong. A yes shows what the server knows them as, their examination and its rules,
 *  and the confirmation before the start; the start opens the examination room. No dashboard, no password, no score here. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { Btn, LinkBtn, Note, PageHead, Pil } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";
import { AuthLayout } from "@/components/auth/AuthLayout";
import { tokenKey } from "@/components/cbt/MyExams";
import { ELIGIBILITY_WORD, codeOf, textOf, whenAt, type MyExam } from "@/lib/cbt";
import type { PutmePublic } from "@/lib/putme-cbt";

type Verified = { candidate: { name: string; jambRegNo: string; applicationNo: string | null; programme: string | null }; session: string; exams: MyExam[]; expiresAt: string };

const REG_SHAPE = /^\d{8,12}[A-Z]{1,3}$/i;

export function PutmeGate({ state }: { state: PutmePublic }) {
  const router = useRouter();
  const [jamb, setJamb] = useState("");
  const [proof, setProof] = useState("");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [verified, setVerified] = useState<Verified | null>(null);
  const [agreed, setAgreed] = useState(false);

  // an attempt this browser already holds the key to may be resumed straight away (read on the client, after verification)
  const held = (attemptId: string) => { try { return typeof window !== "undefined" && !!sessionStorage.getItem(tokenKey(attemptId)); } catch { return false; } };

  async function verify() {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch("/api/auth/putme-cbt", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ session: state.session, jambRegNo: jamb.trim().toUpperCase(), proof: proof.trim() }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      setVerified(j as Verified);
      setAgreed(false);
    } finally { setBusy(false); }
  }

  async function start(x: MyExam) {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/putme/cbt/exams/${x.exam_id}/start`, { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      try { sessionStorage.setItem(tokenKey(j.attemptId), j.token); } catch { /* the room asks again if the key is not kept */ }
      router.push(`/post-utme/cbt/room/${j.attemptId}`);
    } finally { setBusy(false); }
  }

  const eligibilityPill = (x: MyExam) => {
    if (x.attempt_status === "IN_PROGRESS") return <Pil kind="info">Attempt in progress</Pil>;
    if (x.attempt_status && x.attempt_status !== "NOT_STARTED") return <Pil kind="ok">Submitted</Pil>;
    if (!x.eligibility) return <Pil kind="ok">Eligible — you may start</Pil>;
    const code = codeOf(x.eligibility) ?? "";
    return <Pil kind={code === "CBT_EXAM_NOT_STARTED" ? "info" : "bad"}>{ELIGIBILITY_WORD[code] ?? textOf(x.eligibility)}</Pil>;
  };

  if (verified) {
    const c = verified.candidate;
    const open = verified.exams.filter((x) => x.live_state === "OPEN");
    return (
      <AuthLayout eyebrow={`Post-UTME CBT examination · ${verified.session}`} wide lead="Confirm that the information below is yours before you start. The clock starts when you press Start and runs on the University's server.">
        <PageHead title="Candidate confirmation" description="Read the details and the rules; the examination opens on the next screen." />
        <div className="grid grid--2">
          <div><div className="sub2">Candidate name</div><b>{c.name}</b></div>
          <div><div className="sub2">JAMB registration number</div><b className="tnum">{c.jambRegNo}</b></div>
          <div><div className="sub2">Application number</div><b className="tnum">{c.applicationNo ?? "—"}</b></div>
          <div><div className="sub2">Programme</div><b>{c.programme ?? "—"}</b></div>
        </div>
        {problem ? <ProblemNotice problem={problem} /> : null}
        {!verified.exams.length ? <Note kind="info" title="No examination is published for you yet">Your examination appears here once the Directorate of ICT publishes it. Check the date and time on your screening slip.</Note> : null}
        {verified.exams.map((x) => (
          <div key={x.exam_id} className="card mt-2" style={{ padding: 16 }}>
            <div className="row row--inline row--tight" style={{ justifyContent: "space-between", flexWrap: "wrap" }}>
              <div><b>{x.title}</b><div className="sub2">{x.duration_minutes} minutes · {x.questions} questions · {x.attempt_limit} attempt{x.attempt_limit === 1 ? "" : "s"} · {x.starts_at ? `${whenAt(x.starts_at)} → ${whenAt(x.ends_at)}` : "window not dated"}</div></div>
              {eligibilityPill(x)}
            </div>
            <ul className="sub2 mt-2" style={{ paddingLeft: 18 }}>
              <li>The timer is the server&rsquo;s: refreshing the page returns you to the same remaining time; when it runs out the attempt is submitted as it stands.</li>
              <li>Your answers are saved as you go. Leaving the tab, losing focus or leaving fullscreen is recorded and counts against the limit of {x.violation_limit}.</li>
              <li>A second screen or device {x.violation_limit >= 0 ? "is refused or recorded by the examination's rule" : ""}; stay on this one.</li>
              <li>You will not see a score after submission. The University releases Post-UTME scores and tells you where to check them.</li>
            </ul>
            {x.instructions ? <div className="sub2 mt-2" style={{ whiteSpace: "pre-wrap" }}>{x.instructions}</div> : null}
            {x.attempt_status === "IN_PROGRESS" && x.attempt_id && held(x.attempt_id) ? (
              <div className="mt-2"><LinkBtn kind="go" href={`/post-utme/cbt/room/${x.attempt_id}`}>Return to your examination</LinkBtn></div>
            ) : x.live_state === "OPEN" && !x.eligibility && (!x.attempt_status || x.attempt_status === "NOT_STARTED" || x.attempt_status === "IN_PROGRESS") ? (
              <div className="mt-2">
                <label className="row row--inline row--tight"><input type="checkbox" checked={agreed} onChange={(e) => setAgreed(e.target.checked)} /> I confirm that the information above is correct and I have read the rules.</label>
                <div className="mt-2"><Btn kind="go" disabled={busy || !agreed} onClick={() => void start(x)}>{busy ? "Opening…" : x.attempt_status === "IN_PROGRESS" ? "Continue the examination" : "Start exam"}</Btn></div>
              </div>
            ) : null}
          </div>
        ))}
        {!open.length && verified.exams.length ? <div className="sub2 mt-2">No examination is open to you at this moment.</div> : null}
        <div className="mt-2"><Btn kind="ghost" onClick={() => { setVerified(null); setProof(""); }}>Not you? Verify again</Btn></div>
      </AuthLayout>
    );
  }

  return (
    <AuthLayout eyebrow={`Post-UTME CBT examination · ${state.session}`} lead="Enter your JAMB registration number and the verification detail. The JAMB number alone does not open the examination.">
      <PageHead title="Post-UTME CBT examination" description={state.exams.length ? state.exams.map((x) => `${x.title} · ${x.duration_minutes} min · ${x.questions} questions${x.starts_at ? ` · ${whenAt(x.starts_at)} → ${whenAt(x.ends_at)}` : ""}`).join(" · ") : "Your examination is published by the Directorate of ICT."} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      <form onSubmit={(e) => { e.preventDefault(); if (!busy) void verify(); }}>
        <label className="lbl" htmlFor="pc-jamb">JAMB registration number</label>
        <input id="pc-jamb" className="ctl tnum" autoComplete="off" autoCapitalize="characters" value={jamb} onChange={(e) => setJamb(e.target.value.toUpperCase())} placeholder="e.g. 20XXXXXXXXAB" />
        <label className="lbl mt-2" htmlFor="pc-proof">{state.factorLabel}</label>
        <input id="pc-proof" className="ctl" autoComplete="off" value={proof} onChange={(e) => setProof(e.target.value)} placeholder={state.factor === "DATE_OF_BIRTH" ? "yyyy-mm-dd" : state.factor === "PHONE" ? "0803…" : ""} />
        <div className="mt-2"><Btn kind="primary" disabled={busy || !REG_SHAPE.test(jamb.trim()) || !proof.trim()}>{busy ? "Verifying…" : "Verify candidate"}</Btn></div>
      </form>
      <div className="sub2 mt-2">Checking a result? <a href="/post-utme/results">Post-UTME result checking</a>.</div>
    </AuthLayout>
  );
}
