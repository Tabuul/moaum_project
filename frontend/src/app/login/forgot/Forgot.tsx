"use client";
import { notifyProblem } from "@/components/proto/Toast";

/** The first sign-in or a forgotten password, on the sign-in page's own card (proto/part3.html): the same answer whether or not the identifier
 *  names an account. V428: a person's own number is never their password, so a first password is set here, through the link. */
import { useState } from "react";
import Link from "next/link";
import type { Problem } from "@/lib/api";
import { Btn, Note, PageHead } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";
import { AuthLayout } from "@/components/auth/AuthLayout";

export function Forgot() {
  const [identifier, setIdentifier] = useState("");
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);

  async function ask() {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch("/api/auth/forgot", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ identifier: identifier.trim() }) });
      if (!r.ok) {
        const j = await r.json().catch(() => null);
        setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText });
        return;
      }
      setSent(true);
    } finally {
      setBusy(false);
    }
  }

  return (
    <AuthLayout eyebrow="Account recovery" lead={<>A reset link is sent to the email (and phone) on your account. It is valid for an hour and works once.</>}>
        <form className="login-card" onSubmit={(e) => { e.preventDefault(); if (!sent) void ask(); }}>
          <PageHead title="First sign-in or forgotten password" description="Staff, students and applicants. Your own number is never your password: a link lets you choose one." />
          {sent ? (
            <Note kind="ok" title="If that names an account, a reset link is on its way">
              Check the email and phone the University has for you. The link is valid for an hour and works once. If nothing arrives, or none is on record, <Link href="/login/help">ask ICT Support</Link>: a temporary password is given at the desk.
            </Note>
          ) : (
            <>
              <div className="field">
                <label htmlFor="ident">Staff number, matriculation number, application number, email or JAMB number</label>
                <input id="ident" value={identifier} placeholder="e.g. MOAUM/STAFF/1234, MOAUM/SCI/24/0001, APP/26/000123 or you@example.com" autoComplete="username" onChange={(e) => setIdentifier(e.target.value)} />
              </div>
              {problem ? <ProblemNotice problem={problem} /> : null}
              <Btn kind="primary" size="md" type="submit" disabled={busy || !identifier.trim()}>{busy ? "Sending…" : "Send the link"}</Btn>
            </>
          )}
          <div className="login-help">
            <Link href="/login">Back to sign in</Link>
            <Link href="/apply">Post UTME Registration</Link>
          </div>
        </form>
    </AuthLayout>
  );
}
