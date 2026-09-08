"use client";

/** The applicant's forgotten password, on the sign-in page's own card (proto/part3.html): the same answer whether or not the identifier names an account. */
import { useState } from "react";
import Link from "next/link";
import type { Problem } from "@/lib/api";
import { Note } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";

export function Forgot() {
  const [identifier, setIdentifier] = useState("");
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);

  async function ask() {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch("/api/auth/applicant/forgot", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ identifier: identifier.trim() }) });
      if (!r.ok) {
        const j = await r.json().catch(() => null);
        setProblem(j ?? { status: r.status, title: r.statusText });
        return;
      }
      setSent(true);
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
          <h1>Forgotten your password?</h1>
          <p>A reset link is sent to the email and the phone on your application account. It is good for an hour and works once.</p>
        </div>
      </div>
      <div className="login-panel">
        <form className="login-card" onSubmit={(e) => { e.preventDefault(); if (!sent) void ask(); }}>
          <div>
            <div style={{ fontSize: 22, fontWeight: 700, letterSpacing: "-.4px" }}>Reset your password</div>
            <div className="hint" style={{ marginTop: 4 }}>For application accounts. Staff ask the Registry.</div>
          </div>
          {sent ? (
            <Note kind="ok" title="If that names an account, a reset link is on its way">
              Check the email and the phone on your application. The link is good for an hour. If nothing arrives, the address or number on your account may differ from the one you expect &mdash; write to the Registry quoting your application number.
            </Note>
          ) : (
            <>
              <div className="field">
                <label htmlFor="ident">Application number, email or JAMB number</label>
                <input id="ident" value={identifier} placeholder="APP/26/000123" autoComplete="username" onChange={(e) => setIdentifier(e.target.value)} />
              </div>
              {problem ? <ProblemNotice problem={problem} /> : null}
              <button className="btn btn--primary" type="submit" disabled={busy || !identifier.trim()}>{busy ? "Sending…" : "Send the reset link"}</button>
            </>
          )}
          <div className="login-help">
            <Link href="/login">Back to sign in</Link>
            <Link href="/apply">Post UTME Registration</Link>
          </div>
        </form>
      </div>
    </div>
  );
}
