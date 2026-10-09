"use client";

/**
 * The CCE application's first step (V379): the JAMB number and the date of birth, checked together against the CCE list the
 * Academic Office committed. Nothing else is asked until both match; the name and the programme are read from the list and shown
 * back. A number on the list with another date of birth reads exactly as a number not on it. Then the account: email, phone,
 * password — the same applicant account every applicant has, which becomes the student account at matriculation.
 */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";
import { AuthLayout } from "@/components/auth/AuthLayout";
import { phoneRead } from "@/app/apply/Register";

const NUMBER_SHAPE = /^[A-Z0-9/-]{6,24}$/;
const EMAIL_SHAPE = /^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$/;

type Found = { state: "idle" | "nomatch" | "found" | "registered" | "closed"; name?: string; programme?: string; session?: string; window?: string };

export function CceRegister({ session }: { session: string }) {
  const router = useRouter();
  const [num, setNum] = useState("");
  const [dob, setDob] = useState("");
  const [looked, setLooked] = useState<{ ask: string; found: Found } | null>(null);
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [pw, setPw] = useState("");
  const [pw2, setPw2] = useState("");
  const [show, setShow] = useState(false);
  const [err, setErr] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const key = num.replace(/\s/g, "").toUpperCase();
  const ask = `${key}|${dob}`;
  const ready = NUMBER_SHAPE.test(key) && /^\d{4}-\d{2}-\d{2}$/.test(dob);

  useEffect(() => {
    if (!ready) return;
    let live = true;
    const t = window.setTimeout(async () => {
      const r = await fetch("/api/bff/api/v1/applicant/cce/lookup", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ jambKey: key, dateOfBirth: dob }) });
      const j = await r.json().catch(() => null);
      if (!live) return;
      if (r.ok && j) setLooked({ ask, found: j as Found });
      else { setLooked({ ask, found: { state: "idle" } }); if (r.status === 429) notifyProblem(j ?? { status: 429, title: "Too many look-ups from this connection; wait a few minutes" }); }
    }, 350);
    return () => { live = false; window.clearTimeout(t); };
  }, [ask, key, dob, ready]);
  const found: Found = ready && looked && looked.ask === ask ? looked.found : { state: "idle" };

  function judge(): boolean {
    const e: Record<string, string> = {};
    if (!EMAIL_SHAPE.test(email.trim())) e.email = "A complete email address: a name, an @, and a domain with a dot in it.";
    const ph = phoneRead(phone);
    if (!ph.ok) e.phone = `Eleven digits beginning with a zero are needed; ${ph.digits.length} were read. Written as +234 or without the zero is fine.`;
    if (pw.length < 8) e.pw = "Eight characters at the very least. This one account carries you to graduation.";
    else if (pw !== pw2) e.pw2 = "The two passwords do not match.";
    setErr(e);
    return Object.keys(e).length === 0;
  }

  async function create() {
    if (!judge()) return;
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch("/api/auth/applicant/cce-register", { method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ jambKey: key, dateOfBirth: dob, email: email.trim(), phone: phoneRead(phone).digits, password: pw }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      router.push("/applicant/cce");
      router.refresh();
    } finally { setBusy(false); }
  }

  const input = (id: string, label: string, k: string, el: React.ReactNode, hint?: React.ReactNode) => (
    <div className="field">
      <label htmlFor={id}>{label}<span className="lreq">required</span></label>
      {el}
      {err[k] ? <div className="ferr">{err[k]}</div> : null}
      {hint ? <div className="hint">{hint}</div> : null}
    </div>
  );

  return (
    <AuthLayout eyebrow={`Centre for Continuing Education · ${session}`}
      lead={<>Apply to the Centre for Continuing Education: a regular University degree, studied part-time with lectures in the evening. Only candidates whose names JAMB sent the University on the CCE list may apply.</>}
      stats={[["CCE", "part-time"], ["6", "years, typically"], ["0", "fees paid anywhere but here"]]}>
      <form className="login-card" onSubmit={(e) => { e.preventDefault(); if (found.state === "found") void create(); }}>
        <PageHead title="The CCE application" description="Your JAMB number and your date of birth, as on the CCE list. Everything else follows from them." />
        <div className="field">
          <label htmlFor="cj">JAMB number</label>
          <input id="cj" className="tnum" value={num} onChange={(e) => setNum(e.target.value)} placeholder="202512345678CC" maxLength={30} autoComplete="off" spellCheck={false} />
        </div>
        <div className="field">
          <label htmlFor="cd">Date of birth</label>
          <input id="cd" type="date" className="tnum" value={dob} onChange={(e) => setDob(e.target.value)} max={new Date().toISOString().slice(0, 10)} />
          <div className="hint">Checked together with the number against the list JAMB sent. Nothing else is asked until both match.</div>
        </div>
        {found.state === "nomatch" ? (
          <Note kind="bad" title="That JAMB number and date of birth are not together on the CCE list">
            Check both against your JAMB slip. If both are right, your name may not have reached the University yet, or the list may carry a different date: the Centre for Continuing Education can tell you. <b>Nobody can add you to the list here</b> &mdash; it comes from JAMB through the Academic Office.
          </Note>
        ) : null}
        {found.state === "closed" ? (
          <Note kind="bad" title={`The Centre is not admitting into ${found.programme ?? "that programme"} at present`}>
            You are on the list as <b>{found.name}</b>, but the programme is not open for CCE applications. Contact the Centre for Continuing Education.
          </Note>
        ) : null}
        {found.state === "registered" ? (
          <Note kind="info" title="An application account already exists for this number" action={<LinkBtn kind="primary" href="/login">Sign in</LinkBtn>}>
            Sign in with the email and password you chose. A forgotten password is reset from the sign-in page.
          </Note>
        ) : null}
        {found.state === "found" ? (
          <>
            <Note kind="ok" title={`Found on the CCE list for ${found.session}`}>Your name and programme are read from the list, not typed: if either is wrong, the Centre corrects it with the Academic Office.</Note>
            <div className="field"><label>Name</label><div className="readout">{found.name}</div></div>
            <div className="field"><label>Programme (part-time, Centre for Continuing Education)</label><div className="readout">{found.programme}</div></div>
            {input("ce", "Email address", "email", <input id="ce" type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="you@example.com" autoComplete="off" spellCheck={false} required />,
              "Every notice about your application goes here, including the outcome.")}
            {input("cp", "Phone number", "phone", <input id="cp" className="tnum" type="tel" value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="0803 411 7725" inputMode="numeric" autoComplete="off" required />)}
            {input("cw", "Choose a password", "pw", <input id="cw" type={show ? "text" : "password"} value={pw} onChange={(e) => setPw(e.target.value)} autoComplete="new-password" required />)}
            {input("cw2", "Confirm password", "pw2", <input id="cw2" type={show ? "text" : "password"} value={pw2} onChange={(e) => setPw2(e.target.value)} autoComplete="new-password" required />)}
            <label className="row row--inline row--tight mb-2"><input type="checkbox" checked={show} onChange={(e) => setShow(e.target.checked)} /> Show the passwords</label>
            {problem ? <ProblemNotice problem={problem} /> : null}
            <Btn kind="primary" size="md" type="submit" disabled={busy}>{busy ? "Creating your account…" : "Create my account and continue"}</Btn>
          </>
        ) : found.state !== "registered" ? (
          <>
            <Btn kind="primary" size="md" disabled style={{ opacity: 0.45, cursor: "not-allowed" }}>Continue</Btn>
            <div className="hint" style={{ textAlign: "center" }}>Enter your JAMB number and date of birth to continue</div>
          </>
        ) : null}
        <div className="stack" style={{ borderTop: "1px solid var(--line)", paddingTop: "var(--s-4)" }}>
          <LinkBtn kind="ghost" href="/login">I already have an account</LinkBtn>
        </div>
      </form>
    </AuthLayout>
  );
}
