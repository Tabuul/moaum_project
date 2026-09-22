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

interface Prog { code: string; name: string; faculty_name: string; department_name: string; pg_award: string | null; pg_research: boolean; entry_level: number }
interface Applied { application_no: string; reference: string; amount: number }
interface Status { application_no: string; state: string; programme_name: string; pg_award: string | null; surname: string; other_names: string; fee_confirmed_at: string | null; submitted_at: string | null; spgs_note: string | null }

const naira = (n: number) => "NGN " + Number(n).toLocaleString();
const STATE_LABEL: Record<string, string> = {
  DRAFT: "Draft", SUBMITTED: "Submitted — with the department", DEPT_RECOMMENDED: "Recommended — with the School",
  DEPT_DECLINED: "Not recommended by the department", OFFERED: "Offered a place", NOT_OFFERED: "Not offered",
  ACCEPTED: "Offer accepted", ADMITTED: "Admitted — on the register",
};

/** a prior qualification beyond the first degree — a prior Master's, a PGD, an HND/ND, an NCE, etc. */
interface Qual { kind: string; award: string; field: string; institution: string; classOfDegree: string; cgpa: string; year: string }
const KINDS: [string, string][] = [
  ["MASTERS", "Master’s degree"],
  ["PGD", "Postgraduate Diploma (PGD)"],
  ["HND", "Higher National Diploma (HND)"],
  ["ND", "National Diploma (ND)"],
  ["NCE", "Nigeria Certificate in Education (NCE)"],
  ["PHD", "Doctorate (PhD)"],
  ["OTHER", "Other qualification"],
];
const CLASSES = ["First Class", "Second Class (Upper)", "Second Class (Lower)", "Third Class", "Pass", "Distinction", "Credit", "Merit"];
const emptyQual = (kind = "MASTERS"): Qual => ({ kind, award: "", field: "", institution: "", classOfDegree: "", cgpa: "", year: "" });

/** a searchable programme picker: type to filter by name, award, department or faculty, then pick one */
function ProgrammePicker({ progs, value, onPick }: { progs: Prog[]; value: string; onPick: (code: string) => void }) {
  const [q, setQ] = useState("");
  const [open, setOpen] = useState(false);
  const chosen = progs.find((p) => p.code === value) ?? null;
  const ql = q.trim().toLowerCase();
  const matches = (ql
    ? progs.filter((p) => `${p.name} ${p.code} ${p.faculty_name} ${p.department_name} ${p.pg_award ?? ""}`.toLowerCase().includes(ql))
    : progs).slice(0, 60);
  // group the matches by faculty, keeping faculties in first-seen order
  const groups: [string, Prog[]][] = [];
  for (const p of matches) { const g = groups.find(([k]) => k === p.faculty_name); if (g) g[1].push(p); else groups.push([p.faculty_name, [p]]); }
  const shown = open ? q : chosen ? `${chosen.name}${chosen.pg_award ? ` (${chosen.pg_award})` : ""}` : q;

  return (
    <div style={{ position: "relative" }}>
      <input
        id="programme" className="ctl" role="combobox" aria-expanded={open} aria-controls="programme-list" autoComplete="off"
        placeholder={chosen ? undefined : "Search programmes by name, award or faculty…"}
        value={shown}
        onFocus={() => { setOpen(true); setQ(""); }}
        onChange={(e) => { setQ(e.target.value); setOpen(true); }}
        onKeyDown={(e) => { if (e.key === "Escape") setOpen(false); }}
        onBlur={() => window.setTimeout(() => setOpen(false), 150)}
      />
      {open ? (
        <div id="programme-list" role="listbox" style={{ position: "absolute", top: "calc(100% + 4px)", left: 0, right: 0, zIndex: 30, maxHeight: 300, overflowY: "auto", background: "var(--bg, #fff)", border: "1px solid var(--line-2, #d9d9d9)", borderRadius: 8, boxShadow: "0 8px 24px rgba(0,0,0,.12)" }}>
          {groups.length ? groups.map(([fac, list]) => (
            <div key={fac}>
              <div style={{ padding: "7px 12px 4px", fontSize: 11, letterSpacing: ".4px", textTransform: "uppercase", color: "var(--chrome, #888)", position: "sticky", top: 0, background: "var(--bg, #fff)" }}>{fac}</div>
              {list.map((p) => (
                <button
                  key={p.code} type="button" role="option" aria-selected={p.code === value}
                  onMouseDown={(e) => { e.preventDefault(); onPick(p.code); setOpen(false); setQ(""); }}
                  style={{ display: "block", width: "100%", textAlign: "left", padding: "8px 12px", border: "none", background: p.code === value ? "var(--tint, #eef3fb)" : "transparent", cursor: "pointer", fontSize: 13.5 }}
                >
                  <span style={{ fontWeight: 600 }}>{p.name}</span>{p.pg_award ? <span className="sub2"> ({p.pg_award})</span> : null}
                  <div className="sub2">{p.department_name}</div>
                </button>
              ))}
            </div>
          )) : <div className="sub2" style={{ padding: "12px" }}>No programme matches &ldquo;{q}&rdquo;.</div>}
        </div>
      ) : null}
    </div>
  );
}

export function PgApply() {
  const [progs, setProgs] = useState<Prog[]>([]);
  const [f, setF] = useState<Record<string, string>>({});
  const [refs, setRefs] = useState([{ name: "", email: "", institution: "", position: "" }, { name: "", email: "", institution: "", position: "" }]);
  const [quals, setQuals] = useState<Qual[]>([]);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [applied, setApplied] = useState<Applied | null>(null);

  useEffect(() => {
    let live = true;
    fetch("/api/bff/api/v1/pg/programmes").then((r) => (r.ok ? r.json() : [])).then((j) => { if (live) setProgs(Array.isArray(j) ? j : []); }).catch(() => {});
    return () => { live = false; };
  }, []);

  const chosen = useMemo(() => progs.find((p) => p.code === f.programme), [progs, f.programme]);
  const isPhd = (chosen?.entry_level ?? 0) >= 900;
  const set = (k: string) => (e: ChangeEvent<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>) => setF({ ...f, [k]: e.target.value });
  const setQual = (i: number, k: keyof Qual, v: string) => setQuals(quals.map((q, j) => (j === i ? { ...q, [k]: v } : q)));
  function chooseProgramme(code: string) {
    const p = progs.find((x) => x.code === code);
    setF({ ...f, programme: code });
    // a PhD rests on a Master's — seed a Master's row so it is obvious the applicant must give it
    if (p && p.entry_level >= 900 && quals.length === 0) setQuals([emptyQual("MASTERS")]);
  }

  async function submit() {
    setProblem(null);
    if (!f.surname?.trim() || !f.email?.trim() || !(f.password ?? "").trim() || !f.programme) {
      setProblem({ status: 400, title: "Name, email, a password and a programme are required." }); return;
    }
    if ((f.password ?? "").length < 6) { setProblem({ status: 400, title: "Choose a password of at least six characters." }); return; }
    if (!(f.priorInstitution ?? "").trim() || !(f.priorAward ?? "").trim()) {
      setProblem({ status: 400, title: "Your first degree (institution and award) is required." }); return;
    }
    const hasMasters = quals.some((q) => q.kind === "MASTERS" && ((q.institution ?? "").trim() || (q.award ?? "").trim() || (q.field ?? "").trim()));
    if (isPhd && !hasMasters) {
      setProblem({ status: 400, title: "A PhD applicant must also give a Master’s degree.", detail: "Add it under “Other qualifications” below." }); return;
    }
    setBusy(true);
    try {
      const priorDegrees = [
        { kind: "FIRST", institution: f.priorInstitution, award: f.priorAward, field: f.priorField, classOfDegree: f.priorClass, cgpa: f.priorCgpa, year: f.priorYear },
        ...quals.map((q) => ({ kind: q.kind, institution: q.institution, award: q.award, field: q.field, classOfDegree: q.classOfDegree, cgpa: q.cgpa, year: q.year })),
      ].filter((d) => (d.institution ?? "").trim() || (d.award ?? "").trim() || (d.field ?? "").trim());
      const body = { ...f, priorDegrees, referees: refs.filter((r) => r.name.trim()) };
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
          Save your application number. <b>Sign in to pay the application fee of {naira(applied.amount)} online</b> — with the email and password you just chose — then upload your credentials (O&rsquo;Level, A&rsquo;Level and birth certificate / declaration of age, scanned into one PDF) under <b>Documents</b> and follow your application. You can also track it with your application number and email below.
        </Note>
        <div className="card"><div className="card__body">
          <Row k="Application number" v={applied.application_no} />
          <Row k="Payment reference" v={applied.reference} />
          <Row k="Amount" v={naira(applied.amount)} />
        </div></div>
        <div style={{ textAlign: "center" }}><Link href="/login?next=/pg/portal" className="btn btn--primary">Sign in to pay and continue application</Link></div>
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
          <ProgrammePicker progs={progs} value={f.programme ?? ""} onPick={chooseProgramme} />
        </Field>
        {chosen ? <div className="hint">{chosen.department_name} · {chosen.faculty_name}{chosen.pg_research ? " · research degree (a proposal may be added — optional)" : ""}</div> : null}

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
        <div className="hint" style={{ marginTop: -4 }}>Related / relevant Bachelor&rsquo;s degree(s)</div>
        <div className="grid grid--2">
          <Field id="priorInstitution" label="Institution"><input id="priorInstitution" className="ctl" value={f.priorInstitution ?? ""} onChange={set("priorInstitution")} /></Field>
          <Field id="priorAward" label="Degree / award"><input id="priorAward" className="ctl" value={f.priorAward ?? ""} onChange={set("priorAward")} placeholder="B.Sc." /></Field>
          <Field id="priorField" label="Field of study"><input id="priorField" className="ctl" value={f.priorField ?? ""} onChange={set("priorField")} placeholder="Computer Science" /></Field>
          <Field id="priorClass" label="Class of degree"><select id="priorClass" className="ctl" value={f.priorClass ?? ""} onChange={set("priorClass")}><option value="">—</option>{CLASSES.map((c) => <option key={c} value={c}>{c}</option>)}</select></Field>
          <Field id="priorCgpa" label="CGPA (if known)"><input id="priorCgpa" className="ctl tnum" value={f.priorCgpa ?? ""} onChange={set("priorCgpa")} placeholder="3.80" /></Field>
          <Field id="priorYear" label="Year awarded"><input id="priorYear" className="ctl tnum" value={f.priorYear ?? ""} onChange={set("priorYear")} placeholder="2018" /></Field>
        </div>

        <Section title="Other qualifications" />
        <div className="hint" style={{ marginTop: -4 }}>
          Add every other qualification you hold that bears on this application — a prior <b>Master&rsquo;s</b> (in this or a related field), a <b>Postgraduate Diploma</b>, an <b>HND / ND</b>, or an <b>NCE</b> (for example where it covers a subject deficiency).{isPhd ? " A PhD requires a Master’s degree — give it here." : ""}
        </div>
        {quals.map((q, i) => (
          <div key={i} style={{ border: "1px solid var(--line-2)", borderRadius: 10, padding: 12 }}>
            <div className="grid grid--2">
              <Field id={`q-kind-${i}`} label="Qualification"><select id={`q-kind-${i}`} className="ctl" value={q.kind} onChange={(e) => setQual(i, "kind", e.target.value)}>{KINDS.map(([v, l]) => <option key={v} value={v}>{l}</option>)}</select></Field>
              <Field id={`q-inst-${i}`} label="Institution"><input id={`q-inst-${i}`} className="ctl" value={q.institution} onChange={(e) => setQual(i, "institution", e.target.value)} /></Field>
              <Field id={`q-award-${i}`} label="Award / title"><input id={`q-award-${i}`} className="ctl" value={q.award} onChange={(e) => setQual(i, "award", e.target.value)} placeholder="M.Sc. / PGD / HND" /></Field>
              <Field id={`q-field-${i}`} label="Field of study"><input id={`q-field-${i}`} className="ctl" value={q.field} onChange={(e) => setQual(i, "field", e.target.value)} placeholder="Economics" /></Field>
              <Field id={`q-class-${i}`} label="Class / result"><select id={`q-class-${i}`} className="ctl" value={q.classOfDegree} onChange={(e) => setQual(i, "classOfDegree", e.target.value)}><option value="">—</option>{CLASSES.map((c) => <option key={c} value={c}>{c}</option>)}</select></Field>
              <Field id={`q-cgpa-${i}`} label="CGPA (if known)"><input id={`q-cgpa-${i}`} className="ctl tnum" value={q.cgpa} onChange={(e) => setQual(i, "cgpa", e.target.value)} placeholder="4.20" /></Field>
              <Field id={`q-year-${i}`} label="Year awarded"><input id={`q-year-${i}`} className="ctl tnum" value={q.year} onChange={(e) => setQual(i, "year", e.target.value)} placeholder="2021" /></Field>
            </div>
            <div style={{ marginTop: 6 }}><button type="button" className="btn btn--ghost btn--sm" onClick={() => setQuals(quals.filter((_, j) => j !== i))}>Remove this qualification</button></div>
          </div>
        ))}
        <div><button type="button" className="btn btn--ghost btn--sm" onClick={() => setQuals([...quals, emptyQual()])}>+ Add a qualification</button></div>

        {chosen?.pg_research ? (
          <>
            <Section title="Research proposal (optional)" />
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
    <div className="login-wrap">
      <div className="login-brand">
        <div>
          <div className="login-brand__top">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/crest.png" alt="University crest" style={{ width: 56, height: 58, objectFit: "contain" }} />
            <div><span style={{ fontSize: 12, letterSpacing: ".6px", textTransform: "uppercase", color: "var(--chrome-dim)" }}>School of Postgraduate Studies</span></div>
          </div>
          <div style={{ height: 26 }} />
          <h1>Apply for a postgraduate programme</h1>
          <p>Apply directly for a Postgraduate Diploma, Master&rsquo;s or PhD &mdash; no JAMB number. One account carries you from application to admission, and becomes your student account on the day you are admitted.</p>
        </div>
        <div className="login-stats">
          <div className="login-stat"><span className="n">PGD</span><span className="l">Master&rsquo;s · PhD</span></div>
          <div className="login-stat"><span className="n tnum">1</span><span className="l">programme at a time</span></div>
          <div className="login-stat"><span className="n tnum">0</span><span className="l">JAMB number needed</span></div>
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
