"use client";

/**
 * The postgraduate applicant's dashboard. After applying (V205) the applicant signs in on the email they
 * applied with (or their PG application number) and works from here through a small menu: an overview, the
 * full application (bio-data, the degree(s) it rests on, proposal, referees), their credentials document,
 * the application fee (paid online), and the progress of the application through the School's pipeline.
 * Every call is scoped to the signed-in applicant.
 */
import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { Note } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PayByCard } from "@/app/applicant/common";

interface Referee { name: string; email: string | null; institution: string | null; position: string | null }
interface PriorDegree { kind: string; institution: string | null; award: string | null; class_of_degree: string | null; cgpa: number | null; year: number | null }
interface DocMeta { id: string; kind: string; filename: string; content_type: string; uploaded_at: string }
interface Me {
  applicationNo: string; session: string; name: string; surname: string; otherNames: string;
  email: string; phone: string | null;
  state: string; entryLevel: number; programme: string; programmeCode: string; award: string | null; research: boolean;
  faculty: string; department: string; submittedAt: string | null; createdAt: string | null; feeConfirmedAt: string | null;
  applicationFee: number | null; acceptanceFee: number | null; checkingFee: number | null; liveReference: string | null;
  deptNote: string | null; deptDecidedAt: string | null; spgsNote: string | null; spgsDecidedAt: string | null;
  acceptedAt: string | null; admittedAt: string | null;
  biodata: { sex: string | null; dateOfBirth: string | null; stateOfOrigin: string | null; lga: string | null };
  prior: { institution: string | null; award: string | null; classOfDegree: string | null; cgpa: number | null; year: number | null };
  proposal: { title: string | null; text: string | null };
  referees: Referee[]; priorDegrees: PriorDegree[]; documents: DocMeta[];
}

const naira = (n: number | null) => (n == null ? "—" : "₦" + Number(n).toLocaleString());
const LEVEL: Record<number, string> = { 700: "Postgraduate Diploma", 800: "Master’s", 900: "MPhil / PhD" };
const STATE_LABEL: Record<string, string> = {
  DRAFT: "Draft", SUBMITTED: "Submitted — with the department", DEPT_RECOMMENDED: "Recommended — with the School",
  DEPT_DECLINED: "Not recommended by the department", OFFERED: "Offered a place", NOT_OFFERED: "Not offered",
  ACCEPTED: "Offer accepted", ADMITTED: "Admitted — on the register",
};
function fmtDate(v: string | null): string {
  if (!v) return "—";
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? "—" : d.toLocaleDateString("en-GB", { day: "2-digit", month: "long", year: "numeric" });
}
const val = (v: string | number | null | undefined) => (v === null || v === undefined || v === "" ? "—" : String(v));
type Tab = "overview" | "application" | "documents" | "payment" | "progress";
const TABS: [Tab, string][] = [["overview", "Overview"], ["application", "Application"], ["documents", "Documents"], ["payment", "Application fee"], ["progress", "Progress"]];

export function PgPortal() {
  const router = useRouter();
  const [me, setMe] = useState<Me | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [reference, setReference] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<Tab>("overview");
  const [checking, setChecking] = useState(false);

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

  useEffect(() => {
    const paidRef = new URLSearchParams(window.location.search).get("paid");
    void (async () => {
      if (paidRef) {
        try { await fetch("/api/bff/api/v1/payments/verify", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ reference: paidRef }) }); } catch { /* ignore */ }
      }
      await load();
    })();
  }, [load]);

  async function checkNow() {
    if (!reference) return;
    setChecking(true);
    try {
      await fetch("/api/bff/api/v1/payments/verify", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ reference }) });
      await load();
    } finally { setChecking(false); }
  }

  async function signOut() {
    try { await fetch("/api/bff/api/v1/pg/sign-out", { method: "POST" }); } catch { /* ignore */ }
    try { await fetch("/api/auth/sign-out", { method: "POST" }); } catch { /* ignore */ }
    router.push("/login");
    router.refresh();
  }

  if (loading) return <Wrap subtitle="Loading…"><Note kind="info" title="Loading your application…">One moment.</Note></Wrap>;

  if (!me) {
    return (
      <Wrap subtitle="Sign in">
        <Note kind="info" title="Sign in to see your application">Sign in with the email you applied with (or your PG application number) and the password you chose when you applied.</Note>
        <div style={{ textAlign: "center", marginTop: 12 }}><Link href="/login?next=/pg/portal" className="btn btn--primary">Sign in</Link></div>
      </Wrap>
    );
  }

  const paid = !!me.feeConfirmedAt;
  const credentials = me.documents.find((d) => d.kind === "CREDENTIALS") ?? null;

  return (
    <Wrap subtitle={`${me.applicationNo}`}>
      {problem ? <ProblemNotice problem={problem} /> : null}

      <nav className="pg-tabs">
        {TABS.map(([t, label]) => (
          <button key={t} className={t === tab ? "pg-tab pg-tab--on" : "pg-tab"} onClick={() => setTab(t)}>
            {label}
            {t === "documents" && !credentials ? <span className="pg-dot" title="No credentials uploaded" /> : null}
            {t === "payment" && !paid ? <span className="pg-dot" title="Fee not paid" /> : null}
          </button>
        ))}
      </nav>

      {tab === "overview" ? (
        <>
          <Note kind={paid ? "ok" : "info"} title={`${me.name} · ${me.applicationNo}`}>
            Your postgraduate application is <b>{STATE_LABEL[me.state] ?? me.state}</b>.
            {me.state === "OFFERED" ? " You have an offer of admission." : ""}
            {!paid ? " Pay the application fee to have it screened." : ""}
          </Note>
          <Card title="At a glance">
            <KV rows={[
              ["Programme", me.programme],
              ["Award", me.award ?? "—"],
              ["Level", LEVEL[me.entryLevel] ?? String(me.entryLevel)],
              ["Department", me.department],
              ["Faculty", me.faculty],
              ["Status", STATE_LABEL[me.state] ?? me.state],
              ["Application fee", paid ? "Paid" : `${naira(me.applicationFee)} — unpaid`],
              ["Credentials", credentials ? "Uploaded" : "Not uploaded yet"],
            ]} />
          </Card>
          {!credentials ? <Note kind="info" title="Upload your credentials">Scan your O&rsquo;Level, A&rsquo;Level and birth certificate / declaration of age into one PDF and upload it under <b>Documents</b>.</Note> : null}
        </>
      ) : null}

      {tab === "application" ? (
        <>
          <Card title="Application">
            <KV rows={[
              ["Application number", me.applicationNo], ["Session", me.session], ["Programme", me.programme],
              ["Award", me.award ?? "—"], ["Level", LEVEL[me.entryLevel] ?? String(me.entryLevel)],
              ["Faculty", me.faculty], ["Department", me.department], ["Submitted", fmtDate(me.submittedAt)],
            ]} />
          </Card>
          <Card title="Bio-data">
            <KV rows={[
              ["Surname", me.surname], ["Other names", me.otherNames],
              ["Sex", me.biodata.sex === "F" ? "Female" : me.biodata.sex === "M" ? "Male" : "—"],
              ["Date of birth", fmtDate(me.biodata.dateOfBirth)], ["State of origin", val(me.biodata.stateOfOrigin)],
              ["LGA", val(me.biodata.lga)], ["Email", me.email], ["Phone", val(me.phone)],
            ]} />
          </Card>
          {(me.priorDegrees.length ? me.priorDegrees : [{ kind: "FIRST", ...me.prior, class_of_degree: me.prior.classOfDegree } as unknown as PriorDegree]).map((pd, i) => (
            <Card key={i} title={pd.kind === "MASTERS" ? "Master’s degree" : "First degree"}>
              <KV rows={[
                ["Institution", val(pd.institution)], ["Award", val(pd.award)],
                ["Class of degree", val(pd.class_of_degree)], ["CGPA", val(pd.cgpa)], ["Year", val(pd.year)],
              ]} />
            </Card>
          ))}
          {me.research || me.proposal.title || me.proposal.text ? (
            <Card title="Research proposal">
              <KV rows={[["Title", val(me.proposal.title)]]} />
              {me.proposal.text ? <div style={{ marginTop: 8, whiteSpace: "pre-wrap", lineHeight: 1.55 }}>{me.proposal.text}</div> : null}
            </Card>
          ) : null}
          {me.referees.length ? (
            <Card title="Referees">
              <div style={{ display: "grid", gap: 12 }}>
                {me.referees.map((rf, i) => (
                  <div key={i} style={{ borderTop: i ? "1px solid var(--line-2)" : "none", paddingTop: i ? 10 : 0 }}>
                    <KV rows={[["Name", val(rf.name)], ["Position", val(rf.position)], ["Institution", val(rf.institution)], ["Email", val(rf.email)]]} />
                  </div>
                ))}
              </div>
            </Card>
          ) : null}
        </>
      ) : null}

      {tab === "documents" ? <Documents credentials={credentials} onDone={load} /> : null}

      {tab === "payment" ? (
        paid ? (
          <Note kind="ok" title="Application fee paid">Confirmed on {fmtDate(me.feeConfirmedAt)}. The School will screen your application.</Note>
        ) : reference ? (
          <Card title="Pay the application fee">
            <div className="sub2" style={{ marginBottom: 8 }}>Pay {naira(me.applicationFee)} by card, bank transfer or USSD. It is confirmed automatically once the payment reaches the University.</div>
            <PayByCard reference={reference} amount={Number(me.applicationFee ?? 0)} />
            <div style={{ display: "flex", alignItems: "center", gap: 10, flexWrap: "wrap", marginTop: 8 }}>
              <button type="button" className="btn btn--go btn--sm" disabled={checking} onClick={() => void checkNow()}>{checking ? "Checking…" : "I’ve paid — check now"}</button>
              <span className="sub2">Already paid? This asks the gateway to confirm it.</span>
            </div>
            <div className="sub2" style={{ marginTop: 8 }}>Payment reference: <b className="tnum">{reference}</b> · Acceptance later: {naira(me.acceptanceFee)} + checking {naira(me.checkingFee)}.</div>
          </Card>
        ) : <Note kind="bad" title="The application fee could not be prepared">Reload the page, or write to the School of Postgraduate Studies quoting your application number.</Note>
      ) : null}

      {tab === "progress" ? <Progress me={me} /> : null}

      <div style={{ display: "flex", justifyContent: "space-between", marginTop: 8 }}>
        <button type="button" className="btn btn--ghost btn--sm" onClick={() => void load()}>Refresh</button>
        <button type="button" className="btn btn--ghost btn--sm" onClick={() => void signOut()}>Sign out</button>
      </div>

      <style>{`
        .pg-tabs { display: flex; gap: 4px; flex-wrap: wrap; background: var(--surface-2, #eef1f4); padding: 4px; border-radius: 10px; }
        .pg-tab { position: relative; border: 0; background: transparent; padding: 8px 14px; border-radius: 8px; font: inherit; font-size: 13px; font-weight: 600; color: var(--chrome-dim); cursor: pointer; }
        .pg-tab--on { background: var(--surface, #fff); color: var(--ink, #10233b); box-shadow: 0 1px 2px rgba(0,0,0,.08); }
        .pg-dot { display: inline-block; width: 7px; height: 7px; border-radius: 50%; background: var(--chrome); margin-left: 6px; vertical-align: middle; }
        .pg-steps { list-style: none; margin: 0; padding: 0; display: grid; gap: 2px; }
        .pg-step { display: grid; grid-template-columns: 20px 1fr auto; align-items: center; gap: 10px; padding: 7px 0; }
        .pg-step__dot { width: 12px; height: 12px; border-radius: 50%; border: 2px solid var(--line-2); background: transparent; margin-left: 2px; }
        .pg-step--done .pg-step__dot { background: var(--green-ink); border-color: var(--green-ink); }
        .pg-step--done .pg-step__label { font-weight: 600; }
        .pg-kv { display: grid; grid-template-columns: minmax(130px, 34%) 1fr; gap: 6px 14px; }
        .pg-kv dt { color: var(--chrome-dim); font-size: 13px; }
        .pg-kv dd { margin: 0; font-weight: 600; overflow-wrap: anywhere; }
        @media (max-width: 460px) { .pg-kv { grid-template-columns: 1fr; gap: 2px 0; } .pg-kv dd { margin-bottom: 6px; } }
      `}</style>
    </Wrap>
  );
}

function Documents({ credentials, onDone }: { credentials: DocMeta | null; onDone: () => Promise<void> }) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  async function upload(file: File) {
    setErr(null); setOk(null);
    if (file.type !== "application/pdf") { setErr({ status: 400, title: "The credentials must be one PDF file." }); return; }
    if (file.size > 8 * 1024 * 1024) { setErr({ status: 400, title: "The file is larger than 8 MB — reduce the scan resolution." }); return; }
    setBusy(true);
    try {
      const base64 = await new Promise<string>((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(String(reader.result).split(",")[1] ?? "");
        reader.onerror = () => reject(new Error("read failed"));
        reader.readAsDataURL(file);
      });
      const r = await fetch("/api/bff/api/v1/pg/documents", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ filename: file.name, contentType: file.type, base64 }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      setOk("Credentials uploaded.");
      await onDone();
    } finally { setBusy(false); }
  }

  return (
    <Card title="Credentials">
      <div className="sub2" style={{ marginBottom: 10 }}>
        Scan your <b>O&rsquo;Level</b>, <b>A&rsquo;Level</b> and <b>birth certificate / declaration of age</b> into a single PDF and upload it here. Bring the originals for screening.
      </div>
      {err ? <ProblemNotice problem={err} /> : null}
      {ok ? <Note kind="ok" title={ok}>The School will see it with your application.</Note> : null}
      {credentials ? (
        <div className="sub2" style={{ marginBottom: 8 }}>On record: <b>{credentials.filename}</b> — uploaded {fmtDate(credentials.uploaded_at)}. Uploading again replaces it.</div>
      ) : <div className="sub2" style={{ marginBottom: 8 }}>No credentials uploaded yet.</div>}
      <input ref={inputRef} type="file" accept="application/pdf" hidden onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(f); e.target.value = ""; }} />
      <button type="button" className="btn btn--primary btn--sm" disabled={busy} onClick={() => inputRef.current?.click()}>{busy ? "Uploading…" : credentials ? "Replace the PDF" : "Upload the PDF"}</button>
    </Card>
  );
}

function Progress({ me }: { me: Me }) {
  const steps = [
    { label: "Application submitted", done: !!me.submittedAt, when: me.submittedAt },
    { label: "Application fee paid", done: !!me.feeConfirmedAt, when: me.feeConfirmedAt },
    { label: "Department decision", done: !!me.deptDecidedAt, when: me.deptDecidedAt },
    { label: "School decision", done: !!me.spgsDecidedAt, when: me.spgsDecidedAt },
    { label: "Offer accepted", done: !!me.acceptedAt, when: me.acceptedAt },
    { label: "Admitted to the register", done: !!me.admittedAt, when: me.admittedAt },
  ];
  return (
    <>
      <Card title="Progress">
        <ol className="pg-steps">
          {steps.map((s) => (
            <li key={s.label} className={s.done ? "pg-step pg-step--done" : "pg-step"}>
              <span className="pg-step__dot" aria-hidden />
              <span className="pg-step__label">{s.label}</span>
              <span className="pg-step__when sub2">{s.when ? fmtDate(s.when) : (s.done ? "" : "pending")}</span>
            </li>
          ))}
        </ol>
      </Card>
      {me.spgsNote ? <Note kind="info" title="A note from the School">{me.spgsNote}</Note> : null}
      {me.deptNote ? <Note kind="info" title="A note from the department">{me.deptNote}</Note> : null}
    </>
  );
}

function KV({ rows }: { rows: [string, string][] }) {
  return (
    <dl className="pg-kv">
      {rows.map(([k, v]) => (
        <div key={k} style={{ display: "contents" }}><dt>{k}</dt><dd>{v}</dd></div>
      ))}
    </dl>
  );
}

function Card({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="card"><div className="card__body">
      <div style={{ fontWeight: 700, marginBottom: 10, paddingBottom: 8, borderBottom: "1px solid var(--line-2)" }}>{title}</div>
      {children}
    </div></div>
  );
}

function Wrap({ children, subtitle }: { children: ReactNode; subtitle?: string }) {
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
          <p>Everything the University holds on your application — bio-data, the degree(s) it rests on, your credentials, referees and proposal — with its progress and the fee to pay. This account becomes your student account on the day you are admitted.</p>
          {subtitle ? <p className="sub2" style={{ marginTop: 8 }}>{subtitle}</p> : null}
        </div>
      </div>
      <div className="login-panel">
        <div style={{ width: "100%", maxWidth: 660, display: "grid", gap: 14, paddingBlock: 24 }}>
          {children}
        </div>
      </div>
    </div>
  );
}
