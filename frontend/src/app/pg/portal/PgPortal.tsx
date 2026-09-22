"use client";

/**
 * The postgraduate applicant's dashboard, laid out to match the prototype's pgApplicantDash: it sits in
 * the portal's own shell (the sidebar with the "My application" menu, the branded top bar and the account
 * foot — the same shell every signed-in person gets, so the applicant's screen does not digress from the
 * rest of the portal), and inside it an at-a-glance tile row, the application beside its progress, then
 * bio-data, the degree(s) the admission rests on, the proposal, the referees, the credentials document
 * and the fee. Every call is scoped to the signed-in applicant.
 */
import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import type { Problem } from "@/lib/api";
import { Note, Panel, PBody, Tiles, KvGrid } from "@/components/proto/ui";
import { Shell, type Me as ShellMe } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PayByCard } from "@/app/applicant/common";

interface Referee { name: string; email: string | null; institution: string | null; position: string | null }
interface PriorDegree { kind: string; institution: string | null; award: string | null; field?: string | null; class_of_degree: string | null; cgpa: number | null; year: number | null }
const QUAL_LABEL: Record<string, string> = {
  FIRST: "First degree", MASTERS: "Master’s degree", PGD: "Postgraduate Diploma", HND: "Higher National Diploma",
  ND: "National Diploma", NCE: "Nigeria Certificate in Education", PHD: "Doctorate (PhD)", OTHER: "Other qualification",
};
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
const STATE_SHORT: Record<string, string> = {
  DRAFT: "Draft", SUBMITTED: "Submitted", DEPT_RECOMMENDED: "Recommended", DEPT_DECLINED: "Declined",
  OFFERED: "Offered", NOT_OFFERED: "Not offered", ACCEPTED: "Accepted", ADMITTED: "Admitted",
};
function fmtDate(v: string | null): string {
  if (!v) return "—";
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? "—" : d.toLocaleDateString("en-GB", { day: "2-digit", month: "long", year: "numeric" });
}
const val = (v: string | number | null | undefined) => (v === null || v === undefined || v === "" ? "—" : String(v));

export function PgPortal() {
  const [me, setMe] = useState<Me | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [reference, setReference] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
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
    } finally { setLoading(false); }
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

  if (loading) return <Bare><Note kind="info" title="Loading your application…">One moment.</Note></Bare>;

  if (!me) {
    return (
      <Bare>
        <Note kind="info" title="Sign in to see your application">Sign in with the email you applied with (or your PG application number) and the password you chose when you applied.</Note>
        <div style={{ marginTop: 12 }}><Link href="/login?next=/pg/portal" className="btn btn--primary btn--sm">Sign in</Link></div>
      </Bare>
    );
  }

  /* the portal's own shell, with the applicant's "My application" menu, branded top bar and account foot —
     the same shell every signed-in person gets, so the applicant's screen matches the rest of the portal */
  const shellMe: ShellMe = {
    actorId: "", activeOffice: "pgapplicant", offices: ["pgapplicant"],
    name: me.name, staffNumber: me.applicationNo, sessionId: null, unit: me.programme, waiting: {},
  };

  const paid = !!me.feeConfirmedAt;
  const credentials = me.documents.find((d) => d.kind === "CREDENTIALS") ?? null;
  const passport = me.documents.find((d) => d.kind === "PASSPORT") ?? null;
  const degrees = me.priorDegrees.length ? me.priorDegrees : [{ kind: "FIRST", ...me.prior, class_of_degree: me.prior.classOfDegree } as unknown as PriorDegree];
  const steps: [string, boolean, string | null][] = [
    ["Application submitted", !!me.submittedAt, me.submittedAt],
    ["Application fee paid", paid, me.feeConfirmedAt],
    ["Department decision", !!me.deptDecidedAt, me.deptDecidedAt],
    ["School decision", !!me.spgsDecidedAt, me.spgsDecidedAt],
    ["Offer accepted", !!me.acceptedAt, me.acceptedAt],
    ["Admitted to the register", !!me.admittedAt, me.admittedAt],
  ];

  return (
    <Shell route="pg/portal" me={shellMe}>
      <style>{`
        .pg-steps { list-style:none; margin:0; padding:0; display:grid; gap:2px; }
        .pg-step { display:grid; grid-template-columns:20px 1fr auto; align-items:center; gap:10px; padding:7px 0; }
        .pg-step__dot { width:12px; height:12px; border-radius:50%; border:2px solid var(--line-2); background:transparent; margin-left:2px; }
        .pg-step--done .pg-step__dot { background:var(--green-ink); border-color:var(--green-ink); }
        .pg-step--done .pg-step__label { font-weight:600; }
      `}</style>
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Note kind={paid ? "ok" : "info"} title={`${me.name} · ${me.applicationNo}`}>
        Your postgraduate application is <b>{STATE_LABEL[me.state] ?? me.state}</b>.
        {me.state === "OFFERED" ? " You have an offer of admission." : ""}
        {!paid ? " Pay the application fee below to have it screened." : ""}
      </Note>

      <Tiles items={[
        ["Programme", me.award ?? LEVEL[me.entryLevel] ?? "PG", null, me.programme],
        ["Application fee", paid ? "Paid" : naira(me.applicationFee), paid ? "var(--green-ink)" : "var(--chrome)", paid ? "confirmed" : "unpaid"],
        ["Credentials", credentials ? "1 PDF" : "None", credentials ? null : "var(--chrome)", "O’/A’Level, birth cert."],
        ["Stage", STATE_SHORT[me.state] ?? me.state, me.state === "ADMITTED" ? "var(--green-ink)" : null, me.department],
      ]} />

      <div className="grid grid--2" style={{ alignItems: "start" }}>
        <Panel title="Application">
          <PBody>
            <KvGrid cls="grid--1" pairs={[
              ["Application number", me.applicationNo], ["Session", me.session], ["Programme", me.programme],
              ["Award", me.award ?? "—"], ["Level", LEVEL[me.entryLevel] ?? String(me.entryLevel)],
              ["Faculty", me.faculty], ["Department", me.department], ["Submitted", fmtDate(me.submittedAt)],
            ]} />
          </PBody>
        </Panel>
        <Panel title="Progress">
          <PBody>
            <ol className="pg-steps">
              {steps.map(([label, done, when]) => (
                <li key={label} className={done ? "pg-step pg-step--done" : "pg-step"}>
                  <span className="pg-step__dot" aria-hidden />
                  <span className="pg-step__label">{label}</span>
                  <span className="sub2">{when ? fmtDate(when) : (done ? "" : "pending")}</span>
                </li>
              ))}
            </ol>
          </PBody>
        </Panel>
      </div>

      <Panel title="Bio-data">
        <PBody>
          <KvGrid cls="grid--2" pairs={[
            ["Surname", me.surname], ["Other names", me.otherNames],
            ["Sex", me.biodata.sex === "F" ? "Female" : me.biodata.sex === "M" ? "Male" : "—"],
            ["Date of birth", fmtDate(me.biodata.dateOfBirth)], ["State of origin", val(me.biodata.stateOfOrigin)],
            ["LGA", val(me.biodata.lga)], ["Email", me.email], ["Phone", val(me.phone)],
          ]} />
        </PBody>
      </Panel>

      {degrees.map((pd, i) => (
        <Panel key={i} title={QUAL_LABEL[pd.kind] ?? "Qualification"}>
          <PBody>
            <KvGrid cls="grid--2" pairs={[
              ["Institution", val(pd.institution)], ["Award", val(pd.award)], ["Field of study", val(pd.field)],
              ["Class / result", val(pd.class_of_degree)], ["CGPA", val(pd.cgpa)], ["Year", val(pd.year)],
            ]} />
          </PBody>
        </Panel>
      ))}

      {me.research || me.proposal.title || me.proposal.text ? (
        <Panel title="Research proposal">
          <PBody>
            <KvGrid cls="grid--1" pairs={[["Title", val(me.proposal.title)]]} />
            {me.proposal.text ? <div style={{ marginTop: 8, whiteSpace: "pre-wrap", lineHeight: 1.55 }}>{me.proposal.text}</div> : null}
          </PBody>
        </Panel>
      ) : null}

      {me.referees.length ? (
        <Panel title="Referees">
          <PBody style={{ display: "grid", gap: 12 }}>
            {me.referees.map((rf, i) => (
              <div key={i} style={{ borderTop: i ? "1px solid var(--line-2)" : "none", paddingTop: i ? 10 : 0 }}>
                <KvGrid cls="grid--2" pairs={[["Name", val(rf.name)], ["Position", val(rf.position)], ["Institution", val(rf.institution)], ["Email", val(rf.email)]]} />
              </div>
            ))}
          </PBody>
        </Panel>
      ) : null}

      {/* Payment comes first; the credentials and passport uploads unlock once the fee is confirmed */}
      {paid ? (
        <Note kind="ok" title="Application fee paid">Confirmed on {fmtDate(me.feeConfirmedAt)}. The School will screen your application; its progress shows above.</Note>
      ) : reference ? (
        <Panel title="Application fee">
          <PBody>
            <div className="sub2" style={{ marginBottom: 8 }}>Pay {naira(me.applicationFee)} by card, bank transfer or USSD. It is confirmed automatically once the payment reaches the University. <b>Upload your credentials and passport after payment.</b></div>
            <PayByCard reference={reference} amount={Number(me.applicationFee ?? 0)} />
            <div style={{ display: "flex", alignItems: "center", gap: 10, flexWrap: "wrap", marginTop: 8 }}>
              <button type="button" className="btn btn--go btn--sm" disabled={checking} onClick={() => void checkNow()}>{checking ? "Checking…" : "I’ve paid — check now"}</button>
              <span className="sub2">Already paid? This asks the gateway to confirm it.</span>
            </div>
            <div className="sub2" style={{ marginTop: 8 }}>Reference: <b className="tnum">{reference}</b> · Acceptance later: {naira(me.acceptanceFee)} + checking {naira(me.checkingFee)}.</div>
          </PBody>
        </Panel>
      ) : <Note kind="bad" title="The application fee could not be prepared">Reload the page, or write to the School of Postgraduate Studies quoting your application number.</Note>}

      <Documents credentials={credentials} paid={paid} onDone={load} />
      <Passport passport={passport} paid={paid} onDone={load} />

      {me.spgsNote ? <Note kind="info" title="A note from the School">{me.spgsNote}</Note> : null}

      <div style={{ display: "flex", justifyContent: "flex-start", marginTop: 6 }}>
        <button type="button" className="btn btn--ghost btn--sm" onClick={() => void load()}>Refresh</button>
      </div>
    </Shell>
  );
}

function Documents({ credentials, paid, onDone }: { credentials: DocMeta | null; paid: boolean; onDone: () => Promise<void> }) {
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
      setOk("Credentials uploaded."); await onDone();
    } finally { setBusy(false); }
  }

  return (
    <Panel title="Credentials">
      <PBody>
        <div className="sub2" style={{ marginBottom: 10 }}>
          Scan your <b>O&rsquo;Level</b>, <b>A&rsquo;Level</b> and <b>birth certificate / declaration of age</b> into a single PDF and upload it here. Bring the originals for screening.
        </div>
        {!paid ? (
          <Note kind="info" title="Pay the application fee first">Once your payment is confirmed you can upload your credentials here.</Note>
        ) : (
          <>
            {err ? <ProblemNotice problem={err} /> : null}
            {ok ? <Note kind="ok" title={ok}>The School will see it with your application.</Note> : null}
            {credentials ? (
              <div className="sub2" style={{ marginBottom: 8 }}>On record: <b>{credentials.filename}</b> — uploaded {fmtDate(credentials.uploaded_at)}. Uploading again replaces it.</div>
            ) : <div className="sub2" style={{ marginBottom: 8 }}>No credentials uploaded yet.</div>}
            <input ref={inputRef} type="file" accept="application/pdf" hidden onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(f); e.target.value = ""; }} />
            <button type="button" className="btn btn--primary btn--sm" disabled={busy} onClick={() => inputRef.current?.click()}>{busy ? "Uploading…" : credentials ? "Replace the PDF" : "Upload the PDF"}</button>
          </>
        )}
      </PBody>
    </Panel>
  );
}

function Passport({ passport, paid, onDone }: { passport: DocMeta | null; paid: boolean; onDone: () => Promise<void> }) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [ok, setOk] = useState<string | null>(null);

  async function upload(file: File) {
    setErr(null); setOk(null);
    if (file.type !== "image/jpeg" && file.type !== "image/png") { setErr({ status: 400, title: "The passport must be a JPEG or PNG photo." }); return; }
    if (file.size > 4 * 1024 * 1024) { setErr({ status: 400, title: "The photo is larger than 4 MB — reduce its size." }); return; }
    setBusy(true);
    try {
      const base64 = await new Promise<string>((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(String(reader.result).split(",")[1] ?? "");
        reader.onerror = () => reject(new Error("read failed"));
        reader.readAsDataURL(file);
      });
      const r = await fetch("/api/bff/api/v1/pg/passport", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ filename: file.name, contentType: file.type, base64 }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      setOk("Passport uploaded."); await onDone();
    } finally { setBusy(false); }
  }

  return (
    <Panel title="Passport photograph">
      <PBody>
        <div className="sub2" style={{ marginBottom: 10 }}>
          Upload a clear, recent <b>passport photograph</b> (JPEG or PNG) on a plain background. It appears on your record and, once you are admitted, on your identity and examination cards.
        </div>
        {!paid ? (
          <Note kind="info" title="Pay the application fee first">Once your payment is confirmed you can upload your passport here.</Note>
        ) : (
          <>
            {err ? <ProblemNotice problem={err} /> : null}
            {ok ? <Note kind="ok" title={ok}>The School will see it with your application.</Note> : null}
            {passport ? (
              <div className="sub2" style={{ marginBottom: 8 }}>On record: <b>{passport.filename}</b> — uploaded {fmtDate(passport.uploaded_at)}. Uploading again replaces it.</div>
            ) : <div className="sub2" style={{ marginBottom: 8 }}>No passport uploaded yet.</div>}
            <input ref={inputRef} type="file" accept="image/jpeg,image/png" hidden onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(f); e.target.value = ""; }} />
            <button type="button" className="btn btn--primary btn--sm" disabled={busy} onClick={() => inputRef.current?.click()}>{busy ? "Uploading…" : passport ? "Replace the photo" : "Upload the photo"}</button>
          </>
        )}
      </PBody>
    </Panel>
  );
}

/** a plain branded frame for the two states shown before the shell can be built (loading, or not signed in) */
function Bare({ children }: { children: React.ReactNode }) {
  return (
    <div style={{ minHeight: "100vh", background: "var(--bg)" }}>
      <header style={{ background: "var(--chrome-deep, #0b1f3a)", color: "#fff", padding: "16px 22px", display: "flex", alignItems: "center", gap: 14 }}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/crest.png" alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
        <div style={{ flexGrow: 1, minWidth: 0 }}>
          <div style={{ fontSize: 11, letterSpacing: ".6px", textTransform: "uppercase", opacity: .7 }}>School of Postgraduate Studies</div>
          <h1 style={{ fontFamily: "var(--serif, Georgia)", fontSize: 20, fontWeight: 700, margin: "2px 0 0" }}>Your postgraduate application</h1>
        </div>
      </header>
      <div style={{ maxWidth: 900, margin: "0 auto", padding: "18px 16px 56px", display: "grid", gap: 14 }}>
        {children}
      </div>
    </div>
  );
}
