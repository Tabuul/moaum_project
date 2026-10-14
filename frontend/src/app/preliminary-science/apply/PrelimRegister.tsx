"use client";

/**
 * The Preliminary Science application's first step (V446): the name as on the O'Level certificate, sex, date of birth, email,
 * phone and a password. The application number is issued at once and the applicant is signed in; the fee comes next, and the
 * rest of the form opens once the payment is verified. One application per address and per person in a session.
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";
import { AuthLayout } from "@/components/auth/AuthLayout";
import { phoneRead } from "@/app/apply/Register";
import { naira, type PrelimPublic } from "@/lib/preliminary";

const EMAIL_SHAPE = /^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$/;

export function PrelimRegister({ p }: { p: PrelimPublic }) {
  const router = useRouter();
  const [f, setF] = useState({ surname: "", firstName: "", middleName: "", sex: "", dateOfBirth: "", email: "", phone: "", pw: "", pw2: "" });
  const [show, setShow] = useState(false);
  const [agreed, setAgreed] = useState(false);
  const [err, setErr] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const set = (k: keyof typeof f, v: string) => setF({ ...f, [k]: v });

  function judge(): boolean {
    const e: Record<string, string> = {};
    if (!f.surname.trim()) e.surname = "Your surname, as on your O'Level certificate.";
    if (!f.firstName.trim()) e.firstName = "Your first name, as on your O'Level certificate.";
    if (!["M", "F"].includes(f.sex)) e.sex = "Choose one.";
    if (!/^\d{4}-\d{2}-\d{2}$/.test(f.dateOfBirth)) e.dateOfBirth = "Your date of birth.";
    if (!EMAIL_SHAPE.test(f.email.trim())) e.email = "A complete email address: a name, an @, and a domain with a dot in it.";
    const ph = phoneRead(f.phone);
    if (!ph.ok) e.phone = `Eleven digits beginning with a zero are needed; ${ph.digits.length} were read.`;
    if (f.pw.length < 8) e.pw = "At least eight characters.";
    else if (f.pw !== f.pw2) e.pw2 = "The two passwords do not match.";
    if (!agreed) e.agree = "Read the Privacy Policy and tick the box to continue.";
    setErr(e);
    return Object.keys(e).length === 0;
  }

  async function create() {
    if (!judge()) return;
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch("/api/auth/applicant/preliminary-register", { method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ surname: f.surname.trim(), firstName: f.firstName.trim(), middleName: f.middleName.trim() || null, sex: f.sex, dateOfBirth: f.dateOfBirth,
          email: f.email.trim(), phone: phoneRead(f.phone).digits, password: f.pw, acceptPolicy: agreed }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      router.push("/applicant/preliminary");
      router.refresh();
    } finally { setBusy(false); }
  }

  const field = (id: string, label: string, k: string, el: React.ReactNode, hint?: React.ReactNode, optional = false) => (
    <div className="field">
      <label htmlFor={id}>{label}{optional ? null : <span className="lreq">required</span>}</label>
      {el}
      {err[k] ? <div className="ferr">{err[k]}</div> : null}
      {hint ? <div className="hint">{hint}</div> : null}
    </div>
  );

  return (
    <AuthLayout eyebrow={`Preliminary Science · ${p.session}`}
      lead={<>The Preliminary Science Programme prepares candidates for subsequent admission into approved science-based programmes.</>}
      stats={[[String(p.rules.minCredits), "O'Level credits"], [String(p.rules.minCoreCredits), "in core sciences"], [p.fee.stated && p.fee.applicationFee != null ? naira(p.fee.applicationFee) : "—", "application fee"]]}>
      <form className="login-card" onSubmit={(e) => { e.preventDefault(); void create(); }}>
        <PageHead title="Start your Preliminary Science application" description="Your application number is issued at once. Pay the application fee next; the rest of the form opens once the payment is verified." />
        <Note kind="info" title="Before you start">
          You need at least {p.rules.minCredits} O&rsquo;Level credit passes in at most {p.rules.maxSittings} sittings, {p.rules.minCoreCredits} of them in {p.rules.coreSubjects.join(", ")}. An awaiting result is not accepted. <a className="lnk" href="/preliminary-science" target="_blank" rel="noopener">Read the requirements</a>.
        </Note>
        {field("ps-s", "Surname", "surname", <input id="ps-s" value={f.surname} onChange={(e) => set("surname", e.target.value)} maxLength={60} autoComplete="family-name" required />)}
        {field("ps-f", "First name", "firstName", <input id="ps-f" value={f.firstName} onChange={(e) => set("firstName", e.target.value)} maxLength={60} autoComplete="given-name" required />)}
        {field("ps-m", "Middle name", "middleName", <input id="ps-m" value={f.middleName} onChange={(e) => set("middleName", e.target.value)} maxLength={60} autoComplete="additional-name" />, undefined, true)}
        {field("ps-x", "Sex", "sex", (
          <select id="ps-x" value={f.sex} onChange={(e) => set("sex", e.target.value)} required>
            <option value="">Choose…</option><option value="F">Female</option><option value="M">Male</option>
          </select>
        ))}
        {field("ps-d", "Date of birth", "dateOfBirth", <input id="ps-d" type="date" className="tnum" value={f.dateOfBirth} onChange={(e) => set("dateOfBirth", e.target.value)} max={new Date().toISOString().slice(0, 10)} required />)}
        {field("ps-e", "Email address", "email", <input id="ps-e" type="email" value={f.email} onChange={(e) => set("email", e.target.value)} placeholder="you@example.com" autoComplete="email" spellCheck={false} required />,
          "Every notice about your application goes here, including the outcome. You sign in with it or with your application number.")}
        {field("ps-p", "Phone number", "phone", <input id="ps-p" className="tnum" type="tel" value={f.phone} onChange={(e) => set("phone", e.target.value)} placeholder="0803 411 7725" inputMode="numeric" autoComplete="tel" required />)}
        {field("ps-w", "Choose a password", "pw", <input id="ps-w" type={show ? "text" : "password"} value={f.pw} onChange={(e) => set("pw", e.target.value)} autoComplete="new-password" required />)}
        {field("ps-w2", "Confirm password", "pw2", <input id="ps-w2" type={show ? "text" : "password"} value={f.pw2} onChange={(e) => set("pw2", e.target.value)} autoComplete="new-password" required />)}
        <label className="row row--inline row--tight mb-2"><input type="checkbox" checked={show} onChange={(e) => setShow(e.target.checked)} /> Show the passwords</label>
        <label className="row row--inline row--tight mb-1" htmlFor="ps-agree"><input id="ps-agree" type="checkbox" checked={agreed} onChange={(e) => setAgreed(e.target.checked)} /> I have read the <a className="lnk" href="/privacy-policy" target="_blank" rel="noopener">Privacy Policy</a> and accept how the University handles my information.</label>
        {err.agree ? <div className="ferr mb-2">{err.agree}</div> : null}
        {problem ? <ProblemNotice problem={problem} /> : null}
        <Btn kind="primary" size="md" type="submit" disabled={busy}>{busy ? "Starting your application…" : "Start my application"}</Btn>
        <div className="stack" style={{ borderTop: "1px solid var(--line)", paddingTop: "var(--s-4)" }}>
          <LinkBtn kind="ghost" href="/login">I already started an application</LinkBtn>
        </div>
      </form>
    </AuthLayout>
  );
}
