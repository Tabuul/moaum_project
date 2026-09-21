"use client";

/**
 * The postgraduate applicant's portal. After applying (V205) the applicant signs in on the email they
 * applied with (or their PG application number) and lands here: their application, its status through the
 * School's pipeline, and the application fee — paid online through whichever gateway the Bursary has wired,
 * with the same PayByCard the undergraduate applicant uses. Every call is scoped to the signed-in applicant.
 */
import { useCallback, useEffect, useState, type ReactNode } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { Note } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PayByCard } from "@/app/applicant/common";

interface Me {
  applicationNo: string; name: string; email: string; phone: string | null;
  state: string; entryLevel: number; programme: string; award: string | null; research: boolean;
  faculty: string; department: string; submittedAt: string | null; feeConfirmedAt: string | null;
  applicationFee: number | null; liveReference: string | null;
  deptNote: string | null; spgsNote: string | null; acceptedAt: string | null; admittedAt: string | null;
}

const naira = (n: number | null) => (n == null ? "—" : "NGN " + Number(n).toLocaleString());
const STATE_LABEL: Record<string, string> = {
  DRAFT: "Draft", SUBMITTED: "Submitted — with the department", DEPT_RECOMMENDED: "Recommended — with the School",
  DEPT_DECLINED: "Not recommended by the department", OFFERED: "Offered a place", NOT_OFFERED: "Not offered",
  ACCEPTED: "Offer accepted", ADMITTED: "Admitted — on the register",
};

export function PgPortal() {
  const router = useRouter();
  const [me, setMe] = useState<Me | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [reference, setReference] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [signedOut, setSignedOut] = useState(false);

  const load = useCallback(async () => {
    try {
      const r = await fetch("/api/bff/api/v1/pg/me", { cache: "no-store" });
      setProblem(null);
      if (r.status === 401) { setMe(null); setLoading(false); return; }
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); setLoading(false); return; }
      const m = j as Me;
      setMe(m);
      if (!m.feeConfirmedAt) {
        const fr = await fetch("/api/bff/api/v1/pg/fee-reference", { method: "POST", headers: { "Content-Type": "application/json" } });
        const fj = await fr.json().catch(() => null);
        if (fr.ok && fj && typeof fj === "object" && "reference" in fj) setReference(String((fj as { reference: string }).reference));
      }
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  async function signOut() {
    try { await fetch("/api/bff/api/v1/pg/sign-out", { method: "POST" }); } catch { /* ignore */ }
    try { await fetch("/api/auth/sign-out", { method: "POST" }); } catch { /* ignore */ }
    setSignedOut(true);
    router.push("/login");
    router.refresh();
  }

  if (loading) {
    return <Wrap><Note kind="info" title="Loading your application…">One moment.</Note></Wrap>;
  }

  if (!me) {
    return (
      <Wrap>
        <Note kind="info" title="Sign in to see your application">
          Sign in with the email you applied with (or your PG application number) and the password you chose when you applied.
        </Note>
        <div style={{ textAlign: "center", marginTop: 12 }}><Link href="/login?next=/pg/portal" className="btn btn--primary">Sign in</Link></div>
      </Wrap>
    );
  }

  return (
    <Wrap>
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Note kind={me.feeConfirmedAt ? "ok" : "info"} title={`${me.name} — ${me.applicationNo}`}>
        Your postgraduate application is <b>{STATE_LABEL[me.state] ?? me.state}</b>.
        {me.state === "OFFERED" ? " You have an offer — accept it below." : ""}
      </Note>

      <div className="card"><div className="card__body">
        <Row k="Application number" v={me.applicationNo} />
        <Row k="Programme" v={me.programme} />
        <Row k="Award" v={me.award ?? "—"} />
        <Row k="Faculty" v={me.faculty} />
        <Row k="Department" v={me.department} />
        <Row k="Status" v={STATE_LABEL[me.state] ?? me.state} />
        <Row k="Application fee" v={naira(me.applicationFee)} />
        <Row k="Fee" v={me.feeConfirmedAt ? "Paid" : "Not yet paid"} />
      </div></div>

      {me.feeConfirmedAt ? (
        <Note kind="ok" title="Application fee paid">
          Your application fee is confirmed. The School will screen your application; check back here for its progress.
        </Note>
      ) : reference ? (
        <div className="card"><div className="card__body" style={{ display: "grid", gap: 8 }}>
          <div style={{ fontWeight: 700 }}>Pay the application fee</div>
          <div className="sub2">Pay {naira(me.applicationFee)} by card, transfer or USSD. It is confirmed automatically once the payment reaches the University.</div>
          <PayByCard reference={reference} amount={Number(me.applicationFee ?? 0)} />
          <div className="sub2">Payment reference: <b className="tnum">{reference}</b></div>
        </div></div>
      ) : (
        <Note kind="bad" title="The application fee could not be prepared">
          Reload the page, or write to the School of Postgraduate Studies quoting your application number.
        </Note>
      )}

      {me.spgsNote ? <Note kind="info" title="A note from the School">{me.spgsNote}</Note> : null}

      <div style={{ display: "flex", justifyContent: "space-between", marginTop: 12 }}>
        <button type="button" className="btn btn--ghost btn--sm" onClick={() => void load()}>Refresh</button>
        <button type="button" className="btn btn--ghost btn--sm" onClick={() => void signOut()} disabled={signedOut}>Sign out</button>
      </div>
    </Wrap>
  );
}

function Wrap({ children }: { children: ReactNode }) {
  return (
    <div className="login-wrap">
      <div className="login-brand">
        <div>
          <div className="login-brand__top">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/crest.png" alt="University crest" style={{ width: 56, height: 58, objectFit: "contain" }} />
            <div><span style={{ fontSize: 12, letterSpacing: ".6px", textTransform: "uppercase", color: "var(--chrome-dim)" }}>School of Postgraduate Studies</span></div>
          </div>
          <div style={{ height: 26 }} />
          <h1>Your postgraduate application</h1>
          <p>Pay your application fee and follow your application from submission through the School&rsquo;s decision. This account becomes your student account on the day you are admitted.</p>
        </div>
      </div>
      <div className="login-panel">
        <div style={{ width: "100%", maxWidth: 620, display: "grid", gap: 14 }}>
          {children}
        </div>
      </div>
    </div>
  );
}

function Row({ k, v }: { k: string; v: string }) {
  return <div style={{ display: "flex", justifyContent: "space-between", gap: 12, padding: "6px 0", borderBottom: "1px solid var(--line-2)" }}><span className="sub2">{k}</span><span style={{ fontWeight: 700, textAlign: "right" }}>{v}</span></div>;
}
