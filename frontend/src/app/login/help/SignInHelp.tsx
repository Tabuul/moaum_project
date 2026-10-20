"use client";

/**
 * V363: help asked of the ICT Support Desk by a person who cannot sign in. The request becomes a Login Issues ticket that
 * names no account; the desk confirms who the person is before it acts, and the person follows it on /track with the
 * ticket's number and their email. The answer is the number and nothing else.
 * Oct 2026: for the student portal the number is checked against the register by itself as it is typed (a moment after the
 * last key), and a number no student holds keeps the request from being sent; the API refuses it too.
 * V596: the form asks only the account, the number, the name and how to reach the person — not what the portal says, since
 * when or what happened. A student-portal number found names its student (the name in full, the e-mail and phone on the record
 * masked, never in full), and the name is filled in; where the record holds no e-mail or phone, the one given is saved to it,
 * unconfirmed until the student confirms it with a code when they sign in.
 */
import { useRef, useState, type FormEvent } from "react";
import Link from "next/link";
import type { Problem } from "@/lib/api";
import { Btn, LinkBtn, Note, PageHead } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { AuthLayout } from "@/components/auth/AuthLayout";

export interface HelpField { key: string; type?: string; label: string; options?: string[]; required?: boolean; hint?: string }

const LEAD = <>Cannot sign in? Tell the Directorate of ICT. The desk never asks for your password.</>;

/** V596: of the Login Issues fields, the ones the sign-in page asks */
const ASKED = ["account_type", "username"];

/** the account type names the student portal ("Student portal", as the desk words it) — the API's own test */
const studentPortal = (accountType: string | undefined) => (accountType ?? "").toLowerCase().includes("student");

/** a name the request takes as it is: letters, spaces, hyphens and apostrophes */
const plainName = (name: string) => /^[A-Za-z][A-Za-z '-]*$/.test(name);

/** V596: the student a number names — the name in full, the contacts on the record masked */
interface Found { name: string; email: string | null; phone: string | null; hasEmail: boolean; hasPhone: boolean }
type NumberCheck = { state: "checking" | "found" | "corrected" | "missing" | "slow"; words?: string; student?: Found };

export function SignInHelp({ reachable, open, fields }: { reachable: boolean; open: boolean; fields: HelpField[] }) {
  const [f, setF] = useState<Record<string, string>>({});
  const [details, setDetails] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [number, setNumber] = useState<string | null>(null);
  const [saved, setSaved] = useState<string[]>([]);
  const [numberCheck, setNumberCheck] = useState<NumberCheck | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const seq = useRef(0);
  const set = (k: string) => (e: { target: { value: string } }) => setF((p) => ({ ...p, [k]: e.target.value }));
  const asked = ASKED.map((k) => fields.find((x) => x.key === k)).filter((x): x is HelpField => !!x);

  /** a student's number checked against the register a moment after the last key; the latest answer only */
  function scheduleCheck(accountType: string | undefined, number: string | undefined) {
    if (timer.current) clearTimeout(timer.current);
    const n = (number ?? "").trim();
    const mine = ++seq.current;
    if (!studentPortal(accountType) || n.length < 6) { setNumberCheck(null); return; }
    setNumberCheck({ state: "checking" });
    timer.current = setTimeout(async () => {
      try {
        const r = await fetch("/api/bff/api/v1/helpdesk/sign-in-help/check", {
          method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ accountType, number: n }),
        });
        const j = await r.json().catch(() => null);
        if (mine !== seq.current) return;
        if (r.status === 429) { setNumberCheck({ state: "slow", words: j?.detail ?? "Too many checks from this connection; wait a few minutes." }); return; }
        if (!r.ok || !j?.applies) { setNumberCheck(null); return; }
        const student: Found | undefined = j.name ? { name: j.name, email: j.email ?? null, phone: j.phone ?? null, hasEmail: !!j.hasEmail, hasPhone: !!j.hasPhone } : undefined;
        setNumberCheck({ state: j.corrected ? "corrected" : j.found ? "found" : "missing", student });
        // the name filled in from the record, where it is still empty and written as a request takes it
        if (student && plainName(student.name)) setF((p) => ((p.name ?? "").trim() ? p : { ...p, name: student.name }));
      } catch {
        if (mine === seq.current) setNumberCheck(null);
      }
    }, 600);
  }

  const setDetail = (k: string) => (e: { target: { value: string } }) => {
    const v = e.target.value;
    setDetails((p) => ({ ...p, [k]: v }));
    if (k === "username") scheduleCheck(details.account_type, v);
    if (k === "account_type") scheduleCheck(v, details.username);
  };
  const numberUnknown = studentPortal(details.account_type) && numberCheck?.state === "missing";
  const student = studentPortal(details.account_type) ? numberCheck?.student : undefined;

  const missing = [
    ...asked.filter((x) => x.required && !(details[x.key] ?? "").trim()).map((x) => x.label.toLowerCase()),
    !(f.name ?? "").trim() ? "your name" : null,
    !(f.email ?? "").trim() ? "your email" : null,
  ].filter(Boolean) as string[];

  async function send(e: FormEvent) {
    e.preventDefault();
    setProblem(null);
    if (missing.length) { setProblem({ status: 400, title: `Fill in ${missing.join(", ")}.` }); return; }
    if (numberUnknown) { setProblem({ status: 422, title: "No student record holds that number", detail: "Type your matriculation number as it is on your identity card, or your admission number if you have no matriculation number yet." }); return; }
    setBusy(true);
    try {
      const only = Object.fromEntries(ASKED.filter((k) => (details[k] ?? "").trim()).map((k) => [k, details[k].trim()]));
      const r = await fetch("/api/bff/api/v1/helpdesk/sign-in-help", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: f.name.trim(), email: f.email.trim(), phone: (f.phone ?? "").trim() || null, details: only }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok || !j?.number) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: "The request could not be sent just now. Try again in a moment." }); return; }
      setSaved(Array.isArray(j.saved) ? (j.saved as string[]) : []);
      setNumber(String(j.number));
    } catch {
      setProblem({ status: 503, title: "The portal could not be reached just now. Try again in a moment." });
    } finally {
      setBusy(false);
    }
  }

  const savedWords = saved.length === 2 ? "Your e-mail and phone were" : saved.includes("EMAIL") ? "Your e-mail was" : "Your phone was";

  return (
    <AuthLayout eyebrow="ICT support" wide lead={LEAD}>
      <div className="login-card">
        <PageHead title="Ask for help signing in" description={<>Try <Link href="/login/forgot">Forgot password</Link> first. If the link does not arrive or your account is locked, tell the desk here.</>} />
        {number ? (
          <>
            <Note kind="ok" title={`Your request is with ICT Support — ${number}`}>
              Keep this number to track the request; an acknowledgement is on its way to your email. The desk never asks for your password.
            </Note>
            {saved.length ? (
              <Note kind="info" title={`${savedWords} added to your student record`}>
                When you next sign in you will be asked to confirm {saved.length === 2 ? "them" : "it"} with a code sent there. Until then no password-reset link is sent to {saved.length === 2 ? "them" : "it"}.
              </Note>
            ) : null}
            <div><LinkBtn kind="primary" size="md" href="/track">Track the request</LinkBtn></div>
          </>
        ) : !reachable || !open ? (
          <Note kind="bad" title={reachable ? "The desk is not taking requests here just now" : "The portal could not be reached just now"}>
            Visit the Directorate of ICT in person with your identity card, or try again later.
          </Note>
        ) : (
          <form className="stack" onSubmit={(e) => void send(e)}>
            {asked.map((x) => (
              <Field key={x.key} id={`sh-${x.key}`} label={x.label} required={x.required}
                hint={x.key === "username" && studentPortal(details.account_type) && numberCheck
                  ? numberCheck.state === "checking" ? "Checking the register…" : numberCheck.state === "found" ? "✓ A student record holds this number."
                    : numberCheck.state === "corrected" ? "This matriculation number was corrected: sign in with your new number. The University sent it to the e-mail and phone it holds for you; if you have not received it, ask here." : numberCheck.state === "slow" ? numberCheck.words : x.hint
                  : x.hint}
                error={x.key === "username" && numberUnknown
                  ? "No student record holds this number. Type it as it is on your identity card, or your admission number if you have no matriculation number yet; if it is right, visit the Registry with your admission letter."
                  : undefined}>
                {x.type === "select" ? (
                  <select id={`sh-${x.key}`} className="ctl" value={details[x.key] ?? ""} onChange={setDetail(x.key)}>
                    <option value="">— Choose —</option>
                    {(x.options ?? []).map((o) => <option key={o} value={o}>{o}</option>)}
                  </select>
                ) : (
                  <input id={`sh-${x.key}`} className="ctl" type="text" value={details[x.key] ?? ""} onChange={setDetail(x.key)} maxLength={500} autoComplete="off" />
                )}
              </Field>
            ))}
            {student ? (
              <Note kind="info" title={student.name}>
                <span className="blk">E-mail on your record: <b className="tnum">{student.email ?? "none"}</b></span>
                <span className="blk">Phone on your record: <b className="tnum">{student.phone ?? "none"}</b></span>
                {!student.hasEmail || !student.hasPhone
                  ? <span className="blk sub2 mt-1">Your record has no {!student.hasEmail && !student.hasPhone ? "e-mail or phone" : !student.hasEmail ? "e-mail" : "phone"}: the one you give below is saved to it, and you confirm it with a code when you next sign in.</span>
                  : null}
              </Note>
            ) : null}
            <Field id="sh-name" label="Your name" required hint="As the University has it: letters, spaces, hyphens and apostrophes">
              <input id="sh-name" className="ctl" value={f.name ?? ""} onChange={set("name")} autoComplete="name" maxLength={120} />
            </Field>
            <Field id="sh-email" label="Your email" required
              hint={student && !student.hasEmail ? "Saved to your student record (you confirm it when you next sign in); the desk writes to you here and you track the request with it" : "Where the desk writes to you; you track the request with it"}>
              <input id="sh-email" className="ctl" type="email" value={f.email ?? ""} onChange={set("email")} autoComplete="email" maxLength={200} />
            </Field>
            <Field id="sh-phone" label="Your phone"
              hint={student && !student.hasPhone ? "Saved to your student record (you confirm it when you next sign in); the desk may call it to confirm who you are" : "The desk may call it to confirm who you are"}>
              <input id="sh-phone" className="ctl tnum" type="tel" value={f.phone ?? ""} onChange={set("phone")} placeholder="08030000000" autoComplete="tel" maxLength={20} />
            </Field>
            {problem ? <ProblemNotice problem={problem} /> : null}
            <Btn kind="primary" size="md" type="submit" disabled={busy || numberUnknown}>{busy ? "Sending…" : "Send to ICT Support"}</Btn>
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
