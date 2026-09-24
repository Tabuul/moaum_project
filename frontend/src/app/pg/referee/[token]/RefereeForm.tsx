"use client";

/**
 * The postgraduate referee's page (V225) — public, reached by the private link emailed to the referee.
 * It shows who named them and for what programme, then takes a short confidential reference: the
 * relationship, how long they have known the applicant, an academic attestation and a recommendation.
 */
import { useCallback, useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { Note } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";

interface Ctx { found: boolean; refereeName: string; position: string | null; institution: string | null; applicant: string; applicationNo: string; session: string; programme: string; award: string | null; submitted: boolean }

const VERDICTS: [string, string][] = [
  ["RECOMMEND", "I recommend this applicant"],
  ["RECOMMEND_WITH_RESERVATION", "I recommend with reservation"],
  ["DO_NOT_RECOMMEND", "I do not recommend this applicant"],
];

export function RefereeForm({ token }: { token: string }) {
  const [ctx, setCtx] = useState<Ctx | null>(null);
  const [loading, setLoading] = useState(true);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [done, setDone] = useState(false);
  const [busy, setBusy] = useState(false);
  const [f, setF] = useState<Record<string, string>>({ verdict: "RECOMMEND" });
  const set = (k: string) => (e: { target: { value: string } }) => setF((p) => ({ ...p, [k]: e.target.value }));

  const load = useCallback(async () => {
    try {
      const r = await fetch(`/api/bff/api/v1/pg/referee/${encodeURIComponent(token)}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (r.ok && j && j.found) setCtx(j as Ctx);
      else setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: "This reference link is not valid." });
    } finally { setLoading(false); }
  }, [token]);

  useEffect(() => { void load(); }, [load]);

  async function submit() {
    setProblem(null);
    if (!(f.relationship ?? "").trim() || !(f.knownDuration ?? "").trim() || !(f.attestation ?? "").trim()) {
      setProblem({ status: 400, title: "Your relationship, how long you have known the applicant, and your attestation are required." }); return;
    }
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/pg/referee/${encodeURIComponent(token)}`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ relationship: f.relationship, knownDuration: f.knownDuration, attestation: f.attestation, recommendation: f.recommendation ?? "", verdict: f.verdict }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      setDone(true);
    } finally { setBusy(false); }
  }

  return (
    <Frame>
      {loading ? <Note kind="info" title="Loading…">One moment.</Note> : null}
      {!loading && problem && !ctx ? <ProblemNotice problem={problem} /> : null}

      {ctx && (done || ctx.submitted) ? (
        <Note kind="ok" title="Thank you — your reference has been received">
          Your confidential reference for <b>{ctx.applicant}</b> has been recorded. You may close this page.
        </Note>
      ) : null}

      {ctx && !done && !ctx.submitted ? (
        <>
          <Note kind="info" title={`Reference for ${ctx.applicant}`}>
            You have been named as a referee for a postgraduate application to the <b>{ctx.programme}</b>{ctx.award ? ` (${ctx.award})` : ""} for the {ctx.session} session. Please complete this short, confidential reference. Fields marked with an asterisk are required.
          </Note>
          {problem ? <ProblemNotice problem={problem} /> : null}

          <div className="card"><div className="card__body" style={{ display: "grid", gap: 12 }}>
            <div className="field">
              <label htmlFor="relationship">Relationship to the applicant *</label>
              <input id="relationship" className="ctl" placeholder="e.g. Project supervisor, Head of Department" value={f.relationship ?? ""} onChange={set("relationship")} />
            </div>
            <div className="field">
              <label htmlFor="knownDuration">How long have you known the applicant? *</label>
              <input id="knownDuration" className="ctl" placeholder="e.g. 4 years" value={f.knownDuration ?? ""} onChange={set("knownDuration")} />
            </div>
            <div className="field">
              <label htmlFor="attestation">Academic attestation *</label>
              <textarea id="attestation" className="ctl" rows={5} placeholder="The applicant's academic ability, character and suitability for postgraduate study." value={f.attestation ?? ""} onChange={set("attestation")} />
            </div>
            <div className="field">
              <label htmlFor="recommendation">Recommendation (any further remarks)</label>
              <textarea id="recommendation" className="ctl" rows={3} value={f.recommendation ?? ""} onChange={set("recommendation")} />
            </div>
            <div className="field">
              <label htmlFor="verdict">Your recommendation *</label>
              <select id="verdict" className="ctl" value={f.verdict} onChange={set("verdict")}>
                {VERDICTS.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
              </select>
            </div>
            <div className="row">
              <button type="button" className="btn btn--primary" disabled={busy} onClick={() => void submit()}>{busy ? "Submitting…" : "Submit reference"}</button>
              <span className="sub2">Once submitted, a reference cannot be changed.</span>
            </div>
          </div></div>
        </>
      ) : null}
    </Frame>
  );
}

function Frame({ children }: { children: React.ReactNode }) {
  return (
    <div style={{ minHeight: "100vh", background: "var(--bg)" }}>
      <header style={{ background: "var(--chrome-deep, #0b1f3a)", color: "#fff", padding: "16px 22px", display: "flex", alignItems: "center", gap: 14 }}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/crest.png" alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
        <div style={{ flexGrow: 1, minWidth: 0 }}>
          <div style={{ fontSize: 11, letterSpacing: ".6px", textTransform: "uppercase", opacity: .7 }}>School of Postgraduate Studies</div>
          <h1 style={{ fontFamily: "var(--serif, Georgia)", fontSize: 20, fontWeight: 700, margin: "2px 0 0" }}>Referee reference</h1>
        </div>
      </header>
      <div style={{ maxWidth: 760, margin: "0 auto", padding: "18px 16px 56px", display: "grid", gap: 14 }}>
        {children}
      </div>
    </div>
  );
}
