"use client";
/**
 * V658: the public collaboration enquiry — eight steps (Step X of 8), only the essential fields required, conditional questions,
 * the remaining characters shown, an error summary linking each error to its field, the draft kept at a private link (saved and
 * resumed; files attached to it), a review with Edit on every section, the server's own check before submission, and the
 * confirmation with the reference. Nothing is pre-ticked; the declarations are given afresh each time.
 */
import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import Link from "next/link";
import { Btn, Note } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import {
  AGREEMENT_TYPES, ATTACHMENT_KINDS, COI, CONTACT_METHODS, CURRENCIES, FORMATS, FUNDING, HIGH_RISK, INTERNATIONAL_ASPECTS, JOINT_GRANT, LANGUAGES, ORG_TYPES,
  OWN_DD, PROPOSAL_KINDS, RESOURCES, SENSITIVE_KINDS, STEPS, YES_NO_NOT_SURE, bytes, countries, dateWords, fileProblem, fromDraft, payload, stepProblems, word, words,
  type Answers, type Limits, type Opt, type Problem,
} from "@/lib/partnerships";

export interface Options {
  settings: Limits & { public_open: boolean; acknowledge_days: number; draft_days: number; contact_email: string | null; contact_phone: string | null };
  groups: { code: string; label: string }[];
  categories: { code: string; grp: string; label: string }[];
  faculties: { code: string; name: string }[];
  departments: { code: string; name: string; faculty_code: string }[];
  privacyPublished: boolean;
}
interface Attachment { id: string; kind: string; filename: string; size_bytes: number }
interface Submitted { reference: string; received_at: string; email: string; statusPath: string }

const API = "/api/bff/api/v1/public/partnerships";

async function call<T>(method: "GET" | "POST" | "PUT" | "DELETE", path: string, body?: unknown): Promise<{ ok: true; data: T } | { ok: false; message: string; code?: string }> {
  try {
    const r = await fetch(`${API}${path}`, { method, cache: "no-store", headers: body === undefined ? undefined : { "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body) });
    const j = await r.json().catch(() => null);
    if (!r.ok) return { ok: false, message: (j && (j.detail || j.title)) || "That did not go through; try again.", code: j?.code };
    return { ok: true, data: j as T };
  } catch {
    return { ok: false, message: "The University's portal could not be reached; check your connection and try again." };
  }
}

function readDataUrl(file: File): Promise<string> {
  return new Promise((resolve, reject) => { const r = new FileReader(); r.onload = () => resolve(String(r.result)); r.onerror = () => reject(r.error); r.readAsDataURL(file); });
}

/** radios as a fieldset with its legend, keyboard-reachable, the error under them */
function Choice({ id, legend, value, options, onChange, error, required, hint }: { id: string; legend: ReactNode; value: string | undefined | null; options: Opt[];
  onChange: (v: string) => void; error?: string | null; required?: boolean; hint?: ReactNode }) {
  return (
    <fieldset className={`ptn-fs${error ? " is-error" : ""}`} id={id} tabIndex={-1} aria-describedby={error ? `${id}-err` : undefined}>
      <legend>{legend}{required ? <span className="req" aria-hidden="true"> *</span> : null}</legend>
      <div className="ptn-choices">
        {options.map(([k, label]) => (
          <label key={k} className="ptn-choice"><input type="radio" name={id} value={k} checked={value === k} onChange={() => onChange(k)} /> {label}</label>
        ))}
      </div>
      {hint && !error ? <span className="hint">{hint}</span> : null}
      {error ? <span className="ferr" id={`${id}-err`}>{error}</span> : null}
    </fieldset>
  );
}
function Many({ id, legend, value, options, onChange, error }: { id: string; legend: ReactNode; value: string[] | undefined; options: Opt[];
  onChange: (v: string[]) => void; error?: string | null }) {
  const v = value ?? [];
  return (
    <fieldset className={`ptn-fs${error ? " is-error" : ""}`} id={id} tabIndex={-1}>
      <legend>{legend}</legend>
      <div className="ptn-choices">
        {options.map(([k, label]) => (
          <label key={k} className="ptn-choice"><input type="checkbox" checked={v.includes(k)} onChange={(e) => onChange(e.target.checked ? [...v, k] : v.filter((x) => x !== k))} /> {label}</label>
        ))}
      </div>
      {error ? <span className="ferr">{error}</span> : null}
    </fieldset>
  );
}
function Count({ value, max }: { value: string | undefined; max: number }) {
  const left = max - (value ?? "").length;
  return <span className={`ptn-count${left < 0 ? " ink-red" : ""}`} aria-live="polite">{left >= 0 ? `${left.toLocaleString("en-GB")} characters left` : `${(-left).toLocaleString("en-GB")} characters over`}</span>;
}

export function CollaborationForm({ options }: { options: Options }) {
  const lim = options.settings;
  const [step, setStep] = useState(1);
  const [a, setA] = useState<Answers>({ hasContact: null, international: null, highRisk: {}, resourcesRequested: [], countries: [], internationalAspects: [],
    agreementTypes: [], sensitiveKinds: [] });
  const [token, setToken] = useState<string | null>(null);
  const [files, setFiles] = useState<Attachment[]>([]);
  const [problems, setProblems] = useState<Problem[]>([]);
  const [busy, setBusy] = useState<string | null>(null);
  const [message, setMessage] = useState<{ kind: "ok" | "bad" | "info"; text: string } | null>(null);
  const [done, setDone] = useState<Submitted | null>(null);
  const [fileKind, setFileKind] = useState("CONCEPT_NOTE");
  const [hp, setHp] = useState("");
  const summaryRef = useRef<HTMLDivElement>(null);
  const topRef = useRef<HTMLDivElement>(null);
  const countryList = useMemo(() => countries().map((c) => ({ value: c, label: c })), []);
  const set = (p: Partial<Answers>) => setA((x) => ({ ...x, ...p }));
  const err = (field: string) => problems.find((p) => p.field === field)?.message ?? null;

  // a draft resumed from its private link (#d=…); the link is kept out of the address bar's history and the server's logs
  useEffect(() => {
    const m = /#d=([A-Za-z0-9_-]{32,})/.exec(window.location.hash);
    if (!m) return;
    void (async () => {
      const r = await call<{ submitted: boolean; reference: string | null; answers: Record<string, unknown>; attachments: Attachment[] }>("GET", `/drafts/${m[1]}`);
      if (!r.ok) { setMessage({ kind: "bad", text: r.code === "PTN_NOT_FOUND" ? "That draft link no longer opens a draft (drafts are kept " + lim.draft_days + " days)." : r.message }); return; }
      if (r.data.submitted) { setMessage({ kind: "info", text: `This enquiry was submitted (${r.data.reference}); follow it from the link in its acknowledgement email.` }); return; }
      setToken(m[1]);
      setA(fromDraft(r.data.answers));
      setFiles(r.data.attachments);
      setMessage({ kind: "ok", text: "Your saved draft is open. The declarations are given again before submitting." });
    })();
  }, [lim.draft_days]);

  useEffect(() => { if (problems.length) summaryRef.current?.focus(); }, [problems]);

  async function ensureDraft(): Promise<string | null> {
    if (token) return token;
    const r = await call<{ token: string }>("POST", "/drafts", { answers: payload(a), website2: hp });
    if (!r.ok) { setMessage({ kind: "bad", text: r.message }); return null; }
    setToken(r.data.token);
    window.history.replaceState(null, "", `${window.location.pathname}#d=${r.data.token}`);
    return r.data.token;
  }

  async function saveDraft() {
    setBusy("save"); setMessage(null);
    try {
      const t = await ensureDraft();
      if (!t) return;
      const r = await call("PUT", `/drafts/${t}`, { answers: payload(a), website2: hp });
      if (!r.ok) { setMessage({ kind: "bad", text: r.message }); return; }
      setMessage({ kind: "ok", text: `Draft saved. Keep this private link to resume within ${lim.draft_days} days: ${window.location.origin}/partnerships/collaboration#d=${t}` });
    } finally { setBusy(null); }
  }

  function go(to: number) {
    setProblems([]);
    setStep(to);
    setTimeout(() => topRef.current?.focus(), 0);
  }
  async function next() {
    const found = stepProblems(step, a, lim);
    if (found.length) { setProblems(found); return; }
    if (step === 5) { const t = await ensureDraft(); if (!t) return; }
    go(step + 1);
  }

  /** the files chosen, copied out of the picker before it is cleared (a cleared picker empties its list) */
  async function upload(list: File[]) {
    if (!list.length) return;
    const t = await ensureDraft();
    if (!t) return;
    setBusy("upload"); setMessage(null);
    try {
      for (const f of list) {
        const bad = fileProblem(f.name, f.size, lim.max_file_mb);
        if (bad) { setProblems([{ step: 6, field: "attachments", message: `Attachment: ${bad}` }]); continue; }
        if (files.length >= lim.max_files) { setProblems([{ step: 6, field: "attachments", message: `Attachments: attach at most ${lim.max_files} files.` }]); break; }
        const r = await call<{ attachments: Attachment[] }>("POST", `/drafts/${t}/attachments`, { kind: fileKind, filename: f.name, dataUrl: await readDataUrl(f) });
        if (!r.ok) { setProblems([{ step: 6, field: "attachments", message: r.message }]); continue; }
        setFiles(r.data.attachments);
        setMessage({ kind: "ok", text: `${f.name} attached.` });
      }
    } finally { setBusy(null); }
  }
  async function remove(id: string) {
    if (!token) return;
    const r = await call<{ attachments: Attachment[] }>("DELETE", `/drafts/${token}/attachments/${id}`);
    if (r.ok) setFiles(r.data.attachments);
  }

  async function submit() {
    setBusy("submit"); setMessage(null); setProblems([]);
    try {
      const t = await ensureDraft();
      if (!t) return;
      const chk = await call<{ problems: Problem[] }>("POST", `/drafts/${t}/check`, { answers: payload(a), website2: hp });
      if (!chk.ok) { setMessage({ kind: "bad", text: chk.message }); return; }
      if (chk.data.problems.length) { setProblems(chk.data.problems); return; }
      const r = await call<Submitted>("POST", `/drafts/${t}/submit`, { answers: payload(a), website2: hp });
      if (!r.ok) { setMessage({ kind: "bad", text: r.message }); return; }
      window.history.replaceState(null, "", window.location.pathname);
      setDone(r.data);
      setTimeout(() => topRef.current?.focus(), 0);
    } finally { setBusy(null); }
  }

  const deps = options.departments.filter((d) => !a.facultyCode || d.faculty_code === a.facultyCode);
  const catLabel = (k?: string) => options.categories.find((c) => c.code === k)?.label ?? "—";

  if (done) {
    return (
      <div className="ptn-done" ref={topRef} tabIndex={-1}>
        <h2 className="ptn-h2">Thank you</h2>
        <p>Your collaboration enquiry has been received.</p>
        <dl className="ptn-dl">
          <dt>Reference number</dt><dd className="tnum b700">{done.reference}</dd>
          <dt>Date received</dt><dd>{dateWords(done.received_at, true)}</dd>
          <dt>Contact email</dt><dd>{done.email}</dd>
        </dl>
        <p><strong>Next step:</strong> the University will review the submission and route it to the appropriate office or academic unit. We aim to acknowledge complete
          enquiries within {lim.acknowledge_days} working days. An acknowledgement has been sent to {done.email}.</p>
        <p>Follow your enquiry, answer any request and add documents at your private link: <Link href={done.statusPath}>open my enquiry</Link>. Keep the link to yourself.</p>
        <p className="sub2">How your information is used: <Link href="/privacy-policy">privacy policy</Link>.{lim.contact_email ? <> Contact: <a href={`mailto:${lim.contact_email}`}>{lim.contact_email}</a>.</> : null}</p>
      </div>
    );
  }

  const text = (id: keyof Answers, label: string, o: { required?: boolean; max?: number; rows?: number; hint?: ReactNode; type?: string; auto?: string } = {}) => (
    <Field id={`pf-${String(id)}`} label={label} required={o.required} error={err(String(id))} hint={o.hint} full={!!o.rows}>
      {o.rows ? (
        <>
          <textarea id={`pf-${String(id)}`} className="ctl" rows={o.rows} value={String(a[id] ?? "")} onChange={(e) => set({ [id]: e.target.value } as Partial<Answers>)}
            aria-invalid={!!err(String(id))} />
          {o.max ? <Count value={String(a[id] ?? "")} max={o.max} /> : null}
        </>
      ) : (
        <input id={`pf-${String(id)}`} className="ctl" type={o.type ?? "text"} value={String(a[id] ?? "")} onChange={(e) => set({ [id]: e.target.value } as Partial<Answers>)}
          autoComplete={o.auto} aria-invalid={!!err(String(id))} maxLength={o.type === "date" ? undefined : 500} />
      )}
    </Field>
  );
  const select = (id: keyof Answers, label: string, opts: Opt[], o: { required?: boolean; hint?: ReactNode } = {}) => (
    <Field id={`pf-${String(id)}`} label={label} required={o.required} error={err(String(id))} hint={o.hint}>
      <select id={`pf-${String(id)}`} className="ctl" value={String(a[id] ?? "")} onChange={(e) => set({ [id]: e.target.value } as Partial<Answers>)} aria-invalid={!!err(String(id))}>
        <option value="">Choose…</option>
        {opts.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
      </select>
    </Field>
  );
  const yesNo = (v: boolean | null | undefined) => (v === true ? "YES" : v === false ? "NO" : "");
  const catOpts: Opt[] = options.categories.map((c) => [c.code, `${options.groups.find((g) => g.code === c.grp)?.label ?? c.grp}: ${c.label}`]);

  const review: [number, string, [string, ReactNode][]][] = [
    [1, "Applicant details", [["Name", `${a.firstName ?? ""} ${a.lastName ?? ""}`.trim() || "—"], ["Role", a.jobTitle || "—"], ["Organisation", a.orgName || "—"],
      ["Organisation type", a.orgType === "OTHER" ? a.orgTypeOther || "Other" : word(ORG_TYPES, a.orgType)], ["Work email", a.email || "—"], ["Telephone", a.phone || "—"],
      ["Country/territory", a.country || "—"], ["City", a.city || "—"], ["Website", a.website || "—"], ["Preferred contact", word(CONTACT_METHODS, a.contactMethod)]]],
    [2, "Existing University connection", [["Is this", word(PROPOSAL_KINDS, a.proposalKind)], ["Previous reference", a.previousReference || "—"],
      ["University contact", a.hasContact ? `${a.contactName ?? ""}${a.contactUnit ? `, ${a.contactUnit}` : ""}${a.contactEmail ? ` (${a.contactEmail})` : ""}` : a.hasContact === false ? "No" : "—"],
      ["Collaborated before", word(YES_NO_NOT_SURE, a.collaboratedBefore)]]],
    [3, "Partnership proposal", [["Category", catLabel(a.category)], ["Secondary category", a.secondaryCategory ? catLabel(a.secondaryCategory) : "—"], ["Title", a.title || "—"],
      ["Summary", a.summary || "—"], ["Faculty", options.faculties.find((f) => f.code === a.facultyCode)?.name ?? "—"],
      ["Department", options.departments.find((d) => d.code === a.deptCode)?.name ?? "—"], ["Proposed start", a.startDate || "—"], ["Duration", a.duration || "—"],
      ["Format", word(FORMATS, a.collaborationFormat)]]],
    [4, "Funding & resources", [["Funding", word(FUNDING, a.fundingStatus)], ["Estimated budget", a.budget ? `${a.currency ?? ""} ${a.budget}` : "—"], ["Funder", a.funder || "—"],
      ["Joint grant application", word(JOINT_GRANT, a.jointGrant)], ["Resources requested", words(RESOURCES, a.resourcesRequested)]]],
    [5, "International, legal & compliance", [["Partners outside the country", a.international === true ? `Yes: ${(a.countries ?? []).join(", ")}` : a.international === false ? "No" : "—"],
      ["Formal agreement", words(AGREEMENT_TYPES, a.agreementTypes)], ["Personal data", word(YES_NO_NOT_SURE, a.personalData)],
      ["Ethics approval", word(YES_NO_NOT_SURE, a.ethics)], ["High-risk activities", HIGH_RISK.filter(([k]) => a.highRisk?.[k] && a.highRisk[k] !== "NO").map(([k, l]) => `${l} (${word(YES_NO_NOT_SURE, a.highRisk?.[k])})`).join(", ") || "None"],
      ["Conflicts of interest", word(COI, a.coi)], ["Own due diligence", word(OWN_DD, a.ownDueDiligence)]]],
    [6, "Attachments", [["Files", files.length ? files.map((f) => `${f.filename} (${word(ATTACHMENT_KINDS, f.kind)}, ${bytes(f.size_bytes)})`).join("; ") : "None"]]],
    [7, "Declarations", [["Declarations", a.declaredAccurate && a.declaredAuthorised && a.declaredNoCommitment && a.declaredPrivacy && a.consentContact ? "All given" : "Not all given"],
      ["Partnership communications", a.consentMarketing ? "Yes" : "No"]]],
  ];

  return (
    <section className="ptn-form" aria-label="Collaboration enquiry form">
      <div ref={topRef} tabIndex={-1} className="ptn-steptop">
        <p className="ptn-stepof">Step {step} of {STEPS.length}</p>
        <h2 className="ptn-h2">{STEPS[step - 1]}</h2>
        <ol className="ptn-progress" aria-label="Progress">
          {STEPS.map((s, i) => <li key={s} className={i + 1 < step ? "done" : i + 1 === step ? "now" : ""} aria-current={i + 1 === step ? "step" : undefined}><span className="sr-only">{s}</span></li>)}
        </ol>
      </div>

      {problems.length ? (
        <div className="ptn-summary" role="alert" tabIndex={-1} ref={summaryRef} aria-labelledby="ptn-sum-h">
          <h3 id="ptn-sum-h">There {problems.length === 1 ? "is a problem" : `are ${problems.length} problems`}</h3>
          <ul>{problems.map((p) => (
            <li key={p.field + p.message}><a href={`#pf-${p.field.split(".")[0] === "highRisk" ? "highRisk" : p.field}`} onClick={(e) => {
              if (p.step !== step) { e.preventDefault(); setStep(p.step); setTimeout(() => document.getElementById(`pf-${p.field}`)?.focus(), 50); }
            }}>{p.message}</a></li>
          ))}</ul>
        </div>
      ) : null}
      {message ? <Note kind={message.kind} title={message.text} /> : null}

      <div className="ptn-hp" aria-hidden="true"><label htmlFor="pf-website2">Leave this empty</label><input id="pf-website2" tabIndex={-1} autoComplete="off" value={hp} onChange={(e) => setHp(e.target.value)} /></div>

      {step === 1 ? (
        <div className="grid grid--2">
          {text("firstName", "First name", { required: true, auto: "given-name" })}
          {text("lastName", "Last name", { required: true, auto: "family-name" })}
          {text("jobTitle", "Job title / role", { auto: "organization-title" })}
          {text("orgName", "Organisation name", { required: true, auto: "organization" })}
          {select("orgType", "Organisation type", ORG_TYPES, { required: true })}
          {a.orgType === "OTHER" ? text("orgTypeOther", "Organisation type (describe)", { required: true }) : null}
          {text("email", "Work email address", { required: true, type: "email", auto: "email", hint: "An official institutional or business address where you have one." })}
          {text("phone", "Telephone", { type: "tel", auto: "tel", hint: "With the country code, such as +234 803 000 0000." })}
          <Field id="pf-country" label="Country/territory" required error={err("country")}>
            <SearchSelect id="pf-country" value={a.country ?? ""} onChange={(v) => set({ country: v })} options={countryList} placeholder="Search a country…" />
          </Field>
          {text("city", "City", { auto: "address-level2" })}
          {text("address", "Physical address", { auto: "street-address" })}
          {text("website", "Organisation website", { type: "url", auto: "url" })}
          {text("profileUrl", "LinkedIn / organisation profile", { type: "url" })}
          {select("language", "Preferred language", LANGUAGES.map((l) => [l, l]))}
          {select("contactMethod", "Preferred contact method", CONTACT_METHODS)}
          {text("timeZone", "Preferred meeting time zone", { hint: "Such as West Africa Time (UTC+1)." })}
        </div>
      ) : null}

      {step === 2 ? (
        <div className="stack">
          <Choice id="pf-proposalKind" legend="Is this" value={a.proposalKind} options={PROPOSAL_KINDS} onChange={(v) => set({ proposalKind: v })} error={err("proposalKind")} required />
          {a.proposalKind === "FOLLOW_UP" ? text("previousReference", "Reference of the previous submission", { required: true, hint: "PTN/YYYY/NNNNNN" }) : null}
          <Choice id="pf-hasContact" legend="Do you already have a University contact?" value={yesNo(a.hasContact)} options={[["YES", "Yes"], ["NO", "No"]]}
            onChange={(v) => set({ hasContact: v === "YES" })} error={err("hasContact")} required />
          {a.hasContact ? (
            <div className="grid grid--2">
              {text("contactName", "Contact name", { required: true })}
              {text("contactUnit", "Department/unit")}
              {text("contactEmail", "Contact email", { type: "email" })}
            </div>
          ) : null}
          <Choice id="pf-collaboratedBefore" legend="Have you collaborated with the University before?" value={a.collaboratedBefore} options={YES_NO_NOT_SURE}
            onChange={(v) => set({ collaboratedBefore: v })} error={err("collaboratedBefore")} required />
          {a.collaboratedBefore === "YES" ? text("previousCollaboration", "Previous collaboration", { required: true, rows: 3 }) : null}
        </div>
      ) : null}

      {step === 3 ? (
        <div className="grid grid--2">
          {select("category", "Primary collaboration category", catOpts, { required: true })}
          {select("secondaryCategory", "Secondary category", catOpts)}
          {text("title", "Proposed partnership title", { required: true })}
          {text("summary", "Short summary", { required: true, rows: 3, max: lim.summary_max })}
          {text("description", "Detailed description", { required: true, rows: 6, max: lim.text_max })}
          {text("objectives", "Objectives", { rows: 4, max: lim.text_max })}
          {text("activities", "Activities", { rows: 4, max: lim.text_max })}
          {text("expectedResults", "Expected results", { rows: 3, max: lim.text_max })}
          {text("whyUniversity", "Why partner with this University?", { rows: 3, max: lim.text_max })}
          <Field id="pf-facultyCode" label="Relevant faculty" error={err("facultyCode")}>
            <SearchSelect id="pf-facultyCode" value={a.facultyCode ?? ""} onChange={(v) => set({ facultyCode: v, deptCode: "" })} allLabel="Not sure"
              options={options.faculties.map((f) => ({ value: f.code, label: f.name }))} placeholder="Search a faculty…" />
          </Field>
          <Field id="pf-deptCode" label="Relevant department" error={err("deptCode")}>
            <SearchSelect id="pf-deptCode" value={a.deptCode ?? ""} onChange={(v) => set({ deptCode: v })} allLabel="Not sure"
              options={deps.map((d) => ({ value: d.code, label: d.name }))} placeholder="Search a department…" />
          </Field>
          {text("unitText", "Relevant school, college, centre or institute")}
          {text("expertise", "Relevant area of expertise")}
          {text("staffContact", "Specific University staff member or unit")}
          {text("startDate", "Proposed start date", { type: "date" })}
          {text("duration", "Proposed duration", { hint: "Such as 2 years." })}
          {select("collaborationFormat", "Collaboration format", FORMATS)}
          {text("benefitsUniversity", "Expected benefits to the University", { rows: 3, max: lim.benefits_max })}
          {text("benefitsPartner", "Expected benefits to your organisation", { rows: 3, max: lim.benefits_max })}
        </div>
      ) : null}

      {step === 4 ? (
        <div className="stack">
          <Choice id="pf-fundingStatus" legend="Is funding already available?" value={a.fundingStatus} options={FUNDING} onChange={(v) => set({ fundingStatus: v })} error={err("fundingStatus")} required />
          <div className="grid grid--2">
            {text("budget", "Estimated budget", { hint: "In figures, such as 250000." })}
            {select("currency", "Currency", CURRENCIES.map((c) => [c, c]))}
            {text("funder", "Proposed funding source / funder")}
            {select("jointGrant", "Joint grant application?", JOINT_GRANT)}
            {text("fundingDeadline", "Funding deadline", { type: "date" })}
          </div>
          <Many id="pf-resourcesRequested" legend="University resources requested" value={a.resourcesRequested} options={RESOURCES} onChange={(v) => set({ resourcesRequested: v })} error={err("resourcesRequested")} />
          {(a.resourcesRequested ?? []).includes("OTHER") ? text("resourcesOther", "Other resources requested", { required: true }) : null}
          {text("partnerContribution", "Resources your organisation will contribute", { rows: 3, max: lim.benefits_max })}
        </div>
      ) : null}

      {step === 5 ? (
        <div className="stack">
          <Choice id="pf-international" legend="Does the proposal involve partners outside the country?" value={yesNo(a.international)} options={[["YES", "Yes"], ["NO", "No"]]}
            onChange={(v) => set({ international: v === "YES" })} error={err("international")} required />
          {a.international ? (
            <>
              <Field id="pf-countries" label="Countries involved" required error={err("countries")}>
                <SearchSelect id="pf-countries" value="" onChange={(v) => v && !(a.countries ?? []).includes(v) && set({ countries: [...(a.countries ?? []), v] })}
                  options={countryList} placeholder="Add a country…" />
              </Field>
              {(a.countries ?? []).length ? (
                <ul className="ptn-tags">{(a.countries ?? []).map((c) => <li key={c}>{c} <button type="button" className="linklike" onClick={() => set({ countries: (a.countries ?? []).filter((x) => x !== c) })} aria-label={`Remove ${c}`}>×</button></li>)}</ul>
              ) : null}
              <Many id="pf-internationalAspects" legend="What involves other countries" value={a.internationalAspects} options={INTERNATIONAL_ASPECTS} onChange={(v) => set({ internationalAspects: v })} />
            </>
          ) : null}
          <Many id="pf-agreementTypes" legend="Does the proposal require a formal agreement?" value={a.agreementTypes} options={AGREEMENT_TYPES} onChange={(v) => set({ agreementTypes: v })} />
          <Choice id="pf-personalData" legend="Will the project involve personal data?" value={a.personalData} options={YES_NO_NOT_SURE} onChange={(v) => set({ personalData: v })} error={err("personalData")} required
            hint="Only whether it does; do not enter any personal data here." />
          {a.personalData === "YES" ? (
            <>
              <Choice id="pf-sensitiveData" legend="Will it involve sensitive personal data?" value={a.sensitiveData} options={YES_NO_NOT_SURE} onChange={(v) => set({ sensitiveData: v })} error={err("sensitiveData")} required />
              {a.sensitiveData === "YES" || a.sensitiveData === "NOT_SURE" ? (
                <Many id="pf-sensitiveKinds" legend="Which kinds" value={a.sensitiveKinds} options={SENSITIVE_KINDS} onChange={(v) => set({ sensitiveKinds: v })} />
              ) : null}
            </>
          ) : null}
          <Choice id="pf-ethics" legend="Will the project require ethics approval?" value={a.ethics} options={YES_NO_NOT_SURE} onChange={(v) => set({ ethics: v })} error={err("ethics")} required />
          <fieldset className="ptn-fs" id="pf-highRisk" tabIndex={-1}>
            <legend>Does the proposal involve:<span className="req" aria-hidden="true"> *</span></legend>
            <div className="ptn-risk">
              {HIGH_RISK.map(([k, label]) => (
                <div key={k} className={`ptn-riskrow${err(`highRisk.${k}`) ? " is-error" : ""}`} role="radiogroup" aria-label={label} id={`pf-highRisk.${k}`} tabIndex={-1}>
                  <span className="ptn-risklabel">{label}</span>
                  {YES_NO_NOT_SURE.map(([v, l]) => (
                    <label key={v} className="ptn-choice"><input type="radio" name={`hr-${k}`} checked={a.highRisk?.[k] === v} onChange={() => set({ highRisk: { ...(a.highRisk ?? {}), [k]: v } })} /> {l}</label>
                  ))}
                </div>
              ))}
            </div>
            {HIGH_RISK.some(([k]) => err(`highRisk.${k}`)) ? <span className="ferr">Answer yes, no or not sure for each.</span> : null}
          </fieldset>
          <Choice id="pf-coi" legend="Are there known conflicts of interest or existing commercial relationships that should be disclosed?" value={a.coi} options={COI}
            onChange={(v) => set({ coi: v })} error={err("coi")} required hint="Choosing to discuss confidentially: the University's partnerships office will contact you; nothing more is asked here." />
          {a.coi === "YES" ? text("coiDetail", "What should be disclosed", { required: true, rows: 3, max: lim.benefits_max, hint: "Read only by the officers allowed to." }) : null}
          <Choice id="pf-ownDueDiligence" legend="Has your organisation conducted its own due diligence/compliance review?" value={a.ownDueDiligence} options={OWN_DD}
            onChange={(v) => set({ ownDueDiligence: v })} error={err("ownDueDiligence")} required />
        </div>
      ) : null}

      {step === 6 ? (
        <div className="stack">
          <p>Optional. PDF, DOCX, XLSX or PPTX; at most {lim.max_files} files of up to {lim.max_file_mb} MB each. Do not include personal or confidential information the University does not need at this stage.</p>
          <div className="grid grid--2">
            <Field id="pf-fileKind" label="What the document is">
              <select id="pf-fileKind" className="ctl" value={fileKind} onChange={(e) => setFileKind(e.target.value)}>
                {ATTACHMENT_KINDS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
              </select>
            </Field>
            <Field id="pf-attachments" label="Choose a file" error={err("attachments")}>
              <input id="pf-attachments" type="file" className="ctl" accept=".pdf,.docx,.xlsx,.pptx,application/pdf" multiple disabled={busy === "upload" || files.length >= lim.max_files}
                onChange={(e) => { const picked = Array.from(e.target.files ?? []); e.target.value = ""; void upload(picked); }} />
            </Field>
          </div>
          {busy === "upload" ? <p className="sub2" aria-live="polite">Uploading…</p> : null}
          {files.length ? (
            <ul className="ptn-files" aria-label="Attached files">
              {files.map((f) => <li key={f.id}><span>{f.filename}</span> <span className="sub2">{word(ATTACHMENT_KINDS, f.kind)} · {bytes(f.size_bytes)}</span> <Btn kind="ghost" onClick={() => void remove(f.id)}>Remove</Btn></li>)}
            </ul>
          ) : <p className="sub2">No file attached.</p>}
        </div>
      ) : null}

      {step === 7 ? (
        <div className="stack">
          <fieldset className="ptn-fs" id="pf-declarations">
            <legend>Declarations<span className="req" aria-hidden="true"> *</span></legend>
            {([["declaredAccurate", "I confirm that the information provided is accurate to the best of my knowledge."],
              ["declaredAuthorised", "I confirm that I am authorised to submit this enquiry on behalf of my organisation, where applicable."],
              ["declaredNoCommitment", "I understand that submitting this form does not create a legal, financial, or contractual relationship with the University."],
              ["declaredPrivacy", <>I have read the University&rsquo;s <Link href="/privacy-policy" target="_blank">privacy notice</Link> and understand how my information will be used.</>],
              ["consentContact", "I consent to the University contacting me about this collaboration request."]] as [keyof Answers, ReactNode][]).map(([k, label]) => (
              <div key={String(k)} className={`ptn-decl${err(String(k)) ? " is-error" : ""}`}>
                <label><input id={`pf-${String(k)}`} type="checkbox" checked={!!a[k]} onChange={(e) => set({ [k]: e.target.checked } as Partial<Answers>)} /> {label}</label>
                {err(String(k)) ? <span className="ferr">{err(String(k))}</span> : null}
              </div>
            ))}
          </fieldset>
          <fieldset className="ptn-fs">
            <legend>Optional</legend>
            <label className="ptn-decl"><input id="pf-consentMarketing" type="checkbox" checked={!!a.consentMarketing} onChange={(e) => set({ consentMarketing: e.target.checked })} /> I consent to receive relevant University partnership, research, or engagement communications.</label>
          </fieldset>
          {!options.privacyPublished ? <p className="sub2">The University&rsquo;s privacy policy is being finalised; the page shows its current text.</p> : null}
        </div>
      ) : null}

      {step === 8 ? (
        <div className="stack">
          {review.map(([n, title, rows]) => (
            <section key={n} className="ptn-review" aria-label={title}>
              <div className="ptn-reviewhead"><h3>{title}</h3><Btn kind="ghost" onClick={() => go(n)}>Edit<span className="sr-only"> {title}</span></Btn></div>
              <dl className="ptn-dl">{rows.map(([k, v]) => <div key={k} className="ptn-dlrow"><dt>{k}</dt><dd>{v}</dd></div>)}</dl>
            </section>
          ))}
          <Note kind="info" title="Submission of this form does not constitute acceptance of a partnership proposal or create a binding commitment with the University." />
        </div>
      ) : null}

      <div className="ptn-nav">
        {step > 1 ? <Btn kind="ghost" onClick={() => go(step - 1)} disabled={busy !== null}>Back</Btn> : <span />}
        <Btn kind="secondary" onClick={() => void saveDraft()} busy={busy === "save"} busyLabel="Saving…" disabled={busy !== null && busy !== "save"}>Save draft</Btn>
        {step < STEPS.length ? <Btn kind="primary" onClick={() => void next()} disabled={busy !== null}>Next</Btn>
          : <Btn kind="primary" onClick={() => void submit()} busy={busy === "submit"} busyLabel="Submitting…" disabled={busy !== null && busy !== "submit"}>Submit proposal</Btn>}
      </div>
    </section>
  );
}
