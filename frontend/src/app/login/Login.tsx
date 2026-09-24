"use client";

/**
 * viewLogin — proto/part3.html, as drawn: the brand, the card, the number, the
 * password. One door: the number typed says whether a student, a member of staff
 * or an applicant is signing in, and the portal opens on that person's own side.
 */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { Btn, Ico, LinkBtn, Note, PageHead } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";

const MATRIC = /^MOAUM\/[A-Z]{2,4}\/[0-9]{2}\/[0-9]{4}$/i;
const ADMISSION = /^MOAUM\/ADM\/[0-9]{2}\/[0-9]{6}$/i;
const JAMB = /^[0-9]{12}[A-Z]{2,3}$/i;
const APPLICATION = /^APP\/[0-9]{2}\/[0-9]{6}$/i;

function whoIs(id: string): string {
  const s = id.trim();
  if (!s) return "";
  if (ADMISSION.test(s)) return "An admitted student, on the admission number";
  if (MATRIC.test(s)) return "A student, on the matriculation number";
  if (JAMB.test(s) || APPLICATION.test(s)) return "An applicant, on the JAMB or application number";
  if (s.includes("@")) return "A member of staff or an applicant, on the email address";
  return "A member of staff, on the staff number";
}

export function Login({ next, sso, ssoProblem = null }: { next: string; sso: { enabled: boolean; label: string } | null; ssoProblem?: string | null }) {
  const router = useRouter();
  const [uid, setUid] = useState("");
  const [pw, setPw] = useState("");
  const [showPw, setShowPw] = useState(false);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);

  async function signIn() {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch("/api/auth/sign-in", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ identifier: uid, password: pw }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) {
        setProblem(j ?? { status: r.status, title: r.statusText });
        return;
      }
      /* staff go where they were heading; a student or an applicant has one home */
      const home: string = j.kind === "staff" && !j.mustChange ? next : j.mustChange && j.kind === "staff" ? `/account/password?next=${encodeURIComponent(next)}` : j.home;
      router.push(home);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  const who = whoIs(uid);

  return (
    <div className="login-wrap">
      <div className="login-brand">
        <div>
          <div className="login-brand__top">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/crest.png" alt="University crest" style={{ width: 56, height: 58, objectFit: "contain" }} />
            <div><span className="eyebrow" style={{ color: "var(--chrome-dim)" }}>Unified University Portal</span></div>
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
        <form className="login-card" onSubmit={(e) => { e.preventDefault(); void signIn(); }}>
          <PageHead title="Sign in" description="One door for students, staff and applicants. The portal opens on your own side once it knows who you are." />
          <div className="field">
            <label htmlFor="uid">Your number or email address</label>
            <input id="uid" value={uid} placeholder="MOAUM/CSC/23/1487 · MOAUM/STF/1142 · 202699168863AH" autoComplete="username" onChange={(e) => setUid(e.target.value)} />
            <div className="hint">{who || "Students: the matriculation number. Staff: the staff number or email. Applicants: the JAMB or application number, or the email you registered with."}</div>
          </div>
          <div className="field">
            <label htmlFor="pw">Password</label>
            <div className="pwrow">
              <input id="pw" type={showPw ? "text" : "password"} value={pw} autoComplete="current-password" onChange={(e) => setPw(e.target.value)} />
              <button
                type="button"
                className="pweye"
                onClick={() => setShowPw((v) => !v)}
                aria-label={showPw ? "Hide password" : "Show password"}
                aria-pressed={showPw}
                title={showPw ? "Hide password" : "Show password"}
              >
                <Ico name={showPw ? "eyeoff" : "eye"} size={18} stroke="currentColor" w={1.9} />
              </button>
            </div>
          </div>
          {problem ? <ProblemNotice problem={problem} /> : null}
          {ssoProblem ? <Note kind="bad" title="Single sign-on did not complete">{ssoProblem}</Note> : null}
          <Btn kind="primary" size="md" type="submit" disabled={busy || !uid || !pw}>{busy ? "Signing in…" : "Sign in"}</Btn>
          {sso?.enabled ? (
            <a className="btn btn--ghost btn--md" href="/api/auth/sso/start" style={{ width: "100%" }}>{sso.label}</a>
          ) : null}
          <div className="login-help">
            <Link href="/login/forgot">Forgot your password?</Link>
            <Link href="/login/first">First account</Link>
          </div>
          <div className="stack" style={{ borderTop: "1px solid var(--line)", paddingTop: "var(--s-4)" }}>
            <LinkBtn kind="ghost" href="/apply">Post UTME Registration</LinkBtn>
            <div className="hint" style={{ textAlign: "center" }}>No account yet — start from your JAMB registration number</div>
          </div>
          <div className="stack" style={{ borderTop: "1px solid var(--line)", paddingTop: "var(--s-4)" }}>
            <LinkBtn kind="ghost" href="/pg/apply">Postgraduate application</LinkBtn>
            <div className="hint" style={{ textAlign: "center" }}>PGD, Master&rsquo;s and PhD — apply directly, no JAMB number needed</div>
          </div>
          <div className="stack" style={{ borderTop: "1px solid var(--line)", paddingTop: "var(--s-4)" }}>
            <LinkBtn kind="ghost" href="/verify">Verify a payment or receipt</LinkBtn>
            <div className="hint" style={{ textAlign: "center" }}>Employers and institutions — no account needed. A document&rsquo;s QR opens its own check.</div>
          </div>
          <div className="notice notice--info mt-2">
            <Ico name="alert" size={17} stroke="var(--chrome)" w={2} />
            <p>Five failed attempts lock an account for fifteen minutes. {sso?.enabled ? "Staff sign in through the University's single sign-on, which asks for a second step." : "Staff and privileged accounts will also complete a second step when single sign-on is connected."}</p>
          </div>
        </form>
      </div>
    </div>
  );
}
