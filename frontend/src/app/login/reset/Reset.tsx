"use client";

/** A new password against the reset token: eight characters at least, typed twice, and the applicant is signed in. */
import { useState } from "react";
import Link from "next/link";
import type { Problem } from "@/lib/api";
import { Note } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";

export function Reset({ token }: { token: string }) {
  const [pw, setPw] = useState("");
  const [pw2, setPw2] = useState("");
  const [show, setShow] = useState(false);
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const mismatch = pw2.length > 0 && pw !== pw2;

  async function reset() {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch("/api/auth/reset", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ token, password: pw }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) {
        setProblem(j ?? { status: r.status, title: r.statusText });
        return;
      }
      setDone(true);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="login-wrap">
      <div className="login-brand">
        <div>
          <div className="login-brand__top">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/crest.png" alt="University crest" style={{ width: 56, height: 58, objectFit: "contain" }} />
            <div><span style={{ fontSize: 12, letterSpacing: ".6px", textTransform: "uppercase", color: "var(--chrome-dim)" }}>Unified University Portal</span></div>
          </div>
          <div style={{ height: 26 }} />
          <h1>Choose a new password</h1>
          <p>The link you opened is good for an hour and works once. Every session signed in with the old password is ended.</p>
        </div>
      </div>
      <div className="login-panel">
        <form className="login-card" onSubmit={(e) => { e.preventDefault(); if (token && pw.length >= 8 && !mismatch) void reset(); }}>
          <div>
            <div style={{ fontSize: 22, fontWeight: 700, letterSpacing: "-.4px" }}>New password</div>
            <div className="hint mt-1">Eight characters at the very least. This one account carries you to graduation.</div>
          </div>
          {done ? (
            <Note kind="ok" title="Your password has been changed">Sign in with your new password. <Link href="/login">Go to sign in</Link>.</Note>
          ) : !token ? (
            <Note kind="bad" title="This link is incomplete">Open it exactly as it was sent, or <Link href="/login/forgot">ask for a new one</Link>.</Note>
          ) : (
            <>
              <div className="field">
                <label htmlFor="npw">New password</label>
                <div className="pwrow">
                  <input id="npw" type={show ? "text" : "password"} value={pw} autoComplete="new-password" onChange={(e) => setPw(e.target.value)} />
                  <button type="button" className="pweye" aria-pressed={show ? "true" : "false"} onClick={() => setShow(!show)}>{show ? "Hide" : "Show"}</button>
                </div>
              </div>
              <div className="field">
                <label htmlFor="npw2">Type it again</label>
                <input id="npw2" type={show ? "text" : "password"} value={pw2} autoComplete="new-password" onChange={(e) => setPw2(e.target.value)} />
                {mismatch ? <div className="ferr">The two do not match.</div> : null}
              </div>
              {problem ? <ProblemNotice problem={problem} /> : null}
              <button className="btn btn--primary" type="submit" disabled={busy || pw.length < 8 || mismatch}>{busy ? "Saving…" : "Save the new password"}</button>
            </>
          )}
          <div className="login-help">
            <Link href="/login">Back to sign in</Link>
            <Link href="/login/forgot">Ask for a new link</Link>
          </div>
        </form>
      </div>
    </div>
  );
}
