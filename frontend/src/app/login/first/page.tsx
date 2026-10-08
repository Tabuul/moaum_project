"use client";
import { notifyProblem } from "@/components/proto/Toast";

/** The first account, once: the same card as the sign-in page, with the secret the API already trusts. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { Btn, PageHead } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";
import { AuthLayout } from "@/components/auth/AuthLayout";

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
        setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText });
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
    <AuthLayout eyebrow="First account" lead={<>The portal&rsquo;s first account, made once by the Directorate of ICT. Refused once any account exists.</>}>
        <form className="login-card" onSubmit={(e) => { e.preventDefault(); void create(); }}>
          <PageHead title="Create the first account" description="Refused once any account exists." />
          {field("secret", "Bootstrap secret", "password", "The value of MOAUM_AUTH_HMAC_SECRET on the API service. It is checked, never stored here.")}
          {field("surname", "Surname")}
          {field("givenNames", "Given names")}
          {field("staffNumber", "Staff number", "text", "Optional")}
          {field("username", "Username", "text", "The staff number or an email address; what you will type to sign in", "username")}
          {field("password", "Password", "password", "At least ten characters", "new-password")}
          {problem ? <ProblemNotice problem={problem} /> : null}
          <Btn kind="primary" size="md" type="submit" disabled={busy || !f.secret || !f.surname || !f.givenNames || !f.username || !f.password}>{busy ? "Creating…" : "Create and sign in"}</Btn>
          <div className="login-help"><a href="/login">Back to sign in</a><span /></div>
        </form>
    </AuthLayout>
  );
}
