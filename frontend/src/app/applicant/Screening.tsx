"use client";

/** The online screening (V269, V273), page by page as the Registry's paper forms are bound: Form A (the Registrar's registration
 *  form), the Screening of Fresh Undergraduate Students (Sections A and B), Section C with the declaration, the Supplementary
 *  Biodata Form, the Student Data Capture Form, the documents, then the review and the submission. One answer per fact: a
 *  field asked on several pages is the same field everywhere. Nationality, state and local government are chosen from the
 *  University's lists; every page is checked before the next opens; the draft is saved at every step. */
import React, { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, Passport } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { BLOOD_GROUPS, DOC_WORD, MARITAL, RELIGIONS, STATE_WORD, ageOn, fieldProblem, parseTracker, whenAt, type FieldDef, type Institution, type OlevelRow, type RefState, type ScreeningView } from "@/lib/screening";
import { Eligibility } from "./Eligibility";
import { Tracker } from "./Admission";

const GRADES = ["A1", "B2", "B3", "C4", "C5", "C6", "D7", "E8", "F9"];
type StepId = "A" | "B" | "C" | "D" | "E" | "F" | "G";
const STEPS: { id: StepId; short: string; title: string; sub: string }[] = [
  { id: "A", short: "Form A", title: "Form A · Registration form", sub: "Office of the Registrar · to be completed by each new student before full registration" },
  { id: "B", short: "Screening A–B", title: "Screening of Fresh Undergraduate Students", sub: "Section A · Personal data — Section B · Academic record: institutions attended with dates and qualifications obtained" },
  { id: "C", short: "Section C", title: "Section C · Academic record — O'Level results with dates", sub: "Membership of associations · Declaration · Section D (for official use only)" },
  { id: "D", short: "Biodata", title: "Supplementary Biodata Form", sub: "To be completed and returned to Faculty, Department, Academic Office, Students Affairs Division and Security Unit" },
  { id: "E", short: "Data capture", title: "Student Data Capture Form", sub: "The department's record of the student" },
  { id: "F", short: "Documents", title: "Documents", sub: "The originals of your qualifications, your UTME result slip, your certificate of state of origin and your birth certificate or declaration of age — uploaded here, brought when called for" },
  { id: "G", short: "Review", title: "Review and submit", sub: "Every page read back to you, then the declaration" },
];
/** the fields each page asks for (the keys of the biodata catalogue); a key on several pages is one answer */
const PAGE_FIELDS: Record<StepId, string[]> = {
  A: ["nationality", "state_of_origin", "lga", "marital_status", "sponsor_address", "postal_address"],
  B: ["maiden_name", "date_of_birth", "home_address", "lga", "state_of_origin", "nationality", "religion", "marital_status", "working_experience", "sponsor_name", "sponsor_address"],
  C: [],
  D: ["state_of_origin", "lga", "nationality", "date_of_birth", "place_of_birth", "primary_school", "primary_fees_per_term", "secondary_school", "secondary_fees_per_term", "parent_profession", "parent_income", "guardian_name", "guardian_address", "guardian_mobile", "guardian_email"],
  E: ["preferred_name", "date_of_birth", "lga", "state_of_origin", "nationality", "marital_status", "blood_group", "children", "religion", "ethnic_group", "mobile", "alt_mobile", "personal_email", "bank_name", "bank_sort_code", "bank_account_no", "bank_location", "working_experience", "postal_address", "home_address", "sponsor_name", "sponsor_address", "extracurricular", "hobbies", "secondary_graduation_year", "secondary_school", "alevel_institution", "alevel_graduation_year"],
  F: [], G: [],
};
/** what each page insists on beyond the session's policy, as the paper form does */
const PAGE_REQUIRED: Record<StepId, string[]> = {
  A: ["nationality", "state_of_origin", "lga", "marital_status", "sponsor_address"],
  B: ["home_address", "religion", "sponsor_name", "sponsor_address", "date_of_birth"],
  C: [], D: ["guardian_name", "guardian_address", "guardian_mobile", "secondary_school"], E: ["mobile", "personal_email"], F: [], G: [],
};
const LABEL: Record<string, string> = {
  sponsor_address: "Address of sponsor (home)", home_address: "Address (permanent home)", preferred_name: "Nick / pet / alias names", ethnic_group: "Tribe", extracurricular: "Sports", bank_name: "Bankers",
  alt_mobile: "Back-up phone number", mobile: "Phone number", personal_email: "E-mail", guardian_name: "Parent or guardian — name", guardian_address: "Parent or guardian — address", guardian_mobile: "Parent or guardian — phone number", guardian_email: "Parent or guardian — email",
  place_of_birth: "Place of birth", children: "Number of children", date_of_birth: "Date of birth",
};
const TEXTAREA = new Set(["sponsor_address", "postal_address", "home_address", "working_experience", "guardian_address", "memberships", "hobbies"]);
const NUMERIC = new Set(["mobile", "alt_mobile", "guardian_mobile", "bank_account_no", "bank_sort_code", "children", "primary_fees_per_term", "secondary_fees_per_term", "parent_income", "secondary_graduation_year", "alevel_graduation_year"]);

export function Screening({ fallback }: { fallback?: React.ReactNode }) {
  const router = useRouter();
  const [v, setV] = useState<ScreeningView | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [answers, setAnswers] = useState<Record<string, string>>({});
  const [institutions, setInstitutions] = useState<Institution[]>([]);
  const [olevel, setOlevel] = useState<OlevelRow[]>([]);
  const [membership, setMembership] = useState("");
  const [dirty, setDirty] = useState(false);
  const [step, setStep] = useState<StepId>("A");
  const [visited, setVisited] = useState<Set<StepId>>(new Set(["A"]));
  const [tried, setTried] = useState(false);
  const [declaration, setDeclaration] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [tracker, setTracker] = useState<string | null>(null);
  const [states, setStates] = useState<RefState[]>([]);
  const [countries, setCountries] = useState<string[]>([]);

  const load = (j: ScreeningView) => {
    setV(j);
    const a: Record<string, string> = {}; for (const x of j.answers) a[x.field] = x.value;
    if (!a.date_of_birth && j.prefill.date_of_birth) a.date_of_birth = j.prefill.date_of_birth;
    if (!a.state_of_origin && j.prefill.state_of_origin) a.state_of_origin = j.prefill.state_of_origin;
    if (!a.lga && j.prefill.lga) a.lga = j.prefill.lga;
    if (!a.nationality) a.nationality = "Nigeria";
    if (!a.mobile && j.prefill.phone) a.mobile = j.prefill.phone;
    if (!a.personal_email && j.prefill.email) a.personal_email = j.prefill.email;
    setAnswers(a);
    setInstitutions(j.institutions.length ? j.institutions : [{ name: "", from_year: null, to_year: null, certificate: "", award_year: null }]);
    setOlevel(j.olevel);
    setMembership(j.form?.membership ?? "");
    setDirty(false);
  };
  useEffect(() => {
    let live = true;
    Promise.all([
      fetch("/api/bff/api/v1/applicant/me/screening", { cache: "no-store" }).then(async (r) => [r.ok, await r.json().catch(() => null)] as const),
      fetch("/api/bff/api/v1/applicant/me/admission", { cache: "no-store" }).then(async (r) => [r.ok, await r.json().catch(() => null)] as const),
      fetch("/api/bff/api/v1/ref/states").then(async (r) => [r.ok, await r.json().catch(() => null)] as const),
      fetch("/api/bff/api/v1/ref/countries").then(async (r) => [r.ok, await r.json().catch(() => null)] as const),
    ]).then(([[ok, j], [ok2, j2], [ok3, j3], [ok4, j4]]) => {
      if (!live) return;
      if (!ok) setProblem((j as Problem) ?? { status: 0, title: "Could not read the screening form." }); else load(j as ScreeningView);
      if (ok2 && j2) setTracker((j2 as { tracker: string }).tracker);
      if (ok3 && Array.isArray(j3)) setStates(j3 as RefState[]);
      if (ok4 && Array.isArray(j4)) setCountries(j4 as string[]);
    }).catch(() => { if (live) setProblem({ status: 0, title: "Could not read the screening form." }); });
    return () => { live = false; };
  }, []);

  async function call(path: string, method: "PUT" | "POST", body: unknown, label: string, key: string, quiet = false) {
    setBusy(key); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/applicant/me/screening${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(label) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const pr = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(pr); notifyProblem(pr); return false; }
      load(j as ScreeningView); if (!quiet) notify(label); return true;
    } finally { setBusy(null); }
  }
  const save = (quiet = false) => call("", "PUT", { answers, institutions, olevel, membership }, "Screening form saved", "save", quiet);
  const submit = async () => { const ok = await call("/submit", "POST", { declaration }, "Screening form submitted", "submit"); if (ok) { setConfirming(false); setStep("G"); router.refresh(); } };
  async function upload(kind: string, file: File) {
    setBusy(kind); setProblem(null);
    try {
      const buf = await file.arrayBuffer();
      let bin = ""; const bytes = new Uint8Array(buf); for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
      const r = await fetch("/api/bff/api/v1/applicant/me/documents", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Screening document uploaded: ${kind}`) }, body: JSON.stringify({ kind, filename: file.name, contentType: file.type, contentBase64: btoa(bin) }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const pr = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(pr); notifyProblem(pr); return; }
      notify(`${DOC_WORD[kind] ?? kind} uploaded`);
      const again = await fetch("/api/bff/api/v1/applicant/me/screening", { cache: "no-store" }); const jj = await again.json().catch(() => null); if (again.ok && jj) load(jj as ScreeningView);
    } finally { setBusy(null); }
  }

  const f = v?.form ?? null;
  const p = v?.prefill;
  const editable = !!f && (f.state === "DRAFT" || f.state === "RETURNED");
  const catalogue = useMemo(() => { const m: Record<string, FieldDef> = {}; for (const x of v?.fields ?? []) m[x.field] = x; return m; }, [v]);
  const required = useMemo(() => new Set<string>([...(v?.policy?.required_fields ?? []), ...Object.values(PAGE_REQUIRED).flat()]), [v]);
  const ctx = { states, countries, answers };
  const problemsOf = (keys: string[]) => {
    const out: Record<string, string> = {};
    for (const k of keys) {
      const val = (answers[k] ?? "").trim();
      if (!val && required.has(k)) out[k] = "Required";
      else { const pr = fieldProblem(k, val, ctx); if (pr) out[k] = pr; }
    }
    return out;
  };
  const stepProblems = (id: StepId): Record<string, string> => {
    const out = problemsOf(PAGE_FIELDS[id]);
    if (id === "C" && !olevel.some((r) => r.subject.trim() && r.grade)) out.OLEVEL = "At least one O'Level result";
    if (id === "B" && !institutions.some((i) => i.name.trim())) out.INSTITUTIONS = "At least one institution attended";
    if (id === "F") for (const k of v?.policy?.required_documents ?? []) if (!v?.documents.some((d) => d.kind === k && d.status !== "REJECTED")) out[k] = "Required";
    return out;
  };
  const set = (k: string, val: string) => {
    setAnswers((a) => { const n = { ...a, [k]: val }; if (k === "state_of_origin" && a.state_of_origin !== val) n.lga = ""; return n; });
    setDirty(true);
  };
  const idx = STEPS.findIndex((s) => s.id === step);
  const goTo = async (id: StepId) => {
    if (id !== step && STEPS.findIndex((s) => s.id === id) > idx) {
      setTried(true);
      if (editable && Object.keys(stepProblems(step)).length) { notifyProblem({ status: 422, title: "This page is not complete", detail: Object.values(stepProblems(step)).join(" · ") }); return; }
    }
    if (editable && dirty) { const ok = await save(true); if (!ok) return; }
    setTried(false); setStep(id); setVisited((s) => new Set([...s, id]));
    window.scrollTo({ top: 0, behavior: "smooth" });
  };

  if (problem && !v) return <ProblemNotice problem={problem} />;
  if (!v || !p) return <Panel title="Online screening"><PBody><div className="sub2">Reading…</div></PBody></Panel>;
  if (!v.required) return <>{fallback ?? <Note kind="info" title="No online screening is required for your session">Document clearance is at the Registry, in person.</Note>}</>;
  if (!f) return <Note kind="info" title="The screening opens when you have accepted your offer">Accept the offer and pay the acceptance fee; the screening form opens here at once.</Note>;

  const errs = tried ? stepProblems(step) : {};
  const lgasOf = (stateName: string) => { const st = states.find((s) => s.name.toLowerCase() === (stateName ?? "").toLowerCase()); return st ? (JSON.parse(st.lgas) as string[]) : []; };
  const label = (k: string) => LABEL[k] ?? catalogue[k]?.label ?? k;
  const F = (k: string, opts?: { full?: boolean; hint?: string }) => {
    const val = answers[k] ?? "";
    const id = `sf-${k}`;
    const err = errs[k];
    const req = required.has(k);
    let control: React.ReactNode;
    if (k === "nationality") control = <select id={id} className="ctl" disabled={!editable} value={val} onChange={(e) => set(k, e.target.value)}><option value="">Choose…</option>{(countries.length ? countries : ["Nigeria"]).map((c) => <option key={c} value={c}>{c}</option>)}</select>;
    else if (k === "state_of_origin") control = <select id={id} className="ctl" disabled={!editable} value={val} onChange={(e) => set(k, e.target.value)}><option value="">Choose a state…</option>{states.map((s) => <option key={s.code} value={s.name}>{s.name}</option>)}{val && !states.some((s) => s.name === val) ? <option value={val}>{val} (as recorded)</option> : null}</select>;
    else if (k === "lga") { const ls = lgasOf(answers.state_of_origin ?? ""); control = <select id={id} className="ctl" value={val} disabled={!editable || !answers.state_of_origin} onChange={(e) => set(k, e.target.value)}><option value="">{answers.state_of_origin ? "Choose a local government…" : "Choose the state first"}</option>{ls.map((l) => <option key={l} value={l}>{l}</option>)}{val && !ls.some((l) => l.toLowerCase() === val.toLowerCase()) ? <option value={val}>{val} (as recorded)</option> : null}</select>; }
    else if (k === "marital_status") control = <select id={id} className="ctl" disabled={!editable} value={val} onChange={(e) => set(k, e.target.value)}><option value="">Choose…</option>{MARITAL.map((x) => <option key={x}>{x}</option>)}</select>;
    else if (k === "religion") control = <select id={id} className="ctl" disabled={!editable} value={val} onChange={(e) => set(k, e.target.value)}><option value="">Choose…</option>{RELIGIONS.map((x) => <option key={x}>{x}</option>)}</select>;
    else if (k === "blood_group") control = <select id={id} className="ctl" disabled={!editable} value={val} onChange={(e) => set(k, e.target.value)}><option value="">Choose…</option>{BLOOD_GROUPS.map((x) => <option key={x}>{x}</option>)}</select>;
    else if (k === "date_of_birth") control = <input id={id} type="date" className="ctl tnum" value={val} disabled={!editable || !!p.date_of_birth} onChange={(e) => set(k, e.target.value)} />;
    else if (TEXTAREA.has(k)) control = <textarea id={id} className="ctl" rows={2} disabled={!editable} value={val} onChange={(e) => set(k, e.target.value)} />;
    else control = <input id={id} className="ctl" disabled={!editable} value={val} onChange={(e) => set(k, e.target.value)} autoComplete="off" inputMode={NUMERIC.has(k) ? "numeric" : undefined} />;
    return <Field key={k} id={id} label={label(k)} hint={opts?.hint ?? (k === "date_of_birth" && p.date_of_birth ? "As JAMB sent it" : catalogue[k]?.hint ?? undefined)} required={req} error={err} full={opts?.full ?? TEXTAREA.has(k)}>{control}</Field>;
  };
  const record = (pairs: [string, React.ReactNode][]) => <KvGrid cls="grid--4" pairs={pairs} />;
  const dob = answers.date_of_birth || p.date_of_birth || null;
  const age = ageOn(dob);
  const sexWord = p.sex === "M" ? "Male" : p.sex === "F" ? "Female" : p.sex ?? "—";
  const facultyGroup = (() => { const fac = (p.faculty ?? "").toLowerCase(); if (/law/.test(fac)) return "B · Law"; if (/art/.test(fac)) return "A · Arts"; if (/social/.test(fac)) return "B · Social Sciences"; if (/management|admin/.test(fac)) return "B · Management Sciences"; if (/educ/.test(fac)) return "C · Education"; if (/health|medic|clinical|pharm|basic/.test(fac)) return "C · College of Health Sciences"; if (/scien|computing|engineer|agric|environ|architec/.test(fac)) return "C · Sciences"; return p.faculty ?? "—"; })();
  // the passport photograph is JAMB's (V274): never asked for here
  const docKinds = [...new Set([...(v.policy?.required_documents ?? []), ...Object.keys(DOC_WORD).filter((k) => !(v.policy?.required_documents ?? []).includes(k))])].filter((k) => k !== "PASSPORT");
  const docOf = (kind: string) => v.documents.find((d) => d.kind === kind && d.status !== "REJECTED") ?? v.documents.find((d) => d.kind === kind);
  const photo = <Passport w={72} h={90} radius={6} src={p.jamb_passport ?? null} alt="Your passport photograph, as JAMB sent it" />;
  const uploadCell = (k: string) => (editable || !docOf(k)) ? <label key="u" className="btn btn--secondary btn--sm" style={{ cursor: "pointer", margin: 0 }}>{busy === k ? "Uploading…" : docOf(k) ? "Replace" : "Upload"}<input type="file" accept=".pdf,.jpg,.jpeg,.png,application/pdf,image/jpeg,image/png" style={{ display: "none" }} disabled={busy !== null || !editable} onChange={(e) => { const file = e.target.files?.[0]; if (file) void upload(k, file); e.target.value = ""; }} /></label> : <span key="u" />;
  const numCell = (val: number | null | undefined, onChange: (n: number | null) => void, aria: string) => <input className="ctl tnum" style={{ width: 90 }} value={val ?? ""} disabled={!editable} onChange={(e) => onChange(e.target.value ? Number(e.target.value) : null)} aria-label={aria} inputMode="numeric" />;
  const setInst = (i: number, patch: Partial<Institution>) => { const c = [...institutions]; c[i] = { ...c[i], ...patch }; setInstitutions(c); setDirty(true); };
  const setOl = (i: number, patch: Partial<OlevelRow>) => { const c = [...olevel]; c[i] = { ...c[i], ...patch }; setOlevel(c); setDirty(true); };

  return (
    <>
      <Panel title={`Screening of fresh undergraduate students · ${f.screening_no}`} right={<Pil kind={STATE_WORD[f.state][1]}>{STATE_WORD[f.state][0]}</Pil>}>
        <PBody>
          <div className="sub2">Every fresh undergraduate must undergo screening by the Screening Committee before registration as a student. The paper forms are here page by page; what the University already holds is shown first, the rest is completed by you. A question asked on more than one page is answered once.{v.policy?.instructions ? ` ${v.policy.instructions}` : ""}</div>
          {tracker ? <div className="mt-2"><Tracker steps={parseTracker(tracker)} compact /></div> : null}
          <div className="row row--tight mt-2" style={{ flexWrap: "wrap", gap: 6 }} role="tablist" aria-label="Pages of the screening form">
            {STEPS.map((s, i) => { const cur = s.id === step; const can = visited.has(s.id) || i <= idx || !editable; return (
              <button key={s.id} type="button" role="tab" aria-selected={cur} className={`btn btn--sm ${cur ? "btn--primary" : i < idx ? "btn--secondary" : "btn--ghost"}`} disabled={!can} onClick={() => void goTo(s.id)}>{i + 1}. {s.short}</button>
            ); })}
          </div>
        </PBody>
      </Panel>
      {problem ? <ProblemNotice problem={problem} /> : null}

      {f.state === "RETURNED" ? <Note kind="bad" title="Returned for correction">{f.returned_note} — correct it and submit again from the Review page.</Note> : null}
      {f.state === "SUBMITTED" || f.state === "UNDER_REVIEW" ? <Note kind="info" title={`Submitted ${whenAt(f.submitted_at)} · version ${f.version}`}>Your form is with the screening officers. It is read-only now; you are told the outcome here and by email.</Note> : null}
      {f.state === "SUCCESSFUL" ? <Note kind="ok" title="Screening result: you have been successfully screened" action={<LinkBtn kind="primary" href="/applicant/admission">Next step</LinkBtn>}>You can go ahead and pay school fees and commence registration using your admission number. Decided {whenAt(f.decided_at)}{f.decided_office ? ` · ${f.decided_office}` : ""}.{f.remarks ? ` Remarks: ${f.remarks}` : ""}</Note> : null}
      {f.state === "UNSUCCESSFUL" ? (
        <>
          <Note kind="bad" title={`Screening outcome: your screening for ${p.programme} was unsuccessful`}>
            <span className="blk"><b>Reason:</b> {f.decision_reason}</span>{f.remarks ? <span className="blk"><b>Officer&rsquo;s remarks:</b> {f.remarks}</span> : null}
            <span className="blk">You may apply for a change of programme where you are eligible. Your acceptance fee, already paid, remains valid and is not paid again; an approved change takes you straight to school fees.</span>
          </Note>
          {v.changes.some((c) => c.state === "APPROVED") ? (
            <Note kind="ok" title="Programme change approved" action={<LinkBtn kind="primary" href="/applicant/admission">Next step: school fees</LinkBtn>}>
              {v.changes.filter((c) => c.state === "APPROVED").map((c) => <span key={c.id} className="blk">Previous programme: {c.from_programme} → New programme: <b>{c.to_programme}</b> · {whenAt(c.decided_at)}</span>)}
              <span className="blk">Your previous verified acceptance payment remains valid. Do not pay the acceptance fee again.</span>
            </Note>
          ) : <Eligibility />}
        </>
      ) : null}

      <Panel title={`${idx + 1} of ${STEPS.length} · ${STEPS[idx].title}`} right={<span className="sub2">{STEPS[idx].sub}</span>}>
        <PBody>
          {step === "A" ? (
            <>
              {record([["Pin no", <span key="p" className="tnum">{p.application_no}</span>], ["JAMB no", <span key="j" className="tnum">{p.jamb_reg_no}</span>], ["Session", p.session], ["Date paid", "On your acceptance receipt"],
                ["1. Surname", p.surname], ["2. Other names", p.other_names], ["3. Sex", sexWord], ["8. Course admitted into", p.programme], ["9. Faculty", p.faculty ?? "—"], ["Department", p.department ?? "—"]])}
              <div className="grid grid--3 rfgrid mt-2">{F("nationality", { hint: "4. Nationality" })}{F("state_of_origin", { hint: "5. State" })}{F("lga", { hint: "6. LGA — the list follows the state" })}{F("marital_status", { hint: "7. Marital status" })}{F("sponsor_address")}{F("postal_address")}</div>
              <div className="sub2 mt-2">Student&rsquo;s signature and date, and the registration officer&rsquo;s: your submission at the end of this form stands for your signature; the officer signs on the record when the form is decided.</div>
            </>
          ) : null}
          {step === "B" ? (
            <>
              <div className="row row--between">
                {record([["Pin no", <span key="p" className="tnum">{p.application_no}</span>], ["JAMB no", <span key="j" className="tnum">{p.jamb_reg_no}</span>], ["Faculty group (ticked as appropriate)", facultyGroup]])}
                <span title="Passport photograph, as JAMB sent it">{photo}</span>
              </div>
              <div className="sub2 mt-1">To be completed in triplicate: one copy to the Registrar (Academic Office), one to the Dean of Faculty, one to the Head of Department. You must bring to the screening, when called, the originals of your academic qualifications, the original UME result slip, the certificate of state of origin, the birth certificate or declaration of age, the marriage certificate or declaration and the change of name where applicable.</div>
              <div className="eyebrow mt-3 mb-1">Section A · Personal data</div>
              {record([["Surname", p.surname], ["Other names (in full)", p.other_names], ["Sex", sexWord], ["Age last birthday", age != null ? String(age) : "—"], ["Mode of admission", p.entry_mode.replace("_", " ")], ["Next of kin on the application", p.next_of_kin ?? "—"]])}
              <div className="grid grid--3 rfgrid mt-2">{F("maiden_name")}{F("date_of_birth")}{F("home_address", { hint: "Address" })}{F("lga")}{F("state_of_origin")}{F("nationality")}{F("religion")}{F("marital_status")}{F("working_experience", { hint: "Working experience, if any" })}{F("sponsor_name")}{F("sponsor_address")}</div>
              <div className="eyebrow mt-3 mb-1">Section B · Academic record — institutions attended with dates and qualifications obtained</div>
              {errs.INSTITUTIONS ? <div className="ink-red sub2 mb-1">{errs.INSTITUTIONS}</div> : null}
              <DTable pageSize={0} cols={["S/N|num", "Name of institution", "From|mid", "To|mid", "Certificate awarded", "Year of award|mid", "|num"]} rows={institutions.map((it, i) => [
                <span key="sn" className="tnum sub2">{i + 1}</span>,
                <input key="n" className="ctl" value={it.name} disabled={!editable} onChange={(e) => setInst(i, { name: e.target.value })} aria-label={`Institution ${i + 1}`} />,
                <span key="f">{numCell(it.from_year, (n) => setInst(i, { from_year: n }), "From year")}</span>,
                <span key="t">{numCell(it.to_year, (n) => setInst(i, { to_year: n }), "To year")}</span>,
                <input key="c" className="ctl" value={it.certificate ?? ""} disabled={!editable} onChange={(e) => setInst(i, { certificate: e.target.value })} aria-label="Certificate" placeholder="FSLC, SSCE, NCE…" />,
                <span key="y">{numCell(it.award_year, (n) => setInst(i, { award_year: n }), "Year of award")}</span>,
                editable ? <Btn key="x" kind="ghost" size="sm" onClick={() => { setInstitutions(institutions.filter((_, k) => k !== i)); setDirty(true); }}>Remove</Btn> : <span key="x" />,
              ])} />
              {editable ? <div className="mt-1"><Btn kind="ghost" size="sm" onClick={() => { setInstitutions([...institutions, { name: "", from_year: null, to_year: null, certificate: "", award_year: null }]); setDirty(true); }}>Add a row</Btn></div> : null}
            </>
          ) : null}
          {step === "C" ? (
            <>
              <div className="sub2 mb-1">The results below began as JAMB sent them to the University; confirm them, correct a grade or an examination number where the certificate differs, and add a second sitting where you have one. The Registry verifies every result with the examination body.</div>
              {errs.OLEVEL ? <div className="ink-red sub2 mb-1">{errs.OLEVEL}</div> : null}
              <DTable pageSize={0} cols={["S/N|num", "Exam type / body", "Subject", "Exam number", "Grade|mid", "Year of award|mid", "|num"]} rows={olevel.map((r, i) => [
                <span key="sn" className="tnum sub2">{i + 1}</span>,
                <select key="b" className="ctl" value={r.exam_body} disabled={!editable} onChange={(e) => setOl(i, { exam_body: e.target.value })} aria-label="Examination body">{["WAEC", "NECO", "NABTEB", "OTHER"].map((b) => <option key={b}>{b}</option>)}</select>,
                <input key="s" className="ctl" value={r.subject} disabled={!editable} onChange={(e) => setOl(i, { subject: e.target.value })} aria-label="Subject" />,
                <input key="n" className="ctl tnum" value={r.exam_number ?? ""} disabled={!editable} onChange={(e) => setOl(i, { exam_number: e.target.value })} aria-label="Examination number" />,
                <select key="g" className="ctl" value={r.grade} disabled={!editable} onChange={(e) => setOl(i, { grade: e.target.value })} aria-label="Grade">{GRADES.map((g) => <option key={g}>{g}</option>)}</select>,
                <span key="y">{numCell(r.exam_year, (n) => setOl(i, { exam_year: n }), "Year of award")}</span>,
                editable ? <Btn key="x" kind="ghost" size="sm" onClick={() => { setOlevel(olevel.filter((_, k) => k !== i)); setDirty(true); }}>Remove</Btn> : <span key="x" />,
              ])} />
              {editable ? <div className="mt-1"><Btn kind="ghost" size="sm" onClick={() => { setOlevel([...olevel, { exam_body: "WAEC", exam_number: olevel[olevel.length - 1]?.exam_number ?? "", exam_year: olevel[olevel.length - 1]?.exam_year ?? null, subject: "", grade: "C6" }]); setDirty(true); }}>Add a subject</Btn></div> : null}
              {v.jambOlevel.length ? <div className="sub2 mt-2">As JAMB sent it: {v.jambOlevel.map((x) => `${x.subject} ${x.grade}`).join(", ")}.</div> : null}
              <div className="mt-3"><Field id="sf-membership" label="Membership of any association, club, union, society etc." full><input id="sf-membership" className="ctl" value={membership} disabled={!editable} onChange={(e) => { setMembership(e.target.value); setDirty(true); }} /></Field></div>
              <Note kind="info" title="Declaration">I, <b>{p.other_names} {p.surname}</b>, hereby declare that the information given on this form is to the best of my knowledge correct, and that I am bound by the Ordinances, Statutes and Regulations of the University, and that if at any time it is discovered that any of the information provided is false or incorrect, I will be required to withdraw from the institution or be liable to prosecution or both. <span className="sub2">Signed by your submission on the Review page.</span></Note>
              <div className="eyebrow mt-3 mb-1">Section D · For official use only</div>
              {record([["1. Screening result", f.state === "SUCCESSFUL" ? "You have been successfully screened. You can go ahead and pay school fees and commence registration using your registration number." : f.state === "UNSUCCESSFUL" ? `Unsuccessful — ${f.decision_reason ?? ""}` : "Not yet decided"], ["2. Name and signature of chairman", f.decided_office ? `${f.decided_office} · on the record` : "—"], ["Date", f.decided_at ? whenAt(f.decided_at) : "—"], ["Stamp", f.decided_at ? "Recorded on the portal" : "—"]])}
            </>
          ) : null}
          {step === "D" ? (
            <>
              {record([["1. Surname", p.surname], ["2. Other names", p.other_names], ["7. Gender", sexWord], ["8. Department", p.department ?? "—"], ["9. Faculty", p.faculty ?? "—"], ["10. Matriculation (JAMB no until issued)", <span key="m" className="tnum">{p.jamb_reg_no}</span>]])}
              <div className="grid grid--3 rfgrid mt-2">{F("state_of_origin", { hint: "3. State of origin" })}{F("lga", { hint: "4. Local government area" })}{F("nationality", { hint: "5. Nationality" })}{F("date_of_birth", { hint: "6. Date of birth" })}{F("place_of_birth", { hint: "6. Place of birth" })}
                {F("primary_school", { hint: "11. Name of primary school attended" })}{F("primary_fees_per_term", { hint: "Fees paid per term, in naira" })}{F("secondary_school", { hint: "12. Name of secondary school attended" })}{F("secondary_fees_per_term", { hint: "Fees paid per term, in naira" })}
                {F("parent_profession", { hint: "13." })}{F("parent_income", { hint: "14. Estimated annual income, in naira" })}{F("guardian_name", { hint: "15. Name" })}{F("guardian_address", { hint: "15. Address" })}{F("guardian_mobile", { hint: "15. Phone no" })}{F("guardian_email", { hint: "15. Email" })}</div>
              <div className="sub2 mt-2">Declaration: I hereby declare that the information given above is to the best of my knowledge correct, and that I am bound by the Regulations of the University, and that if at any time it is discovered that any of the information provided is false or incorrect, I shall be summarily expelled from the University.</div>
            </>
          ) : null}
          {step === "E" ? (
            <>
              <div className="row row--between">
                {record([["JAMB reg. no", <span key="j" className="tnum">{p.jamb_reg_no}</span>], ["Matric no", "Issued after registration"], ["Surname · other names", `${p.surname} · ${p.other_names}`], ["Course of study", p.programme], ["Sex", sexWord], ["Level", "100"], ["Present age", age != null ? String(age) : "—"], ["Mode of entry", p.entry_mode.replace("_", " ")]])}
                <span title="Passport photograph, as JAMB sent it">{photo}</span>
              </div>
              <div className="grid grid--3 rfgrid mt-2">{F("preferred_name")}{F("date_of_birth")}{F("lga")}{F("state_of_origin")}{F("nationality")}{F("marital_status")}{F("blood_group")}{F("children")}{F("religion")}{F("ethnic_group")}
                {F("mobile")}{F("alt_mobile")}{F("personal_email")}{F("bank_name")}{F("bank_sort_code")}{F("bank_account_no")}{F("bank_location")}{F("working_experience", { hint: "Rank, place and duration" })}{F("postal_address")}{F("home_address", { hint: "Permanent home address (village)" })}
                {F("sponsor_name")}{F("sponsor_address")}{F("extracurricular")}{F("hobbies", { hint: "Hobbies / skills / handwork" })}{F("secondary_graduation_year")}{F("secondary_school")}
                {p.entry_mode === "DIRECT_ENTRY" ? <>{F("alevel_institution", { hint: "(For D.E. students only) name of C.O.E. / polytechnic / institution of A-Level / school attended" })}{F("alevel_graduation_year")}</> : null}</div>
            </>
          ) : null}
          {step === "F" ? (
            <>
              <div className="sub2">PDF, JPEG or PNG, at most 2 MB each. A document an officer rejected is replaced by uploading it again.</div>
              <DTable pageSize={0} cols={["Document", "Required|mid", "Uploaded", "Status|mid", "|num"]} rows={docKinds.map((k) => { const d = docOf(k); const req = (v.policy?.required_documents ?? []).includes(k); return [
                <span key="d"><b>{DOC_WORD[k] ?? k}</b>{errs[k] ? <div className="ink-red sub2">{errs[k]}</div> : null}</span>, req ? <Pil key="r" kind="warn">Required</Pil> : <span key="r" className="sub2">Optional</span>,
                <span key="u" className="sub2">{d ? <>{d.filename} · {Math.round(d.bytes / 1024)} KB · {whenAt(d.uploaded_at)}{d.review_note ? <div className="ink-red">{d.review_note}</div> : null}</> : "—"}</span>,
                d ? <Pil key="s" kind={d.status === "ACCEPTED" ? "ok" : d.status === "REJECTED" ? "bad" : "info"}>{d.status}</Pil> : <Pil key="s" kind="grey">NOT UPLOADED</Pil>, uploadCell(k),
              ]; })} />
            </>
          ) : null}
          {step === "G" ? (
            <>
              {v.missing.length && editable ? <Note kind="bad" title="Still required before submission">{v.missing.map((m) => m.label).join(" · ")}</Note> : editable ? <Note kind="ok" title="Every page is complete">Read it back, accept the declaration and submit.</Note> : null}
              {(["A", "B", "D", "E"] as StepId[]).map((id) => { const keys = [...new Set(PAGE_FIELDS[id])].filter((k) => (answers[k] ?? "").trim()); return keys.length ? <div key={id} className="mb-2"><div className="eyebrow mb-1">{STEPS.find((s) => s.id === id)?.title}</div><KvGrid cls="grid--3" pairs={keys.map((k) => [label(k), answers[k]] as [string, string])} /></div> : null; })}
              <div className="eyebrow mb-1">Institutions attended</div><div className="sub2 mb-2">{institutions.filter((i) => i.name.trim()).map((i) => `${i.name} (${i.from_year ?? "?"}–${i.to_year ?? "?"}, ${i.certificate || "—"} ${i.award_year ?? ""})`).join("; ") || "None"}</div>
              <div className="eyebrow mb-1">O&rsquo;Level results</div><div className="sub2 mb-2">{olevel.map((r) => `${r.subject} ${r.grade} (${r.exam_body}${r.exam_year ? ` ${r.exam_year}` : ""})`).join(", ") || "None"}</div>
              <div className="eyebrow mb-1">Documents</div><div className="sub2 mb-2">{v.documents.filter((d) => d.status !== "REJECTED").map((d) => DOC_WORD[d.kind] ?? d.kind).join(", ") || "None"}</div>
              {editable ? (
                <>
                  <Note kind="info" title="Declaration">I, <b>{p.other_names} {p.surname}</b>, hereby declare that the information given on this form is to the best of my knowledge correct, and that I am bound by the Ordinances, Statutes and Regulations of the University, and that if at any time it is discovered that any of the information provided is false or incorrect, I will be required to withdraw from the institution or be liable to prosecution or both.</Note>
                  <label className="row row--tight mt-2" style={{ gap: 8 }}><input type="checkbox" className="pchk" checked={declaration} onChange={(e) => setDeclaration(e.target.checked)} /> I accept the declaration above; my submission stands for my signature and today&rsquo;s date.</label>
                </>
              ) : null}
            </>
          ) : null}
          <div className="row row--between mt-3">
            <span className="row row--inline row--tight">{idx > 0 ? <Btn kind="ghost" onClick={() => void goTo(STEPS[idx - 1].id)}>Back</Btn> : null}{editable ? <Btn kind="secondary" disabled={busy !== null || !dirty} onClick={() => void save()}>{busy === "save" ? "Saving…" : dirty ? "Save draft" : "Saved"}</Btn> : null}</span>
            <span className="row row--inline row--tight">
              {idx < STEPS.length - 1 ? <Btn kind="primary" disabled={busy !== null} onClick={() => void goTo(STEPS[idx + 1].id)}>{editable ? "Save and continue" : "Next page"}</Btn>
                : editable ? <Btn kind="primary" disabled={busy !== null || !declaration || v.missing.length > 0} onClick={async () => { if (dirty) { const ok = await save(true); if (!ok) return; } setConfirming(true); }}>Submit the screening form</Btn> : null}
            </span>
          </div>
        </PBody>
      </Panel>

      {confirming ? (
        <Modal title="Submit your screening form" sub={`${f.screening_no} · read-only after submission until an officer returns it`} onClose={() => setConfirming(false)}
          foot={<><Btn kind="ghost" onClick={() => setConfirming(false)}>Back</Btn><span className="grow" /><Btn kind="primary" disabled={busy !== null} onClick={() => void submit()}>{busy === "submit" ? "Submitting…" : "Submit"}</Btn></>}>
          <p>The five pages, your O&rsquo;Level results and your documents go to the screening officers as they stand. You are told the outcome here and by email.</p>
        </Modal>
      ) : null}
    </>
  );
}
