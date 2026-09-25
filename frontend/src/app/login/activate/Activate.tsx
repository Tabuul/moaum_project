"use client";
/** /login/activate — an external examiner's invitation (V254): who is invited, by whom, until when; a password chosen
 *  here and never sent by email; then to the sign-in with the email address as the username. */
import { useEffect, useState } from "react";
import Link from "next/link";
import type { Problem } from "@/lib/api";
import { Btn, Note } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";

interface Invitation { name: string; institution: string; email: string; status: string; expires_at: string; appointment: string | null; university: string }

export function Activate({ token }: { token: string }) {
  const [inv, setInv] = useState<Invitation | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [password, setPassword] = useState("");
  const [again, setAgain] = useState("");
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState<string | null>(null);

  useEffect(() => {
    if (!token) return;
    let live = true;
    fetch(`/api/bff/api/v1/examiners/invitation/${encodeURIComponent(token)}`).then(async (r) => {
      const j = await r.json().catch(() => null);
      if (!live) return;
      if (!r.ok) setProblem(j ?? { status: r.status, title: "This invitation link has expired or was already used." });
      else setInv(j as Invitation);
    }).catch(() => { if (live) setProblem({ status: 503, title: "The portal could not be reached just now." }); });
    return () => { live = false; };
  }, [token]);

  const strong = password.length >= 10 && !(inv && password.toLowerCase().includes(inv.email.toLowerCase()));
  const ready = strong && password === again;

  async function activate(e: React.FormEvent) {
    e.preventDefault();
    if (!ready) return;
    setBusy(true); setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/examiners/activate", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ token, password }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: "The account could not be activated." }); return; }
      setDone(String(j?.username ?? inv?.email ?? ""));
    } catch { setProblem({ status: 503, title: "The portal could not be reached just now." }); }
    finally { setBusy(false); }
  }

  return (
    <div style={{ minHeight: "100vh", background: "var(--bg)", display: "flex", alignItems: "flex-start", justifyContent: "center", padding: "var(--s-8) var(--s-4)" }}>
      <div className="card" style={{ width: "100%", maxWidth: 520, overflow: "hidden" }}>
        <div className="card__head" style={{ borderBottom: "2px solid var(--chrome)" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
          <div className="grow">
            <div className="eyebrow" style={{ color: "var(--amber)" }}>Rev. Fr. Moses Orshio Adasu University, Makurdi</div>
            <h1 className="phead__t ink-chrome m-0">External Examiner Appointment</h1>
          </div>
        </div>
        <div className="card__body">
          {done ? (
            <>
              <Note kind="ok" title="Your examiner account is active">Sign in with your email address, <b>{done}</b>, and the password you chose. The projects assigned to you, their documents and the assessment form are in your workspace.</Note>
              <div><Link className="btn btn--primary" href="/login">Sign In</Link></div>
            </>
          ) : !token ? (
            <>
              <Note kind="bad" title="This link carries no invitation">Open the link from the invitation email, or ask the Academic Office to resend it.</Note>
              <div><Link className="lnk" href="/login">Go to the sign-in</Link></div>
            </>
          ) : problem && !inv ? (
            <>
              <Note kind="bad" title={problem.title ?? "This invitation cannot be opened"}>{problem.detail ?? "The link may have expired, or was already used. Each invitation link is good for fourteen days and works once."} {problem.remedy?.message}</Note>
              <div><Link className="lnk" href="/login">Go to the sign-in</Link></div>
            </>
          ) : !inv ? (
            <p className="m-0 ink-muted">Reading the invitation…</p>
          ) : (
            <form onSubmit={(e) => void activate(e)} className="stack">
              <p className="m-0">Dear <b>{inv.name}</b> ({inv.institution}), the University invites you to serve as an External Examiner{inv.appointment ? <> for <b>{inv.appointment}</b></> : null}. Choose a password to activate your account. Your username will be <b>{inv.email}</b>.</p>
              <p className="m-0 sub2">This link works once and expires on {new Date(inv.expires_at).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" })}.</p>
              {problem ? <Note kind="bad" title={problem.title ?? "Not activated"}>{problem.detail}</Note> : null}
              <Field id="ac-pw" label="Password" required hint="At least ten characters, not containing your email address">
                <input id="ac-pw" className="ctl" type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="new-password" />
              </Field>
              <Field id="ac-pw2" label="Password again" required error={again && again !== password ? "The two do not match." : undefined}>
                <input id="ac-pw2" className="ctl" type="password" value={again} onChange={(e) => setAgain(e.target.value)} autoComplete="new-password" />
              </Field>
              <div className="row row--base">
                <Btn kind="primary" size="md" type="submit" disabled={busy || !ready}>{busy ? "Activating…" : "Activate My Account"}</Btn>
                <span className="sub2">The University never sends passwords by email.</span>
              </div>
            </form>
          )}
        </div>
      </div>
    </div>
  );
}
