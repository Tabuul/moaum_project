"use client";

/** The online screening form (V269), as the Registry's paper forms ask it: the personal data on record and the fields to
 *  complete, the institutions attended, the O'Level results as JAMB sent them (to confirm or correct), the sponsor and the
 *  parent or guardian, the next of kin, the documents, the declaration. Saved as a draft, submitted once complete, then
 *  read-only until an officer returns it. The outcome, and — when unsuccessful — the change of programme, live here too. */
import React, { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { DOC_WORD, SECTION_WORD, STATE_WORD, whenAt, type Institution, type OlevelRow, type ScreeningView } from "@/lib/screening";
import { Eligibility } from "./Eligibility";
import { Tracker } from "./Admission";
import { parseTracker } from "@/lib/screening";

const SECTIONS = ["personal", "origin", "contact", "family", "kin", "education", "health", "bank"];
const GRADES = ["A1", "B2", "B3", "C4", "C5", "C6", "D7", "E8", "F9"];

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
  const [declaration, setDeclaration] = useState(false);
  const [reviewing, setReviewing] = useState(false);
  const [tracker, setTracker] = useState<string | null>(null);

  const load = (j: ScreeningView) => {
    setV(j);
    const a: Record<string, string> = {}; for (const x of j.answers) a[x.field] = x.value; setAnswers(a);
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
    ]).then(([[ok, j], [ok2, j2]]) => {
      if (!live) return;
      if (!ok) setProblem((j as Problem) ?? { status: 0, title: "Could not read the screening form." }); else load(j as ScreeningView);
      if (ok2 && j2) setTracker((j2 as { tracker: string }).tracker);
    }).catch(() => { if (live) setProblem({ status: 0, title: "Could not read the screening form." }); });
    return () => { live = false; };
  }, []);

  async function call(path: string, method: "PUT" | "POST", body: unknown, label: string, key: string) {
    setBusy(key); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/applicant/me/screening${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(label) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const pr = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(pr); notifyProblem(pr); return false; }
      load(j as ScreeningView); notify(label); return true;
    } finally { setBusy(null); }
  }
  const save = () => call("", "PUT", { answers, institutions, olevel, membership }, "Screening form saved", "save");
  const submit = async () => { const ok = await call("/submit", "POST", { declaration }, "Screening form submitted", "submit"); if (ok) { setReviewing(false); router.refresh(); } };
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

  if (problem && !v) return <ProblemNotice problem={problem} />;
  if (!v) return <Panel title="Online screening"><PBody><div className="sub2">Reading…</div></PBody></Panel>;
  if (!v.required) return <>{fallback ?? <Note kind="info" title="No online screening is required for your session">Document clearance is at the Registry, in person.</Note>}</>;
  const f = v.form;
  const p = v.prefill;
  if (!f) return <Note kind="info" title="The screening opens when you have accepted your offer">Accept the offer and pay the acceptance fee; the screening form opens here at once.</Note>;
  const editable = f.state === "DRAFT" || f.state === "RETURNED";
  const set = (k: string, val: string) => { setAnswers((a) => ({ ...a, [k]: val })); setDirty(true); };
  const docKinds = [...new Set([...(v.policy?.required_documents ?? []), ...Object.keys(DOC_WORD).filter((k) => !(v.policy?.required_documents ?? []).includes(k))])];
  const docOf = (kind: string) => v.documents.find((d) => d.kind === kind && d.status !== "REJECTED") ?? v.documents.find((d) => d.kind === kind);
  const isReq = (field: string) => (v.policy?.required_fields ?? []).includes(field);
  const fieldsIn = (section: string) => v.fields.filter((x) => x.section === section && x.tier !== "locked" && !["legacy_appno", "university_email", "senatorial_district"].includes(x.field));

  return (
    <>
      <Panel title={`Screening of fresh undergraduate students · ${f.screening_no}`} right={<Pil kind={STATE_WORD[f.state][1]}>{STATE_WORD[f.state][0]}</Pil>}>
        <PBody>
          <div className="sub2">Every fresh undergraduate must undergo screening by the Screening Committee before registration as a student. Complete the form below with the information the University keeps on record shown first; the originals of your qualifications, your UTME result slip, your certificate of state of origin and your birth certificate or declaration of age are uploaded here and may be called for in person.{v.policy?.instructions ? ` ${v.policy.instructions}` : ""}</div>
          {tracker ? <div className="mt-2"><Tracker steps={parseTracker(tracker)} compact /></div> : null}
        </PBody>
      </Panel>
      {problem ? <ProblemNotice problem={problem} /> : null}

      {f.state === "RETURNED" ? <Note kind="bad" title="Returned for correction">{f.returned_note} — correct it below and submit again.</Note> : null}
      {f.state === "SUBMITTED" || f.state === "UNDER_REVIEW" ? <Note kind="info" title={`Submitted ${whenAt(f.submitted_at)} · version ${f.version}`}>Your form is with the screening officers. It is read-only now; you are told the outcome here and by email.</Note> : null}
      {f.state === "SUCCESSFUL" ? (
        <Note kind="ok" title="Screening result: you have been successfully screened" action={<LinkBtn kind="primary" href="/applicant/admission">Next step</LinkBtn>}>
          You can go ahead and pay school fees and commence registration using your admission number. Decided {whenAt(f.decided_at)}{f.decided_office ? ` · ${f.decided_office}` : ""}.{f.remarks ? ` Remarks: ${f.remarks}` : ""}
        </Note>
      ) : null}
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

      {/* ── Section A: personal data ── */}
      <Panel title="Section A · Personal data" right="On record from JAMB and your application">
        <PBody>
          <KvGrid cls="grid--4" pairs={[["Surname", p.surname], ["Other names", p.other_names], ["JAMB registration number", <span key="j" className="tnum">{p.jamb_reg_no}</span>], ["Session", p.session],
            ["Sex", p.sex ?? "—"], ["Date of birth", p.date_of_birth ?? "—"], ["State of origin (JAMB)", p.state_of_origin ?? "—"], ["LGA (JAMB)", p.lga ?? "—"],
            ["Course admitted into", p.programme], ["Faculty", p.faculty ?? "—"], ["Department", p.department ?? "—"], ["Mode of admission", p.entry_mode.replace("_", " ")],
            ["Email", p.email], ["Phone", <span key="ph" className="tnum">{p.phone}</span>], ["Next of kin (application form)", p.next_of_kin ?? "—"], ["Application number", <span key="an" className="tnum">{p.application_no}</span>]]} />
        </PBody>
      </Panel>
      {SECTIONS.map((section) => {
        const fs = fieldsIn(section);
        if (!fs.length) return null;
        return (
          <Panel key={section} title={SECTION_WORD[section] ?? section} right={`${fs.filter((x) => (answers[x.field] ?? "").trim()).length} of ${fs.length} filled`}>
            <PBody>
              <div className="grid grid--3 rfgrid">
                {fs.map((x) => (
                  <Field key={x.field} id={`sf-${x.field}`} label={x.label} hint={x.hint ?? undefined} required={isReq(x.field)} full={!!x.wide}>
                    {x.wide ? <textarea id={`sf-${x.field}`} className="ctl" rows={2} value={answers[x.field] ?? ""} disabled={!editable} onChange={(e) => set(x.field, e.target.value)} />
                      : <input id={`sf-${x.field}`} className="ctl" value={answers[x.field] ?? ""} disabled={!editable} onChange={(e) => set(x.field, e.target.value)} autoComplete="off" />}
                  </Field>
                ))}
              </div>
            </PBody>
          </Panel>
        );
      })}

      {/* ── Section B: institutions attended ── */}
      <Panel title="Section B · Academic record — institutions attended with dates and qualifications obtained" right={editable ? <Btn kind="ghost" size="sm" onClick={() => { setInstitutions([...institutions, { name: "", from_year: null, to_year: null, certificate: "", award_year: null }]); setDirty(true); }}>Add a row</Btn> : `${institutions.length} row(s)`}>
        <DTable pageSize={0} cols={["S/N|num", "Name of institution", "From|mid", "To|mid", "Certificate awarded", "Year of award|mid", "|num"]} rows={institutions.map((it, i) => [
          <span key="sn" className="tnum sub2">{i + 1}</span>,
          <input key="n" className="ctl" value={it.name} disabled={!editable} onChange={(e) => { const c = [...institutions]; c[i] = { ...it, name: e.target.value }; setInstitutions(c); setDirty(true); }} aria-label={`Institution ${i + 1}`} />,
          <input key="f" className="ctl tnum" style={{ width: 90 }} value={it.from_year ?? ""} disabled={!editable} onChange={(e) => { const c = [...institutions]; c[i] = { ...it, from_year: e.target.value ? Number(e.target.value) : null }; setInstitutions(c); setDirty(true); }} aria-label="From year" />,
          <input key="t" className="ctl tnum" style={{ width: 90 }} value={it.to_year ?? ""} disabled={!editable} onChange={(e) => { const c = [...institutions]; c[i] = { ...it, to_year: e.target.value ? Number(e.target.value) : null }; setInstitutions(c); setDirty(true); }} aria-label="To year" />,
          <input key="c" className="ctl" value={it.certificate ?? ""} disabled={!editable} onChange={(e) => { const c = [...institutions]; c[i] = { ...it, certificate: e.target.value }; setInstitutions(c); setDirty(true); }} aria-label="Certificate" placeholder="FSLC, SSCE, NCE…" />,
          <input key="y" className="ctl tnum" style={{ width: 90 }} value={it.award_year ?? ""} disabled={!editable} onChange={(e) => { const c = [...institutions]; c[i] = { ...it, award_year: e.target.value ? Number(e.target.value) : null }; setInstitutions(c); setDirty(true); }} aria-label="Year of award" />,
          editable ? <Btn key="x" kind="ghost" size="sm" onClick={() => { setInstitutions(institutions.filter((_, k) => k !== i)); setDirty(true); }}>Remove</Btn> : <span key="x" />,
        ])} />
      </Panel>

      {/* ── Section C: O'Level results ── */}
      <Panel title="Section C · Academic record — O'Level results with dates" right={editable ? <Btn kind="ghost" size="sm" onClick={() => { setOlevel([...olevel, { exam_body: "WAEC", exam_number: olevel[olevel.length - 1]?.exam_number ?? "", exam_year: olevel[olevel.length - 1]?.exam_year ?? null, subject: "", grade: "C6" }]); setDirty(true); }}>Add a subject</Btn> : `${olevel.length} subject(s)`}>
        <PBody><div className="sub2">The results below began as JAMB sent them to the University; confirm them, correct a grade or an examination number where the certificate differs, and add a second sitting where you have one. The Registry verifies every result with the examination body; the eligibility engine reads JAMB&rsquo;s record.</div></PBody>
        <DTable pageSize={0} cols={["S/N|num", "Exam type / body", "Subject", "Exam number", "Grade|mid", "Year of award|mid", "|num"]} rows={olevel.map((r, i) => [
          <span key="sn" className="tnum sub2">{i + 1}</span>,
          <select key="b" className="ctl" value={r.exam_body} disabled={!editable} onChange={(e) => { const c = [...olevel]; c[i] = { ...r, exam_body: e.target.value }; setOlevel(c); setDirty(true); }} aria-label="Examination body">{["WAEC", "NECO", "NABTEB", "OTHER"].map((b) => <option key={b}>{b}</option>)}</select>,
          <input key="s" className="ctl" value={r.subject} disabled={!editable} onChange={(e) => { const c = [...olevel]; c[i] = { ...r, subject: e.target.value }; setOlevel(c); setDirty(true); }} aria-label="Subject" />,
          <input key="n" className="ctl tnum" value={r.exam_number ?? ""} disabled={!editable} onChange={(e) => { const c = [...olevel]; c[i] = { ...r, exam_number: e.target.value }; setOlevel(c); setDirty(true); }} aria-label="Examination number" />,
          <select key="g" className="ctl" value={r.grade} disabled={!editable} onChange={(e) => { const c = [...olevel]; c[i] = { ...r, grade: e.target.value }; setOlevel(c); setDirty(true); }} aria-label="Grade">{GRADES.map((g) => <option key={g}>{g}</option>)}</select>,
          <input key="y" className="ctl tnum" style={{ width: 90 }} value={r.exam_year ?? ""} disabled={!editable} onChange={(e) => { const c = [...olevel]; c[i] = { ...r, exam_year: e.target.value ? Number(e.target.value) : null }; setOlevel(c); setDirty(true); }} aria-label="Year of award" />,
          editable ? <Btn key="x" kind="ghost" size="sm" onClick={() => { setOlevel(olevel.filter((_, k) => k !== i)); setDirty(true); }}>Remove</Btn> : <span key="x" />,
        ])} />
        {v.jambOlevel.length ? <PBody><div className="sub2">As JAMB sent it: {v.jambOlevel.map((x) => `${x.subject} ${x.grade}`).join(", ")}{v.jambOlevel[0]?.exam_body ? ` (${v.jambOlevel[0].exam_body}${v.jambOlevel[0].exam_year ? ` ${v.jambOlevel[0].exam_year}` : ""})` : ""}.</div></PBody> : null}
        <PBody><Field id="sf-membership" label="Membership of any association, club, union, society etc."><input id="sf-membership" className="ctl" value={membership} disabled={!editable} onChange={(e) => { setMembership(e.target.value); setDirty(true); }} /></Field></PBody>
      </Panel>

      {/* ── documents ── */}
      <Panel title="Documents" right={`${(v.policy?.required_documents ?? []).filter((k) => docOf(k)).length} of ${(v.policy?.required_documents ?? []).length} required uploaded`}>
        <PBody><div className="sub2">PDF, JPEG or PNG, at most 2 MB each. A document an officer rejected is replaced by uploading it again. The originals are brought when the screening committee calls for them.</div></PBody>
        <DTable pageSize={0} cols={["Document", "Required|mid", "Uploaded", "Status|mid", "|num"]} rows={docKinds.map((k) => { const d = docOf(k); const req = (v.policy?.required_documents ?? []).includes(k); return [
          <span key="d"><b>{DOC_WORD[k] ?? k}</b></span>, req ? <Pil key="r" kind="warn">Required</Pil> : <span key="r" className="sub2">Optional</span>,
          <span key="u" className="sub2">{d ? <>{d.filename} · {Math.round(d.bytes / 1024)} KB · {whenAt(d.uploaded_at)}{d.review_note ? <div className="ink-red">{d.review_note}</div> : null}</> : "—"}</span>,
          d ? <Pil key="s" kind={d.status === "ACCEPTED" ? "ok" : d.status === "REJECTED" ? "bad" : "info"}>{d.status}</Pil> : <Pil key="s" kind="grey">NOT UPLOADED</Pil>,
          editable || !d ? <label key="x" className="btn btn--secondary btn--sm" style={{ cursor: "pointer", margin: 0 }}>{busy === k ? "Uploading…" : d ? "Replace" : "Upload"}<input type="file" accept=".pdf,.jpg,.jpeg,.png,application/pdf,image/jpeg,image/png" style={{ display: "none" }} disabled={busy !== null || !editable} onChange={(e) => { const file = e.target.files?.[0]; if (file) void upload(k, file); e.target.value = ""; }} /></label> : <span key="x" />,
        ]; })} />
      </Panel>

      {editable ? (
        <Panel title="Declaration and submission" right={v.missing.length ? <Pil kind="warn">{v.missing.length} item(s) outstanding</Pil> : <Pil kind="ok">Complete</Pil>}>
          <PBody>
            {v.missing.length ? <Note kind="info" title="Still required before submission">{v.missing.map((m) => m.label).join(" · ")}</Note> : null}
            <div className="row row--inline row--tight mt-2">
              <Btn kind="secondary" disabled={busy !== null} onClick={() => void save()}>{busy === "save" ? "Saving…" : dirty ? "Save draft" : "Saved"}</Btn>
              <Btn kind="primary" disabled={busy !== null} onClick={async () => { if (dirty) { const ok = await save(); if (!ok) return; } setDeclaration(false); setReviewing(true); }}>Review and submit</Btn>
            </div>
          </PBody>
        </Panel>
      ) : null}
      {v.events.length ? <Panel title="Trail" right={`${v.events.length} entries`}><PBody>{v.events.slice(0, 12).map((e, i) => <div key={i} className="sub2"><span className="tnum">{whenAt(e.at)}</span> · <b>{e.action.replace(/_/g, " ").toLowerCase()}</b>{e.detail ? ` · ${e.detail}` : ""}{e.actor_office ? ` · ${e.actor_office}` : ""}</div>)}</PBody></Panel> : null}

      {reviewing ? (
        <Modal title="Review and submit your screening form" sub={`${f.screening_no} · read-only after submission until an officer returns it`} wide onClose={() => setReviewing(false)}
          foot={<><Btn kind="ghost" onClick={() => setReviewing(false)}>Back</Btn><span className="grow" /><Btn kind="primary" disabled={busy !== null || !declaration || v.missing.length > 0} onClick={() => void submit()}>{busy === "submit" ? "Submitting…" : "Submit the screening form"}</Btn></>}>
          {v.missing.length ? <Note kind="bad" title="The form is not complete">{v.missing.map((m) => m.label).join(" · ")}</Note> : null}
          {SECTIONS.map((section) => { const fs = fieldsIn(section).filter((x) => (answers[x.field] ?? "").trim()); return fs.length ? <div key={section} className="mb-2"><div className="eyebrow mb-1">{SECTION_WORD[section]}</div><KvGrid cls="grid--3" pairs={fs.map((x) => [x.label, answers[x.field]] as [string, string])} /></div> : null; })}
          <div className="eyebrow mb-1">O&rsquo;Level results</div>
          <div className="sub2 mb-2">{olevel.map((r) => `${r.subject} ${r.grade} (${r.exam_body}${r.exam_year ? ` ${r.exam_year}` : ""})`).join(", ") || "None"}</div>
          <div className="eyebrow mb-1">Documents</div>
          <div className="sub2 mb-2">{v.documents.filter((d) => d.status !== "REJECTED").map((d) => DOC_WORD[d.kind] ?? d.kind).join(", ") || "None"}</div>
          <Note kind="info" title="Declaration">
            I, <b>{p.other_names} {p.surname}</b>, hereby declare that the information given on this form is to the best of my knowledge correct, and that I am bound by the Ordinances, Statutes and Regulations of the University, and that if at any time it is discovered that any of the information provided is false or incorrect, I will be required to withdraw from the institution or be liable to prosecution or both.
          </Note>
          <label className="row row--tight mt-2" style={{ gap: 8 }}><input type="checkbox" className="pchk" checked={declaration} onChange={(e) => setDeclaration(e.target.checked)} /> I accept the declaration above.</label>
        </Modal>
      ) : null}
    </>
  );
}
