"use client";

/** A JUPEB candidate's forgotten password (V339): the link is emailed to the address applied with, good for an hour and used
 *  once; following it, the candidate chooses a new password and is signed in to their portal. The answer to a request is the
 *  same whether or not the account exists. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { Btn, Note, PageHead } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { jcall } from "@/lib/jupeb";

export function JupebReset({ token }: { token: string }) {
  const router = useRouter();
  const [id, setId] = useState("");
  const [pw, setPw] = useState("");
  const [pw2, setPw2] = useState("");
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);

  async function ask() {
    setBusy(true); setProblem(null);
    try {
      const r = await jcall("/api/v1/jupeb/forgot", "POST", { identifier: id.trim() });
      if (!r.ok) setProblem(r.problem); else setSent(true);
    } finally { setBusy(false); }
  }
  async function choose() {
    setProblem(null);
    if (pw.length < 8) { setProblem({ status: 400, title: "Choose a password of at least eight characters." }); return; }
    if (pw !== pw2) { setProblem({ status: 400, title: "The two passwords do not match." }); return; }
    setBusy(true);
    try {
      const r = await fetch("/api/auth/jupeb/reset", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ token, password: pw }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      router.push("/jupeb/portal");
    } finally { setBusy(false); }
  }
  return (
    <div className="login-wrap">
      <div className="login-panel" style={{ gridColumn: "1 / -1" }}>
        <div className="login-card">
          <PageHead title={token ? "Choose a new password" : "Forgotten your JUPEB password?"} description={token ? "The link is good for an hour and is used once." : "We email a reset link to the address you applied with."} />
          {problem ? <ProblemNotice problem={problem} /> : null}
          {token ? (
            <>
              <Field id="pw" label="New password" hint="At least eight characters"><input id="pw" type="password" className="ctl" value={pw} onChange={(e) => setPw(e.target.value)} autoComplete="new-password" /></Field>
              <Field id="pw2" label="Confirm new password"><input id="pw2" type="password" className="ctl" value={pw2} onChange={(e) => setPw2(e.target.value)} autoComplete="new-password" /></Field>
              <Btn kind="primary" size="md" disabled={busy || !pw} onClick={() => void choose()}>{busy ? "Saving…" : "Save and sign in"}</Btn>
            </>
          ) : sent ? (
            <Note kind="ok" title="Check your email">If a JUPEB application uses that email or number, a reset link is on its way. It is good for an hour.</Note>
          ) : (
            <>
              <Field id="id" label="Email or JUPEB application number"><input id="id" className="ctl" value={id} onChange={(e) => setId(e.target.value)} autoComplete="username" /></Field>
              <Btn kind="primary" size="md" disabled={busy || !id.trim()} onClick={() => void ask()}>{busy ? "Sending…" : "Email me a reset link"}</Btn>
            </>
          )}
          <div className="login-help"><Link href="/login?next=/jupeb/portal">Back to sign in</Link></div>
        </div>
      </div>
    </div>
  );
}
