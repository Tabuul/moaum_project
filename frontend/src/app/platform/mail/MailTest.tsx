"use client";

/**
 * V532: the SMTP settings on the Mail server screen tried before (or after) they are saved — the server reached and the account
 * signed in, nothing sent; or a short test e-mail sent to an address, which also shows whether the mailbox may send as the From
 * address. The API answers how far it got and what a failure means; the password typed is used, else the saved one.
 */
import { useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface SmtpForm { smtpHost: string; smtpPort: string; smtpEncryption: string; username: string; fromAddress: string; password: string }

interface TestResult { ok: boolean; stage: string; kind?: string; words: string; detail?: string; host: string; port: number; from?: string; sendTo?: string; ms: number }

const STAGE: Record<string, string> = { CONNECTION: "reaching the server", SIGN_IN: "signing in", SEND: "sending" };

export function MailTest({ f, may }: { f: SmtpForm; may: boolean }) {
  const [sendTo, setSendTo] = useState("");
  const [result, setResult] = useState<TestResult | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);

  async function run(to: string | null) {
    setProblem(null);
    setResult(null);
    const r = await fetch("/api/bff/api/v1/platform/mail/test", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(to ? `Test e-mail to ${to}` : "Mail server connection tested") },
      body: JSON.stringify({ smtpHost: f.smtpHost, smtpPort: Number(f.smtpPort) || null, smtpEncryption: f.smtpEncryption, username: f.username,
        fromAddress: f.fromAddress, password: f.password || null, sendTo: to }),
    });
    const j = await r.json().catch(() => null);
    if (!r.ok) {
      const p = j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText };
      setProblem(p);
      notifyProblem(p);
      return;
    }
    setResult(j as TestResult);
  }

  return (
    <Panel title="Test the settings" right="The values on this screen, saved or not">
      <PBody>
        <div className="sub2 mb-2">
          Tries the SMTP server, port, encryption, username and From address shown above, with the password typed above or else the saved one. Test the connection
          to check the server and the sign-in without sending anything; send a test e-mail to check that the mailbox may also send from the From address.
        </div>
        {problem ? <ProblemNotice problem={problem} /> : null}
        <div className="row row--wrap" style={{ alignItems: "flex-end", gap: 8 }}>
          <Btn kind="secondary" disabled={!may} busyLabel="Testing connection..." onClick={() => run(null)}>Test connection</Btn>
          <Field id="mail-test-to" label="Send a test e-mail to" hint="An address you can read, such as your own">
            <input id="mail-test-to" className="ctl" type="email" value={sendTo} onChange={(e) => setSendTo(e.target.value)} disabled={!may} autoComplete="off" placeholder="you@moaum.edu.ng" />
          </Field>
          <Btn kind="secondary" disabled={!may || !sendTo.trim()} busyLabel="Sending test e-mail..." onClick={() => run(sendTo.trim())}>Send a test e-mail</Btn>
        </div>
        {result ? (
          <Note kind={result.ok ? "ok" : "bad"}
            title={result.ok ? (result.stage === "SEND" ? "Test e-mail sent" : "Connected and signed in") : `Failed at ${STAGE[result.stage] ?? result.stage.toLowerCase()}`}>
            <div>{result.words}</div>
            {result.detail ? <div className="sub2 tnum" style={{ wordBreak: "break-word", marginTop: 4 }}>{result.detail}</div> : null}
            <div className="sub2" style={{ marginTop: 4 }}>{result.host}:{result.port} · {(result.ms / 1000).toFixed(1)} s{result.ok ? "" : ". Nothing was saved; change the settings above and test again."}</div>
          </Note>
        ) : null}
      </PBody>
    </Panel>
  );
}
