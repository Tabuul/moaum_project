"use client";

/**
 * The JUPEB candidate's dashboard (V339–V342), applicant to student to result, in the portal's own shell.
 *
 * While the application is a draft (or returned for correction) it is a guided application of five steps — personal
 * information, O'Level (one or two sittings), documents (each sitting's result its own), the programme (Science or
 * Non-Science, and a subject combination the University offers for it), and the review with the application fee and the
 * submission. "Save & Continue" saves the step and moves on when the server finds it complete; otherwise it stays, with each
 * field to correct marked. The candidate resumes at the first incomplete step.
 *
 * Once submitted: admission status checking (the Bursary's fee, once, while the Directorate of ICT has checking open), the
 * acceptance fee and letter, screening, the school fees, the subjects, attendance, results, the document centre and support.
 * Every amount is the server's; every call is scoped to the signed-in candidate.
 */
import { useCallback, useEffect, useMemo, useState, type ChangeEvent, type ReactNode } from "react";
import type { Problem } from "@/lib/api";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tabs, KvGrid } from "@/components/proto/ui";
import { Field, Steps as StepList } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { Shell, type Me as ShellMe } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PayByCard } from "@/app/applicant/common";
import { STATES, lgasOf, NATIONALITIES } from "@/lib/nigeria";
import {
  ADMISSION_STATUS, CHANGE_KIND, DOC_STATUS, EVENT_LABEL, FEE_KIND, REQUEST_STATE, laterSessions, OLEVEL_EXAMS, OLEVEL_GRADES, OLEVEL_SUBJECTS, SCREENING_LABEL, STATE_SHORT,
  day, feeCategoryLabel, fileBase64, fullName, jcall, naira, stateKind, streamLabel, when, type Candidate, type Combination, type Doc, type FeeRef, type StepProblem,
} from "@/lib/jupeb";

type Tab = "overview" | "admission" | "payments" | "subjects" | "attendance" | "results" | "documents" | "requests" | "support";
type Act = (path: string, method?: string, body?: unknown) => Promise<Candidate | null>;

interface Ticket { id: string; number: string; subject: string; category: string; status: string; created_at: string; updated_at: string; queue: string | null }
interface TicketDetail extends Ticket { description: string; resolution_summary: string | null; comments: { id: string; author_kind: string; author_name: string; body: string; created_at: string }[] }
interface Support { categories: { code: string; name: string; fields: string }[]; tickets: Ticket[] }

const ADMITTED = new Set(["ADMITTED", "STUDENT", "COMPLETED"]);
const STEP_ORDER = ["PERSONAL", "OLEVEL", "DOCUMENTS", "PROGRAMME", "REVIEW"] as const;
const STEP_TITLE: Record<string, string> = { PERSONAL: "Personal information", OLEVEL: "O’Level", DOCUMENTS: "Documents", PROGRAMME: "Programme", REVIEW: "Review & submit" };
const PHOTO = "/api/bff/api/v1/jupeb/me/documents/PASSPORT/content?format=jpeg";

/** the offered combinations that suit a programme (the server marks each one Science and/or Non-Science) */
const suiting = (all: Combination[] | undefined, stream: string | null) =>
  (all ?? []).filter((c) => c.offered && (stream === "SCIENCE" ? c.science : stream ? c.non_science : false));

export function JupebPortal() {
  const [me, setMe] = useState<Candidate | null>(null);
  const [loading, setLoading] = useState(true);
  const [signedOut, setSignedOut] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [tab, setTab] = useState<Tab>("overview");
  const [verifying, setVerifying] = useState(false);

  const load = useCallback(async () => {
    const r = await jcall<Candidate>("/api/v1/jupeb/me");
    if (!r.ok) {
      if (r.problem.status === 401 || r.problem.status === 403 || r.problem.status === 404) setSignedOut(true);
      else setProblem(r.problem);
    } else { setMe(r.data); setProblem(null); }
    setLoading(false);
  }, []);

  /* the gateway returns the payer with ?paid=REF: the gateway is asked, a few times, until the University has the payment */
  const pollConfirm = useCallback(async (ref: string, tries: number) => {
    for (let i = 0; i < tries; i++) {
      await jcall("/api/v1/payments/verify", "POST", { reference: ref });
      const r = await jcall<Candidate>("/api/v1/jupeb/me");
      if (r.ok) {
        setMe(r.data);
        if (r.data.references.some((x) => x.reference === ref && x.confirmed_at)) return true;
      }
      if (i < tries - 1) await new Promise((res) => setTimeout(res, 4000));
    }
    return false;
  }, []);

  useEffect(() => {
    const paid = new URLSearchParams(window.location.search).get("paid");
    void (async () => {
      await load();
      if (paid) {
        setVerifying(true);
        setTab(paid.includes("CHK") || paid.includes("ACC") ? "admission" : "payments");
        const ok = await pollConfirm(paid, 8);
        setVerifying(false);
        if (ok) notify("Payment confirmed — thank you.");
      }
    })();
  }, [load, pollConfirm]);

  /** one act; the record the server returns replaces the page's */
  const act: Act = useCallback(async (path, method = "POST", body) => {
    const r = await jcall<Candidate>(path, method, body);
    if (!r.ok) { notifyProblem(r.problem); return null; }
    setMe(r.data);
    return r.data;
  }, []);

  if (loading) return <Bare><Note kind="info" title="Loading your JUPEB record…">One moment.</Note></Bare>;
  if (signedOut || !me) {
    return (
      <Bare>
        {problem ? <ProblemNotice problem={problem} /> : null}
        <Note kind="info" title="Sign in to your JUPEB application">Sign in with the email you applied with, or your JUPEB application number, and your password.</Note>
        <div className="row mt-3"><LinkBtn kind="primary" href="/login?next=/jupeb/portal">Sign in</LinkBtn><LinkBtn kind="ghost" href="/jupeb/apply">Apply</LinkBtn></div>
      </Bare>
    );
  }

  const shellMe: ShellMe = {
    actorId: "", activeOffice: "jupebcandidate", offices: ["jupebcandidate"],
    name: fullName(me), staffNumber: me.exam_no ?? me.application_no, sessionId: null, unit: `JUPEB ${me.session}`, waiting: {},
  };
  const guided = me.state === "DRAFT" || me.state === "RETURNED";
  const admitted = ADMITTED.has(me.state);
  const tabs: { id: Tab; label: string; disabled?: boolean }[] = [
    { id: "overview", label: "Overview" }, { id: "admission", label: "Admission" }, { id: "payments", label: "Payments" },
    { id: "subjects", label: "Subjects", disabled: !admitted }, { id: "attendance", label: "Attendance", disabled: !(me.state === "STUDENT" || me.state === "COMPLETED") },
    { id: "results", label: "Results", disabled: !admitted }, { id: "documents", label: "Documents" },
    { id: "requests", label: me.requests.some((r) => r.state === "PENDING") ? "Requests (1)" : "Requests" }, { id: "support", label: "Support" },
  ];

  return (
    <Shell route="jupeb/portal" me={shellMe}>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Profile me={me} />
      {me.state === "WITHDRAWN" ? <Note kind="bad" title="Your application is withdrawn">{`Withdrawn${me.withdrawn_at ? ` on ${day(me.withdrawn_at)}` : ""}. Your record is kept; any refund is the Bursary's decision under its own rules.`}</Note> : null}
      <AttendanceWarning me={me} onOpen={() => setTab("attendance")} />
      {me.state === "DEFERRED" ? <Note kind="info" title={`Your admission is deferred to ${me.deferred_to ?? "a later session"}`}>The JUPEB Office resumes it in that session; you will be told, and your payments stand.</Note> : null}
      {verifying ? <Note kind="info" title="Confirming your payment…">The page updates on its own once the payment reaches the University.</Note> : null}
      {guided ? <Guided me={me} act={act} /> : (
        <>
          <Tabs items={tabs} value={tab} onChange={setTab} look="line" label="Your JUPEB record" />
          {tab === "overview" ? <Overview me={me} /> : null}
          {tab === "admission" ? <Admission me={me} reload={load} /> : null}
          {tab === "payments" ? <Payments me={me} reload={load} /> : null}
          {tab === "subjects" ? <Subjects me={me} act={act} /> : null}
          {tab === "attendance" ? <Attendance /> : null}
          {tab === "results" ? <Results me={me} /> : null}
          {tab === "documents" ? <DocumentCentre me={me} /> : null}
          {tab === "requests" ? <Requests me={me} act={act} /> : null}
          {tab === "support" ? <SupportTab /> : null}
        </>
      )}
    </Shell>
  );
}

/* ── the profile: the passport, and who the candidate is ─────────────────────────────────────────── */

function Passport({ src }: { src: string | null }) {
  return src ? (
    // eslint-disable-next-line @next/next/no-img-element
    <img src={src} alt="Passport photograph" style={{ width: 96, height: 120, objectFit: "contain", border: "1px solid var(--line-2)", borderRadius: "var(--r-sm)", background: "var(--bg)" }} />
  ) : (
    <div aria-label="No passport photograph" style={{ width: 96, height: 120, border: "1px dashed var(--line-2)", borderRadius: "var(--r-sm)", display: "grid", placeItems: "center", color: "var(--chrome)", fontSize: 11, textAlign: "center" }}>
      PASSPORT<br />PHOTOGRAPH
    </div>
  );
}

function Profile({ me }: { me: Candidate }) {
  const sc = me.statusChecking;
  const status = sc.may_check && sc.status ? ADMISSION_STATUS[sc.status] : null;
  return (
    <div className="card">
      <div className="card__body" style={{ display: "flex", flexDirection: "row", gap: "var(--s-4)", alignItems: "center", flexWrap: "wrap" }}>
        <Passport src={me.has_passport ? `${PHOTO}&v=${encodeURIComponent(me.updated_at)}` : null} />
        <div style={{ flex: 1, minWidth: 240 }}>
          <div className="b700" style={{ fontSize: 18 }}>{fullName(me)}</div>
          <KvGrid cls="grid--3" pairs={[
            ["Application number", me.application_no],
            ["JUPEB examination number", me.exam_no ?? "Not yet assigned"],
            ["Programme", `${streamLabel(me.stream)}${me.combination_code ? ` · ${me.combination_code}` : ""}`],
            ["Session", me.session],
            ["Application", <Pil key="s" kind={stateKind(me.state)}>{STATE_SHORT[me.state] ?? me.state}</Pil>],
            ["Admission status", status ? <Pil key="a" kind={status[1]}>{status[0]}</Pil> : <span key="a" className="sub2">{me.submitted_at ? "Not yet checked" : "—"}</span>],
          ]} />
        </div>
      </div>
    </div>
  );
}

/* ── the guided application ─────────────────────────────────────────────────────────────────────── */

function Guided({ me, act }: { me: Candidate; act: Act }) {
  const startAt = Math.max(0, STEP_ORDER.indexOf((me.steps?.current ?? "PERSONAL") as (typeof STEP_ORDER)[number]));
  const [step, setStep] = useState<number>(startAt);
  const [shown, setShown] = useState<StepProblem[]>([]);
  const status = (n: number) => me.steps.steps.find((s) => s.step === STEP_ORDER[n]);

  /** after a save: on to the next step when the server finds this one complete; otherwise stay, with what to correct */
  const advance = useCallback((fresh: Candidate | null, n: number) => {
    if (!fresh) return;
    const st = fresh.steps.steps.find((s) => s.step === STEP_ORDER[n]);
    if (st && st.ok) {
      setShown([]);
      setStep(Math.min(n + 1, STEP_ORDER.length - 1));
      window.scrollTo({ top: 0, behavior: "smooth" });
    } else {
      setShown(st?.problems ?? []);
      notifyProblem({ status: 422, title: "Some things on this step still need your attention." });
    }
  }, []);
  const back = () => { setShown([]); setStep((n) => Math.max(0, n - 1)); };
  const errors = useMemo(() => Object.fromEntries(shown.map((p) => [p.field, p.message])), [shown]);

  return (
    <>
      {me.state === "RETURNED" && me.return_note ? <Note kind="bad" title="The JUPEB Office returned your application">{me.return_note} Correct it below and submit again.</Note> : null}
      <div style={{ display: "flex", gap: "var(--s-2)" }} role="list" aria-label="Application steps">
        {STEP_ORDER.map((k, i) => {
          const done = status(i)?.ok, cur = step === i;
          return (
            <button key={k} type="button" role="listitem" aria-current={cur ? "step" : undefined} onClick={() => { setShown([]); setStep(i); }}
              style={{ flex: 1, textAlign: "left", background: "none", border: "none", padding: 0, cursor: "pointer" }}>
              <div style={{ height: 5, borderRadius: "var(--r-sm)", background: done ? "var(--green-ink)" : cur ? "var(--chrome)" : "var(--line-2)" }} />
              <div className="sub2 mt-2" style={{ fontWeight: cur ? 700 : 500, color: cur || done ? "var(--ink)" : "var(--chrome)" }}>{i + 1}. {STEP_TITLE[k]}{done ? " ✓" : ""}</div>
            </button>
          );
        })}
      </div>
      {shown.length ? <Note kind="bad" title="Please correct the following">{shown.map((p) => p.message).join(" · ")}</Note> : null}
      {step === 0 ? <PersonalStep me={me} act={act} errors={errors} onSaved={(f) => advance(f, 0)} /> : null}
      {step === 1 ? <OlevelStep me={me} act={act} errors={errors} onSaved={(f) => advance(f, 1)} onBack={back} /> : null}
      {step === 2 ? <DocumentsStep me={me} act={act} errors={errors} onContinue={() => advance(me, 2)} onBack={back} /> : null}
      {step === 3 ? <ProgrammeStep me={me} act={act} errors={errors} onSaved={(f) => advance(f, 3)} onBack={back} /> : null}
      {step === 4 ? <ReviewStep me={me} act={act} onBack={back} onGo={(n) => { setShown([]); setStep(n); }} /> : null}
    </>
  );
}

function StepFoot({ onBack, children }: { onBack?: () => void; children: ReactNode }) {
  return (
    <div className="row mt-3">
      {onBack ? <Btn kind="ghost" onClick={onBack}>← Back</Btn> : null}
      <span className="grow" />
      {children}
    </div>
  );
}

function PersonalStep({ me, act, errors, onSaved }: { me: Candidate; act: Act; errors: Record<string, string>; onSaved: (c: Candidate | null) => void }) {
  const [f, setF] = useState<Record<string, string>>(() => ({
    middleName: me.middle_name ?? "", sex: me.sex ?? "", dob: me.date_of_birth ?? "", nin: me.nin ?? "", phone: me.phone ?? "",
    nationality: me.nationality ?? "Nigerian", stateOfOrigin: me.state_of_origin ?? "", lga: me.lga ?? "", contactAddress: me.contact_address ?? "",
    permanentAddress: me.permanent_address ?? "", homeTown: me.home_town ?? "", guardianName: me.guardian_name ?? "", guardianPhone: me.guardian_phone ?? "",
    guardianAddress: me.guardian_address ?? "", nextOfKinName: me.next_of_kin_name ?? "", nextOfKinPhone: me.next_of_kin_phone ?? "", nextOfKinRelationship: me.next_of_kin_relationship ?? "",
  }));
  const [busy, setBusy] = useState(false);
  const set = (k: string) => (e: ChangeEvent<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>) => setF({ ...f, [k]: e.target.value });
  const nigerian = f.nationality === "Nigerian";
  async function save() {
    setBusy(true);
    try {
      const body = Object.fromEntries(Object.entries(f).map(([k, v]) => [k, v.trim() === "" ? null : v.trim()]));
      onSaved(await act("/api/v1/jupeb/me/biodata", "PUT", body));
    } finally { setBusy(false); }
  }
  const input = (k: string, label: string, o: { max?: number; type?: string; required?: boolean; hint?: string } = {}) => (
    <Field id={`p-${k}`} label={label} required={o.required} hint={o.hint} error={errors[k]}>
      <input id={`p-${k}`} className="ctl" type={o.type ?? "text"} value={f[k] ?? ""} onChange={set(k)} maxLength={o.max ?? 120} />
    </Field>
  );
  return (
    <Panel title="Step 1 · Personal information">
      <PBody>
        <KvGrid pairs={[["Surname", me.surname], ["First name", me.first_name], ["Email", me.email], ["Application number", me.application_no]]} />
        <div className="grid grid--3 mt-3">
          {input("middleName", "Middle name", { max: 80 })}
          <Field id="p-sex" label="Sex" required error={errors.sex}><select id="p-sex" className="ctl" value={f.sex} onChange={set("sex")}><option value="">—</option><option value="F">Female</option><option value="M">Male</option></select></Field>
          {input("dob", "Date of birth", { type: "date", required: true })}
          {input("nin", "NIN", { max: 11, required: true, hint: "Eleven digits" })}
          {input("phone", "Phone", { max: 11, required: true, hint: "e.g. 08012345678" })}
          <Field id="p-nat" label="Nationality">
            <select id="p-nat" className="ctl" value={f.nationality} onChange={(e) => setF({ ...f, nationality: e.target.value, ...(e.target.value === "Nigerian" ? {} : { stateOfOrigin: "", lga: "" }) })}>
              {NATIONALITIES.map((n) => <option key={n} value={n}>{n}</option>)}
            </select>
          </Field>
          <Field id="p-state" label="State of origin" required hint="Decides the indigene school fee" error={errors.stateOfOrigin}>
            <select id="p-state" className="ctl" value={f.stateOfOrigin} onChange={(e) => setF({ ...f, stateOfOrigin: e.target.value, lga: "" })} disabled={!nigerian}>
              <option value="">— Select a state —</option>{STATES.map((s) => <option key={s} value={s}>{s}</option>)}
            </select>
          </Field>
          <Field id="p-lga" label="Local government" required error={errors.lga}>
            <select id="p-lga" className="ctl" value={f.lga} onChange={set("lga")} disabled={!nigerian || !f.stateOfOrigin}>
              <option value="">{f.stateOfOrigin ? "— Select an LGA —" : "Select a state first"}</option>{lgasOf(f.stateOfOrigin).map((l) => <option key={l} value={l}>{l}</option>)}
            </select>
          </Field>
          {input("homeTown", "Home town", { max: 80 })}
        </div>
        <div className="grid grid--2">
          <Field id="p-ca" label="Contact address" required error={errors.contactAddress}><textarea id="p-ca" className="ctl" rows={2} maxLength={300} value={f.contactAddress} onChange={set("contactAddress")} /></Field>
          <Field id="p-pa" label="Permanent home address"><textarea id="p-pa" className="ctl" rows={2} maxLength={300} value={f.permanentAddress} onChange={set("permanentAddress")} /></Field>
        </div>
        <div className="eyebrow mt-3">Parent or guardian</div>
        <div className="grid grid--3">{input("guardianName", "Name")}{input("guardianPhone", "Phone", { max: 11 })}{input("guardianAddress", "Address", { max: 300 })}</div>
        <div className="eyebrow mt-3">Next of kin</div>
        <div className="grid grid--3">{input("nextOfKinName", "Name", { required: true })}{input("nextOfKinPhone", "Phone", { max: 11, required: true })}{input("nextOfKinRelationship", "Relationship", { max: 60 })}</div>
        <StepFoot><Btn kind="primary" size="md" disabled={busy} onClick={() => void save()}>{busy ? "Saving…" : "Save & Continue"}</Btn></StepFoot>
      </PBody>
    </Panel>
  );
}

interface Line { subject: string; grade: string }
interface Sitting { examType: string; examNumber: string; examYear: string; lines: Line[] }

function OlevelStep({ me, act, errors, onSaved, onBack }: { me: Candidate; act: Act; errors: Record<string, string>; onSaved: (c: Candidate | null) => void; onBack: () => void }) {
  const init = (n: number): Sitting => {
    const rows = me.olevel.filter((o) => o.sitting === n);
    return {
      examType: rows[0]?.exam_type ?? (n === 1 ? "WAEC" : "NECO"), examNumber: rows[0]?.exam_number ?? "", examYear: rows[0]?.exam_year ? String(rows[0].exam_year) : "",
      lines: rows.length ? rows.map((r) => ({ subject: r.subject, grade: r.grade })) : ["English Language", "Mathematics", "", "", ""].map((s) => ({ subject: n === 1 ? s : "", grade: "" })),
    };
  };
  const [count, setCount] = useState<number>(me.olevel_sittings ?? (me.olevel.some((o) => o.sitting === 2) ? 2 : 1));
  const [s, setS] = useState<Sitting[]>(() => [init(1), init(2)]);
  const [busy, setBusy] = useState(false);
  const upd = (i: number, patch: Partial<Sitting>) => setS(s.map((x, j) => (j === i ? { ...x, ...patch } : x)));
  const updLine = (i: number, k: number, patch: Partial<Line>) => upd(i, { lines: s[i].lines.map((l, m) => (m === k ? { ...l, ...patch } : l)) });
  async function save() {
    const grades = s.slice(0, count).flatMap((x, i) => x.lines.filter((l) => l.subject.trim() && l.grade).map((l) => ({
      sitting: i + 1, examType: x.examType, examNumber: x.examNumber.trim() || null, examYear: x.examYear ? Number(x.examYear) : null, subject: l.subject.trim(), grade: l.grade,
    })));
    setBusy(true);
    try { onSaved(await act("/api/v1/jupeb/me/olevel", "PUT", { sittings: count, grades })); } finally { setBusy(false); }
  }
  const c = me.olevelCheck;
  return (
    <div className="stack">
      <Panel title="Step 2 · O’Level results">
        <PBody>
          <p className="sub2">At least five credits including English Language and Mathematics, in no more than two sittings. With two sittings, enter each sitting&rsquo;s results separately; you upload each result in the next step.</p>
          <Field id="o-count" label="Number of sittings" required error={errors.olevelSittings}>
            <select id="o-count" className="ctl" style={{ maxWidth: 220 }} value={count} onChange={(e) => setCount(Number(e.target.value))}>
              <option value={1}>One sitting</option><option value={2}>Two sittings</option>
            </select>
          </Field>
          {c.sittings > 0 ? <Note kind={c.ok ? "ok" : "info"} title={c.ok ? `Requirement met — ${c.credits} credits` : "Not yet meeting the requirement"}>{c.ok ? "Your combined O’Level meets the JUPEB requirement." : c.reasons.join("; ") + "."}</Note> : null}
        </PBody>
      </Panel>
      <datalist id="olevel-subjects">{OLEVEL_SUBJECTS.map((x) => <option key={x} value={x} />)}</datalist>
      {s.slice(0, count).map((x, i) => (
        <Panel key={i} title={i === 0 ? "First sitting" : "Second sitting"}>
          <PBody>
            <div className="grid grid--3">
              <Field id={`ex-${i}`} label="Examination body" required><select id={`ex-${i}`} className="ctl" value={x.examType} onChange={(e) => upd(i, { examType: e.target.value })}>{OLEVEL_EXAMS.map((t) => <option key={t}>{t}</option>)}</select></Field>
              <Field id={`en-${i}`} label="Examination number" required><input id={`en-${i}`} className="ctl" maxLength={30} value={x.examNumber} onChange={(e) => upd(i, { examNumber: e.target.value })} /></Field>
              <Field id={`ey-${i}`} label="Year" required><input id={`ey-${i}`} className="ctl tnum" inputMode="numeric" maxLength={4} value={x.examYear} onChange={(e) => upd(i, { examYear: e.target.value.replace(/\D/g, "") })} /></Field>
            </div>
            {x.lines.map((l, k) => (
              <div key={k} className="row" style={{ gap: "var(--s-2)", marginTop: "var(--s-2)" }}>
                <input className="ctl grow" list="olevel-subjects" placeholder="Subject" aria-label={`Sitting ${i + 1} subject ${k + 1}`} value={l.subject} onChange={(e) => updLine(i, k, { subject: e.target.value })} maxLength={60} />
                <select className="ctl" style={{ width: 110 }} aria-label={`Sitting ${i + 1} grade ${k + 1}`} value={l.grade} onChange={(e) => updLine(i, k, { grade: e.target.value })}>
                  <option value="">Grade</option>{OLEVEL_GRADES.map((g) => <option key={g}>{g}</option>)}
                </select>
                <Btn kind="ghost" onClick={() => upd(i, { lines: x.lines.filter((_, m) => m !== k) })} aria-label="Remove subject">&times;</Btn>
              </div>
            ))}
            {x.lines.length < 12 ? <div className="mt-2"><Btn kind="ghost" onClick={() => upd(i, { lines: [...x.lines, { subject: "", grade: "" }] })}>Add a subject</Btn></div> : null}
          </PBody>
        </Panel>
      ))}
      <StepFoot onBack={onBack}><Btn kind="primary" size="md" disabled={busy} onClick={() => void save()}>{busy ? "Saving…" : "Save & Continue"}</Btn></StepFoot>
    </div>
  );
}

const sittingQ = (d: Doc) => (d.sitting ? `?sitting=${d.sitting}` : "");
const docUrl = (d: Doc) => `/api/bff/api/v1/jupeb/me/documents/${d.kind}/content${sittingQ(d)}`;

function DocumentRows({ me, act, editable, errors }: { me: Candidate; act: Act; editable: boolean; errors?: Record<string, string> }) {
  const [busy, setBusy] = useState<string | null>(null);
  const key = (d: Doc) => `${d.kind}:${d.sitting ?? ""}`;
  async function upload(d: Doc, file: File | undefined) {
    if (!file) return;
    if (file.size > 5 * 1024 * 1024) { notifyProblem({ status: 400, title: "A document is at most 5 MB." }); return; }
    setBusy(key(d));
    try {
      const base64 = await fileBase64(file);
      const r = await act(`/api/v1/jupeb/me/documents/${d.kind}${sittingQ(d)}`, "POST", { filename: file.name, contentType: file.type || "application/octet-stream", base64 });
      if (r) notify(`${d.label} uploaded.`);
    } finally { setBusy(null); }
  }
  return (
    <DTable noPrint pageSize={0} cols={["Document", "Status", "File", "Uploaded", "Action|mid"]} rows={me.documents.map((d) => {
      const replace = d.status === "REJECTED" || d.status === "REPLACEMENT_REQUIRED";
      const can = editable || replace;
      const err = errors?.[`doc:${d.kind}${d.sitting ? `:${d.sitting}` : ""}`];
      return [
        <span key="l"><b>{d.label}</b>{d.required ? <span className="sub2"> · required</span> : null}{d.exam_body ? <div className="sub2">{d.exam_body}{d.exam_year ? ` ${d.exam_year}` : ""}</div> : null}
          {d.review_note ? <div className="sub2">{d.review_note}</div> : null}{err ? <div className="ferr">{err}</div> : null}</span>,
        d.status ? <Pil key="s" kind={stateKind(d.status)}>{DOC_STATUS[d.status] ?? d.status}</Pil> : <Pil key="s" kind={err ? "bad" : "grey"}>Not uploaded</Pil>,
        d.filename ? <a key="f" href={docUrl(d)} target="_blank" rel="noreferrer">{d.filename}</a> : "—",
        day(d.uploaded_at),
        <span key="a" className="row" style={{ gap: "var(--s-1)", justifyContent: "center" }}>
          {can ? (
            <label className="btn btn--secondary btn--sm" style={{ cursor: busy ? "wait" : "pointer" }}>
              {busy === key(d) ? "Uploading…" : d.filename ? "Replace" : "Upload"}
              <input type="file" hidden accept={d.image ? "image/jpeg,image/png" : "application/pdf,image/jpeg,image/png"} onChange={(e) => void upload(d, e.target.files?.[0])} disabled={!!busy} />
            </label>
          ) : null}
          {editable && d.filename ? <Btn kind="ghost" onClick={() => void act(`/api/v1/jupeb/me/documents/${d.kind}${sittingQ(d)}`, "DELETE")}>Remove</Btn> : null}
        </span>,
      ];
    })} />
  );
}

function DocumentsStep({ me, act, errors, onContinue, onBack }: { me: Candidate; act: Act; errors: Record<string, string>; onContinue: () => void; onBack: () => void }) {
  return (
    <Panel title="Step 3 · Documents" right={<span className="sub2">PDF, JPEG or PNG · at most 5 MB · the passport photograph is an image</span>}>
      <PBody>
        {(me.olevel_sittings ?? 1) === 2 ? <Note kind="info" title="Two sittings">Upload each sitting&rsquo;s O&rsquo;Level result on its own line — both are required.</Note> : null}
        <DocumentRows me={me} act={act} editable errors={errors} />
        <StepFoot onBack={onBack}><Btn kind="primary" size="md" onClick={onContinue}>Save & Continue</Btn></StepFoot>
      </PBody>
    </Panel>
  );
}

/** the subject combinations offered for a programme, grouped by the Board's areas, with the three subjects of each */
function CombinationPicker({ list, value, onChange, id, error }: { list: Combination[]; value: string; onChange: (id: string) => void; id: string; error?: string }) {
  const areas = [...new Set(list.map((c) => c.area ?? "Other"))];
  const chosen = list.find((c) => c.id === value) ?? null;
  return (
    <>
      <Field id={id} label="Subject combination" required error={error} hint={list.length ? "The three subjects you will study and be examined in by the Board." : "No combination is offered for this programme yet."}>
        <select id={id} className="ctl" value={value} onChange={(e) => onChange(e.target.value)} disabled={!list.length}>
          <option value="">— Choose a combination —</option>
          {areas.map((a) => (
            <optgroup key={a} label={a}>
              {list.filter((c) => (c.area ?? "Other") === a).map((c) => <option key={c.id} value={c.id}>{c.code} — {c.subject1}, {c.subject2}, {c.subject3}</option>)}
            </optgroup>
          ))}
        </select>
      </Field>
      {chosen ? <DTable noPrint pageSize={0} cols={["Code", "Subject"]} rows={[[chosen.subject1_code, chosen.subject1], [chosen.subject2_code, chosen.subject2], [chosen.subject3_code, chosen.subject3]]} /> : null}
    </>
  );
}

function ProgrammeStep({ me, act, errors, onSaved, onBack }: { me: Candidate; act: Act; errors: Record<string, string>; onSaved: (c: Candidate | null) => void; onBack: () => void }) {
  const [stream, setStream] = useState<string>(me.stream === "ARTS" ? "NON_SCIENCE" : me.stream ?? "");
  const offered = suiting(me.combinations, stream || null);
  const held = me.combination_id && offered.some((c) => c.id === me.combination_id) ? me.combination_id : "";
  const [combination, setCombination] = useState<string>(held);
  const [busy, setBusy] = useState(false);
  const heldButGone = !!me.combination_id && !held && me.stream === stream;
  async function save() {
    if (!stream) { onSaved(me); return; }
    setBusy(true);
    try { onSaved(await act("/api/v1/jupeb/me/choice", "PUT", { stream, combination: combination || null })); } finally { setBusy(false); }
  }
  return (
    <Panel title="Step 4 · Programme and subject combination">
      <PBody>
        <Field id="g-stream" label="Programme" required error={errors.stream}>
          <select id="g-stream" className="ctl" style={{ maxWidth: 320 }} value={stream}
            onChange={(e) => { setStream(e.target.value); if (!suiting(me.combinations, e.target.value).some((c) => c.id === combination)) setCombination(""); }}>
            <option value="">— Science or Non-Science —</option><option value="SCIENCE">Science</option><option value="NON_SCIENCE">Non-Science</option>
          </select>
        </Field>
        {heldButGone ? <Note kind="bad" title={`${me.combination_code} is no longer offered`}>The University no longer offers the combination you chose. Choose another below.</Note> : null}
        {stream ? <CombinationPicker id="g-comb" list={offered} value={combination} onChange={setCombination} error={errors.combination} /> : null}
        <StepFoot onBack={onBack}><Btn kind="primary" size="md" disabled={busy} onClick={() => void save()}>{busy ? "Saving…" : "Save & Continue"}</Btn></StepFoot>
      </PBody>
    </Panel>
  );
}

function ReviewStep({ me, act, onBack, onGo }: { me: Candidate; act: Act; onBack: () => void; onGo: (n: number) => void }) {
  const [busy, setBusy] = useState(false);
  const [ref, setRef] = useState<{ reference: string; amount: number } | null>(null);
  const incomplete = me.steps.steps.filter((s) => s.step !== "REVIEW" && !s.ok);
  const comb = (me.combinations ?? []).find((c) => c.id === me.combination_id);
  async function payFee() {
    const r = await jcall<{ reference: string; amount: number }>("/api/v1/jupeb/me/fee-reference?kind=APPLICATION", "POST");
    if (!r.ok) { notifyProblem(r.problem); return; }
    setRef(r.data);
  }
  async function submit() {
    setBusy(true);
    try {
      const r = await act("/api/v1/jupeb/me/submit");
      if (r) notify("Your application is submitted. We have emailed you.");
    } finally { setBusy(false); }
  }
  return (
    <div className="stack">
      <Panel title="Step 5 · Review your application">
        <PBody>
          {incomplete.length ? <Note kind="bad" title="Not ready to submit">{incomplete.map((s) => (
            <span key={s.step}><a href="#" onClick={(e) => { e.preventDefault(); onGo(STEP_ORDER.indexOf(s.step)); }}>{STEP_TITLE[s.step]}</a>: {s.problems.map((p) => p.message).join("; ")}. </span>
          ))}</Note> : <Note kind="ok" title="Everything is in">Check the details below, then submit. Once submitted, the application cannot be changed unless the JUPEB Office returns it.</Note>}
          <div className="eyebrow mt-2">Personal information</div>
          <KvGrid pairs={[["Name", fullName(me)], ["Sex", me.sex === "F" ? "Female" : me.sex === "M" ? "Male" : "—"], ["Date of birth", day(me.date_of_birth)], ["NIN", me.nin ?? "—"],
            ["Phone", me.phone ?? "—"], ["State / LGA", `${me.state_of_origin ?? "—"} / ${me.lga ?? "—"}`], ["Contact address", me.contact_address ?? "—"], ["Next of kin", me.next_of_kin_name ? `${me.next_of_kin_name} (${me.next_of_kin_phone ?? ""})` : "—"]]} />
          <div className="eyebrow mt-3">O&rsquo;Level ({me.olevel_sittings === 2 ? "two sittings" : "one sitting"})</div>
          <DTable noPrint pageSize={0} cols={["Sitting|num", "Examination", "Number", "Year", "Subject", "Grade|mid"]} rows={me.olevel.map((o) => [o.sitting, o.exam_type, o.exam_number ?? "—", o.exam_year ?? "—", o.subject, o.grade])} />
          <div className="eyebrow mt-3">Documents</div>
          <DTable noPrint pageSize={0} cols={["Document", "File", "Status"]} rows={me.documents.map((d) => [d.label, d.filename ?? "Not uploaded", d.status ? DOC_STATUS[d.status] ?? d.status : "—"])} />
          <div className="eyebrow mt-3">Programme and fee</div>
          <KvGrid pairs={[["Programme", streamLabel(me.stream)], ["Subject combination", comb ? `${comb.code} — ${comb.subject1}, ${comb.subject2}, ${comb.subject3}` : me.combination_code ?? "—"],
            ["Application fee", me.fee_confirmed_at ? `Paid ${day(me.fee_confirmed_at)}` : `Unpaid · ${naira(me.application_fee)}`]]} />
          {!me.fee_confirmed_at ? (
            <div className="mt-3">
              {ref ? (
                <><PayByCard reference={ref.reference} amount={Number(ref.amount)} /><div className="sub2 mt-1">Reference <b className="tnum">{ref.reference}</b>. The page confirms the payment when you return from the gateway.</div></>
              ) : <Btn kind="secondary" onClick={() => void payFee()}>Pay the application fee ({naira(me.application_fee)})</Btn>}
            </div>
          ) : null}
        </PBody>
      </Panel>
      <StepFoot onBack={onBack}><Btn kind="go" size="md" disabled={busy || !me.steps.complete} onClick={() => void submit()}>{busy ? "Submitting…" : me.state === "RETURNED" ? "Submit again" : "Submit application"}</Btn></StepFoot>
    </div>
  );
}

/* ── after submission ───────────────────────────────────────────────────────────────────────────── */

function Overview({ me }: { me: Candidate }) {
  const sc = me.statusChecking;
  const screeningDone = me.screening_state === "CLEARED" || !me.screeningSetting.screening_required;
  const steps: ["done" | "now" | "todo", string, string][] = [
    ["done", "Application submitted", day(me.submitted_at)],
    [sc.paid ? "done" : sc.window_open ? "now" : "todo", "Admission status checked", sc.paid ? day(sc.paid_at) : sc.window_open ? "Checking is open — pay and check" : "Checking is not open yet"],
    [me.accepted_at ? "done" : sc.may_check && sc.status === "ADMITTED" ? "now" : "todo", "Admission accepted (acceptance fee)", me.accepted_at ? day(me.accepted_at) : "—"],
    [me.accepted_at && screeningDone ? "done" : me.accepted_at ? "now" : "todo", "Screening", me.screening_state ? SCREENING_LABEL[me.screening_state] ?? me.screening_state : me.screeningSetting.screening_required ? "Required" : "Not required"],
    [me.activated_at ? "done" : me.accepted_at ? "now" : "todo", "School fee paid — studentship activated", me.activated_at ? day(me.activated_at) : "—"],
    [me.subjects_registered_at ? "done" : me.state === "STUDENT" ? "now" : "todo", "Subject combination registered", me.subjects_registered_at ? day(me.subjects_registered_at) : "—"],
    [me.exam_no ? "done" : "todo", "JUPEB examination number", me.exam_no ?? "—"],
    [me.state === "COMPLETED" ? "done" : "todo", "Results published", me.resultsPublished ? "Published" : "—"],
  ];
  return (
    <div className="grid grid--2">
      <Panel title="Your progress"><PBody><StepList list={steps} /></PBody></Panel>
      <Panel title="What has happened">
        <PBody>
          <ul style={{ listStyle: "none", margin: 0, padding: 0 }}>
            {[...me.events].reverse().map((e, i) => (
              <li key={i} style={{ padding: "var(--s-2) 0", borderBottom: "1px solid var(--line)" }}>
                <div className="b600">{EVENT_LABEL[e.kind] ?? e.kind}</div>
                <div className="sub2">{e.note ? `${e.note} · ` : ""}{when(e.at)}</div>
              </li>
            ))}
          </ul>
        </PBody>
      </Panel>
    </div>
  );
}

/** a fee's payment: the reference is made by the server, on the Bursary's amount; confirmation is the gateway's, never the page's */
function PayBox({ kind, amount, me, reload, label }: { kind: string; amount: number; me: Candidate; reload: () => Promise<void>; label: string }) {
  const [ref, setRef] = useState<{ reference: string; amount: number } | null>(null);
  const [busy, setBusy] = useState(false);
  const open = me.references.find((x) => x.kind === kind && !x.confirmed_at && new Date(x.expires_at) > new Date());
  async function prepare() {
    setBusy(true);
    try {
      const r = await jcall<{ reference: string; amount: number }>(`/api/v1/jupeb/me/fee-reference?kind=${kind}`, "POST");
      if (!r.ok) { notifyProblem(r.problem); return; }
      setRef(r.data);
    } finally { setBusy(false); }
  }
  async function check(reference: string) {
    setBusy(true);
    try { await jcall("/api/v1/payments/verify", "POST", { reference }); await reload(); } finally { setBusy(false); }
  }
  const r = ref ?? (open ? { reference: open.reference, amount: open.amount } : null);
  return r ? (
    <>
      <PayByCard reference={r.reference} amount={Number(r.amount)} />
      <div className="row mt-2"><Btn kind="secondary" disabled={busy} onClick={() => void check(r.reference)}>{busy ? "Checking…" : "I’ve paid — check now"}</Btn><span className="sub2">Reference <b className="tnum">{r.reference}</b></span></div>
    </>
  ) : <Btn kind="primary" disabled={busy} onClick={() => void prepare()}>{label} ({naira(amount)})</Btn>;
}

function Admission({ me, reload }: { me: Candidate; reload: () => Promise<void> }) {
  const sc = me.statusChecking;
  const status = sc.status ? ADMISSION_STATUS[sc.status] : null;
  const ss = me.screeningSetting;
  return (
    <div className="stack">
      <Panel title="Admission status" right={sc.may_check && status ? <Pil kind={status[1]}>{status[0]}</Pil> : null}>
        <PBody>
          {sc.may_check && status ? (
            <>
              <Note kind={status[1] === "warn" ? "info" : status[1]} title={`Your admission status: ${status[0]}`}>
                {sc.status === "ADMITTED" ? `You are offered provisional admission into the JUPEB programme${me.admission_ref ? ` (${me.admission_ref})` : ""}. ${me.admission_note ?? ""}`
                  : sc.status === "NOT_ADMITTED" ? (me.admission_note ?? me.eligibility_note ?? "You were not offered admission this session.")
                  : sc.status === "PENDING" ? (me.admission_note ?? "A decision on your application is pending.")
                  : sc.status === "REQUIRES_REVIEW" ? "Your application needs your attention: see the return note."
                  : "Your application is being processed. Check again later; you will not pay again."}
              </Note>
              <div className="row">
                <LinkBtn kind="ghost" href="/jupeb/pdf/status">Admission status slip</LinkBtn>
                {sc.status === "ADMITTED" ? <LinkBtn kind="ghost" href="/jupeb/pdf/letter">Admission letter</LinkBtn> : null}
              </div>
            </>
          ) : !sc.valid ? <p className="sub2">Status checking is for a submitted application whose fee is paid.</p>
            : !sc.window_open ? <Note kind="info" title="Admission status checking is not open yet">The Directorate of ICT opens it when admissions are ready. You will pay a status checking fee of {naira(me.feeRule.checking_fee)} once, then check your status as often as you like.</Note>
            : (
              <>
                <p>Pay the admission status checking fee once ({naira(me.feeRule.checking_fee)}) to see your admission status. You will not pay it again.</p>
                <PayBox kind="STATUS_CHECKING" amount={me.feeRule.checking_fee} me={me} reload={reload} label="Pay and check my status" />
              </>
            )}
        </PBody>
      </Panel>
      {sc.may_check && sc.status === "ADMITTED" ? (
        <Panel title="Acceptance" right={me.accepted_at ? <Pil kind="ok">Accepted {day(me.accepted_at)}</Pil> : <Pil kind="warn">Not yet accepted</Pil>}>
          <PBody>
            {me.accepted_at ? (
              <div className="row"><LinkBtn kind="primary" href="/jupeb/pdf/acceptance">Download acceptance letter</LinkBtn><span className="sub2">Your school fees are next (Payments).</span></div>
            ) : (
              <>
                <p>Accept your admission by paying the acceptance fee of {naira(me.feeRule.acceptance_fee)}. Your acceptance letter is issued once the payment is confirmed; school fees follow.</p>
                <PayBox kind="ACCEPTANCE" amount={me.feeRule.acceptance_fee} me={me} reload={reload} label="Pay the acceptance fee" />
              </>
            )}
          </PBody>
        </Panel>
      ) : null}
      {sc.may_check && ADMITTED.has(me.state) && (ss.screening_required || me.screening_state) ? (
        <Panel title="Screening" right={me.screening_state ? <Pil kind={stateKind(me.screening_state)}>{SCREENING_LABEL[me.screening_state] ?? me.screening_state}</Pil> : null}>
          <PBody>
            <KvGrid pairs={[["Venue", me.screening_venue ?? ss.screening_venue ?? "—"], ["When", me.screening_at ? when(me.screening_at) : ss.screening_starts_on ? `${day(ss.screening_starts_on)} – ${day(ss.screening_ends_on)}` : "—"]]} />
            {ss.screening_instructions ? <p className="mt-2" style={{ whiteSpace: "pre-line" }}>{ss.screening_instructions}</p> : null}
            {me.screening_reason ? <Note kind={me.screening_state === "CLEARED" ? "ok" : "bad"} title="From the screening desk">{me.screening_reason}</Note> : null}
          </PBody>
        </Panel>
      ) : null}
    </div>
  );
}

function Payments({ me, reload }: { me: Candidate; reload: () => Promise<void> }) {
  const f = me.fees;
  const admitted = !!f && ADMITTED.has(me.state);
  const screeningFirst = me.screeningSetting.screening_required && me.state === "ADMITTED" && me.screening_state !== "CLEARED";
  const rule = me.feeRule;
  return (
    <div className="stack">
      <Panel title="Payment summary">
        <PBody>
          <DTable noPrint pageSize={0} cols={["Fee", "Amount|num", "Status"]} rows={[
            ["Application fee", naira(rule.application_fee), me.fee_confirmed_at ? <Pil key="a" kind="ok">Paid</Pil> : <Pil key="a" kind="warn">Unpaid</Pil>],
            ["Admission status checking fee", naira(rule.checking_fee), me.checking_paid_at ? <Pil key="b" kind="ok">Paid</Pil> : <Pil key="b" kind="grey">When checking opens</Pil>],
            ["Acceptance fee", naira(rule.acceptance_fee), me.accepted_at ? <Pil key="c" kind="ok">Paid</Pil> : <Pil key="c" kind="grey">If admitted</Pil>],
            ["School fees", f ? naira(f.total) : "—", f && admitted ? <Pil key="d" kind={stateKind(f.status)}>{f.status.replace("_", " ").toLowerCase()}</Pil> : <Pil key="d" kind="grey">After acceptance</Pil>],
          ]} />
        </PBody>
      </Panel>
      {admitted && f ? (
        <Panel title="School fees">
          <PBody>
            <KvGrid pairs={[
              ["Category", `${feeCategoryLabel(f.category)} · ${f.indigene ? `${rule.indigene_state} indigene` : "non-indigene"}`],
              ["School fee", naira(f.total)], ["Paid", naira(f.paid)], ["Outstanding", naira(f.outstanding)],
              [`First semester (${Number(f.first_percent)}%)`, `${naira(f.first_amount)}${f.first_paid ? " · paid" : ""}`],
              [`Second semester (${100 - Number(f.first_percent)}%)`, `${naira(f.second_amount)}${f.second_paid ? " · paid" : ""}`],
            ]} />
            {!me.accepted_at && me.state === "ADMITTED" ? <Note kind="info" title="Acceptance first">Pay the acceptance fee (Admission tab); school fees follow it.</Note>
              : screeningFirst ? <Note kind="info" title="Screening first">School fees open once you are cleared at screening.</Note>
              : f.status !== "PAID" ? (
                <div className="row mt-3" style={{ flexWrap: "wrap", gap: "var(--s-3)" }}>
                  {!f.first_paid ? <PayBox kind="SCHOOL_FIRST" amount={Number(f.first_amount)} me={me} reload={reload} label="Pay first semester" /> : null}
                  {f.first_paid && !f.second_paid ? <PayBox kind="SCHOOL_SECOND" amount={Number(f.second_amount)} me={me} reload={reload} label="Pay second semester" /> : null}
                  {f.allow_full && Number(f.paid) === 0 ? <PayBox kind="SCHOOL_FULL" amount={Number(f.total)} me={me} reload={reload} label="Pay in full" /> : null}
                </div>
              ) : null}
            {me.accepted_at ? <div className="row mt-2"><LinkBtn kind="ghost" href="/jupeb/pdf/invoice">School fees invoice</LinkBtn></div> : null}
          </PBody>
        </Panel>
      ) : null}
      <Panel title="Payment history">
        <PBody>
          <DTable noPrint pageSize={0} cols={["Fee", "Reference", "Amount|num", "Generated", "Confirmed", "Receipt|mid"]} rows={me.references.map((x: FeeRef) => [
            FEE_KIND[x.kind] ?? x.kind, <span key="r" className="tnum">{x.reference}</span>, naira(x.amount), day(x.created_at),
            x.confirmed_at ? `${day(x.confirmed_at)}${x.channel ? ` · ${x.channel}` : ""}` : <Pil key="p" kind="grey">{new Date(x.expires_at) < new Date() ? "Expired" : "Awaiting payment"}</Pil>,
            x.confirmed_at ? <a key="a" href={`/jupeb/pdf/receipt?ref=${encodeURIComponent(x.reference)}`} target="_blank" rel="noreferrer">Receipt</a> : "—",
          ])} />
        </PBody>
      </Panel>
    </div>
  );
}

function Subjects({ me, act }: { me: Candidate; act: Act }) {
  const offered = suiting(me.combinations, me.stream);
  const [busy, setBusy] = useState(false);
  const [choice, setChoice] = useState<string>(me.combination_id && offered.some((c) => c.id === me.combination_id) ? me.combination_id : "");
  const chosen = offered.find((c) => c.id === choice) ?? null;
  const open = me.state === "STUDENT" && !me.subjects_registered_at;
  const heldButGone = open && !!me.combination_id && !offered.some((c) => c.id === me.combination_id);
  const rows = me.registered.length ? me.registered.map((r) => [r.code, r.title])
    : chosen ? [[chosen.subject1_code, chosen.subject1], [chosen.subject2_code, chosen.subject2], [chosen.subject3_code, chosen.subject3]]
    : me.subjects.map((s) => [s.code, s.title]);
  return (
    <Panel title="Subject registration" right={me.subjects_registered_at ? <Pil kind="ok">Registered {day(me.subjects_registered_at)}</Pil> : null}>
      <PBody>
        <KvGrid pairs={[["Programme", streamLabel(me.stream)], ["Combination", me.combination_code ?? "Not yet chosen"], ["Class", me.class_name ?? "Not yet placed"], ["JUPEB examination number", me.exam_no ?? "Not yet assigned"]]} />
        {heldButGone ? <Note kind="bad" title={`${me.combination_code} is no longer offered`}>The University no longer offers the combination you chose on your application. Choose another to register.</Note> : null}
        {open ? (
          <Field id="s-comb" label={`Your subject combination (${streamLabel(me.stream)})`} hint={offered.length ? "The combination you chose on your application is selected; you may choose another until you register." : "No combination is offered for your programme yet; the JUPEB Office will add them."}>
            <select id="s-comb" className="ctl" value={choice} onChange={(e) => setChoice(e.target.value)} disabled={!offered.length}>
              <option value="">— Choose a combination —</option>
              {offered.map((c) => <option key={c.id} value={c.id}>{c.code} — {c.subject1}, {c.subject2}, {c.subject3}</option>)}
            </select>
          </Field>
        ) : null}
        {rows.length ? <DTable noPrint pageSize={0} cols={["Code", "Subject"]} rows={rows} /> : null}
        {open ? (
          <div className="row mt-3"><Btn kind="primary" disabled={busy || !choice} onClick={() => { setBusy(true); void act("/api/v1/jupeb/me/register-subjects", "POST", { combination: choice }).finally(() => setBusy(false)); }}>{busy ? "Registering…" : "Register these three subjects"}</Btn></div>
        ) : me.state === "ADMITTED" ? <p className="hint mt-2">You register your subjects once your school fee activates your studentship.</p> : null}
        {me.subjects_registered_at ? <div className="row mt-3"><LinkBtn kind="ghost" href="/jupeb/pdf/slip">Download registration slip</LinkBtn></div> : null}
      </PBody>
    </Panel>
  );
}

interface AttendanceRow { session: string; semester: number; code: string; title: string; total: number; present: number; absent: number; late: number; excused: number; rate: number | null; min_percent: number | null; verdict: string | null; at_risk: boolean; counted: number }

/** V344: below the minimum (or close to it) in a subject — said where the student will see it */
function AttendanceWarning({ me, onOpen }: { me: Candidate; onOpen: () => void }) {
  const below = (me.attendanceStanding ?? []).filter((r) => r.verdict === "NOT_ELIGIBLE");
  const risk = (me.attendanceStanding ?? []).filter((r) => r.at_risk);
  const list = (rows: typeof below) => rows.map((r) => `${r.title} ${r.rate == null ? "—" : `${Number(r.rate)}%`}`).join(", ");
  if (below.length) {
    return <Note kind="bad" title={`Your attendance is below the minimum of ${Number(below[0].min_percent)}%`} action={<Btn kind="ghost" onClick={onOpen}>See your attendance</Btn>}>
      {`In ${list(below)}. Attend every class from now on; if you were absent for a good reason, see the JUPEB Office (an excused absence does not count against you).`}</Note>;
  }
  if (risk.length) {
    return <Note kind="info" title="Your attendance is close to the minimum" action={<Btn kind="ghost" onClick={onOpen}>See your attendance</Btn>}>
      {`In ${list(risk)} (minimum ${Number(risk[0].min_percent)}%). Missing more classes would take you below it.`}</Note>;
  }
  return null;
}
interface AttendanceMine { subjects: AttendanceRow[]; recent: { held_on: string; session: string; semester: number; code: string; title: string; status: string; marked_time: string | null; remarks: string | null }[] }

function Attendance() {
  const [data, setData] = useState<AttendanceMine | null>(null);
  const [subject, setSubject] = useState("");
  const [semester, setSemester] = useState("");
  useEffect(() => {
    let live = true;
    void jcall<AttendanceMine>("/api/v1/jupeb/me/attendance").then((r) => { if (live && r.ok) setData(r.data); });
    return () => { live = false; };
  }, []);
  if (!data) return <Note kind="info" title="Loading your attendance…">One moment.</Note>;
  const rows = data.subjects.filter((r) => (!subject || r.code === subject) && (!semester || String(r.semester) === semester));
  const sum = rows.reduce((a, r) => ({ total: a.total + r.total, present: a.present + r.present, absent: a.absent + r.absent, late: a.late + r.late, excused: a.excused + r.excused }), { total: 0, present: 0, absent: 0, late: 0, excused: 0 });
  const rate = sum.total - sum.excused > 0 ? Math.round((10000 * (sum.present + sum.late)) / (sum.total - sum.excused)) / 100 : null;
  return (
    <div className="stack">
      <Panel title="Attendance summary">
        <PBody>
          <div className="row" style={{ gap: "var(--s-2)", marginBottom: "var(--s-2)", flexWrap: "wrap" }}>
            <select className="ctl" style={{ width: 220 }} aria-label="Subject" value={subject} onChange={(e) => setSubject(e.target.value)}><option value="">All subjects</option>{[...new Set(data.subjects.map((r) => r.code))].map((c) => <option key={c} value={c}>{data.subjects.find((r) => r.code === c)?.title}</option>)}</select>
            <select className="ctl" style={{ width: 180 }} aria-label="Semester" value={semester} onChange={(e) => setSemester(e.target.value)}><option value="">Both semesters</option><option value="1">First semester</option><option value="2">Second semester</option></select>
          </div>
          <KvGrid cls="grid--3" pairs={[["Total classes", sum.total], ["Present", sum.present], ["Late", sum.late], ["Absent", sum.absent], ["Excused", sum.excused], ["Attendance rate", rate == null ? "—" : `${rate}%`]]} />
          <DTable noPrint pageSize={0} cols={["Subject", "Semester|num", "Classes|num", "Present|num", "Late|num", "Absent|num", "Excused|num", "Rate|num", "Standing"]} rows={rows.map((r) => [
            r.title, r.semester, r.total, r.present, r.late, r.absent, r.excused, r.rate == null ? "—" : `${Number(r.rate)}%`,
            r.verdict === "NOT_ELIGIBLE" ? <Pil key="v" kind="bad">Below the minimum</Pil> : r.at_risk ? <Pil key="v" kind="warn">Close to the minimum</Pil>
              : r.verdict === "ELIGIBLE" ? <Pil key="v" kind="ok">Meets the minimum</Pil> : r.verdict === "REQUIRES_REVIEW" ? <Pil key="v" kind="grey">All excused</Pil> : <span key="v" className="sub2">—</span>,
          ])} />
        </PBody>
      </Panel>
      <Panel title="Recent classes">
        <PBody><DTable pageSize={20} cols={["Date", "Subject", "Status", "Time", "Remarks"]} rows={data.recent.filter((r) => !subject || r.code === subject).map((r) => [day(r.held_on), r.title,
          <Pil key="s" kind={r.status === "PRESENT" ? "ok" : r.status === "ABSENT" ? "bad" : r.status === "LATE" ? "warn" : "grey"}>{r.status.toLowerCase()}</Pil>, r.marked_time ?? "—", r.remarks ?? "—"])} /></PBody>
      </Panel>
    </div>
  );
}

function Results({ me }: { me: Candidate }) {
  if (!me.resultsPublished) return <Note kind="info" title="Results not yet published">Your JUPEB results appear here once the JUPEB Office publishes them. You will be told by email.</Note>;
  const gp = me.gradePoint;
  return (
    <Panel title="JUPEB results" right={<LinkBtn kind="ghost" href="/jupeb/pdf/result">Statement of result</LinkBtn>}>
      <PBody>
        <KvGrid pairs={[["Examination number", me.exam_no ?? "—"], ["Combination", me.combination_code ?? "—"], ["Grade point", gp ? `${Number(gp.total)}/${gp.out_of}` : "—"], ["Session", me.session]]} />
        <DTable noPrint pageSize={0} cols={["Subject", "Grade|mid", "Grade point|num"]} rows={me.registered.map((r) => [r.title, r.grade ?? "—", r.points == null ? "—" : Number(r.points).toFixed(1)])} />
        {gp && gp.bonus ? <p className="hint">One point added: all three subjects are passed.</p> : null}
      </PBody>
    </Panel>
  );
}

function DocumentCentre({ me }: { me: Candidate }) {
  const sc = me.statusChecking;
  const items: [string, string | null, string][] = [
    ["Application acknowledgement", me.submitted_at ? "/jupeb/pdf/acknowledgement" : null, "after submission"],
    ["Application summary", "/jupeb/pdf/summary", ""],
    ["Admission status slip", sc.may_check ? "/jupeb/pdf/status" : null, "after checking your status"],
    ["Admission letter", sc.may_check && sc.status === "ADMITTED" ? "/jupeb/pdf/letter" : null, "if admitted"],
    ["Acceptance letter", me.accepted_at ? "/jupeb/pdf/acceptance" : null, "after the acceptance fee"],
    ["School fees invoice", me.accepted_at ? "/jupeb/pdf/invoice" : null, "after acceptance"],
    ["Registration slip", me.subjects_registered_at ? "/jupeb/pdf/slip" : null, "after subject registration"],
    ["Statement of result", me.resultsPublished && me.registered.length ? "/jupeb/pdf/result" : null, "once results are published"],
  ];
  return (
    <div className="stack">
      <Panel title="Your JUPEB documents">
        <PBody>
          <DTable noPrint pageSize={0} cols={["Document", "Available"]} rows={items.map(([label, href, later]) => [label,
            href ? <a key="a" href={href} target="_blank" rel="noreferrer">Download</a> : <span key="a" className="sub2">{later ? `Available ${later}` : "—"}</span>])} />
        </PBody>
      </Panel>
      <Panel title="Receipts">
        <PBody>
          <DTable noPrint pageSize={0} cols={["Fee", "Reference", "Amount|num", "Receipt|mid"]} rows={me.references.filter((x) => x.confirmed_at).map((x) => [FEE_KIND[x.kind] ?? x.kind, x.reference, naira(x.amount),
            <a key="r" href={`/jupeb/pdf/receipt?ref=${encodeURIComponent(x.reference)}`} target="_blank" rel="noreferrer">Receipt</a>])} />
        </PBody>
      </Panel>
      <Panel title="Your uploaded documents">
        <PBody>
          <DTable noPrint pageSize={0} cols={["Document", "File", "Status"]} rows={me.documents.filter((d) => d.filename).map((d) => [d.label,
            <a key="f" href={docUrl(d)} target="_blank" rel="noreferrer">{d.filename}</a>, d.status ? <Pil key="s" kind={stateKind(d.status)}>{DOC_STATUS[d.status] ?? d.status}</Pil> : "—"])} />
        </PBody>
      </Panel>
    </div>
  );
}

/** V343: after submission, a change is asked for — never made — and the JUPEB Office decides it */
function Requests({ me, act }: { me: Candidate; act: Act }) {
  const st = me.state;
  const open = me.requests.find((r) => r.state === "PENDING") ?? null;
  const kinds = [
    ...(st !== "COMPLETED" && st !== "WITHDRAWN" ? ["WITHDRAW"] : []),
    ...(st === "ADMITTED" && me.accepted_at ? ["DEFER"] : []),
    ...(!me.exam_no && ["SUBMITTED", "UNDER_REVIEW", "ELIGIBLE", "PENDING", "ADMITTED", "STUDENT", "DEFERRED"].includes(st) ? ["CHANGE_COMBINATION"] : []),
    ...(!me.fees?.frozen && ["SUBMITTED", "UNDER_REVIEW", "ELIGIBLE", "PENDING", "ADMITTED", "DEFERRED"].includes(st) ? ["CHANGE_PROGRAMME"] : []),
  ];
  const [kind, setKind] = useState<string>(kinds.includes("CHANGE_COMBINATION") ? "CHANGE_COMBINATION" : kinds[0] ?? "");
  const [stream, setStream] = useState<string>(me.stream === "SCIENCE" ? "NON_SCIENCE" : "SCIENCE");
  const [comb, setComb] = useState("");
  const [toSession, setToSession] = useState(laterSessions(me.session)[0] ?? "");
  const [reason, setReason] = useState("");
  const [sure, setSure] = useState(false);
  const [busy, setBusy] = useState(false);
  const list = kind === "CHANGE_PROGRAMME" ? suiting(me.combinations, stream) : suiting(me.combinations, me.stream).filter((c) => c.id !== me.combination_id);
  async function send() {
    setBusy(true);
    try {
      const r = await act("/api/v1/jupeb/me/requests", "POST", {
        kind, stream: kind === "CHANGE_PROGRAMME" ? stream : null, combination: kind === "CHANGE_COMBINATION" || kind === "CHANGE_PROGRAMME" ? comb || null : null,
        toSession: kind === "DEFER" ? toSession : null, reason: reason.trim(),
      });
      if (r) { notify("Your request is with the JUPEB Office. You will be told of its decision."); setReason(""); setComb(""); setSure(false); }
    } finally { setBusy(false); }
  }
  return (
    <div className="stack">
      {open ? (
        <Note kind="info" title="Your request is with the JUPEB Office" action={<Btn kind="ghost" onClick={() => void act(`/api/v1/jupeb/me/requests/${open.id}/cancel`)}>Cancel the request</Btn>}>
          {`You asked to ${open.words}, on ${day(open.requested_at)}. One request is open at a time.`}
        </Note>
      ) : kinds.length ? (
        <Panel title="Ask the JUPEB Office for a change">
          <PBody>
            <p className="sub2">Your submitted application is changed only by the JUPEB Office. Say what you need and why; you will be told of the decision by email and here.</p>
            <Field id="rq-kind" label="What do you need?">
              <select id="rq-kind" className="ctl" style={{ maxWidth: 420 }} value={kind} onChange={(e) => { setKind(e.target.value); setComb(""); setSure(false); }}>
                {kinds.map((k) => <option key={k} value={k}>{CHANGE_KIND[k]}</option>)}
              </select>
            </Field>
            {kind === "CHANGE_PROGRAMME" ? (
              <Field id="rq-stream" label="New programme">
                <select id="rq-stream" className="ctl" style={{ maxWidth: 320 }} value={stream} onChange={(e) => { setStream(e.target.value); setComb(""); }}>
                  {me.stream !== "SCIENCE" ? <option value="SCIENCE">Science</option> : null}{me.stream === "SCIENCE" ? <option value="NON_SCIENCE">Non-Science</option> : null}
                </select>
              </Field>
            ) : null}
            {kind === "CHANGE_COMBINATION" || kind === "CHANGE_PROGRAMME" ? <CombinationPicker id="rq-comb" list={list} value={comb} onChange={setComb} /> : null}
            {kind === "DEFER" ? (
              <Field id="rq-session" label="Defer to" hint="Your acceptance and payments stand; school fees are paid in that session.">
                <select id="rq-session" className="ctl" style={{ maxWidth: 220 }} value={toSession} onChange={(e) => setToSession(e.target.value)}>
                  {laterSessions(me.session).map((x) => <option key={x}>{x}</option>)}
                </select>
              </Field>
            ) : null}
            {kind === "WITHDRAW" ? (
              <Note kind="bad" title="Withdrawing ends your application">Your record is kept, but you will not continue in the JUPEB programme. Any refund is the Bursary&rsquo;s decision under its own rules.</Note>
            ) : null}
            <Field id="rq-reason" label="Why?" required hint="At least ten characters"><textarea id="rq-reason" className="ctl" rows={3} maxLength={1000} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
            {kind === "WITHDRAW" ? <label className="row" style={{ gap: "var(--s-1)" }}><input type="checkbox" checked={sure} onChange={(e) => setSure(e.target.checked)} /> I understand and want to withdraw</label> : null}
            <div className="row mt-2"><Btn kind="primary" disabled={busy || reason.trim().length < 10 || ((kind === "CHANGE_COMBINATION" || kind === "CHANGE_PROGRAMME") && list.length > 0 && !comb) || (kind === "WITHDRAW" && !sure)}
              onClick={() => void send()}>{busy ? "Sending…" : "Send the request"}</Btn></div>
          </PBody>
        </Panel>
      ) : <Note kind="info" title="No change can be asked for now">Your record as it stands takes no change request.</Note>}
      <Panel title="Your requests">
        <PBody>
          <DTable noPrint pageSize={0} cols={["Asked", "Request", "Why", "Decision", "Note"]} rows={me.requests.map((r) => [
            day(r.requested_at), r.words, r.reason,
            <Pil key="s" kind={(REQUEST_STATE[r.state] ?? [r.state, "grey"])[1]}>{(REQUEST_STATE[r.state] ?? [r.state])[0]}</Pil>,
            r.decision_note ? `${r.decision_note}${r.decided_at ? ` · ${day(r.decided_at)}` : ""}` : r.decided_at ? day(r.decided_at) : "—",
          ])} />
        </PBody>
      </Panel>
    </div>
  );
}

function SupportTab() {
  const [data, setData] = useState<Support | null>(null);
  const [open, setOpen] = useState<TicketDetail | null>(null);
  const [f, setF] = useState<Record<string, string>>({ issue: "Application" });
  const [reply, setReply] = useState("");
  const [busy, setBusy] = useState(false);
  const [tick, setTick] = useState(0);
  useEffect(() => {
    let live = true;
    void jcall<Support>("/api/v1/jupeb/me/support").then((r) => { if (live && r.ok) setData(r.data); });
    return () => { live = false; };
  }, [tick]);
  const options: string[] = (() => {
    try { const fields = JSON.parse(data?.categories[0]?.fields ?? "[]") as { key: string; options?: string[] }[]; return fields.find((x) => x.key === "jupeb_issue")?.options ?? []; } catch { return []; }
  })();
  async function raise() {
    if (!f.subject?.trim() || !f.description?.trim()) { notifyProblem({ status: 400, title: "Give the ticket a subject and describe the problem." }); return; }
    setBusy(true);
    try {
      const r = await jcall<{ number: string }>("/api/v1/jupeb/me/support", "POST", { category: "JUPEB", subject: f.subject, description: f.description, details: { jupeb_issue: f.issue, payment_reference: f.reference ?? "" } });
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(`Ticket ${r.data.number} raised. The JUPEB support desk will answer by email and here.`);
      setF({ issue: "Application" });
      setTick((t) => t + 1);
    } finally { setBusy(false); }
  }
  async function view(id: string) { const r = await jcall<TicketDetail>(`/api/v1/jupeb/me/support/${id}`); if (r.ok) setOpen(r.data); else notifyProblem(r.problem); }
  async function say() {
    if (!open || !reply.trim()) return;
    const r = await jcall<TicketDetail>(`/api/v1/jupeb/me/support/${open.id}/comments`, "POST", { body: reply });
    if (r.ok) { setOpen(r.data); setReply(""); } else notifyProblem(r.problem);
  }
  return (
    <div className="grid grid--2">
      <Panel title="Raise a support ticket">
        <PBody>
          <Field id="t-issue" label="What it is about"><select id="t-issue" className="ctl" value={f.issue} onChange={(e) => setF({ ...f, issue: e.target.value })}>{options.map((o) => <option key={o}>{o}</option>)}</select></Field>
          <Field id="t-subject" label="Subject"><input id="t-subject" className="ctl" maxLength={200} value={f.subject ?? ""} onChange={(e) => setF({ ...f, subject: e.target.value })} /></Field>
          <Field id="t-ref" label="Payment reference, if a payment"><input id="t-ref" className="ctl" maxLength={60} value={f.reference ?? ""} onChange={(e) => setF({ ...f, reference: e.target.value })} /></Field>
          <Field id="t-desc" label="Describe the problem"><textarea id="t-desc" className="ctl" rows={4} maxLength={8000} value={f.description ?? ""} onChange={(e) => setF({ ...f, description: e.target.value })} /></Field>
          <Btn kind="primary" disabled={busy} onClick={() => void raise()}>{busy ? "Sending…" : "Raise ticket"}</Btn>
        </PBody>
      </Panel>
      <Panel title="Your tickets">
        <PBody>
          {open ? (
            <div className="stack">
              <div className="row"><b>{open.number}</b><Pil kind={stateKind(open.status)}>{open.status.replace(/_/g, " ").toLowerCase()}</Pil><span className="grow" /><Btn kind="ghost" onClick={() => setOpen(null)}>Back</Btn></div>
              <div className="b600">{open.subject}</div><p style={{ whiteSpace: "pre-line" }}>{open.description}</p>
              {open.comments.map((c) => <div key={c.id} className="card"><div className="card__body"><div className="sub2">{c.author_name} · {when(c.created_at)}</div><div style={{ whiteSpace: "pre-line" }}>{c.body}</div></div></div>)}
              {open.status !== "CLOSED" ? <><textarea className="ctl" rows={3} aria-label="Reply" value={reply} onChange={(e) => setReply(e.target.value)} /><Btn kind="secondary" onClick={() => void say()}>Reply</Btn></> : null}
            </div>
          ) : data && data.tickets.length ? (
            <DTable noPrint pageSize={0} cols={["Ticket", "Subject", "Status", "Updated"]} rows={data.tickets.map((t) => [
              <a key="n" href="#" onClick={(e) => { e.preventDefault(); void view(t.id); }}>{t.number}</a>, t.subject, t.status.replace(/_/g, " ").toLowerCase(), day(t.updated_at),
            ])} />
          ) : <p className="sub2">No tickets yet.</p>}
        </PBody>
      </Panel>
    </div>
  );
}

function Bare({ children }: { children: ReactNode }) {
  return <div style={{ maxWidth: 640, margin: "var(--s-6) auto", padding: "0 var(--s-4)", display: "grid", gap: "var(--s-3)" }}>{children}</div>;
}
