"use client";

/** viewLogin — proto/part3.html, as drawn: the brand, the card, the three tabs, the office, the number, the password. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { Ico } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";

const ROLE_LABEL: Record<string, string> = { student: "Student", staff: "Staff", applicant: "Applicant" };
const LOGIN_ID: Record<string, [string, string]> = {
  student: ["Matriculation number", "MOAUM/CSC/23/1487"],
  staff: ["Staff number", "MOAUM/STF/1142"],
  applicant: ["Application number, email or JAMB number", "APP/26/000123"],
};

export function Login({ next, offices }: { next: string; offices: { code: string; label: string }[] }) {
  const router = useRouter();
  const [role, setRole] = useState("staff");
  const [office, setOffice] = useState("");
  const [uid, setUid] = useState("");
  const [pw, setPw] = useState("");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const f = LOGIN_ID[role];

  const live = role === "staff" || role === "applicant" || role === "student";

  async function signIn() {
    setBusy(true);
    setProblem(null);
    try {
      const r = role === "applicant"
        ? await fetch("/api/auth/applicant/sign-in", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ identifier: uid, password: pw }) })
        : role === "student"
          ? await fetch("/api/auth/student/sign-in", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ matricNo: uid, password: pw }) })
          : await fetch("/api/auth/sign-in", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ username: uid, password: pw, office: office || undefined }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) {
        setProblem(j ?? { status: r.status, title: r.statusText });
        return;
      }
      if (role === "applicant") {
        router.push("/applicant");
        router.refresh();
        return;
      }
      if (role === "student") {
        router.push(j.mustChange ? "/student/profile?change=1" : "/student");
        router.refresh();
        return;
      }
      router.push(j.mustChange ? `/account/password?next=${encodeURIComponent(next)}` : next);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

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
          <h1>Rev. Fr. Moses Orshio Adasu University, Makurdi</h1>
          <p>One place for admission, registration, results, fees and records. Sign in with the number the University issued you.</p>
        </div>
        <div className="login-stats">
          <div className="login-stat"><span className="n tnum">12</span><span className="l">faculties</span></div>
          <div className="login-stat"><span className="n tnum">1</span><span className="l">college</span></div>
          <div className="login-stat"><span className="n tnum">1992</span><span className="l">established</span></div>
        </div>
      </div>
      <div className="login-panel">
        <form className="login-card" onSubmit={(e) => { e.preventDefault(); if (live) void signIn(); }}>
          <div>
            <div style={{ fontSize: 22, fontWeight: 700, letterSpacing: "-.4px" }}>Sign in</div>
            <div className="hint" style={{ marginTop: 4 }}>{role === "staff" ? "Each office sees only its own work." : role === "applicant" ? "The account you made at Post-UTME registration." : "Your matriculation number and the password you chose at application, or the one the Registry gave you."}</div>
          </div>
          <div className="role-tabs" role="tablist">
            {["student", "staff", "applicant"].map((r) => (
              <button type="button" key={r} role="tab" aria-selected={role === r ? "true" : "false"} onClick={() => setRole(r)}>{ROLE_LABEL[r]}</button>
            ))}
          </div>
          {role === "staff" ? (
            <div className="field">
              <label htmlFor="office">Your office</label>
              <select id="office" className="ws__select" style={{ width: "100%" }} value={office} onChange={(e) => setOffice(e.target.value)}>
                <option value="">The first office you hold</option>
                {offices.map((o) => <option key={o.code} value={o.code}>{o.label}</option>)}
              </select>
              <div className="hint">Twenty-five offices sign in here. Each sees only its own work.</div>
            </div>
          ) : null}
          <div className="field">
            <label htmlFor="uid">{f[0]}</label>
            <input id="uid" value={uid} placeholder={f[1]} autoComplete="username" onChange={(e) => setUid(e.target.value)} disabled={!live} />
          </div>
          <div className="field">
            <label htmlFor="pw">Password</label>
            <input id="pw" type="password" value={pw} autoComplete="current-password" onChange={(e) => setPw(e.target.value)} disabled={!live} />
          </div>
          {problem ? <ProblemNotice problem={problem} /> : null}
          <button className="btn btn--primary" type="submit" disabled={busy || !live || !uid || !pw}>{busy ? "Signing in…" : "Sign in"}</button>
          <div className="login-help">
            {role === "applicant" ? <Link href="/login/forgot">Forgot your password?</Link> : <a href="#" onClick={(e) => e.preventDefault()} title="Ask the Registry to reset it">Forgot your password?</a>}
            {role === "applicant" ? <Link href="/apply">Post UTME Registration</Link> : <Link href="/login/first">First account</Link>}
          </div>
          {role === "applicant" ? (
            <div style={{ borderTop: "1px solid var(--line)", paddingTop: 14 }}>
              <Link href="/apply" className="btn btn--ghost btn--sm" style={{ width: "100%" }}>Post UTME Registration</Link>
              <div className="hint" style={{ marginTop: 6, textAlign: "center" }}>No account yet — start from your JAMB registration number</div>
            </div>
          ) : null}
          <div style={{ borderTop: "1px solid var(--line)", paddingTop: 14 }}>
            <button type="button" className="btn btn--ghost btn--sm" style={{ width: "100%" }} disabled title="Arrives with the credentials module">Verify a certificate or transcript</button>
            <div className="hint" style={{ marginTop: 6, textAlign: "center" }}>Employers and institutions — no account needed</div>
          </div>
          <div style={{ borderTop: "1px solid var(--line)", paddingTop: 14 }}>
            <button type="button" className="btn btn--ghost btn--sm" style={{ width: "100%" }} disabled title="No address recorded for CHS-AMS yet">College of Health Sciences → CHS-AMS</button>
            <div className="hint" style={{ marginTop: 6, textAlign: "center" }}>MBBS, BDS, Nursing and Medical Laboratory Science — College academic business runs in a separate system. Sign in <b>here</b> for fees, records and the transcript.</div>
          </div>
          <div className="notice notice--info" style={{ marginTop: 6 }}>
            <Ico name="alert" size={17} stroke="var(--chrome)" w={2} />
            <p>Five failed attempts lock an account for fifteen minutes. Staff and privileged accounts will also complete a second step when it arrives.</p>
          </div>
        </form>
      </div>
    </div>
  );
}
