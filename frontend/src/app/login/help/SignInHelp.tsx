"use client";

/**
 * V363: help asked of the ICT Support Desk by a person who cannot sign in. The request becomes a Login Issues ticket that
 * names no account; the desk confirms who the person is before it acts, and the person follows it on /track with the
 * ticket's number and their email. The answer is the number and nothing else — whether an account exists is never said.
 */
import { useState, type FormEvent } from "react";
import Link from "next/link";
import type { Problem } from "@/lib/api";
import { Btn, LinkBtn, Note, PageHead } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { AuthLayout } from "@/components/auth/AuthLayout";

export interface HelpField { key: string; type?: string; label: string; options?: string[]; required?: boolean; hint?: string }

const LEAD = <>Cannot sign in? Tell the Directorate of ICT. The desk confirms who you are &mdash; it may call you &mdash; before it changes anything on an account, and it never asks for your password.</>;

export function SignInHelp({ reachable, open, fields }: { reachable: boolean; open: boolean; fields: HelpField[] }) {
  const [f, setF] = useState<Record<string, string>>({});
  const [details, setDetails] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [number, setNumber] = useState<string | null>(null);
  const set = (k: string) => (e: { target: { value: string } }) => setF((p) => ({ ...p, [k]: e.target.value }));
  const setDetail = (k: string) => (e: { target: { value: string } }) => setDetails((p) => ({ ...p, [k]: e.target.value }));

  const missing = [
    !(f.name ?? "").trim() ? "your name" : null,
    ...fields.filter((x) => x.required && x.type !== "file" && !(details[x.key] ?? "").trim()).map((x) => x.label.toLowerCase()),
    !(f.description ?? "").trim() ? "what happened" : null,
    !(f.email ?? "").trim() ? "your email" : null,
  ].filter(Boolean) as string[];

  async function send(e: FormEvent) {
    e.preventDefault();
    setProblem(null);
    if (missing.length) { setProblem({ status: 400, title: `Fill in ${missing.join(", ")}.` }); return; }
    setBusy(true);
    try {
      const r = await fetch("/api/bff/api/v1/helpdesk/sign-in-help", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: f.name.trim(), email: f.email.trim(), phone: (f.phone ?? "").trim() || null, description: f.description.trim(), details }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok || !j?.number) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: "The request could not be sent just now. Try again in a moment." }); return; }
      setNumber(String(j.number));
    } catch {
      setProblem({ status: 503, title: "The portal could not be reached just now. Try again in a moment." });
    } finally {
      setBusy(false);
    }
  }

  return (
    <AuthLayout eyebrow="ICT support" wide lead={LEAD}>
      <div className="login-card">
        <PageHead title="Ask for help signing in" description={<>Try <Link href="/login/forgot">Forgot password</Link> first: a reset link reaches the email on your account within minutes. If it does not arrive, your account is locked, or the portal does not know your number, tell the desk here.</>} />
        {number ? (
          <>
            <Note kind="ok" title={`Your request is with ICT Support — ${number}`}>
              Keep this number. Track the request with it and the email address you gave; an acknowledgement is on its way to that address. The desk confirms who you are before it changes anything, and never asks for your password.
            </Note>
            <div><LinkBtn kind="primary" size="md" href="/track">Track the request</LinkBtn></div>
          </>
        ) : !reachable || !open ? (
          <Note kind="bad" title={reachable ? "The desk is not taking requests here just now" : "The portal could not be reached just now"}>
            Visit the Directorate of ICT in person with your identity card, or try again later.
          </Note>
        ) : (
          <form className="stack" onSubmit={(e) => void send(e)}>
            <Field id="sh-name" label="Your name" required hint="As the University has it: letters, spaces, hyphens and apostrophes">
              <input id="sh-name" className="ctl" value={f.name ?? ""} onChange={set("name")} autoComplete="name" maxLength={120} />
            </Field>
            {fields.filter((x) => x.type !== "file").map((x) => (
              <Field key={x.key} id={`sh-${x.key}`} label={x.label} required={x.required} hint={x.hint}>
                {x.type === "select" ? (
                  <select id={`sh-${x.key}`} className="ctl" value={details[x.key] ?? ""} onChange={setDetail(x.key)}>
                    <option value="">— Choose —</option>
                    {(x.options ?? []).map((o) => <option key={o} value={o}>{o}</option>)}
                  </select>
                ) : (
                  <input id={`sh-${x.key}`} className="ctl" type={x.type === "date" ? "date" : "text"} value={details[x.key] ?? ""} onChange={setDetail(x.key)} maxLength={500} autoComplete="off" />
                )}
              </Field>
            ))}
            <Field id="sh-description" label="What happened" required hint="What you tried, and what the portal did">
              <textarea id="sh-description" className="ctl" rows={4} value={f.description ?? ""} onChange={set("description")} maxLength={4000} />
            </Field>
            <Field id="sh-email" label="Your email" required hint="Where the desk writes to you; you track the request with it">
              <input id="sh-email" className="ctl" type="email" value={f.email ?? ""} onChange={set("email")} autoComplete="email" maxLength={200} />
            </Field>
            <Field id="sh-phone" label="Your phone" hint="The desk may call it to confirm who you are">
              <input id="sh-phone" className="ctl tnum" type="tel" value={f.phone ?? ""} onChange={set("phone")} placeholder="08030000000" autoComplete="tel" maxLength={20} />
            </Field>
            {problem ? <ProblemNotice problem={problem} /> : null}
            <Btn kind="primary" size="md" type="submit" disabled={busy}>{busy ? "Sending…" : "Send to ICT Support"}</Btn>
          </form>
        )}
        <div className="login-help">
          <Link href="/login">Back to sign in</Link>
          <Link href="/track">Track a request</Link>
        </div>
      </div>
    </AuthLayout>
  );
}
