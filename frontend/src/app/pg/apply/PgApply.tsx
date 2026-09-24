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
import { Btn, LinkBtn, Note } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { STATES, lgasOf } from "@/lib/nigeria";

interface Prog { code: string; name: string; faculty_name: string; department_name: string; pg_award: string | null; pg_research: boolean; entry_level: number }
interface Applied { application_no: string; reference: string; amount: number }
interface Status { application_no: string; state: string; programme_name: string; pg_award: string | null; surname: string; other_names: string; fee_confirmed_at: string | null; submitted_at: string | null; spgs_note: string | null }

const naira = (n: number) => "NGN " + Number(n).toLocaleString();
const STATE_LABEL: Record<string, string> = {
  DRAFT: "Draft", SUBMITTED: "Submitted — with the department", DEPT_RECOMMENDED: "Recommended — with the School",
  DEPT_DECLINED: "Not recommended by the department", OFFERED: "Offered a place", NOT_OFFERED: "Not offered", DECISION_LOCKED: "Decision ready — pay the checking fee to see it",
  ACCEPTED: "Offer accepted", ADMITTED: "Admitted — on the register",
};

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
        <div id="programme-list" role="listbox" style={{ position: "absolute", top: "calc(100% + 4px)", left: 0, right: 0, zIndex: 30, maxHeight: 300, overflowY: "auto", background: "var(--bg)", border: "1px solid var(--line-2)", borderRadius: "var(--r-md)", boxShadow: "var(--sh-3)" }}>
          {groups.length ? groups.map(([fac, list]) => (
            <div key={fac}>
              <div className="eyebrow ink-chrome" style={{ padding: "var(--s-2) var(--s-3) var(--s-1)", position: "sticky", top: 0, background: "var(--bg)" }}>{fac}</div>
              {list.map((p) => (
                <button
                  key={p.code} type="button" role="option" aria-selected={p.code === value}
                  onMouseDown={(e) => { e.preventDefault(); onPick(p.code); setOpen(false); setQ(""); }}
                  style={{ display: "block", width: "100%", textAlign: "left", padding: "var(--s-2) var(--s-3)", border: "none", background: p.code === value ? "var(--tint)" : "transparent", cursor: "pointer" }}
                >
                  <span className="b600">{p.name}</span>{p.pg_award ? <span className="sub2"> ({p.pg_award})</span> : null}
                  <div className="sub2">{p.department_name}</div>
                </button>
              ))}
            </div>
          )) : <div className="sub2" style={{ padding: "var(--s-3)" }}>No programme matches &ldquo;{q}&rdquo;.</div>}
        </div>
      ) : null}
    </div>
  );
}

export function PgApply() {
  const [progs, setProgs] = useState<Prog[]>([]);
  const [f, setF] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [applied, setApplied] = useState<Applied | null>(null);

  useEffect(() => {
    let live = true;
    fetch("/api/bff/api/v1/pg/programmes").then((r) => (r.ok ? r.json() : [])).then((j) => { if (live) setProgs(Array.isArray(j) ? j : []); }).catch(() => {});
    return () => { live = false; };
  }, []);

  const [step, setStep] = useState(1);
  const chosen = useMemo(() => progs.find((p) => p.code === f.programme), [progs, f.programme]);
  const set = (k: string) => (e: ChangeEvent<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>) => setF({ ...f, [k]: e.target.value });
  function chooseProgramme(code: string) { setF({ ...f, programme: code }); }

  const STEPS = ["Programme", "Your details", "Account"];
  function next() {
    setProblem(null);
    if (step === 1 && !f.programme) { setProblem({ status: 400, title: "Choose a programme to continue." }); return; }
    if (step === 2) {
      if (!f.surname?.trim() || !f.otherNames?.trim()) { setProblem({ status: 400, title: "Your surname and other names are required." }); return; }
      if (!f.email?.trim()) { setProblem({ status: 400, title: "Your email is required — you sign in with it to pay." }); return; }
    }
    setStep((n) => Math.min(STEPS.length, n + 1));
    if (typeof window !== "undefined") window.scrollTo({ top: 0, behavior: "smooth" });
  }
  function back() { setProblem(null); setStep((n) => Math.max(1, n - 1)); }

  async function submit() {
    setProblem(null);
    if (!f.surname?.trim() || !f.email?.trim() || !(f.password ?? "").trim() || !f.programme) {
      setProblem({ status: 400, title: "Name, email, a password and a programme are required." }); return;
    }
    if ((f.password ?? "").length < 6) { setProblem({ status: 400, title: "Choose a password of at least six characters." }); return; }
    if ((f.password ?? "") !== (f.password2 ?? "")) { setProblem({ status: 400, title: "The two passwords do not match." }); return; }
    setBusy(true);
    try {
      // the academic record (first degree, other qualifications, referees) is supplied in the portal after payment
      const { password2: _pw2, ...rest } = f; // the confirm-password stays in the browser
      void _pw2;
      const body = { ...rest };
      const r = await fetch("/api/bff/api/v1/pg/apply", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      setApplied(j as Applied);
    } finally { setBusy(false); }
  }

  if (applied) {
    return (
      <Wrap>
        <Note kind="ok" title={`Account created — ${applied.application_no}`}>
          Save your application number. <b>Sign in to pay the application fee of {naira(applied.amount)} online</b> — with the email and password you just chose. After payment you complete your application in the portal: your <b>first degree</b>, any <b>other qualifications</b>, your <b>referees</b> (who are then emailed a reference request), and your <b>documents and passport</b>. You can also track it with your application number and email below.
        </Note>
        <div className="card"><div className="card__body">
          <Row k="Application number" v={applied.application_no} />
          <Row k="Payment reference" v={applied.reference} />
          <Row k="Amount" v={naira(applied.amount)} />
        </div></div>
        <div className="row" style={{ justifyContent: "center" }}><LinkBtn kind="primary" size="md" href="/login?next=/pg/portal">Sign in to pay and continue application</LinkBtn></div>
        <StatusCheck initialNo={applied.application_no} />
        <div className="mt-3" style={{ textAlign: "center" }}><Link href="/login">Back to sign in</Link></div>
      </Wrap>
    );
  }

  const last = step === STEPS.length;
  return (
    <Wrap>
      <Note kind="info" title="Apply for a postgraduate programme">
        Choose a programme and create your account in the steps below. The application fee is stated once you submit; after you pay, you complete your application in the portal — your first degree, other qualifications, referees, documents and passport. You may apply for only one programme at a time.
      </Note>

      <Stepper steps={STEPS} current={step} onGo={(n) => { if (n < step) { setProblem(null); setStep(n); } }} />
      {problem ? <ProblemNotice problem={problem} /> : null}

      <div className="card"><div className="card__body">
        {step === 1 ? (
          <>
            <Section title="Programme" />
            <Field id="programme" label="Programme applied for">
              <ProgrammePicker progs={progs} value={f.programme ?? ""} onPick={chooseProgramme} />
            </Field>
            {chosen ? <div className="hint">{chosen.department_name} · {chosen.faculty_name}{chosen.pg_research ? " · research degree (you can add a proposal in the last step)" : ""}</div> : <div className="hint">Search and pick the postgraduate programme you are applying for.</div>}
          </>
        ) : null}

        {step === 2 ? (
          <>
            <Section title="Your details" />
            <div className="grid grid--2">
              <Field id="surname" label="Surname"><input id="surname" className="ctl" value={f.surname ?? ""} onChange={set("surname")} autoComplete="family-name" /></Field>
              <Field id="otherNames" label="Other names"><input id="otherNames" className="ctl" value={f.otherNames ?? ""} onChange={set("otherNames")} autoComplete="given-name" /></Field>
              <Field id="sex" label="Sex"><select id="sex" className="ctl" value={f.sex ?? ""} onChange={set("sex")}><option value="">—</option><option value="F">Female</option><option value="M">Male</option></select></Field>
              <Field id="dob" label="Date of birth"><input id="dob" type="date" className="ctl" value={f.dob ?? ""} onChange={set("dob")} /></Field>
              <Field id="state" label="State of origin">
                <select id="state" className="ctl" value={f.state ?? ""} onChange={(e) => setF({ ...f, state: e.target.value, lga: "" })}>
                  <option value="">— Select a state —</option>
                  {STATES.map((s) => <option key={s} value={s}>{s}</option>)}
                </select>
              </Field>
              <Field id="lga" label="Local government">
                <select id="lga" className="ctl" value={f.lga ?? ""} onChange={set("lga")} disabled={!f.state}>
                  <option value="">{f.state ? "— Select an LGA —" : "Select a state first"}</option>
                  {lgasOf(f.state ?? "").map((l) => <option key={l} value={l}>{l}</option>)}
                </select>
              </Field>
              <Field id="email" label="Email"><input id="email" type="email" className="ctl" value={f.email ?? ""} onChange={set("email")} autoComplete="email" /></Field>
              <Field id="phone" label="Phone"><input id="phone" className="ctl" value={f.phone ?? ""} onChange={set("phone")} placeholder="08030000000" autoComplete="tel" /></Field>
            </div>
          </>
        ) : null}

        {step === 3 ? (
          <>
            <Section title="Choose a password" />
            <div className="grid grid--2">
              <Field id="password" label="Password" hint="At least six characters — to sign in and pay later"><input id="password" type="password" className="ctl" value={f.password ?? ""} onChange={set("password")} autoComplete="new-password" /></Field>
              <Field id="password2" label="Confirm password"><input id="password2" type="password" className="ctl" value={f.password2 ?? ""} onChange={set("password2")} autoComplete="new-password" /></Field>
            </div>
            {chosen?.pg_research ? (
              <>
                <Section title="Research proposal (optional)" />
                <Field id="proposalTitle" label="Proposed topic"><input id="proposalTitle" className="ctl" value={f.proposalTitle ?? ""} onChange={set("proposalTitle")} /></Field>
                <Field id="proposalText" label="Summary of the proposed research"><textarea id="proposalText" className="ctl" rows={4} value={f.proposalText ?? ""} onChange={set("proposalText")} /></Field>
              </>
            ) : null}
            <div className="hint">After you submit, sign in to pay the application fee. You then complete your first degree, other qualifications, referees, documents and passport in the portal.</div>
          </>
        ) : null}

        <div className="row mt-1">
          {step > 1 ? <Btn kind="ghost" onClick={back}>Back</Btn> : <LinkBtn kind="ghost" href="/login">Cancel</LinkBtn>}
          <span className="grow" />
          <span className="sub2">Step {step} of {STEPS.length}</span>
          {last
            ? <Btn kind="primary" size="md" disabled={busy} onClick={() => void submit()}>{busy ? "Submitting…" : "Create account & continue"}</Btn>
            : <Btn kind="primary" size="md" onClick={next}>Next</Btn>}
        </div>
      </div></div>

      <StatusCheck />
    </Wrap>
  );
}

/** the step indicator across the top of the application wizard; a completed step can be clicked to go back */
function Stepper({ steps, current, onGo }: { steps: string[]; current: number; onGo: (n: number) => void }) {
  return (
    <div style={{ display: "flex", gap: "var(--s-2)" }}>
      {steps.map((t, i) => {
        const n = i + 1;
        const done = current > n, cur = current === n;
        const on = done || cur;
        return (
          <button key={t} type="button" onClick={() => (done ? onGo(n) : undefined)} disabled={!done}
            style={{ flex: 1, textAlign: "left", background: "none", border: "none", padding: 0, cursor: done ? "pointer" : "default" }}>
            <div style={{ height: 5, borderRadius: "var(--r-sm)", background: on ? "var(--chrome)" : "var(--line-2)" }} />
            <div className="sub2 mt-2" style={{ fontWeight: cur ? 700 : 500, color: on ? "var(--ink)" : "var(--chrome)" }}>{n}. {t}</div>
          </button>
        );
      })}
    </div>
  );
}

function StatusCheck({ initialNo }: { initialNo?: string }) {
  const [no, setNo] = useState(initialNo ?? "");
  const [email, setEmail] = useState("");
  const [st, setSt] = useState<Status | null>(null);
  const [msg, setMsg] = useState<string | null>(null);

  async function check() {
    setMsg(null); setSt(null);
    const r = await fetch(`/api/bff/api/v1/pg/status?applicationNo=${encodeURIComponent(no.trim())}&email=${encodeURIComponent(email.trim())}`);
    const j = await r.json().catch(() => null);
    if (j && j.found) setSt(j.application as Status); else setMsg("No application matches that number and email.");
  }

  return (
    <div className="card mt-4"><div className="card__body">
      <Section title="Check your application" />
      <div className="grid grid--2">
        <Field id="st-no" label="Application number"><input id="st-no" className="ctl" value={no} onChange={(e) => setNo(e.target.value)} placeholder="PG/25/000001" /></Field>
        <Field id="st-em" label="Email"><input id="st-em" className="ctl" value={email} onChange={(e) => setEmail(e.target.value)} /></Field>
      </div>
      <div><Btn kind="ghost" onClick={() => void check()}>Check status</Btn></div>
      {msg ? <div className="hint">{msg}</div> : null}
      {st ? (
        <Note kind={st.state === "OFFERED" || st.state === "ACCEPTED" || st.state === "ADMITTED" ? "ok" : st.state === "NOT_OFFERED" || st.state === "DEPT_DECLINED" ? "bad" : "info"} title={STATE_LABEL[st.state] ?? st.state}>
          {st.surname}, {st.other_names} · {st.programme_name}{st.pg_award ? ` (${st.pg_award})` : ""}. {st.spgs_note ? `Note: ${st.spgs_note}. ` : ""}{st.fee_confirmed_at ? "Application fee confirmed." : "Application fee not yet confirmed."}
          {st.state === "DECISION_LOCKED" || st.state === "OFFERED" || !st.fee_confirmed_at ? (
            <div className="mt-2"><LinkBtn kind="primary" href="/login?next=/pg/portal">{st.state === "DECISION_LOCKED" ? "Sign in to pay the checking fee and see the decision" : st.state === "OFFERED" ? "Sign in to pay the acceptance fee and accept" : "Sign in to pay the application fee"}</LinkBtn></div>
          ) : null}
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
            <div><span className="eyebrow" style={{ color: "var(--chrome-dim)" }}>School of Postgraduate Studies</span></div>
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
        <div style={{ width: "100%", maxWidth: 620, display: "grid", gap: "var(--s-4)" }}>
          {children}
        </div>
      </div>
    </div>
  );
}

function Section({ title }: { title: string }) {
  return <div className="eyebrow" style={{ borderBottom: "1px solid var(--line-2)", paddingBottom: "var(--s-1)" }}>{title}</div>;
}
function Row({ k, v }: { k: string; v: string }) {
  return <div className="row row--between" style={{ padding: "var(--s-2) 0", borderBottom: "1px solid var(--line-2)" }}><span className="sub2">{k}</span><span className="tnum b700">{v}</span></div>;
}
