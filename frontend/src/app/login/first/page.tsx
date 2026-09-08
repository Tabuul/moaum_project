"use client";

/** The first account, once: the same card as the sign-in page, with the secret the API already trusts. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { ProblemNotice } from "@/components/ProblemNotice";

export default function FirstAccountPage() {
  const router = useRouter();
  const [f, setF] = useState({ secret: "", staffNumber: "", surname: "", givenNames: "", username: "", password: "" });
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);

  async function create() {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch("/api/auth/bootstrap", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(f) });
      const j = await r.json().catch(() => null);
      if (!r.ok) {
        setProblem(j ?? { status: r.status, title: r.statusText });
        return;
      }
      router.push("/people");
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  const field = (k: keyof typeof f, label: string, type = "text", hint?: string, autoComplete?: string) => (
    <div className="field">
      <label htmlFor={`fa-${k}`}>{label}</label>
      <input id={`fa-${k}`} type={type} value={f[k]} autoComplete={autoComplete ?? "off"} onChange={(e) => setF({ ...f, [k]: e.target.value })} />
      {hint ? <div className="hint">{hint}</div> : null}
    </div>
  );

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
          <h1>The first account</h1>
          <p>Made once, by the Directorate of ICT, with the secret the API already trusts. It holds the Registrar&rsquo;s, the Academic Office&rsquo;s and the platform&rsquo;s offices, so that every other account can be made and granted from the Users &amp; roles screen — on an instrument, with a date.</p>
        </div>
      </div>
      <div className="login-panel">
        <form className="login-card" onSubmit={(e) => { e.preventDefault(); void create(); }}>
          <div>
            <div style={{ fontSize: 22, fontWeight: 700, letterSpacing: "-.4px" }}>Create the first account</div>
            <div className="hint" style={{ marginTop: 4 }}>Refused once any account exists.</div>
          </div>
          {field("secret", "Bootstrap secret", "password", "The value of MOAUM_AUTH_HMAC_SECRET on the API service. It is checked, never stored here.")}
          {field("surname", "Surname")}
          {field("givenNames", "Given names")}
          {field("staffNumber", "Staff number", "text", "Optional")}
          {field("username", "Username", "text", "The staff number or an email address; what you will type to sign in", "username")}
          {field("password", "Password", "password", "At least ten characters", "new-password")}
          {problem ? <ProblemNotice problem={problem} /> : null}
          <button className="btn btn--primary" type="submit" disabled={busy || !f.secret || !f.surname || !f.givenNames || !f.username || !f.password}>{busy ? "Creating…" : "Create and sign in"}</button>
          <div className="login-help"><a href="/login">Back to sign in</a><span /></div>
        </form>
      </div>
    </div>
  );
}
