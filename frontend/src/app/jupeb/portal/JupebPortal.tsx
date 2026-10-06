"use client";

/**
 * The JUPEB candidate's dashboard (V339), applicant to student to result, in the portal's own shell. The short application
 * form asked only what opens an application; here the candidate continues the biodata (nationality, state and LGA, addresses,
 * home town, guardian, next of kin), enters the O'Level, uploads the documents, pays — every amount the server's, from the
 * Bursary's rule — submits, reads the decision and the admission letter, pays the school fees 70% then 30% (or at once where
 * the Bursary allows), chooses a combination of their Science or Arts stream and registers its three subjects, sees the official examination number and, once published,
 * the results, and raises support tickets. Every call is scoped to the signed-in candidate.
 */
import { useCallback, useEffect, useState, type ChangeEvent } from "react";
import type { Problem } from "@/lib/api";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tabs, Tiles, KvGrid } from "@/components/proto/ui";
import { Field, Steps } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { Shell, type Me as ShellMe } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PayByCard } from "@/app/applicant/common";
import { STATES, lgasOf, NATIONALITIES } from "@/lib/nigeria";
import {
  DOC_STATUS, EVENT_LABEL, FEE_KIND, OLEVEL_EXAMS, OLEVEL_GRADES, OLEVEL_SUBJECTS, SCREENING_LABEL, STATE_LABEL, STATE_SHORT,
  day, feeCategoryLabel, fileBase64, fullName, jcall, naira, stateKind, streamLabel, when, type Candidate, type Doc, type FeeRef,
} from "@/lib/jupeb";

type Tab = "overview" | "biodata" | "olevel" | "documents" | "payments" | "admission" | "subjects" | "results" | "support";

interface Ticket { id: string; number: string; subject: string; category: string; status: string; created_at: string; updated_at: string; queue: string | null }
interface TicketDetail extends Ticket { description: string; resolution_summary: string | null; comments: { id: string; author_kind: string; author_name: string; body: string; created_at: string }[] }
interface Support { categories: { code: string; name: string; fields: string }[]; tickets: Ticket[] }

const ADMITTED = new Set(["ADMITTED", "STUDENT", "COMPLETED"]);

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
        setTab("payments");
        const ok = await pollConfirm(paid, 8);
        setVerifying(false);
        if (ok) notify("Payment confirmed — thank you.");
      }
    })();
  }, [load, pollConfirm]);

  /** one act; the record the server returns replaces the page's */
  const act = useCallback(async (path: string, method = "POST", body?: unknown): Promise<boolean> => {
    const r = await jcall<Candidate>(path, method, body);
    if (!r.ok) { notifyProblem(r.problem); return false; }
    setMe(r.data);
    return true;
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
    name: fullName(me), staffNumber: me.application_no, sessionId: null, unit: `JUPEB ${me.session}`, waiting: {},
  };
  const admitted = ADMITTED.has(me.state);
  const tabs: { id: Tab; label: string; disabled?: boolean }[] = [
    { id: "overview", label: "Overview" }, { id: "biodata", label: "Biodata" }, { id: "olevel", label: "O’Level" }, { id: "documents", label: "Documents" },
    { id: "payments", label: "Payments" }, { id: "admission", label: "Admission" }, { id: "subjects", label: "Subjects", disabled: !admitted },
    { id: "results", label: "Results", disabled: !admitted }, { id: "support", label: "Support" },
  ];

  return (
    <Shell route="jupeb/portal" me={shellMe}>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Note kind={stateKind(me.state) === "bad" ? "bad" : admitted ? "ok" : "info"} title={`${fullName(me)} · ${me.application_no}`}>
        Your JUPEB record for {me.session} is <b>{STATE_LABEL[me.state] ?? me.state}</b>.
        {me.state === "RETURNED" && me.return_note ? <> The JUPEB Office asks: <b>{me.return_note}</b></> : null}
      </Note>
      {verifying ? <Note kind="info" title="Confirming your payment…">The page updates on its own once the payment reaches the University.</Note> : null}
      <Tiles items={[
        ["Status", STATE_SHORT[me.state] ?? me.state, null, me.submitted_at ? `submitted ${day(me.submitted_at)}` : "not yet submitted"],
        ["Application fee", me.fee_confirmed_at ? "Paid" : "Unpaid", null, naira(me.application_fee)],
        ["School fees", admitted ? (me.fees.status === "PAID" ? "Paid" : me.fees.status === "PARTIALLY_PAID" ? "Part paid" : "Unpaid") : "—", null, admitted ? `${naira(me.fees.outstanding)} outstanding` : "after admission"],
        ["JUPEB exam no.", me.exam_no ?? "Not yet", null, me.exam_no ? `assigned ${day(me.exam_no_assigned_at)}` : "issued by the Board"],
      ]} />
      <Tabs items={tabs} value={tab} onChange={setTab} look="line" label="Your JUPEB record" />
      {tab === "overview" ? <Overview me={me} act={act} go={setTab} /> : null}
      {tab === "biodata" ? <Biodata me={me} act={act} /> : null}
      {tab === "olevel" ? <OlevelTab me={me} act={act} /> : null}
      {tab === "documents" ? <Documents me={me} act={act} /> : null}
      {tab === "payments" ? <Payments me={me} reload={load} /> : null}
      {tab === "admission" ? <Admission me={me} /> : null}
      {tab === "subjects" ? <Subjects me={me} act={act} /> : null}
      {tab === "results" ? <Results me={me} /> : null}
      {tab === "support" ? <SupportTab /> : null}
    </Shell>
  );
}

type Act = (path: string, method?: string, body?: unknown) => Promise<boolean>;

function Overview({ me, act, go }: { me: Candidate; act: Act; go: (t: Tab) => void }) {
  const [busy, setBusy] = useState(false);
  const has = (k: string) => me.events.some((e) => e.kind === k);
  const steps: ["done" | "now" | "todo", string, string][] = [
    ["done", "Application started", day(me.created_at)],
    [me.fee_confirmed_at ? "done" : "now", "Application fee paid", me.fee_confirmed_at ? day(me.fee_confirmed_at) : "Pay it under Payments"],
    [me.submitted_at ? "done" : me.fee_confirmed_at ? "now" : "todo", "Biodata, O’Level and documents completed and submitted", me.submitted_at ? day(me.submitted_at) : `${me.missing.length} item(s) outstanding`],
    [me.eligibility_decided_at ? "done" : me.submitted_at ? "now" : "todo", "Eligibility confirmed by the JUPEB Office", me.eligibility_decided_at ? day(me.eligibility_decided_at) : "—"],
    [me.admission_decided_at ? "done" : "todo", "Admission decision", me.admission_decided_at ? `${STATE_SHORT[me.state] ?? me.state} · ${day(me.admission_decided_at)}` : "—"],
    [me.activated_at ? "done" : ADMITTED.has(me.state) ? "now" : "todo", "School fee paid — studentship activated", me.activated_at ? day(me.activated_at) : "—"],
    [me.subjects_registered_at ? "done" : me.state === "STUDENT" ? "now" : "todo", "Three subjects registered", me.subjects_registered_at ? day(me.subjects_registered_at) : "—"],
    [me.exam_no ? "done" : "todo", "JUPEB examination number", me.exam_no ?? "—"],
    [me.state === "COMPLETED" || has("COMPLETED") ? "done" : "todo", "Results published", me.resultsPublished ? "Published" : "—"],
  ];
  async function submit() {
    setBusy(true);
    try {
      if (await act("/api/v1/jupeb/me/submit")) notify("Your application is submitted to the JUPEB Office.");
    } finally { setBusy(false); }
  }
  return (
    <div className="grid grid--2">
      <Panel title="Your progress"><PBody><Steps list={steps} /></PBody></Panel>
      <div className="stack">
        {me.editable ? (
          <Panel title={me.state === "RETURNED" ? "Correct and submit again" : "Before you submit"}>
            <PBody>
              {me.missing.length ? (
                <>
                  <p className="sub2">Complete each of these, then submit:</p>
                  <ul style={{ margin: "var(--s-2) 0 var(--s-3)", paddingLeft: "1.2em" }}>{me.missing.map((m) => <li key={m}>{m}</li>)}</ul>
                  <div className="row">
                    {!me.fee_confirmed_at ? <Btn kind="secondary" onClick={() => go("payments")}>Pay the application fee</Btn> : null}
                    <Btn kind="ghost" onClick={() => go("biodata")}>Biodata</Btn><Btn kind="ghost" onClick={() => go("olevel")}>O&rsquo;Level</Btn><Btn kind="ghost" onClick={() => go("documents")}>Documents</Btn>
                  </div>
                </>
              ) : (
                <>
                  <Note kind="ok" title="Everything is in">Your application is complete. Once submitted it cannot be changed unless the JUPEB Office returns it.</Note>
                  <Btn kind="primary" size="md" disabled={busy} onClick={() => void submit()}>{busy ? "Submitting…" : me.state === "RETURNED" ? "Submit again" : "Submit my application"}</Btn>
                </>
              )}
            </PBody>
          </Panel>
        ) : null}
        {me.state === "INELIGIBLE" && me.eligibility_note ? <Note kind="bad" title="Not eligible">{me.eligibility_note}</Note> : null}
        <Panel title="What has happened">
          <PBody>
            <ul className="pg-steps" style={{ listStyle: "none", margin: 0, padding: 0 }}>
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
    </div>
  );
}

function Biodata({ me, act }: { me: Candidate; act: Act }) {
  const [f, setF] = useState<Record<string, string>>(() => ({
    middleName: me.middle_name ?? "", sex: me.sex ?? "", dob: me.date_of_birth ?? "", nin: me.nin ?? "", phone: me.phone ?? "",
    nationality: me.nationality ?? "Nigerian", stateOfOrigin: me.state_of_origin ?? "", lga: me.lga ?? "", contactAddress: me.contact_address ?? "",
    permanentAddress: me.permanent_address ?? "", homeTown: me.home_town ?? "", guardianName: me.guardian_name ?? "", guardianPhone: me.guardian_phone ?? "",
    guardianAddress: me.guardian_address ?? "", nextOfKinName: me.next_of_kin_name ?? "", nextOfKinPhone: me.next_of_kin_phone ?? "",
    nextOfKinRelationship: me.next_of_kin_relationship ?? "", stream: me.stream ?? "",
  }));
  const [busy, setBusy] = useState(false);
  const ro = !me.editable;
  const set = (k: string) => (e: ChangeEvent<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>) => setF({ ...f, [k]: e.target.value });
  const nigerian = f.nationality === "Nigerian";
  async function save() {
    setBusy(true);
    try {
      const { stream, ...bio } = f;
      const body = Object.fromEntries(Object.entries(bio).map(([k, v]) => [k, v.trim() === "" ? null : v.trim()]));
      if (!(await act("/api/v1/jupeb/me/biodata", "PUT", body))) return;
      if (stream && stream !== me.stream) {
        if (!(await act("/api/v1/jupeb/me/choice", "PUT", { stream }))) return;
      }
      notify("Your biodata is saved.");
    } finally { setBusy(false); }
  }
  const input = (k: string, label: string, opts: { hint?: string; max?: number; type?: string; required?: boolean } = {}) => (
    <Field id={`b-${k}`} label={label} hint={opts.hint} required={opts.required}>
      <input id={`b-${k}`} className="ctl" type={opts.type ?? "text"} value={f[k] ?? ""} onChange={set(k)} maxLength={opts.max ?? 120} disabled={ro} />
    </Field>
  );
  return (
    <Panel title="Biodata" right={ro ? <Pil kind="grey">Locked while with the JUPEB Office</Pil> : null}>
      <PBody>
        <KvGrid pairs={[["Surname", me.surname], ["First name", me.first_name], ["Email", me.email], ["Application number", me.application_no]]} />
        <div className="grid grid--3 mt-3">
          {input("middleName", "Middle name", { max: 80 })}
          <Field id="b-sex" label="Sex" required><select id="b-sex" className="ctl" value={f.sex} onChange={set("sex")} disabled={ro}><option value="">—</option><option value="F">Female</option><option value="M">Male</option></select></Field>
          {input("dob", "Date of birth", { type: "date", required: true })}
          {input("nin", "NIN", { max: 11, required: true })}
          {input("phone", "Phone", { max: 11, required: true, hint: "e.g. 08012345678" })}
          <Field id="b-nat" label="Nationality">
            <select id="b-nat" className="ctl" value={f.nationality} onChange={(e) => setF({ ...f, nationality: e.target.value, ...(e.target.value === "Nigerian" ? {} : { stateOfOrigin: "", lga: "" }) })} disabled={ro}>
              {NATIONALITIES.map((n) => <option key={n} value={n}>{n}</option>)}
            </select>
          </Field>
          <Field id="b-state" label="State of origin" required hint="Decides the indigene school fee">
            <select id="b-state" className="ctl" value={f.stateOfOrigin} onChange={(e) => setF({ ...f, stateOfOrigin: e.target.value, lga: "" })} disabled={ro || !nigerian}>
              <option value="">— Select a state —</option>{STATES.map((s) => <option key={s} value={s}>{s}</option>)}
            </select>
          </Field>
          <Field id="b-lga" label="Local government" required>
            <select id="b-lga" className="ctl" value={f.lga} onChange={set("lga")} disabled={ro || !nigerian || !f.stateOfOrigin}>
              <option value="">{f.stateOfOrigin ? "— Select an LGA —" : "Select a state first"}</option>{lgasOf(f.stateOfOrigin).map((l) => <option key={l} value={l}>{l}</option>)}
            </select>
          </Field>
          {input("homeTown", "Home town", { max: 80 })}
        </div>
        <div className="grid grid--2">
          <Field id="b-ca" label="Contact address" required><textarea id="b-ca" className="ctl" rows={2} maxLength={300} value={f.contactAddress} onChange={set("contactAddress")} disabled={ro} /></Field>
          <Field id="b-pa" label="Permanent home address"><textarea id="b-pa" className="ctl" rows={2} maxLength={300} value={f.permanentAddress} onChange={set("permanentAddress")} disabled={ro} /></Field>
        </div>
        <div className="eyebrow mt-3">Parent or guardian</div>
        <div className="grid grid--3">
          {input("guardianName", "Name")}{input("guardianPhone", "Phone", { max: 11 })}{input("guardianAddress", "Address", { max: 300 })}
        </div>
        <div className="eyebrow mt-3">Next of kin</div>
        <div className="grid grid--3">
          {input("nextOfKinName", "Name", { required: true })}{input("nextOfKinPhone", "Phone", { max: 11, required: true })}{input("nextOfKinRelationship", "Relationship", { max: 60 })}
        </div>
        <div className="eyebrow mt-3">Programme</div>
        {ro ? <KvGrid cls="grid--2" pairs={[["Programme", streamLabel(me.stream)]]} /> : (
          <div className="grid grid--3">
            <Field id="b-stream" label="Programme" required>
              <select id="b-stream" className="ctl" value={f.stream} onChange={set("stream")}>
                <option value="">— Science or Arts —</option><option value="SCIENCE">Science</option><option value="ARTS">Arts</option>
              </select>
            </Field>
          </div>
        )}
        {!ro ? <div className="row mt-3"><span className="grow" /><Btn kind="primary" disabled={busy} onClick={() => void save()}>{busy ? "Saving…" : "Save biodata"}</Btn></div> : null}
      </PBody>
    </Panel>
  );
}

interface Line { subject: string; grade: string }
interface Sitting { examType: string; examNumber: string; examYear: string; lines: Line[] }

function OlevelTab({ me, act }: { me: Candidate; act: Act }) {
  const init = (n: number): Sitting => {
    const rows = me.olevel.filter((o) => o.sitting === n);
    return {
      examType: rows[0]?.exam_type ?? "WAEC", examNumber: rows[0]?.exam_number ?? "", examYear: rows[0]?.exam_year ? String(rows[0].exam_year) : "",
      lines: rows.length ? rows.map((r) => ({ subject: r.subject, grade: r.grade })) : n === 1 ? ["English Language", "Mathematics", "", "", ""].map((s) => ({ subject: s, grade: "" })) : [],
    };
  };
  const [s, setS] = useState<Sitting[]>(() => [init(1), init(2)]);
  const [busy, setBusy] = useState(false);
  const ro = !me.editable;
  const upd = (i: number, patch: Partial<Sitting>) => setS(s.map((x, j) => (j === i ? { ...x, ...patch } : x)));
  const updLine = (i: number, k: number, patch: Partial<Line>) => upd(i, { lines: s[i].lines.map((l, m) => (m === k ? { ...l, ...patch } : l)) });
  async function save() {
    const grades = s.flatMap((x, i) => x.lines.filter((l) => l.subject.trim() && l.grade).map((l) => ({
      sitting: i + 1, examType: x.examType, examNumber: x.examNumber.trim() || null, examYear: x.examYear ? Number(x.examYear) : null, subject: l.subject.trim(), grade: l.grade,
    })));
    setBusy(true);
    try { if (await act("/api/v1/jupeb/me/olevel", "PUT", { grades })) notify("Your O’Level results are saved."); } finally { setBusy(false); }
  }
  const c = me.olevelCheck;
  return (
    <div className="stack">
      <Note kind={c.ok ? "ok" : "info"} title={c.ok ? `Requirement met — ${c.credits} credits` : "Five credits including English Language and Mathematics, in at most two sittings"}>
        {c.ok ? "Your O’Level meets the JUPEB requirement." : c.reasons.length ? c.reasons.join("; ") + "." : "Enter your results below."}
      </Note>
      <datalist id="olevel-subjects">{OLEVEL_SUBJECTS.map((x) => <option key={x} value={x} />)}</datalist>
      {s.map((x, i) => (
        <Panel key={i} title={`Sitting ${i + 1}${i === 1 ? " (if any)" : ""}`}>
          <PBody>
            <div className="grid grid--3">
              <Field id={`ex-${i}`} label="Examination"><select id={`ex-${i}`} className="ctl" value={x.examType} onChange={(e) => upd(i, { examType: e.target.value })} disabled={ro}>{OLEVEL_EXAMS.map((t) => <option key={t}>{t}</option>)}</select></Field>
              <Field id={`en-${i}`} label="Examination number"><input id={`en-${i}`} className="ctl" maxLength={30} value={x.examNumber} onChange={(e) => upd(i, { examNumber: e.target.value })} disabled={ro} /></Field>
              <Field id={`ey-${i}`} label="Year"><input id={`ey-${i}`} className="ctl tnum" inputMode="numeric" maxLength={4} value={x.examYear} onChange={(e) => upd(i, { examYear: e.target.value.replace(/\D/g, "") })} disabled={ro} /></Field>
            </div>
            {x.lines.map((l, k) => (
              <div key={k} className="row" style={{ gap: "var(--s-2)", marginTop: "var(--s-2)" }}>
                <input className="ctl grow" list="olevel-subjects" placeholder="Subject" aria-label={`Sitting ${i + 1} subject ${k + 1}`} value={l.subject} onChange={(e) => updLine(i, k, { subject: e.target.value })} disabled={ro} maxLength={60} />
                <select className="ctl" style={{ width: 110 }} aria-label={`Sitting ${i + 1} grade ${k + 1}`} value={l.grade} onChange={(e) => updLine(i, k, { grade: e.target.value })} disabled={ro}>
                  <option value="">Grade</option>{OLEVEL_GRADES.map((g) => <option key={g}>{g}</option>)}
                </select>
                {!ro ? <Btn kind="ghost" onClick={() => upd(i, { lines: x.lines.filter((_, m) => m !== k) })} aria-label="Remove subject">&times;</Btn> : null}
              </div>
            ))}
            {!ro && x.lines.length < 12 ? <div className="mt-2"><Btn kind="ghost" onClick={() => upd(i, { lines: [...x.lines, { subject: "", grade: "" }] })}>Add a subject</Btn></div> : null}
          </PBody>
        </Panel>
      ))}
      {!ro ? <div className="row"><span className="grow" /><Btn kind="primary" disabled={busy} onClick={() => void save()}>{busy ? "Saving…" : "Save O’Level results"}</Btn></div> : null}
    </div>
  );
}

function Documents({ me, act }: { me: Candidate; act: Act }) {
  const [busy, setBusy] = useState<string | null>(null);
  async function upload(d: Doc, file: File | undefined) {
    if (!file) return;
    if (file.size > 5 * 1024 * 1024) { notifyProblem({ status: 400, title: "A document is at most 5 MB." }); return; }
    setBusy(d.kind);
    try {
      const base64 = await fileBase64(file);
      if (await act(`/api/v1/jupeb/me/documents/${d.kind}`, "POST", { filename: file.name, contentType: file.type || "application/octet-stream", base64 })) notify(`${d.label} uploaded.`);
    } finally { setBusy(null); }
  }
  return (
    <Panel title="Documents" right={<span className="sub2">PDF, JPEG or PNG · at most 5 MB · the passport photograph is an image</span>}>
      <PBody>
        <DTable noPrint pageSize={0} cols={["Document", "Status", "File", "Uploaded", "Action|mid"]} rows={me.documents.map((d) => {
          const replace = d.status === "REJECTED" || d.status === "REPLACEMENT_REQUIRED";
          const can = me.editable || replace;
          return [
            <span key="l"><b>{d.label}</b>{d.required ? <span className="sub2"> · required</span> : null}{d.review_note ? <div className="sub2">{d.review_note}</div> : null}</span>,
            d.status ? <Pil key="s" kind={stateKind(d.status)}>{DOC_STATUS[d.status] ?? d.status}</Pil> : <Pil key="s" kind="grey">Not uploaded</Pil>,
            d.filename ? <a key="f" href={`/api/bff/api/v1/jupeb/me/documents/${d.kind}/content`} target="_blank" rel="noreferrer">{d.filename}</a> : "—",
            day(d.uploaded_at),
            <span key="a" className="row" style={{ gap: "var(--s-1)", justifyContent: "center" }}>
              {can ? (
                <label className="btn btn--secondary btn--sm" style={{ cursor: busy ? "wait" : "pointer" }}>
                  {busy === d.kind ? "Uploading…" : d.filename ? "Replace" : "Upload"}
                  <input type="file" hidden accept={d.image ? "image/jpeg,image/png" : "application/pdf,image/jpeg,image/png"} onChange={(e) => void upload(d, e.target.files?.[0])} disabled={!!busy} />
                </label>
              ) : null}
              {me.editable && d.filename ? <Btn kind="ghost" onClick={() => void act(`/api/v1/jupeb/me/documents/${d.kind}`, "DELETE")}>Remove</Btn> : null}
            </span>,
          ];
        })} />
      </PBody>
    </Panel>
  );
}

function Payments({ me, reload }: { me: Candidate; reload: () => Promise<void> }) {
  const [ref, setRef] = useState<{ reference: string; amount: number; kind: string } | null>(null);
  const [busy, setBusy] = useState(false);
  async function prepare(kind: string) {
    setBusy(true);
    try {
      const r = await jcall<{ reference: string; amount: number; kind: string }>(`/api/v1/jupeb/me/fee-reference?kind=${kind}`, "POST");
      if (!r.ok) { notifyProblem(r.problem); return; }
      setRef(r.data);
    } finally { setBusy(false); }
  }
  async function checkNow(reference: string) {
    setBusy(true);
    try {
      await jcall("/api/v1/payments/verify", "POST", { reference });
      await reload();
    } finally { setBusy(false); }
  }
  const f = me.fees;
  const admitted = ADMITTED.has(me.state);
  const screeningFirst = me.screeningSetting.screening_required && me.state === "ADMITTED" && me.screening_state !== "CLEARED";
  return (
    <div className="stack">
      <Panel title="Application fee" right={me.fee_confirmed_at ? <Pil kind="ok">Paid {day(me.fee_confirmed_at)}</Pil> : <Pil kind="warn">Unpaid</Pil>}>
        <PBody>
          {me.fee_confirmed_at ? <p className="sub2">Your application fee of {naira(me.references.find((x) => x.kind === "APPLICATION" && x.confirmed_at)?.amount ?? me.application_fee)} is confirmed.</p> : (
            ref?.kind === "APPLICATION" ? (
              <>
                <PayByCard reference={ref.reference} amount={Number(ref.amount)} />
                <div className="row mt-2"><Btn kind="go" disabled={busy} onClick={() => void checkNow(ref.reference)}>{busy ? "Checking…" : "I’ve paid — check now"}</Btn><span className="sub2">Reference <b className="tnum">{ref.reference}</b></span></div>
              </>
            ) : <Btn kind="primary" disabled={busy} onClick={() => void prepare("APPLICATION")}>Pay the application fee ({naira(me.application_fee)})</Btn>
          )}
        </PBody>
      </Panel>
      <Panel title="School fees" right={admitted ? <Pil kind={stateKind(f.status)}>{f.status.replace("_", " ").toLowerCase()}</Pil> : null}>
        <PBody>
          {!admitted ? <p className="sub2">School fees are paid once you are admitted.</p> : (
            <>
              <KvGrid pairs={[
                ["Category", `${feeCategoryLabel(f.category)} · ${f.indigene ? `${me.feeRule.indigene_state} indigene` : "non-indigene"}`],
                ["School fee", naira(f.total)], ["Paid", naira(f.paid)], ["Outstanding", naira(f.outstanding)],
                [`First semester (${Number(f.first_percent)}%)`, `${naira(f.first_amount)}${f.first_paid ? " · paid" : ""}`],
                [`Second semester (${100 - Number(f.first_percent)}%)`, `${naira(f.second_amount)}${f.second_paid ? " · paid" : ""}`],
              ]} />
              {screeningFirst ? <Note kind="info" title="Screening first">School fees open once you are cleared at screening. See the Admission tab.</Note> : f.status !== "PAID" ? (
                <div className="mt-3">
                  {ref && ref.kind !== "APPLICATION" ? (
                    <>
                      <div className="sub2 mb-2">{FEE_KIND[ref.kind]} — {naira(ref.amount)}</div>
                      <PayByCard reference={ref.reference} amount={Number(ref.amount)} />
                      <div className="row mt-2"><Btn kind="go" disabled={busy} onClick={() => void checkNow(ref.reference)}>{busy ? "Checking…" : "I’ve paid — check now"}</Btn><span className="sub2">Reference <b className="tnum">{ref.reference}</b></span></div>
                    </>
                  ) : (
                    <div className="row">
                      {!f.first_paid ? <Btn kind="primary" disabled={busy} onClick={() => void prepare("SCHOOL_FIRST")}>Pay first semester ({naira(f.first_amount)})</Btn> : null}
                      {f.first_paid && !f.second_paid ? <Btn kind="primary" disabled={busy} onClick={() => void prepare("SCHOOL_SECOND")}>Pay second semester ({naira(f.second_amount)})</Btn> : null}
                      {f.allow_full && Number(f.paid) === 0 ? <Btn kind="secondary" disabled={busy} onClick={() => void prepare("SCHOOL_FULL")}>Pay in full ({naira(f.total)})</Btn> : null}
                    </div>
                  )}
                </div>
              ) : null}
              {me.state === "ADMITTED" ? <p className="hint mt-2">Your studentship is activated when {me.feeRule.activation === "FULL" ? "the full school fee" : "the first semester's share"} is paid.</p> : null}
            </>
          )}
        </PBody>
      </Panel>
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

function Admission({ me }: { me: Candidate }) {
  const sc = me.screeningSetting;
  return (
    <div className="stack">
      <Panel title="Admission decision">
        <PBody>
          {me.admission_decided_at ? (
            <Note kind={ADMITTED.has(me.state) ? "ok" : me.state === "NOT_ADMITTED" ? "bad" : "info"} title={ADMITTED.has(me.state) ? `Admitted · ${me.admission_ref}` : STATE_LABEL[me.state] ?? me.state}>
              {me.admission_note ?? (ADMITTED.has(me.state) ? "Congratulations on your admission into the University's JUPEB programme." : "")}
            </Note>
          ) : <p className="sub2">The JUPEB Office decides on submitted, eligible applications. Your decision appears here and is sent to your email.</p>}
          <KvGrid pairs={[["Programme", streamLabel(me.stream)], ["Combination", me.combination_code ?? "Chosen at subject registration"], ["Session", me.session]]} cls="grid--3" />
          {ADMITTED.has(me.state) ? <div className="row mt-3"><LinkBtn kind="primary" href="/jupeb/pdf/letter">Download admission letter</LinkBtn></div> : null}
        </PBody>
      </Panel>
      {ADMITTED.has(me.state) && (sc.screening_required || me.screening_state) ? (
        <Panel title="Screening" right={me.screening_state ? <Pil kind={stateKind(me.screening_state)}>{SCREENING_LABEL[me.screening_state] ?? me.screening_state}</Pil> : null}>
          <PBody>
            <KvGrid pairs={[["Venue", me.screening_venue ?? sc.screening_venue ?? "—"], ["When", me.screening_at ? when(me.screening_at) : sc.screening_starts_on ? `${day(sc.screening_starts_on)} – ${day(sc.screening_ends_on)}` : "—"]]} />
            {sc.screening_instructions ? <p className="mt-2" style={{ whiteSpace: "pre-line" }}>{sc.screening_instructions}</p> : null}
            {me.screening_reason ? <Note kind={me.screening_state === "CLEARED" ? "ok" : "bad"} title="From the screening desk">{me.screening_reason}</Note> : null}
          </PBody>
        </Panel>
      ) : null}
    </div>
  );
}

function Subjects({ me, act }: { me: Candidate; act: Act }) {
  const [busy, setBusy] = useState(false);
  const [choice, setChoice] = useState<string>(me.combination_id ?? "");
  const offered = me.combinations ?? [];
  const chosen = offered.find((c) => c.id === choice) ?? null;
  const open = me.state === "STUDENT" && !me.subjects_registered_at;
  const rows = me.registered.length ? me.registered.map((r) => [r.code, r.title])
    : chosen ? [[chosen.subject1_code, chosen.subject1], [chosen.subject2_code, chosen.subject2], [chosen.subject3_code, chosen.subject3]]
    : me.subjects.map((s) => [s.code, s.title]);
  return (
    <Panel title="Subject registration" right={me.subjects_registered_at ? <Pil kind="ok">Registered {day(me.subjects_registered_at)}</Pil> : null}>
      <PBody>
        <KvGrid pairs={[["Programme", streamLabel(me.stream)], ["Combination", me.combination_code ?? (chosen ? chosen.code : "Not yet chosen")], ["Class", me.class_name ?? "Not yet placed"], ["JUPEB examination number", me.exam_no ?? "Not yet assigned"]]} />
        {open ? (
          <Field id="s-comb" label={`Your subject combination (${streamLabel(me.stream)})`} hint={offered.length ? "Choose the three subjects you will study and be examined in." : "No combination is open for your programme yet; the JUPEB Office will add them."}>
            <select id="s-comb" className="ctl" value={choice} onChange={(e) => setChoice(e.target.value)} disabled={!offered.length}>
              <option value="">— Choose a combination —</option>
              {offered.map((c) => <option key={c.id} value={c.id}>{c.code} — {c.subject1}, {c.subject2}, {c.subject3}</option>)}
            </select>
          </Field>
        ) : null}
        {rows.length ? <DTable noPrint pageSize={0} cols={["Code", "Subject"]} rows={rows} /> : null}
        {open ? (
          <div className="row mt-3"><Btn kind="primary" disabled={busy || !choice} onClick={() => { setBusy(true); void act("/api/v1/jupeb/me/register-subjects", "POST", { combination: choice }).finally(() => setBusy(false)); }}>{busy ? "Registering…" : "Register these three subjects"}</Btn></div>
        ) : me.state === "ADMITTED" ? <p className="hint mt-2">You choose your combination and register your subjects once your school fee activates your studentship.</p> : null}
        {me.subjects_registered_at ? <div className="row mt-3"><LinkBtn kind="ghost" href="/jupeb/pdf/slip">Download registration slip</LinkBtn></div> : null}
      </PBody>
    </Panel>
  );
}

function Results({ me }: { me: Candidate }) {
  if (!me.resultsPublished) return <Note kind="info" title="Results not yet published">Your JUPEB results appear here once the JUPEB Office publishes them. You will be told by email.</Note>;
  const total = me.registered.reduce((n, r) => n + Number(r.points ?? 0), 0);
  return (
    <Panel title="JUPEB results" right={<LinkBtn kind="ghost" href="/jupeb/pdf/result">Download statement</LinkBtn>}>
      <PBody>
        <KvGrid pairs={[["Examination number", me.exam_no ?? "—"], ["Combination", me.combination_code ?? "—"], ["Total points", String(total)], ["Session", me.session]]} />
        <DTable noPrint pageSize={0} cols={["Code", "Subject", "Grade|mid", "Points|num"]} rows={me.registered.map((r) => [r.code, r.title, r.grade ?? "—", r.points ?? "—"])} />
      </PBody>
    </Panel>
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

function Bare({ children }: { children: React.ReactNode }) {
  return <div style={{ maxWidth: 640, margin: "var(--s-6) auto", padding: "0 var(--s-4)", display: "grid", gap: "var(--s-3)" }}>{children}</div>;
}
