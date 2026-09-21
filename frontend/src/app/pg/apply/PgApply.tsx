"use client";

/**
 * The public postgraduate application — open to the world, no JAMB number. A prospective postgraduate
 * chooses a programme, states the first degree the admission rests on, gives a research proposal for a
 * research degree, names referees, and receives an application number and a fee reference to pay. They
 * track and accept the offer with the application number and their email.
 */
import { useEffect, useMemo, useState, type ChangeEvent, type ReactNode } from "react";
import Link from "next/link";
import type { Problem } from "@/lib/api";
import { Note } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";

interface Prog { code: string; name: string; faculty_name: string; department_name: string; pg_award: string | null; pg_research: boolean }
interface Applied { application_no: string; reference: string; amount: number }
interface Status { application_no: string; state: string; programme_name: string; pg_award: string | null; surname: string; other_names: string; fee_confirmed_at: string | null; submitted_at: string | null; spgs_note: string | null }

const naira = (n: number) => "NGN " + Number(n).toLocaleString();
const STATE_LABEL: Record<string, string> = {
  DRAFT: "Draft", SUBMITTED: "Submitted — with the department", DEPT_RECOMMENDED: "Recommended — with the School",
  DEPT_DECLINED: "Not recommended by the department", OFFERED: "Offered a place", NOT_OFFERED: "Not offered",
  ACCEPTED: "Offer accepted", ADMITTED: "Admitted — on the register",
};

export function PgApply() {
  const [progs, setProgs] = useState<Prog[]>([]);
  const [f, setF] = useState<Record<string, string>>({});
  const [refs, setRefs] = useState([{ name: "", email: "", institution: "", position: "" }, { name: "", email: "", institution: "", position: "" }]);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [applied, setApplied] = useState<Applied | null>(null);

  useEffect(() => {
    let live = true;
    fetch("/api/bff/api/v1/pg/programmes").then((r) => (r.ok ? r.json() : [])).then((j) => { if (live) setProgs(Array.isArray(j) ? j : []); }).catch(() => {});
    return () => { live = false; };
  }, []);

  const chosen = useMemo(() => progs.find((p) => p.code === f.programme), [progs, f.programme]);
  const byFaculty = useMemo(() => {
    const m = new Map<string, Prog[]>();
    for (const p of progs) { const k = p.faculty_name; if (!m.has(k)) m.set(k, []); m.get(k)!.push(p); }
    return [...m.entries()];
  }, [progs]);
  const set = (k: string) => (e: ChangeEvent<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>) => setF({ ...f, [k]: e.target.value });

  async function submit() {
    setProblem(null);
    if (!f.surname?.trim() || !f.email?.trim() || !(f.password ?? "").trim() || !f.programme) {
      setProblem({ status: 400, title: "Name, email, a password and a programme are required." }); return;
    }
    if ((f.password ?? "").length < 6) { setProblem({ status: 400, title: "Choose a password of at least six characters." }); return; }
    if (chosen?.pg_research && !(f.proposalText ?? "").trim()) { setProblem({ status: 400, title: "This is a research programme — a research proposal is required." }); return; }
    setBusy(true);
    try {
      const body = { ...f, referees: refs.filter((r) => r.name.trim()) };
      const r = await fetch("/api/bff/api/v1/pg/apply", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      setApplied(j as Applied);
    } finally { setBusy(false); }
  }

  if (applied) {
    return (
      <Wrap>
        <Note kind="ok" title={`Application received — ${applied.application_no}`}>
          Save your application number. Pay the application fee of <b>{naira(applied.amount)}</b> with the reference below, then track your application with your application number and email.
        </Note>
        <div className="card"><div className="card__body">
          <Row k="Application number" v={applied.application_no} />
          <Row k="Payment reference" v={applied.reference} />
          <Row k="Amount" v={naira(applied.amount)} />
        </div></div>
        <StatusCheck initialNo={applied.application_no} />
        <div style={{ textAlign: "center", marginTop: 12 }}><Link href="/login">Back to sign in</Link></div>
      </Wrap>
    );
  }

  return (
    <Wrap>
      <Note kind="info" title="Apply for a postgraduate programme">
        Complete the form below. Applications without official transcripts of academic record shall not be processed — bring your transcripts for screening. You may apply for only one programme at a time. The application fee is stated after you submit.
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}

      <div className="card"><div className="card__body" style={{ display: "grid", gap: 12 }}>
        <Section title="Programme" />
        <Field id="programme" label="Programme applied for">
          <select id="programme" className="ctl" value={f.programme ?? ""} onChange={set("programme")}>
            <option value="">Choose a programme…</option>
            {byFaculty.map(([fac, list]) => (
              <optgroup key={fac} label={fac}>
                {list.map((p) => <option key={p.code} value={p.code}>{p.name}{p.pg_award ? ` (${p.pg_award})` : ""}</option>)}
              </optgroup>
            ))}
          </select>
        </Field>
        {chosen ? <div className="hint">{chosen.department_name} · {chosen.faculty_name}{chosen.pg_research ? " · research degree (a proposal is required)" : ""}</div> : null}

        <Section title="Your details" />
        <div className="grid grid--2">
          <Field id="surname" label="Surname"><input id="surname" className="ctl" value={f.surname ?? ""} onChange={set("surname")} autoComplete="family-name" /></Field>
          <Field id="otherNames" label="Other names"><input id="otherNames" className="ctl" value={f.otherNames ?? ""} onChange={set("otherNames")} autoComplete="given-name" /></Field>
          <Field id="sex" label="Sex"><select id="sex" className="ctl" value={f.sex ?? ""} onChange={set("sex")}><option value="">—</option><option value="F">Female</option><option value="M">Male</option></select></Field>
          <Field id="dob" label="Date of birth"><input id="dob" type="date" className="ctl" value={f.dob ?? ""} onChange={set("dob")} /></Field>
          <Field id="state" label="State of origin"><input id="state" className="ctl" value={f.state ?? ""} onChange={set("state")} /></Field>
          <Field id="lga" label="Local government"><input id="lga" className="ctl" value={f.lga ?? ""} onChange={set("lga")} /></Field>
          <Field id="email" label="Email"><input id="email" type="email" className="ctl" value={f.email ?? ""} onChange={set("email")} autoComplete="email" /></Field>
          <Field id="phone" label="Phone"><input id="phone" className="ctl" value={f.phone ?? ""} onChange={set("phone")} placeholder="08030000000" autoComplete="tel" /></Field>
          <Field id="password" label="Choose a password" hint="At least six characters — to check your status later"><input id="password" type="password" className="ctl" value={f.password ?? ""} onChange={set("password")} autoComplete="new-password" /></Field>
        </div>

        <Section title="Your first degree" />
        <div className="grid grid--2">
          <Field id="priorInstitution" label="Institution"><input id="priorInstitution" className="ctl" value={f.priorInstitution ?? ""} onChange={set("priorInstitution")} /></Field>
          <Field id="priorAward" label="Degree / award"><input id="priorAward" className="ctl" value={f.priorAward ?? ""} onChange={set("priorAward")} placeholder="B.Sc. Computer Science" /></Field>
          <Field id="priorClass" label="Class of degree"><select id="priorClass" className="ctl" value={f.priorClass ?? ""} onChange={set("priorClass")}><option value="">—</option>{["First Class", "Second Class (Upper)", "Second Class (Lower)", "Third Class", "Pass", "Distinction", "Credit", "Merit"].map((c) => <option key={c} value={c}>{c}</option>)}</select></Field>
          <Field id="priorCgpa" label="CGPA (if known)"><input id="priorCgpa" className="ctl tnum" value={f.priorCgpa ?? ""} onChange={set("priorCgpa")} placeholder="3.80" /></Field>
          <Field id="priorYear" label="Year awarded"><input id="priorYear" className="ctl tnum" value={f.priorYear ?? ""} onChange={set("priorYear")} placeholder="2022" /></Field>
        </div>

        {chosen?.pg_research ? (
          <>
            <Section title="Research proposal" />
            <Field id="proposalTitle" label="Proposed topic"><input id="proposalTitle" className="ctl" value={f.proposalTitle ?? ""} onChange={set("proposalTitle")} /></Field>
            <Field id="proposalText" label="Summary of the proposed research"><textarea id="proposalText" className="ctl" rows={4} value={f.proposalText ?? ""} onChange={set("proposalText")} /></Field>
          </>
        ) : null}

        <Section title="Referees" />
        {refs.map((r, i) => (
          <div className="grid grid--2" key={i}>
            <Field id={`rn${i}`} label={`Referee ${i + 1} — name`}><input id={`rn${i}`} className="ctl" value={r.name} onChange={(e) => { const a = [...refs]; a[i] = { ...a[i], name: e.target.value }; setRefs(a); }} /></Field>
            <Field id={`re${i}`} label="Email"><input id={`re${i}`} className="ctl" value={r.email} onChange={(e) => { const a = [...refs]; a[i] = { ...a[i], email: e.target.value }; setRefs(a); }} /></Field>
            <Field id={`ri${i}`} label="Institution"><input id={`ri${i}`} className="ctl" value={r.institution} onChange={(e) => { const a = [...refs]; a[i] = { ...a[i], institution: e.target.value }; setRefs(a); }} /></Field>
            <Field id={`rp${i}`} label="Position"><input id={`rp${i}`} className="ctl" value={r.position} onChange={(e) => { const a = [...refs]; a[i] = { ...a[i], position: e.target.value }; setRefs(a); }} /></Field>
          </div>
        ))}

        <div style={{ display: "flex", gap: 10, alignItems: "center", marginTop: 4 }}>
          <button type="button" className="btn btn--primary" disabled={busy} onClick={() => void submit()}>{busy ? "Submitting…" : "Submit application"}</button>
          <Link href="/login" className="btn btn--ghost btn--sm">Cancel</Link>
        </div>
      </div></div>

      <StatusCheck />
    </Wrap>
  );
}

function StatusCheck({ initialNo }: { initialNo?: string }) {
  const [no, setNo] = useState(initialNo ?? "");
  const [email, setEmail] = useState("");
  const [st, setSt] = useState<Status | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function check() {
    setMsg(null); setSt(null);
    const r = await fetch(`/api/bff/api/v1/pg/status?applicationNo=${encodeURIComponent(no.trim())}&email=${encodeURIComponent(email.trim())}`);
    const j = await r.json().catch(() => null);
    if (j && j.found) setSt(j.application as Status); else setMsg("No application matches that number and email.");
  }
  async function accept() {
    setBusy(true); setMsg(null);
    try {
      const r = await fetch("/api/bff/api/v1/pg/accept", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ applicationNo: no.trim(), email: email.trim() }) });
      const j = await r.json().catch(() => null);
      if (j && j.ok) { setMsg("Offer accepted. The School will admit you onto the register."); await check(); }
      else setMsg((j && j.reason) || "That could not be accepted.");
    } finally { setBusy(false); }
  }

  return (
    <div className="card" style={{ marginTop: 14 }}><div className="card__body" style={{ display: "grid", gap: 10 }}>
      <Section title="Check your application" />
      <div className="grid grid--2">
        <Field id="st-no" label="Application number"><input id="st-no" className="ctl" value={no} onChange={(e) => setNo(e.target.value)} placeholder="PG/25/000001" /></Field>
        <Field id="st-em" label="Email"><input id="st-em" className="ctl" value={email} onChange={(e) => setEmail(e.target.value)} /></Field>
      </div>
      <div><button type="button" className="btn btn--ghost btn--sm" onClick={() => void check()}>Check status</button></div>
      {msg ? <div className="hint">{msg}</div> : null}
      {st ? (
        <Note kind={st.state === "OFFERED" || st.state === "ACCEPTED" || st.state === "ADMITTED" ? "ok" : st.state === "NOT_OFFERED" || st.state === "DEPT_DECLINED" ? "bad" : "info"} title={STATE_LABEL[st.state] ?? st.state}>
          {st.surname}, {st.other_names} · {st.programme_name}{st.pg_award ? ` (${st.pg_award})` : ""}. {st.spgs_note ? `Note: ${st.spgs_note}. ` : ""}{st.fee_confirmed_at ? "Application fee confirmed." : "Application fee not yet confirmed."}
          {st.state === "OFFERED" ? <div style={{ marginTop: 8 }}><button type="button" className="btn btn--primary btn--sm" disabled={busy} onClick={() => void accept()}>{busy ? "Accepting…" : "Accept the offer"}</button></div> : null}
        </Note>
      ) : null}
    </div></div>
  );
}

function Wrap({ children }: { children: ReactNode }) {
  return (
    <div style={{ minHeight: "100vh", background: "var(--bg, #f6f3ea)", padding: "28px 14px" }}>
      <div style={{ maxWidth: 720, margin: "0 auto", display: "grid", gap: 14 }}>
        <div style={{ textAlign: "center" }}>
          <div style={{ fontSize: 12, letterSpacing: ".14em", textTransform: "uppercase", color: "var(--gold, #b0842e)", fontWeight: 700 }}>Rev. Fr. Moses Orshio Adasu University, Makurdi</div>
          <div style={{ fontSize: 20, fontWeight: 700 }}>Postgraduate application</div>
        </div>
        {children}
      </div>
    </div>
  );
}

function Section({ title }: { title: string }) {
  return <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: ".06em", textTransform: "uppercase", color: "var(--muted)", borderBottom: "1px solid var(--line-2)", paddingBottom: 4 }}>{title}</div>;
}
function Field({ id, label, hint, children }: { id: string; label: string; hint?: string; children: ReactNode }) {
  return (
    <div className="field">
      <label htmlFor={id}>{label}</label>
      {children}
      {hint ? <div className="hint">{hint}</div> : null}
    </div>
  );
}
function Row({ k, v }: { k: string; v: string }) {
  return <div style={{ display: "flex", justifyContent: "space-between", gap: 12, padding: "6px 0", borderBottom: "1px solid var(--line-2)" }}><span className="sub2">{k}</span><span className="tnum" style={{ fontWeight: 700 }}>{v}</span></div>;
}
