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

interface Referee { name: string; email: string | null; phone: string | null; institution: string | null; position: string | null; submitted_at: string | null; verdict: string | null }
interface PriorDegree { kind: string; institution: string | null; award: string | null; field?: string | null; class_of_degree: string | null; cgpa: number | null; year: number | null }
interface DocMeta { id: string; kind: string; filename: string; content_type: string; uploaded_at: string }
interface Me {
  applicationNo: string; session: string; name: string; surname: string; otherNames: string;
  email: string; phone: string | null;
  state: string; entryLevel: number; programme: string; programmeCode: string; award: string | null; research: boolean;
  faculty: string; department: string; submittedAt: string | null; createdAt: string | null; feeConfirmedAt: string | null;
  applicationFee: number | null; acceptanceFee: number | null; checkingFee: number | null; liveReference: string | null;
  deptNote: string | null; deptDecidedAt: string | null; spgsNote: string | null; spgsDecidedAt: string | null;
  acceptedAt: string | null; admittedAt: string | null;
  decisionLocked?: boolean; checkingConfirmedAt: string | null; acceptanceConfirmedAt: string | null;
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
  DECISION_LOCKED: "A decision has been made — pay the checking fee to view it",
};
const STATE_SHORT: Record<string, string> = {
  DRAFT: "Draft", SUBMITTED: "Submitted", DEPT_RECOMMENDED: "Recommended", DEPT_DECLINED: "Declined",
  OFFERED: "Offered", NOT_OFFERED: "Not offered", ACCEPTED: "Accepted", ADMITTED: "Admitted",
  DECISION_LOCKED: "Decision ready",
};
function fmtDate(v: string | null): string {
  if (!v) return "—";
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? "—" : d.toLocaleDateString("en-GB", { day: "2-digit", month: "long", year: "numeric" });
}
const val = (v: string | number | null | undefined) => (v === null || v === undefined || v === "" ? "—" : String(v));

/** the documents an applicant uploads, each on its own PDF (the School downloads them merged) */
const DOC_TYPES: { kind: string; label: string; optional?: boolean; multi?: boolean }[] = [
  { kind: "HIGHER_DEGREE", label: "Higher degree certificate", multi: true },
  { kind: "UNDERGRAD_CERT", label: "Undergraduate certificate" },
  { kind: "OLEVEL", label: "O’Level result" },
  { kind: "BIRTH_CERTIFICATE", label: "Birth certificate / declaration of age" },
  { kind: "NYSC", label: "NYSC certificate" },
  { kind: "LGA_CERTIFICATE", label: "LGA / indigene certificate" },
  { kind: "NAME_CHANGE", label: "Change of name / marriage certificate", optional: true },
];

export function PgPortal() {
  const [me, setMe] = useState<Me | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [reference, setReference] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [checking, setChecking] = useState(false);
  const [verifying, setVerifying] = useState(false);
  const [emailing, setEmailing] = useState(false);
  const [emailed, setEmailed] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const r = await fetch("/api/bff/api/v1/pg/me", { cache: "no-store" });
      setProblem(null);
      if (r.status === 401) { setMe(null); setLoading(false); return; }
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); setLoading(false); return; }
      const m = j as Me;
      setMe(m);
      // the fee to prepare for the current step: application, then checking (to see the decision), then acceptance
      const kind = !m.feeConfirmedAt ? "APPLICATION"
        : m.state === "DECISION_LOCKED" ? "CHECKING"
        : (!m.acceptanceConfirmedAt && (m.state === "OFFERED" || m.state === "ACCEPTED" || m.state === "ADMITTED")) ? "ACCEPTANCE"
        : null;
      if (kind) {
        const fr = await fetch(`/api/bff/api/v1/pg/fee-reference?kind=${kind}`, { method: "POST", headers: { "Content-Type": "application/json" } });
        const fj = await fr.json().catch(() => null);
        setReference(fr.ok && fj && typeof fj === "object" && "reference" in fj ? String((fj as { reference: string }).reference) : null);
      } else {
        setReference(null);
      }
    } finally { setLoading(false); }
  }, []);

  /* verify a reference and re-read the application a few times — a gateway can take a little while to
     settle after the "success" screen, so we poll rather than checking once and leaving it unpaid.
     which confirmation to wait for is read from the reference's kind (APP / CHK / ACC). */
  const pollConfirm = useCallback(async (ref: string, tries: number): Promise<boolean> => {
    const done = (m: Me) => ref.includes("PGACC") ? !!m.acceptanceConfirmedAt
      : ref.includes("PGCHK") ? !!m.checkingConfirmedAt
      : !!m.feeConfirmedAt;
    for (let i = 0; i < tries; i++) {
      try { await fetch("/api/bff/api/v1/payments/verify", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ reference: ref }) }); } catch { /* ignore */ }
      const r = await fetch("/api/bff/api/v1/pg/me", { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (r.ok && j) { setMe(j as Me); if (done(j as Me)) return true; }
      if (i < tries - 1) await new Promise((res) => setTimeout(res, 4000));
    }
    return false;
  }, []);

  useEffect(() => {
    const paidRef = new URLSearchParams(window.location.search).get("paid");
    void (async () => {
      await load();
      if (paidRef) {
        setVerifying(true);
        await pollConfirm(paidRef, 8);
        setVerifying(false);
        await load();
      }
    })();
  }, [load, pollConfirm]);

  async function checkNow() {
    if (!reference) return;
    setChecking(true);
    try {
      await pollConfirm(reference, 4);
      await load();
    } finally { setChecking(false); }
  }

  async function emailSummary() {
    setEmailing(true); setEmailed(null);
    try {
      const r = await fetch("/api/bff/api/v1/pg/email-summary", { method: "POST", headers: { "Content-Type": "application/json" } });
      const j = await r.json().catch(() => null);
      if (r.ok && j && j.ok) setEmailed(String(j.email ?? ""));
    } finally { setEmailing(false); }
  }

  if (loading) return <Bare><Note kind="info" title="Loading your application…">One moment.</Note></Bare>;

  if (!me) {
    return (
      <Bare>
        <Note kind="info" title="Sign in to see your application">Sign in with the email you applied with (or your PG application number) and the password you chose when you applied.</Note>
        <div className="mt-3"><Link href="/login?next=/pg/portal" className="btn btn--primary btn--sm">Sign in</Link></div>
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
  const passport = me.documents.find((d) => d.kind === "PASSPORT") ?? null;
  const docCount = me.documents.filter((d) => d.kind !== "PASSPORT").length;
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

      {verifying ? <Note kind="info" title="Confirming your payment…">This can take a moment after the gateway&rsquo;s success page — the page updates on its own once the payment reaches the University.</Note> : null}

      <Tiles items={[
        ["Programme", me.award ?? LEVEL[me.entryLevel] ?? "PG", null, me.programme],
        ["Application fee", paid ? "Paid" : naira(me.applicationFee), paid ? "var(--green-ink)" : "var(--chrome)", paid ? "confirmed" : "unpaid"],
        ["Documents", `${new Set(me.documents.filter((d) => d.kind !== "PASSPORT").map((d) => d.kind)).size}/${DOC_TYPES.length}`, docCount ? null : "var(--chrome)", "uploaded"],
        ["Stage", STATE_SHORT[me.state] ?? me.state, me.state === "ADMITTED" ? "var(--green-ink)" : null, me.department],
      ]} />

      {/* The decision gate: once the School decides, the applicant pays the checking fee to view the
          outcome; if offered, they pay the acceptance fee to accept, and can then print the offer letter. */}
      {paid && me.state === "DECISION_LOCKED" ? (
        <Panel title="Your admission decision is ready">
          <PBody>
            <div className="sub2 mb-2">
              The School of Postgraduate Studies has taken a decision on your application. Pay the checking fee of <b>{naira(me.checkingFee)}</b> to view your admission status. If you are offered a place, you will then pay the acceptance fee to accept the offer and print your admission letter.
            </div>
            {reference ? (
              <>
                <PayByCard reference={reference} amount={Number(me.checkingFee ?? 0)} />
                <div style={{ display: "flex", alignItems: "center", gap: 10, flexWrap: "wrap", marginTop: 8 }}>
                  <button type="button" className="btn btn--go btn--sm" disabled={checking} onClick={() => void checkNow()}>{checking ? "Checking…" : "I’ve paid — show my status"}</button>
                  <span className="sub2">Reference: <b className="tnum">{reference}</b></span>
                </div>
              </>
            ) : <Note kind="bad" title="The checking fee could not be prepared">Reload the page, or write to the School quoting your application number.</Note>}
          </PBody>
        </Panel>
      ) : null}

      {paid && !me.acceptanceConfirmedAt && (me.state === "OFFERED" || me.state === "ACCEPTED" || me.state === "ADMITTED") ? (
        <Panel title="Congratulations — you have been offered a place">
          <PBody>
            <Note kind="ok" title={`Offer of provisional admission · ${me.programme}`}>
              You have been offered provisional admission for the {me.session} session. Pay the acceptance fee of <b>{naira(me.acceptanceFee)}</b> to accept the offer, then print your offer of admission.
            </Note>
            {reference ? (
              <div className="mt-3">
                <PayByCard reference={reference} amount={Number(me.acceptanceFee ?? 0)} />
                <div style={{ display: "flex", alignItems: "center", gap: 10, flexWrap: "wrap", marginTop: 8 }}>
                  <button type="button" className="btn btn--go btn--sm" disabled={checking} onClick={() => void checkNow()}>{checking ? "Checking…" : "I’ve paid — check now"}</button>
                  <span className="sub2">Reference: <b className="tnum">{reference}</b></span>
                </div>
              </div>
            ) : <Note kind="bad" title="The acceptance fee could not be prepared">Reload the page, or write to the School quoting your application number.</Note>}
          </PBody>
        </Panel>
      ) : null}

      {paid && me.acceptanceConfirmedAt ? (
        <Panel title="Offer of admission">
          <PBody>
            <Note kind="ok" title="Your offer is accepted">You accepted your offer of admission on {fmtDate(me.acceptanceConfirmedAt)} (acceptance fee paid). Download and print your offer of admission below; bring the originals of all uploaded documents for screening.</Note>
            <div className="mt-3">
              <a href="/pg/offer/pdf" target="_blank" rel="noopener" className="btn btn--primary btn--sm">Download / print offer of admission (PDF)</a>
            </div>
          </PBody>
        </Panel>
      ) : null}

      {paid && me.state === "NOT_OFFERED" ? (
        <Panel title="Admission decision">
          <PBody>
            <Note kind="bad" title="Not offered a place">We regret that you were not offered admission for the {me.session} session.{me.spgsNote ? "" : " You may wish to apply again in a future session."}</Note>
            {me.spgsNote ? <div className="sub2 mt-2">{me.spgsNote}</div> : null}
          </PBody>
        </Panel>
      ) : null}

      {/* Payment comes first; the academic record, credentials and passport unlock once the fee is confirmed */}
      {paid ? null : reference ? (
        <Panel title="Application fee">
          <PBody>
            <div className="sub2 mb-2">Pay {naira(me.applicationFee)} by card, bank transfer or USSD. It is confirmed automatically once the payment reaches the University. <b>Upload your credentials and passport after payment.</b></div>
            <PayByCard reference={reference} amount={Number(me.applicationFee ?? 0)} />
            <div style={{ display: "flex", alignItems: "center", gap: 10, flexWrap: "wrap", marginTop: 8 }}>
              <button type="button" className="btn btn--go btn--sm" disabled={checking} onClick={() => void checkNow()}>{checking ? "Checking…" : "I’ve paid — check now"}</button>
              <span className="sub2">Already paid? This asks the gateway to confirm it.</span>
            </div>
            <div className="sub2 mt-2">Reference: <b className="tnum">{reference}</b> · Acceptance later: {naira(me.acceptanceFee)} + checking {naira(me.checkingFee)}.</div>
          </PBody>
        </Panel>
      ) : <Note kind="bad" title="The application fee could not be prepared">Reload the page, or write to the School of Postgraduate Studies quoting your application number.</Note>}

      <div className="grid grid--2" style={{ alignItems: "start" }}>
        <Panel title="Application">
          <PBody>
            <KvGrid cls="grid--1" pairs={[
              ["Application number", me.applicationNo], ["Session", me.session], ["Programme", me.programme],
              ["Award", me.award ?? "—"], ["Level", LEVEL[me.entryLevel] ?? String(me.entryLevel)],
              ["Faculty", me.faculty], ["Department", me.department], ["Date applied", fmtDate(me.submittedAt)],
            ]} />
            <div className="sub2 eyebrow eyebrow--gap">Bio-data</div>
            <KvGrid cls="grid--2" pairs={[
              ["Surname", me.surname], ["Other names", me.otherNames],
              ["Sex", me.biodata.sex === "F" ? "Female" : me.biodata.sex === "M" ? "Male" : "—"],
              ["Date of birth", fmtDate(me.biodata.dateOfBirth)], ["State of origin", val(me.biodata.stateOfOrigin)],
              ["LGA", val(me.biodata.lga)], ["Email", me.email], ["Phone", val(me.phone)],
            ]} />
            {me.research || me.proposal.title ? (
              <>
                <div className="sub2 eyebrow eyebrow--gap">Research proposal</div>
                <KvGrid cls="grid--1" pairs={[["Title", val(me.proposal.title)]]} />
                {me.proposal.text ? <div className="sub2" style={{ marginTop: 6, whiteSpace: "pre-wrap", lineHeight: 1.55 }}>{me.proposal.text}</div> : null}
              </>
            ) : null}
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

      <CompleteSteps me={me} paid={paid} passport={passport} onDone={load} />

      {paid ? (
        <Panel title="Application summary">
          <PBody>
            <div className="sub2 mb-3">Print your completed application, or download it as a PDF. You can also have the summary emailed to you.</div>
            <div className="row">
              <a href="/pg/summary/pdf" target="_blank" rel="noopener" className="btn btn--primary btn--sm">Download / print summary (PDF)</a>
              <button type="button" className="btn btn--ghost btn--sm" disabled={emailing} onClick={() => void emailSummary()}>{emailing ? "Sending…" : "Email me the summary"}</button>
              {emailed ? <span className="sub2 ink-green">Sent to {emailed}.</span> : null}
            </div>
          </PBody>
        </Panel>
      ) : null}

      {me.spgsNote && me.state !== "NOT_OFFERED" ? <Note kind="info" title="A note from the School">{me.spgsNote}</Note> : null}

      <div style={{ display: "flex", justifyContent: "flex-start", marginTop: 6 }}>
        <button type="button" className="btn btn--ghost btn--sm" onClick={() => void load()}>Refresh</button>
      </div>
    </Shell>
  );
}

function DocList({ documents, paid, onDone }: { documents: DocMeta[]; paid: boolean; onDone: () => Promise<void> }) {
  const [busy, setBusy] = useState<string | null>(null);
  const [err, setErr] = useState<Problem | null>(null);

  async function upload(kind: string, file: File) {
    setErr(null);
    if (file.type !== "application/pdf") { setErr({ status: 400, title: "Each document is a single PDF file.", detail: "Scan the certificate to PDF and upload it." }); return; }
    if (file.size > 8 * 1024 * 1024) { setErr({ status: 400, title: "The file is larger than 8 MB — reduce the scan resolution." }); return; }
    setBusy(kind);
    try {
      const base64 = await new Promise<string>((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(String(reader.result).split(",")[1] ?? "");
        reader.onerror = () => reject(new Error("read failed"));
        reader.readAsDataURL(file);
      });
      const r = await fetch("/api/bff/api/v1/pg/documents", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ kind, filename: file.name, contentType: file.type, base64 }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      await onDone();
    } finally { setBusy(null); }
  }

  async function remove(id: string) {
    setErr(null); setBusy(id);
    try {
      const r = await fetch(`/api/bff/api/v1/pg/documents/${encodeURIComponent(id)}`, { method: "DELETE" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      await onDone();
    } finally { setBusy(null); }
  }

  return (
    <Panel title="Documents">
      <PBody>
        <div className="sub2 mb-3">
          Upload each document as its own <b>PDF</b>. Bring the originals for screening. The School reads them together as one document.
        </div>
        {!paid ? (
          <Note kind="info" title="Pay the application fee first">Once your payment is confirmed you can upload your documents here.</Note>
        ) : (
          <>
            {err ? <ProblemNotice problem={err} /> : null}
            <div style={{ display: "grid", gap: 2 }}>
              {DOC_TYPES.map((t) => {
                const on = documents.filter((d) => d.kind === t.kind);
                const single = on[0] ?? null;
                return (
                  <div key={t.kind} style={{ padding: "9px 0", borderBottom: "1px solid var(--line-2)" }}>
                    <div style={{ display: "flex", gap: 12, alignItems: "center", flexWrap: "wrap" }}>
                      <div style={{ flex: "1 1 240px", minWidth: 0 }}>
                        <div style={{ fontWeight: 600, fontSize: 13.5 }}>{t.label}{t.optional ? <span className="sub2" style={{ fontWeight: 400 }}> · optional</span> : null}{t.multi ? <span className="sub2" style={{ fontWeight: 400 }}> · you may add more than one</span> : null}</div>
                        {t.multi
                          ? <div className="sub2">{on.length ? `${on.length} uploaded` : "Not uploaded"}</div>
                          : <div className="sub2">{single ? <>On record: {single.filename} · uploaded {fmtDate(single.uploaded_at)}</> : "Not uploaded"}</div>}
                      </div>
                      <label className={`btn btn--sm ${!t.multi && single ? "btn--ghost" : "btn--primary"}`} style={{ cursor: busy ? "not-allowed" : "pointer", margin: 0 }}>
                        {busy === t.kind ? "Uploading…" : t.multi ? (on.length ? "Add another" : "Upload PDF") : single ? "Replace" : "Upload PDF"}
                        <input type="file" accept="application/pdf" hidden disabled={busy !== null} onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(t.kind, f); e.target.value = ""; }} />
                      </label>
                    </div>
                    {t.multi && on.length ? (
                      <div style={{ display: "grid", gap: 3, marginTop: 6, paddingLeft: 4 }}>
                        {on.map((d) => (
                          <div key={d.id} className="sub2 row">
                            <span>• {d.filename} · uploaded {fmtDate(d.uploaded_at)}</span>
                            <button type="button" className="btn btn--ghost btn--sm" disabled={busy !== null} onClick={() => void remove(d.id)}>{busy === d.id ? "Removing…" : "Remove"}</button>
                          </div>
                        ))}
                      </div>
                    ) : null}
                  </div>
                );
              })}
            </div>
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
        <div className="sub2 mb-3">
          Upload a clear, recent <b>passport photograph</b> (JPEG or PNG) on a plain background. It appears on your record and, once you are admitted, on your identity and examination cards.
        </div>
        {!paid ? (
          <Note kind="info" title="Pay the application fee first">Once your payment is confirmed you can upload your passport here.</Note>
        ) : (
          <>
            {err ? <ProblemNotice problem={err} /> : null}
            {ok ? <Note kind="ok" title={ok}>The School will see it with your application.</Note> : null}
            {passport ? (
              <div className="sub2 mb-2">On record: <b>{passport.filename}</b> — uploaded {fmtDate(passport.uploaded_at)}. Uploading again replaces it.</div>
            ) : <div className="sub2 mb-2">No passport uploaded yet.</div>}
            <input ref={inputRef} type="file" accept="image/jpeg,image/png" hidden onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(f); e.target.value = ""; }} />
            <button type="button" className="btn btn--primary btn--sm" disabled={busy} onClick={() => inputRef.current?.click()}>{busy ? "Uploading…" : passport ? "Replace the photo" : "Upload the photo"}</button>
          </>
        )}
      </PBody>
    </Panel>
  );
}

const CLASSES = ["First Class", "Second Class (Upper)", "Second Class (Lower)", "Third Class", "Pass", "Distinction", "Credit", "Merit"];
const QUAL_KINDS: [string, string][] = [
  ["MASTERS", "Master’s degree"], ["PGD", "Postgraduate Diploma (PGD)"], ["HND", "Higher National Diploma (HND)"],
  ["ND", "National Diploma (ND)"], ["NCE", "Nigeria Certificate in Education (NCE)"], ["PHD", "Doctorate (PhD)"], ["OTHER", "Other qualification"],
];
type QRow = { kind: string; institution: string; award: string; field: string; classOfDegree: string; cgpa: string; year: string };
const emptyQ = (kind = "MASTERS"): QRow => ({ kind, institution: "", award: "", field: "", classOfDegree: "", cgpa: "", year: "" });

/** the post-payment tasks arranged as steps — the applicant moves from one to the next, as on the apply form */
function CompleteSteps({ me, paid, passport, onDone }: { me: Me; paid: boolean; passport: DocMeta | null; onDone: () => Promise<void> }) {
  const [step, setStep] = useState(1);
  if (!paid) {
    return (
      <Panel title="Complete your application">
        <PBody><Note kind="info" title="Pay the application fee first">Once your payment is confirmed you complete your application here — your first degree, other qualifications, referees, documents and passport.</Note></PBody>
      </Panel>
    );
  }
  const first = me.priorDegrees.find((d) => d.kind === "FIRST");
  const docCount = me.documents.filter((d) => d.kind !== "PASSPORT").length;
  const steps: { label: string; done: boolean; node: React.ReactNode }[] = [
    { label: "Academic record", done: !!(first?.institution || first?.award || me.prior.institution || me.prior.award), node: <AcademicRecord me={me} paid onDone={onDone} /> },
    { label: "Referees", done: me.referees.length > 0, node: <RefereesEditor me={me} paid onDone={onDone} /> },
    { label: "Documents", done: docCount > 0, node: <DocList documents={me.documents} paid onDone={onDone} /> },
    { label: "Passport", done: !!passport, node: <Passport passport={passport} paid onDone={onDone} /> },
  ];
  const cur = Math.min(step, steps.length);
  return (
    <Panel title="Complete your application">
      <PBody style={{ display: "grid", gap: 14 }}>
        <PortalStepper steps={steps.map((s) => ({ label: s.label, done: s.done }))} current={cur} onGo={setStep} />
        {steps[cur - 1].node}
        <div className="row">
          <button type="button" className="btn btn--ghost btn--sm" disabled={cur === 1} onClick={() => setStep(cur - 1)}>Back</button>
          <span className="grow" />
          <span className="sub2">Step {cur} of {steps.length}</span>
          <button type="button" className="btn btn--primary btn--sm" disabled={cur === steps.length} onClick={() => setStep(cur + 1)}>Next</button>
        </div>
      </PBody>
    </Panel>
  );
}

/** a step indicator with a tick on completed steps; any step can be opened directly */
function PortalStepper({ steps, current, onGo }: { steps: { label: string; done: boolean }[]; current: number; onGo: (n: number) => void }) {
  return (
    <div style={{ display: "flex", gap: 8 }}>
      {steps.map((s, i) => {
        const n = i + 1, cur = current === n;
        const on = cur || s.done;
        return (
          <button key={s.label} type="button" onClick={() => onGo(n)}
            style={{ flex: 1, textAlign: "left", background: "none", border: "none", padding: 0, cursor: "pointer" }}>
            <div style={{ height: 5, borderRadius: 3, background: on ? "var(--chrome, var(--sky-ink))" : "var(--line-2, var(--line))" }} />
            <div className="sub2" style={{ marginTop: 6, fontWeight: cur ? 700 : 500, color: on ? "var(--ink)" : "var(--chrome, var(--faint))" }}>
              {s.done ? "✓ " : `${n}. `}{s.label}
            </div>
          </button>
        );
      })}
    </div>
  );
}

function AcademicRecord({ me, paid, onDone }: { me: Me; paid: boolean; onDone: () => Promise<void> }) {
  const first = me.priorDegrees.find((d) => d.kind === "FIRST");
  const [fd, setFd] = useState({
    institution: first?.institution ?? me.prior.institution ?? "", award: first?.award ?? me.prior.award ?? "",
    field: first?.field ?? "", classOfDegree: first?.class_of_degree ?? me.prior.classOfDegree ?? "",
    cgpa: first?.cgpa != null ? String(first.cgpa) : (me.prior.cgpa != null ? String(me.prior.cgpa) : ""),
    year: first?.year != null ? String(first.year) : (me.prior.year != null ? String(me.prior.year) : ""),
  });
  const [quals, setQuals] = useState<QRow[]>(me.priorDegrees.filter((d) => d.kind !== "FIRST").map((d) => ({
    kind: d.kind, institution: d.institution ?? "", award: d.award ?? "", field: d.field ?? "",
    classOfDegree: d.class_of_degree ?? "", cgpa: d.cgpa != null ? String(d.cgpa) : "", year: d.year != null ? String(d.year) : "",
  })));
  const [busy, setBusy] = useState<string | null>(null);
  const [err, setErr] = useState<Problem | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const setQ = (i: number, k: keyof QRow, v: string) => setQuals(quals.map((q, j) => (j === i ? { ...q, [k]: v } : q)));

  async function saveFirst() {
    setErr(null); setOk(null); setBusy("first");
    try {
      const r = await fetch("/api/bff/api/v1/pg/first-degree", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(fd) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      setOk("First degree saved."); await onDone();
    } finally { setBusy(null); }
  }
  async function saveQuals() {
    setErr(null); setOk(null); setBusy("quals");
    try {
      const r = await fetch("/api/bff/api/v1/pg/qualifications", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(quals) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      setOk("Other qualifications saved."); await onDone();
    } finally { setBusy(null); }
  }

  return (
    <Panel title="Your academic record">
      <PBody>
        {!paid ? (
          <Note kind="info" title="Pay the application fee first">Once your payment is confirmed you supply your first degree and other qualifications here.</Note>
        ) : (
          <div style={{ display: "grid", gap: 16 }}>
            {err ? <ProblemNotice problem={err} /> : null}
            {ok ? <Note kind="ok" title={ok}>The School will see it with your application.</Note> : null}
            <div>
              <div style={{ fontWeight: 600, marginBottom: 6 }}>First degree <span className="sub2" style={{ fontWeight: 400 }}>· the related / relevant Bachelor’s degree the admission rests on</span></div>
              <div className="grid grid--2">
                <Fld id="fd-inst" label="Institution" v={fd.institution} on={(v) => setFd({ ...fd, institution: v })} />
                <Fld id="fd-award" label="Degree / award" v={fd.award} on={(v) => setFd({ ...fd, award: v })} ph="B.Sc." />
                <Fld id="fd-field" label="Field of study" v={fd.field} on={(v) => setFd({ ...fd, field: v })} ph="Computer Science" />
                <Sel id="fd-class" label="Class of degree" v={fd.classOfDegree} on={(v) => setFd({ ...fd, classOfDegree: v })} options={CLASSES} />
                <Fld id="fd-cgpa" label="CGPA (if known)" v={fd.cgpa} on={(v) => setFd({ ...fd, cgpa: v })} ph="3.80" num />
                <Fld id="fd-year" label="Year awarded" v={fd.year} on={(v) => setFd({ ...fd, year: v })} ph="2018" num />
              </div>
              <div className="mt-2"><button type="button" className="btn btn--primary btn--sm" disabled={busy !== null} onClick={() => void saveFirst()}>{busy === "first" ? "Saving…" : "Save first degree"}</button></div>
            </div>

            <div style={{ borderTop: "1px solid var(--line-2)", paddingTop: 14 }}>
              <div style={{ fontWeight: 600, marginBottom: 2 }}>Other qualifications</div>
              <div className="sub2 mb-2">Any qualification beyond the first degree that bears on this application — a prior Master’s, a Postgraduate Diploma, an HND / ND, or an NCE. A PhD applicant should give their Master’s here.</div>
              <div style={{ display: "grid", gap: 10 }}>
                {quals.map((q, i) => (
                  <div key={i} style={{ border: "1px solid var(--line-2)", borderRadius: 10, padding: 12 }}>
                    <div className="grid grid--2">
                      <Sel id={`q-kind-${i}`} label="Qualification" v={q.kind} on={(v) => setQ(i, "kind", v)} options={QUAL_KINDS} />
                      <Fld id={`q-inst-${i}`} label="Institution" v={q.institution} on={(v) => setQ(i, "institution", v)} />
                      <Fld id={`q-award-${i}`} label="Award / title" v={q.award} on={(v) => setQ(i, "award", v)} ph="M.Sc. / PGD / HND" />
                      <Fld id={`q-field-${i}`} label="Field of study" v={q.field} on={(v) => setQ(i, "field", v)} />
                      <Sel id={`q-class-${i}`} label="Class / result" v={q.classOfDegree} on={(v) => setQ(i, "classOfDegree", v)} options={CLASSES} />
                      <Fld id={`q-cgpa-${i}`} label="CGPA (if known)" v={q.cgpa} on={(v) => setQ(i, "cgpa", v)} num />
                      <Fld id={`q-year-${i}`} label="Year awarded" v={q.year} on={(v) => setQ(i, "year", v)} num />
                    </div>
                    <div className="mt-2"><button type="button" className="btn btn--ghost btn--sm" onClick={() => setQuals(quals.filter((_, j) => j !== i))}>Remove</button></div>
                  </div>
                ))}
                <div className="row">
                  <button type="button" className="btn btn--ghost btn--sm" onClick={() => setQuals([...quals, emptyQ()])}>+ Add a qualification</button>
                  <button type="button" className="btn btn--primary btn--sm" disabled={busy !== null} onClick={() => void saveQuals()}>{busy === "quals" ? "Saving…" : "Save other qualifications"}</button>
                </div>
              </div>
            </div>
          </div>
        )}
      </PBody>
    </Panel>
  );
}

type RRow = { name: string; email: string; phone: string; institution: string; position: string };

/** the referees — supplied in the portal after payment; each new referee with an email is emailed a reference request */
function RefereesEditor({ me, paid, onDone }: { me: Me; paid: boolean; onDone: () => Promise<void> }) {
  const submitted = me.referees.filter((r) => r.submitted_at);
  const [rows, setRows] = useState<RRow[]>(() => {
    const editable = me.referees.filter((r) => !r.submitted_at).map((r) => ({ name: r.name ?? "", email: r.email ?? "", phone: r.phone ?? "", institution: r.institution ?? "", position: r.position ?? "" }));
    return editable.length ? editable : [{ name: "", email: "", phone: "", institution: "", position: "" }, { name: "", email: "", phone: "", institution: "", position: "" }];
  });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const setR = (i: number, k: keyof RRow, v: string) => setRows(rows.map((r, j) => (j === i ? { ...r, [k]: v } : r)));

  async function save() {
    setErr(null); setOk(null); setBusy(true);
    try {
      const r = await fetch("/api/bff/api/v1/pg/referees", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(rows.filter((x) => x.name.trim())) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      setOk("Referees saved — a reference request was emailed to each referee with an email."); await onDone();
    } finally { setBusy(false); }
  }

  return (
    <Panel title="Referees">
      <PBody>
        {!paid ? (
          <Note kind="info" title="Pay the application fee first">Once your payment is confirmed you name your referees here.</Note>
        ) : (
          <div style={{ display: "grid", gap: 12 }}>
            <div className="sub2">Each referee with an email is sent a private link to complete a short, confidential reference for you. You can update referees who have not yet responded.</div>
            {err ? <ProblemNotice problem={err} /> : null}
            {ok ? <Note kind="ok" title={ok}>Thank you.</Note> : null}
            {submitted.length ? (
              <div style={{ display: "grid", gap: 4 }}>
                {submitted.map((r, i) => (
                  <div key={i} className="sub2 ink-green">✓ Reference received from <b>{r.name}</b>{r.email ? ` · ${r.email}` : ""}.</div>
                ))}
              </div>
            ) : null}
            {rows.map((r, i) => (
              <div className="grid grid--2" key={i} style={{ borderTop: i ? "1px solid var(--line-2)" : "none", paddingTop: i ? 10 : 0 }}>
                <Fld id={`rf-n-${i}`} label={`Referee ${i + 1} — name`} v={r.name} on={(v) => setR(i, "name", v)} />
                <Fld id={`rf-e-${i}`} label="Email" v={r.email} on={(v) => setR(i, "email", v)} />
                <Fld id={`rf-p-${i}`} label="Phone number" v={r.phone} on={(v) => setR(i, "phone", v)} />
                <Fld id={`rf-i-${i}`} label="Institution" v={r.institution} on={(v) => setR(i, "institution", v)} />
                <Fld id={`rf-po-${i}`} label="Position" v={r.position} on={(v) => setR(i, "position", v)} />
              </div>
            ))}
            <div className="row">
              <button type="button" className="btn btn--ghost btn--sm" onClick={() => setRows([...rows, { name: "", email: "", phone: "", institution: "", position: "" }])}>+ Add a referee</button>
              <button type="button" className="btn btn--primary btn--sm" disabled={busy} onClick={() => void save()}>{busy ? "Saving…" : "Save referees & send requests"}</button>
            </div>
          </div>
        )}
      </PBody>
    </Panel>
  );
}

function Fld({ id, label, v, on, ph, num }: { id: string; label: string; v: string; on: (v: string) => void; ph?: string; num?: boolean }) {
  return (
    <div className="field">
      <label htmlFor={id}>{label}</label>
      <input id={id} className={`ctl${num ? " tnum" : ""}`} value={v} placeholder={ph} onChange={(e) => on(e.target.value)} />
    </div>
  );
}
function Sel({ id, label, v, on, options }: { id: string; label: string; v: string; on: (v: string) => void; options: string[] | [string, string][] }) {
  const opts: [string, string][] = options.map((o) => (Array.isArray(o) ? o : [o, o]));
  return (
    <div className="field">
      <label htmlFor={id}>{label}</label>
      <select id={id} className="ctl" value={v} onChange={(e) => on(e.target.value)}>
        <option value="">—</option>
        {opts.map(([val2, lab]) => <option key={val2} value={val2}>{lab}</option>)}
      </select>
    </div>
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
