"use client";

/** The applicant's screening (V280): nothing to fill but the schools attended. Once the acceptance is settled the University
 *  screens the record it already holds — what JAMB sent, what the application gave, the documents uploaded — and the
 *  applicant waits, enters the schools attended with their dates, or provides the one correction an officer asks for. On
 *  success the official screening forms are generated from the record, numbered and versioned, to view, download and print;
 *  on failure the reason is shown and, where the University permits, the change of programme. The record the officers
 *  screen is shown here as it stands. */
import React, { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Passport } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { DOC_WORD, STATE_WORD, dayOf, parseTracker, whenAt, type Facts, type Institution, type ScreeningView } from "@/lib/screening";
import { Tracker, stepHref, useAdmission } from "./Admission";
import { Eligibility } from "./Eligibility";

const KINDS = ["OLEVEL_STATEMENT", "JAMB_SLIP", "BIRTH_CERT", "LGA_ID", "JAMB_ADMISSION_LETTER", "STATE_OF_ORIGIN", "MARRIAGE_CERT", "CHANGE_OF_NAME", "PREVIOUS_QUALIFICATION", "OTHER"];
const word = (k: string) => k.replace(/_/g, " ").toLowerCase().replace(/^./, (c) => c.toUpperCase());
const val = (v: unknown) => (v == null || v === "" ? "—" : typeof v === "boolean" ? (v ? "Yes" : "No") : String(v));
const EMPTY_ROW: Institution = { name: "", from_year: null, to_year: null, certificate: "", award_year: null };

export function Screening({ fallback }: { fallback?: React.ReactNode }) {
  const router = useRouter();
  const { d: adm } = useAdmission();
  const [v, setV] = useState<ScreeningView | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [kind, setKind] = useState("OLEVEL_STATEMENT");
  const [inst, setInst] = useState<Institution[]>([]);
  const [dirty, setDirty] = useState(false);
  const [tick, setTick] = useState(0);

  useEffect(() => {
    let live = true;
    fetch("/api/bff/api/v1/applicant/me/screening", { cache: "no-store" }).then(async (r) => {
      const j = await r.json().catch(() => null);
      if (!live) return;
      if (!r.ok) { setProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      const view = j as ScreeningView;
      setV(view);
      setInst(view.institutions.length ? view.institutions : [{ ...EMPTY_ROW }, { ...EMPTY_ROW }]);
      setDirty(false);
    }).catch(() => { if (live) setProblem({ status: 0, title: "Could not read your screening." }); });
    return () => { live = false; };
  }, [tick]);

  if (problem) return <ProblemNotice problem={problem} />;
  if (!v) return <Panel title="Screening"><PBody><div className="sub2">Reading your record…</div></PBody></Panel>;
  if (!v.required) return <>{fallback}<Note kind="info" title="No screening is required for your session">Your admission proceeds to school fees once accepted.</Note></>;
  const f = v.form;
  const p = v.prefill;
  const facts: Facts | null = (() => { try { return v.facts ? (JSON.parse(v.facts) as Facts) : null; } catch { return null; } })();
  if (!f) {
    return (
      <Note kind="info" title="The University's screening opens once your acceptance is settled" action={<LinkBtn kind="primary" href="/applicant/admission">Admission progress</LinkBtn>}>
        Accept the offer and pay the acceptance fee; from then on the screening is done by the University on the information it already holds. There is nothing for you to fill.
      </Note>
    );
  }
  const o = adm?.offer;
  const ent = adm?.entitlement;
  const forms = v.forms;
  const editable = ["PENDING", "IN_REVIEW", "CORRECTION_REQUIRED"].includes(f.state);

  async function upload(file: File) {
    setBusy("upload");
    try {
      const b64 = await new Promise<string>((res, rej) => { const fr = new FileReader(); fr.onload = () => res(String(fr.result).split(",")[1] ?? ""); fr.onerror = () => rej(fr.error); fr.readAsDataURL(file); });
      const r = await fetch("/api/bff/api/v1/applicant/me/documents", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Correction: ${kind} uploaded`) },
        body: JSON.stringify({ kind, filename: file.name, contentType: file.type || "application/octet-stream", contentBase64: b64 }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      notify(`${DOC_WORD[kind] ?? kind} uploaded`);
      setTick(tick + 1);
    } finally { setBusy(null); }
  }
  async function corrected() {
    setBusy("corrected");
    try {
      const r = await fetch("/api/bff/api/v1/applicant/me/screening/submit", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Correction provided") }, body: JSON.stringify({ declaration: true }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      notify("Your correction is with the screening officers");
      setTick(tick + 1);
      router.refresh();
    } finally { setBusy(null); }
  }
  async function saveSchools() {
    setBusy("schools");
    try {
      const rows = inst.filter((i) => i.name.trim());
      const r = await fetch("/api/bff/api/v1/applicant/me/screening", { method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Schools attended saved") }, body: JSON.stringify({ institutions: rows }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      notify("Schools attended saved");
      setV(j as ScreeningView);
      setInst((j as ScreeningView).institutions.length ? (j as ScreeningView).institutions : [{ ...EMPTY_ROW }]);
      setDirty(false);
    } finally { setBusy(null); }
  }
  const setRow = (i: number, patch: Partial<Institution>) => { const c = [...inst]; c[i] = { ...c[i], ...patch }; setInst(c); setDirty(true); };
  const num = (x: number | null | undefined, on: (n: number | null) => void, aria: string) => <input className="ctl tnum" style={{ width: 90 }} value={x ?? ""} disabled={!editable} inputMode="numeric" aria-label={aria} onChange={(e) => on(e.target.value ? Number(e.target.value.replace(/[^0-9]/g, "")) : null)} />;

  const id = facts?.identity ?? {};
  const jb = facts?.jamb ?? {};
  const ad = facts?.admission ?? {};
  const pay = facts?.payments ?? {};
  const ol = facts?.olevel ?? [];
  const docs = facts?.documents ?? [];
  const photo = <Passport w={72} h={90} radius={6} src={p.jamb_passport ?? null} alt="Your passport photograph, as JAMB sent it" />;

  return (
    <>
      <Panel title={`Screening · ${f.screening_no}`} right={<Pil kind={STATE_WORD[f.state][1]}>{STATE_WORD[f.state][0]}</Pil>}>
        <PBody>
          <div className="sub2">The University screens your admission on the information JAMB and your application already gave. The only thing asked of you is the schools you attended, with their dates. You are told the outcome here and by email.</div>
          {adm ? <div className="mt-2"><Tracker steps={parseTracker(adm.tracker)} compact /></div> : null}
        </PBody>
      </Panel>

      <Panel title="Acceptance successful" right={<span className="sub2">Congratulations — your acceptance payment has been confirmed</span>}>
        <PBody>
          <div className="row row--between">
            <KvGrid cls="grid--4" pairs={[
              ["Student name", `${p.surname}, ${p.other_names}`], ["Application number", <span key="a" className="tnum">{p.application_no}</span>], ["JAMB registration number", <span key="j" className="tnum">{p.jamb_reg_no}</span>], ["Admission session", p.session],
              ["Faculty", o?.faculty ?? p.faculty ?? "—"], ["Department", o?.department ?? p.department ?? "—"], ["Programme", o?.changed_to ?? p.programme], ["Admission type", `${p.entry_mode.replace("_", " ")}${o?.entry_level ? ` · ${o.entry_level} Level` : ""}`],
              ["Acceptance payment reference", <span key="r" className="tnum">{ent?.reference ?? "—"}</span>], ["Payment date", ent?.confirmed_at ? whenAt(ent.confirmed_at) : "—"],
              ["Acceptance letter", o?.accepted_at ? <a key="l" className="lnk" href="/applicant/status/letter" target="_blank" rel="noopener">Available · view and print</a> : <span key="l" className="sub2">After acceptance</span>],
              ["Admission number", <span key="n" className="tnum">{o?.admission_no ?? "Issued when the screening succeeds"}</span>],
            ]} />
            <span title="Passport photograph, as JAMB sent it">{photo}</span>
          </div>
        </PBody>
      </Panel>

      {f.state === "PENDING" ? <Note kind="info" title="Your admission is awaiting screening">Your information has been received. Please wait for the University&rsquo;s screening process to be completed. Meanwhile, enter the schools you attended below; nothing else is asked of you.</Note> : null}
      {f.state === "IN_REVIEW" ? <Note kind="info" title="Screening in progress">A screening officer has opened your record{f.review_started_at ? ` on ${dayOf(f.review_started_at)}` : ""}. You are told the outcome here and by email.</Note> : null}
      {f.state === "CORRECTION_REQUIRED" ? (
        <>
          <Note kind="bad" title="One correction is required">{f.returned_note}</Note>
          <Panel title="Provide the correction" right="Only what the officer named; nothing else is asked">
            <PBody>
              <div className="grid grid--3">
                <Field id="cor-kind" label="Document to upload or replace"><select id="cor-kind" className="ctl" value={kind} onChange={(e) => setKind(e.target.value)}>{KINDS.map((k) => <option key={k} value={k}>{DOC_WORD[k] ?? word(k)}</option>)}</select></Field>
                <Field id="cor-file" label="File" hint="PDF, JPEG or PNG, at most 2 MB"><input id="cor-file" className="ctl" type="file" accept=".pdf,.jpg,.jpeg,.png,application/pdf,image/jpeg,image/png" disabled={busy !== null} onChange={(e) => { const file = e.target.files?.[0]; if (file) void upload(file); e.target.value = ""; }} /></Field>
              </div>
              <div className="row mt-2"><Btn kind="primary" disabled={busy !== null} onClick={() => void corrected()}>{busy === "corrected" ? "Sending…" : "I have made the correction"}</Btn><span className="sub2">Your record goes back to the screening officers.</span></div>
            </PBody>
          </Panel>
        </>
      ) : null}
      {f.state === "SUCCESSFUL" ? (
        <>
          <Note kind="ok" title="Screening successful" action={<LinkBtn kind="primary" href={stepHref("/student/fees")}>Pay school fees</LinkBtn>}>Congratulations. Your admission screening has been successfully completed{f.decided_at ? ` on ${dayOf(f.decided_at)}` : ""}. The next step is school fees, then course registration.</Note>
          <Panel title="Screening forms" right={forms?.number ? <span className="sub2 tnum">{forms.number} · version {forms.version}{forms.state === "DOWNLOADED" ? ` · opened ${forms.downloads} time${forms.downloads === 1 ? "" : "s"}` : ""}</span> : <span className="sub2">Generated from your record</span>}>
            <PBody>
              <div className="sub2">Your screening forms have been generated from the information the University holds: Form A, the Screening of Fresh Undergraduate Students, Section C, the Supplementary Biodata Form and the Student Data Capture Form. Fields the University does not hold are left blank for you to fill by hand. Each print carries the document number and a verification code.</div>
              <div className="row mt-2">
                <a className="btn btn--primary" href="/applicant/clearance/print" target="_blank" rel="noopener">View</a>
                <a className="btn btn--secondary" href="/applicant/clearance/print?download=1">Download PDF</a>
                <a className="btn btn--ghost" href="/applicant/clearance/print" target="_blank" rel="noopener">Print</a>
                {forms?.state ? <Pil kind={forms.state === "NOT_GENERATED" ? "grey" : "ok"}>{forms.state.replace("_", " ")}</Pil> : null}
              </div>
            </PBody>
          </Panel>
        </>
      ) : null}
      {f.state === "UNSUCCESSFUL" ? (
        <>
          <Note kind="bad" title={`Screening outcome: your screening for ${p.programme} was unsuccessful`}>
            <span className="blk"><b>Reason:</b> {f.decision_reason}</span>{f.remarks ? <span className="blk"><b>Officer&rsquo;s remarks:</b> {f.remarks}</span> : null}
            <span className="blk">You may apply for a change of programme where you are eligible. Your acceptance fee, already paid, remains valid and is not paid again; an approved change takes you straight to school fees.</span>
          </Note>
          {v.changes.some((c) => c.state === "APPROVED") ? (
            <Note kind="ok" title="Programme change approved" action={<LinkBtn kind="primary" href={stepHref("/student/fees")}>Next step: school fees</LinkBtn>}>
              {v.changes.filter((c) => c.state === "APPROVED").map((c) => <span key={c.id} className="blk">Previous programme: {c.from_programme} → New programme: <b>{c.to_programme}</b> · {whenAt(c.decided_at)}</span>)}
              <span className="blk">Your previous verified acceptance payment remains valid. Do not pay the acceptance fee again.</span>
            </Note>
          ) : <Eligibility />}
        </>
      ) : null}

      <Panel title="Schools attended, with dates" right={editable ? <span className="sub2">The one thing you enter: it prints on Section B of your screening forms</span> : <span className="sub2">As entered before the decision</span>}>
        <DTable pageSize={0} cols={["S/N|num", "Name of institution", "From|mid", "To|mid", "Certificate awarded", "Year of award|mid", "|num"]} rows={inst.map((it, i) => [
          <span key="sn" className="tnum sub2">{i + 1}</span>,
          <input key="n" className="ctl" value={it.name} disabled={!editable} onChange={(e) => setRow(i, { name: e.target.value })} aria-label={`Institution ${i + 1}`} placeholder="Primary school, secondary school, college…" />,
          <span key="f">{num(it.from_year, (n) => setRow(i, { from_year: n }), "From year")}</span>,
          <span key="t">{num(it.to_year, (n) => setRow(i, { to_year: n }), "To year")}</span>,
          <input key="c" className="ctl" value={it.certificate ?? ""} disabled={!editable} onChange={(e) => setRow(i, { certificate: e.target.value })} aria-label="Certificate" placeholder="FSLC, SSCE, NCE…" />,
          <span key="y">{num(it.award_year, (n) => setRow(i, { award_year: n }), "Year of award")}</span>,
          editable ? <Btn key="x" kind="ghost" size="sm" onClick={() => { setInst(inst.filter((_, k) => k !== i)); setDirty(true); }}>Remove</Btn> : <span key="x" />,
        ])} />
        {editable ? <PBody><div className="row"><Btn kind="ghost" size="sm" onClick={() => { setInst([...inst, { ...EMPTY_ROW }]); setDirty(true); }}>Add a school</Btn><Btn kind="primary" size="sm" disabled={busy !== null || !dirty} onClick={() => void saveSchools()}>{busy === "schools" ? "Saving…" : dirty ? "Save schools attended" : "Saved"}</Btn></div></PBody> : null}
      </Panel>

      <Panel title="What the University holds on you" right="Read from JAMB, your application and your documents; the officers screen this record">
        <PBody>
          <div className="eyebrow mb-1">Identity</div>
          <KvGrid cls="grid--4" pairs={[["Surname", val(id.surname)], ["Other names", val(id.other_names)], ["Sex", id.sex === "M" ? "Male" : id.sex === "F" ? "Female" : val(id.sex)], ["Date of birth", val(id.date_of_birth)], ["State of origin", val(id.state_of_origin)], ["Local government", val(id.lga)], ["Email", val(id.email)], ["Phone", val(id.phone)], ["Next of kin", val(id.next_of_kin)], ["Photograph", id.passport ? "As JAMB sent it" : "Not received"]]} />
          <div className="eyebrow mt-3 mb-1">JAMB</div>
          <KvGrid cls="grid--4" pairs={[["Registration number", val(jb.jamb_reg_no)], ["UTME aggregate", val(jb.utme_aggregate)], ["UTME subjects", val(jb.utme_subjects)], ["Entry mode", val(jb.entry_mode)], ["Entry level", val(jb.entry_level)], ["Programme on the list", val(jb.programme)], ["Session", val(jb.session)], ["List source", val(jb.list_source)]]} />
          <div className="eyebrow mt-3 mb-1">Admission</div>
          <KvGrid cls="grid--4" pairs={[["Programme", val(ad.programme)], ["Faculty", val(ad.faculty)], ["Department", val(ad.department)], ["Decision", val(ad.decision)], ["Released", ad.decision_released_at ? whenAt(String(ad.decision_released_at)) : "—"], ["Accepted", ad.accepted_at ? whenAt(String(ad.accepted_at)) : "—"], ["Admission number", val(ad.admission_no)], ["Matriculation number", val(ad.matric_no)]]} />
          <div className="eyebrow mt-3 mb-1">O&rsquo;Level results{ol.length ? "" : " — none received from JAMB"}</div>
          {ol.length ? <DTable pageSize={0} cols={["S/N|num", "Exam body", "Subject", "Exam number", "Grade|mid", "Year|mid"]} rows={ol.map((r, i) => [<span key="sn" className="tnum sub2">{i + 1}</span>, val(r.exam_body), val(r.subject), <span key="n" className="tnum">{val(r.exam_number)}</span>, <b key="g">{val(r.grade)}</b>, <span key="y" className="tnum">{val(r.exam_year)}</span>])} /> : null}
          <div className="eyebrow mt-3 mb-1">Documents on record</div>
          {docs.length ? <DTable pageSize={0} cols={["Document", "File", "Status|mid", "Note"]} rows={docs.map((x) => [<b key="k">{DOC_WORD[String(x.kind)] ?? word(String(x.kind))}</b>, <span key="f" className="sub2">{val(x.filename)} · {x.uploaded_at ? dayOf(String(x.uploaded_at)) : ""}</span>, <Pil key="s" kind={x.status === "ACCEPTED" ? "ok" : x.status === "REJECTED" ? "bad" : "info"}>{val(x.status)}</Pil>, <span key="n" className="sub2">{val(x.review_note)}</span>])} /> : <div className="sub2">No document uploaded; none is required unless an officer asks for one.</div>}
          <div className="eyebrow mt-3 mb-1">Payments</div>
          <KvGrid cls="grid--3" pairs={(["APPLICATION", "CHECKING", "ACCEPTANCE"] as const).map((k) => { const x = pay[k]; return [k === "APPLICATION" ? "Application fee" : k === "CHECKING" ? "Admission checking fee" : "Acceptance fee", x ? <span key={k}><span className="tnum">{val(x.reference)}</span> · {x.confirmed_at ? dayOf(String(x.confirmed_at)) : ""}</span> : <span key={k} className="sub2">—</span>] as [string, React.ReactNode]; })} />
        </PBody>
      </Panel>
    </>
  );
}
