"use client";
/** V385: Post-UTME result checking. The JAMB registration number and the verification detail; the released score, or why there is none
 *  yet. Only while the Director of ICT's result-checking window is open, only what the Academic Office has released. */
import { useState } from "react";
import type { Problem } from "@/lib/api";
import { Btn, Note, PageHead } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";
import { AuthLayout } from "@/components/auth/AuthLayout";
import { whenAt } from "@/lib/cbt";
import type { PutmePublic } from "@/lib/putme-cbt";

type Result = { outcome: "CLOSED" | "NOT_RELEASED" | "RELEASED"; candidate_name: string | null; jamb_reg_no: string | null; application_no: string | null; programme: string | null; score: number | null; released_at: string | null };

export function ResultCheck({ state }: { state: PutmePublic }) {
  const [jamb, setJamb] = useState("");
  const [proof, setProof] = useState("");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [result, setResult] = useState<Result | null>(null);

  async function check() {
    setBusy(true); setProblem(null); setResult(null);
    try {
      const r = await fetch("/api/bff/api/v1/putme/results/check", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ session: state.session, jambRegNo: jamb.trim().toUpperCase(), proof: proof.trim() }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      setResult(j as Result);
    } finally { setBusy(false); }
  }

  return (
    <AuthLayout eyebrow={`Post-UTME result checking · ${state.session}`} lead="Enter your JAMB registration number and the verification detail to read your released Post-UTME score.">
      <PageHead title="Post-UTME result checking" description="The score the University released for you, as the Academic Office recorded it." />
      {problem ? <ProblemNotice problem={problem} /> : null}
      {result ? (
        result.outcome === "RELEASED" ? (
          <div className="card" style={{ padding: 16 }}>
            <div className="grid grid--2">
              <div><div className="sub2">Candidate</div><b>{result.candidate_name}</b></div>
              <div><div className="sub2">JAMB registration number</div><b className="tnum">{result.jamb_reg_no}</b></div>
              <div><div className="sub2">Programme</div><b>{result.programme ?? "—"}</b></div>
              <div><div className="sub2">Released</div><b className="tnum">{whenAt(result.released_at)}</b></div>
            </div>
            <div className="mt-2"><div className="sub2">Post-UTME score</div><div style={{ fontSize: 32, fontWeight: 700 }} className="tnum">{Number(result.score).toFixed(2)}</div></div>
            <div className="sub2 mt-2">This is the screening score on your application. Your admission status is a separate decision of the University; check it on the portal when admission status checking opens.</div>
          </div>
        ) : result.outcome === "NOT_RELEASED" ? (
          <Note kind="info" title={`${result.candidate_name}: not yet released`}>Your Post-UTME score has not been released by the University yet. Check again when the release is announced.</Note>
        ) : (
          <Note kind="info" title="Result checking is closed">The University announces when Post-UTME results may be checked.</Note>
        )
      ) : null}
      <form onSubmit={(e) => { e.preventDefault(); if (!busy) void check(); }}>
        <label className="lbl" htmlFor="rc-jamb">JAMB registration number</label>
        <input id="rc-jamb" className="ctl tnum" autoComplete="off" value={jamb} onChange={(e) => setJamb(e.target.value.toUpperCase())} />
        <label className="lbl mt-2" htmlFor="rc-proof">{state.resultFactorLabel}</label>
        <input id="rc-proof" className="ctl" autoComplete="off" value={proof} onChange={(e) => setProof(e.target.value)} placeholder={state.resultFactor === "DATE_OF_BIRTH" ? "yyyy-mm-dd" : ""} />
        <div className="mt-2"><Btn kind="primary" disabled={busy || !jamb.trim() || !proof.trim()}>{busy ? "Checking…" : "Check result"}</Btn></div>
      </form>
    </AuthLayout>
  );
}
