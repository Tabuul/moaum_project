"use client";

import { notifyProblem } from "@/components/proto/Toast";
/**
 * The sign-in page, drawn as the University's CMS sign-in is (cms.moaum.edu.ng): the brand card with the crest turning in
 * its orbits, and the form beside it. One door: the number typed says whether a student, a member of staff or an applicant
 * is signing in, and the portal opens on that person's own side.
 */
import { useState, type ReactNode } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { Note } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";
import { AuthLayout } from "@/components/auth/AuthLayout";
import css from "./Login.module.css";

const MATRIC = /^MOAUM\/[A-Z]{2,4}\/[0-9]{2}\/[0-9]{4}$/i;
const ADMISSION = /^MOAUM\/ADM\/[0-9]{2}\/[0-9]{6}$/i;
const JAMB = /^[0-9]{12}[A-Z]{2,3}$/i;
const APPLICATION = /^APP\/[0-9]{2}\/[0-9]{6}$/i;
const JUPEB = /^JUPEB\/APP\/[0-9]{4}\/[0-9]{6}$/i;

function whoIs(id: string): string {
  const s = id.trim();
  if (!s) return "";
  if (ADMISSION.test(s)) return "An admitted student, on the admission number";
  if (MATRIC.test(s)) return "A student, on the matriculation number";
  if (JUPEB.test(s)) return "A JUPEB applicant or student, on the JUPEB application number";
  if (JAMB.test(s) || APPLICATION.test(s)) return "An applicant, on the JAMB or application number";
  if (s.includes("@")) return "A member of staff or an applicant, on the email address";
  return "A member of staff, on the staff number";
}

/** the line icons the form uses, drawn as the CMS draws them */
function Icon({ name, className }: { name: "shield" | "user" | "lock" | "eye" | "eyeoff"; className?: string }) {
  const paths: Record<string, ReactNode> = {
    shield: <><path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z" /><path d="m9 12 2 2 4-4" /></>,
    user: <><circle cx="12" cy="8" r="4" /><path d="M4 21a8 8 0 0 1 16 0" /></>,
    lock: <><rect width="18" height="11" x="3" y="11" rx="2" ry="2" /><path d="M7 11V7a5 5 0 0 1 10 0v4" /></>,
    eye: <><path d="M2.06 12.35a1 1 0 0 1 0-.7 10.75 10.75 0 0 1 19.88 0 1 1 0 0 1 0 .7 10.75 10.75 0 0 1-19.88 0" /><circle cx="12" cy="12" r="3" /></>,
    eyeoff: <><path d="M10.73 5.08A10.43 10.43 0 0 1 12 5c4.98 0 9.2 3.13 10.88 7.55a1 1 0 0 1 0 .7 10.97 10.97 0 0 1-1.44 2.49" /><path d="M14.08 14.16a3 3 0 0 1-4.24-4.24" /><path d="M17.48 17.5A10.75 10.75 0 0 1 1.12 12.55a1 1 0 0 1 0-.7 10.75 10.75 0 0 1 4.45-5.14" /><path d="m2 2 20 20" /></>,
  };
  return (
    <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={name === "shield" ? 2 : 1.5}
      strokeLinecap="round" strokeLinejoin="round" className={className} aria-hidden="true">{paths[name]}</svg>
  );
}

export function Login({ next, sso, ssoProblem = null }: {
  next: string; sso: { enabled: boolean; label: string } | null; ssoProblem?: string | null;
  /** V312: which application windows are open — no longer shown here: the sign-in page is for signing in alone, and applicants reach their application pages directly */
  applications?: { postUtme: boolean; postgraduate: boolean } | null;
}) {
  const router = useRouter();
  const [uid, setUid] = useState("");
  const [pw, setPw] = useState("");
  const [showPw, setShowPw] = useState(false);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);

  async function signIn() {
    if (!uid.trim() || !pw) {
      setProblem({ status: 400, title: "Enter your username and password", detail: "Both are needed to sign in." });
      return;
    }
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch("/api/auth/sign-in", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ identifier: uid, password: pw }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) {
        setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText });
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
    <AuthLayout bare lead={<>Sign-in for students, staff and applicants.</>}>
        <div className={css.formWrap}>
          <p className={css.eyebrow}><Icon name="shield" className={css.eyebrowIcon} />Secure sign-in</p>
          <h2 className={css.heading}>Portal Login</h2>

          <form className={css.form} noValidate onSubmit={(e) => { e.preventDefault(); void signIn(); }}>
            <div className={css.fieldBlock}>
              <div className={css.labelRow}>
                <label htmlFor="uid" className={css.label}>Username<span className={css.req} aria-hidden="true">*</span></label>
              </div>
              <div className={css.inputBox}>
                <Icon name="user" className={css.inputIcon} />
                <input id="uid" className={css.input} value={uid} placeholder="Matric, staff or JAMB number, or email" autoComplete="username" required
                  aria-describedby={who ? "uid-hint" : undefined} onChange={(e) => setUid(e.target.value)} />
              </div>
              {/* what the username was read as, once one is typed */}
              {who ? <div id="uid-hint" className={css.hint}>{who}</div> : null}
            </div>

            <div className={css.fieldBlock}>
              <div className={css.labelRow}>
                <label htmlFor="pw" className={css.label}>Password<span className={css.req} aria-hidden="true">*</span></label>
                <Link href="/login/forgot" className={css.forgot}>Forgot password?</Link>
              </div>
              <div className={css.inputBox}>
                <Icon name="lock" className={css.inputIcon} />
                <input id="pw" className={`${css.input} ${css.inputPw}`} type={showPw ? "text" : "password"} value={pw} autoComplete="current-password" required
                  autoCapitalize="none" spellCheck={false} onChange={(e) => setPw(e.target.value)} />
                <button type="button" className={css.eye} onClick={() => setShowPw((v) => !v)} aria-label={showPw ? "Hide password" : "Show password"}
                  aria-pressed={showPw} title={showPw ? "Hide password" : "Show password"}>
                  <Icon name={showPw ? "eyeoff" : "eye"} className={css.eyeIcon} />
                </button>
              </div>
            </div>

            {problem || ssoProblem ? (
              <div className={css.notices}>
                {problem ? <ProblemNotice problem={problem} /> : null}
                {ssoProblem ? <Note kind="bad" title="Single sign-on did not complete">{ssoProblem}</Note> : null}
              </div>
            ) : null}

            <button type="submit" className={css.submit} disabled={busy}>{busy ? "Signing in…" : "Sign in"}</button>
            {sso?.enabled ? <a className={css.sso} href="/api/auth/sso/start">{sso.label}</a> : null}
          </form>

          <p className={css.foot}>Cannot sign in? <Link href="/login/help">Ask ICT Support for help</Link> · <Link href="/track">Track a request</Link></p>
        </div>
    </AuthLayout>
  );
}
