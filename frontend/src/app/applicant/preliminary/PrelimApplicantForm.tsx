"use client";

/**
 * The Preliminary Science application (V446), as the applicant works through it: the application fee first (the form opens once
 * the payment is verified by the payment service — never on returning from the gateway); the details; the O'Level in one sitting
 * or two, each released (an awaiting result is not accepted), with the eligibility the backend reads from it; the target programme,
 * chosen among the configured ones, an intended progression only; the documents; then the declaration and the submission, and
 * the application form to print or download. Once submitted the application is the Preliminary Science Office's: it changes only
 * when the Office asks for a correction.
 */
import { useEffect, useState, type ReactNode } from "react";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { confirmedReference, openReference } from "@/lib/applicant";
import { ACTION, BODIES, ELIGIBILITY, EXAM_TYPES, GRADES, REMEDIATION, STATE, SUBJECTS, TARGET_NOTE, fileBase64, labelOf, naira, pcall, remediationWords, when,
         type PrelimOlevel, type PrelimView } from "@/lib/preliminary";
import { PayByCard } from "../common";
import { ReceiptCheck } from "@/components/ReceiptCheck";
import { applicantReceiptTitle } from "@/lib/applicant-receipt";

/** the PDF papers are route handlers, not pages: plain links, opened in a new tab */
const FORM_PDF = "/applicant/preliminary/pdf/form";
const LETTER_PDF = "/applicant/preliminary/pdf/letter";

interface Sitting { exam_body: string; exam_type: string; exam_number: string; exam_year: string; subjects: { subject: string; grade: string }[] }

function sittingsOf(rows: PrelimOlevel[]): Sitting[] {
  const out: Sitting[] = [];
  for (const n of [1, 2]) {
    const r = rows.filter((o) => o.sitting === n);
    if (r.length) out.push({ exam_body: r[0].exam_body, exam_type: r[0].exam_type ?? "SSCE", exam_number: r[0].exam_number, exam_year: String(r[0].exam_year), subjects: r.map((o) => ({ subject: o.subject, grade: o.grade })) });
  }
  return out.length ? out : [{ exam_body: "WAEC", exam_type: "SSCE", exam_number: "", exam_year: "",
    subjects: ["English Language", "Mathematics", "Chemistry", "Physics", "Biology"].map((s) => ({ subject: s, grade: "" })) }];
}

export function PrelimApplicantForm() {
  const [v, setV] = useState<PrelimView | null>(null);
  const [tick, setTick] = useState(0);
  const [busy, setBusy] = useState<string | null>(null);
  const [fields, setFields] = useState<Record<string, string> | null>(null);
  const [sex, setSex] = useState("");
  const [sittings, setSittings] = useState<Sitting[] | null>(null);
  const [target, setTarget] = useState("");
  const [declared, setDeclared] = useState(false);
  useEffect(() => {
    let live = true;
    void pcall<PrelimView>("/api/v1/applicant/me/preliminary").then((r) => {
      if (!live) return;
      if (r.ok) {
        setV(r.data);
        setFields(Object.fromEntries(r.data.preliminary.fields.map((f) => [f.field, f.value ?? ""])));
        setSex(r.data.preliminary.sex ?? "");
        setSittings(sittingsOf(r.data.preliminary.olevel));
        setTarget(r.data.preliminary.targetProgramme ?? "");
      } else notifyProblem(r.problem);
    });
    return () => { live = false; };
  }, [tick]);
  if (!v || !fields || !sittings) return <Note kind="info" title="Reading your Preliminary Science application…">One moment.</Note>;

  const p = v.preliminary;
  const info = p.programmeInfo;
  const state = p.state;
  const editable = p.editable;
  const asked = state === "CORRECTION_REQUIRED";
  const problems = p.problems;
  const byStep = (s: string) => problems.filter((x) => x.step === s);
  const fee = v.fees.applicationFee == null ? null : Number(v.fees.applicationFee);
  const paid = confirmedReference(v, "APPLICATION");
  const open = openReference(v, "APPLICATION");
  const settled = p.feeSettled;
  const formOpen = editable && settled;
  const twoSittings = sittings.length === 2;
  const doc = (kind: string) => v.documents.find((d) => d.kind === kind) ?? null;
  const docKinds = info.documents.filter((d) => !d.secondSittingOnly || twoSittings);
  const elig = p.eligibility;
  const [eligWord, eligKind] = labelOf(ELIGIBILITY, elig.status);
  const published = state === "ADMITTED" || ((state === "NOT_ADMITTED" || state === "REJECTED") && v.decisionReleasedAt);

  async function call(key: string, method: "POST" | "PUT", path: string, body: unknown, reason: string) {
    setBusy(key);
    try {
      const r = await pcall<PrelimView>(`/api/v1/applicant${path}`, method, body, reason);
      if (!r.ok) { notifyProblem(r.problem); return false; }
      notify(reason);
      setTick((t) => t + 1);
      return true;
    } finally { setBusy(null); }
  }
  async function upload(kind: string, file: File | null) {
    if (!file) return;
    if ((kind === "PASSPORT" || kind === "PASSPORT_2") && file.type !== "image/jpeg") { notifyProblem({ status: 422, title: "A passport photograph is a JPEG image (.jpg)" }); return; }
    if (file.size > 2 * 1024 * 1024) { notifyProblem({ status: 422, title: `The file is ${Math.round(file.size / 1024)} KB; 2 MB at most` }); return; }
    const label = info.documents.find((d) => d.kind === kind)?.label ?? kind;
    await call(`doc-${kind}`, "POST", "/me/documents", { kind, filename: file.name, contentType: file.type, contentBase64: await fileBase64(file) }, `${label} uploaded`);
  }

  const head = (
    <>
      <Tiles cls="grid--4" items={[
        ["APPLICATION", v.applicationNo, null, `Preliminary Science · ${v.session}`],
        ["STATE", labelOf(STATE, state)[0], null, p.submittedAt ? `submitted ${when(p.submittedAt)}` : "not yet submitted"],
        ["ELIGIBILITY", eligWord, eligKind === "bad" ? "var(--red-ink)" : eligKind === "warn" ? "var(--amber-ink)" : null, elig.sittings ? `${elig.totalCredits} credits · ${elig.coreCredits} core` : "no result given yet"],
        ["STILL NEEDED", editable ? problems.length : 0, editable && problems.length ? "var(--amber-ink)" : null, editable ? (problems.length ? "before you can submit" : "ready to submit") : "with the Office"],
      ]} />
      {asked ? <Note kind="bad" title="The Preliminary Science Office asks for a correction">{p.requestNote} Make it below, then send the application back to the Office.</Note> : null}
      {state === "ADMITTED" ? (
        <Note kind="ok" title="You are admitted into the Preliminary Science Programme"
          action={<a className="btn btn--primary btn--sm" href={LETTER_PDF} target="_blank" rel="noopener">Print your admission letter</a>}>
          {p.targetName ? <>Your intended progression is {info.targets.find((t) => t.programmeCode === p.targetProgramme)?.name ?? p.targetName}. </> : null}{TARGET_NOTE}
          {p.remediation.status === "REQUIRED" ? <> Before completing the programme you are to make up: <b>{remediationWords(p.remediation)}</b>.</> : null}
        </Note>
      ) : published ? (
        <Note kind="bad" title="Your application was not successful">{v.decisionNote ?? "The outcome of your application is published."}</Note>
      ) : !editable && state !== "WITHDRAWN" ? (
        <Note kind="info" title="Your application is with the Preliminary Science Office"
          action={<a className="btn btn--secondary btn--sm" href={FORM_PDF} target="_blank" rel="noopener">Print your application form</a>}>
          The Office reviews it. You are told here and by email if anything more is needed, and when the outcome is published.
        </Note>
      ) : state === "WITHDRAWN" ? <Note kind="info" title="This application was withdrawn">It is kept on the record and cannot be continued.</Note> : null}
    </>
  );

  const section = (n: number, title: string, step: string, body: ReactNode) => {
    const missing = byStep(step);
    return (
      <Panel title={`${n} · ${title}`} right={missing.length ? <Pil kind="warn">{missing.length} to do</Pil> : <Pil kind="ok">Done</Pil>}>
        <PBody>
          {editable && !settled && step !== "PAYMENT" ? <Note kind="info" title="Pay the application fee first">This part of the form opens once your payment is verified.</Note> : null}
          {missing.length && editable && (settled || step === "PAYMENT") ? <div className="sub2 mb-2">{missing.map((x) => x.message).join("; ")}.</div> : null}
          {body}
        </PBody>
      </Panel>
    );
  };

  const groups = [...new Set(info.targets.map((t) => t.group))];

  return (
    <>
      {head}
      {section(1, "Application fee", "PAYMENT", paid ? (
        <>
          <div className="b700 mb-1">{applicantReceiptTitle("APPLICATION", "PRELIMINARY")}</div>
          <div className="mb-2">Paid <b>{naira(paid.amount)}</b> · <span className="tnum">{paid.reference}</span> · receipt {paid.receiptNo ?? "—"} · verified {when(paid.confirmedAt)}</div>
          <ReceiptCheck reference={paid.reference} source={`/api/bff/api/v1/applicant/me/receipts/${encodeURIComponent(paid.reference)}`}
            pdf={`/applicant/fee/receipt?reference=${encodeURIComponent(paid.reference)}`} />
        </>
      ) : !v.fees.stated || fee == null ? (
        <div className="sub2">The Bursary has not yet stated the Preliminary Science application fee for {v.session}.</div>
      ) : fee === 0 ? <div className="sub2">No application fee is charged.</div> : (
        <>
          <div className="mb-2">Preliminary Science application fee <b>{naira(fee)}</b>. Pay it first: the rest of the form opens once the payment is verified.</div>
          {open ? <div className="mb-2">Your reference: <b className="tnum">{open.reference}</b> (expires {when(open.expiresAt)}). Pay it on the gateway, or at a bank quoting it.</div> : null}
          <div className="row row--inline row--tight">
            {open ? <PayByCard reference={open.reference} amount={fee} /> : null}
            {!open ? <Btn kind="primary" disabled={busy !== null} onClick={() => void call("ref", "POST", "/me/fee-references", { kind: "APPLICATION" }, "Application fee reference generated")}>{busy === "ref" ? "Generating…" : `Generate a reference for ${naira(fee)}`}</Btn> : null}
          </div>
        </>
      ))}

      {section(2, "Your details", "PERSONAL", (
        <>
          <KvGrid cls="grid--3" pairs={[["Name", v.name], ["Application number", v.applicationNo], ["Email (your account)", v.email]]} />
          <div className="grid grid--3 mt-2">
            <Field id="ps-sex" label="Sex" required>
              <select id="ps-sex" className="ctl" disabled={!formOpen} value={sex} onChange={(e) => setSex(e.target.value)}><option value="">Choose…</option><option value="F">Female</option><option value="M">Male</option></select>
            </Field>
            {p.fields.map((f) => (
              <Field key={f.field} id={`ps-${f.field}`} label={f.label ?? f.field.replace(/_/g, " ")} required={f.required}>
                {f.field === "date_of_birth"
                  ? <input id={`ps-${f.field}`} type="date" className="ctl" disabled={!formOpen} value={fields[f.field] ?? ""} onChange={(e) => setFields({ ...fields, [f.field]: e.target.value })} />
                  : f.field === "home_address" || f.field === "kin_address" || f.field === "postal_address"
                    ? <textarea id={`ps-${f.field}`} className="ctl" rows={2} disabled={!formOpen} value={fields[f.field] ?? ""} onChange={(e) => setFields({ ...fields, [f.field]: e.target.value })} />
                    : <input id={`ps-${f.field}`} className="ctl" disabled={!formOpen} value={fields[f.field] ?? ""} onChange={(e) => setFields({ ...fields, [f.field]: e.target.value })} />}
              </Field>
            ))}
          </div>
          {formOpen ? <Btn kind="primary" disabled={busy !== null} onClick={() => void call("bio", "PUT", "/me/preliminary/biodata", { fields, sex: sex || null }, "Your details saved")}>{busy === "bio" ? "Saving…" : "Save your details"}</Btn> : null}
        </>
      ))}

      {section(3, "O'Level results", "OLEVEL", (
        <>
          <Note kind="info" title={`At least ${info.rules.minCredits} credits in at most ${info.rules.maxSittings} sitting${info.rules.maxSittings === 1 ? "" : "s"}; ${info.rules.minCoreCredits} of them in ${info.rules.coreSubjects.join(", ")}`}>
            Give results already released. An awaiting result is not accepted for Preliminary Science.
          </Note>
          <div className={`grid grid--${twoSittings ? "2" : "3"} mt-2`}>
            {sittings.map((s, i) => (
              <div key={i} className="card" style={{ padding: 10 }}>
                <div className="row row--inline row--tight mb-2" style={{ justifyContent: "space-between" }}><b>Sitting {i + 1}</b>
                  {formOpen && i === 1 ? <Btn kind="ghost" onClick={() => setSittings([sittings[0]])}>Remove the second sitting</Btn> : null}</div>
                <div className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
                  <Field id={`ol-b${i}`} label="Examination body"><select id={`ol-b${i}`} className="ctl" disabled={!formOpen} value={s.exam_body} onChange={(e) => setSittings(sittings.map((x, j) => (j === i ? { ...x, exam_body: e.target.value } : x)))}>{BODIES.map(([k, n]) => <option key={k} value={k}>{n}</option>)}</select></Field>
                  <Field id={`ol-t${i}`} label="Examination"><select id={`ol-t${i}`} className="ctl" disabled={!formOpen} value={s.exam_type} onChange={(e) => setSittings(sittings.map((x, j) => (j === i ? { ...x, exam_type: e.target.value } : x)))}>{EXAM_TYPES.map(([k, n]) => <option key={k} value={k}>{n}</option>)}</select></Field>
                  <Field id={`ol-n${i}`} label="Examination number"><input id={`ol-n${i}`} className="ctl tnum" disabled={!formOpen} value={s.exam_number} onChange={(e) => setSittings(sittings.map((x, j) => (j === i ? { ...x, exam_number: e.target.value } : x)))} /></Field>
                  <Field id={`ol-y${i}`} label="Year"><input id={`ol-y${i}`} className="ctl tnum" inputMode="numeric" maxLength={4} style={{ maxWidth: 90 }} disabled={!formOpen} value={s.exam_year} onChange={(e) => setSittings(sittings.map((x, j) => (j === i ? { ...x, exam_year: e.target.value.replace(/[^0-9]/g, "") } : x)))} /></Field>
                </div>
                <datalist id="ps-subjects">{SUBJECTS.map((x) => <option key={x} value={x} />)}</datalist>
                {s.subjects.map((g, k) => (
                  <div key={k} className="row row--inline row--tight mb-1">
                    <input className="ctl" list="ps-subjects" aria-label={`Sitting ${i + 1} subject ${k + 1}`} disabled={!formOpen} value={g.subject} style={{ flex: 1 }}
                      onChange={(e) => setSittings(sittings.map((x, j) => (j === i ? { ...x, subjects: x.subjects.map((y, m) => (m === k ? { ...y, subject: e.target.value } : y)) } : x)))} />
                    <select className="ctl" aria-label={`Sitting ${i + 1} grade ${k + 1}`} disabled={!formOpen} value={g.grade} style={{ width: 80 }}
                      onChange={(e) => setSittings(sittings.map((x, j) => (j === i ? { ...x, subjects: x.subjects.map((y, m) => (m === k ? { ...y, grade: e.target.value } : y)) } : x)))}>
                      <option value="">Grade</option>{GRADES.map((gr) => <option key={gr} value={gr}>{gr}</option>)}
                    </select>
                    {formOpen ? <Btn kind="ghost" aria-label="Remove the subject" onClick={() => setSittings(sittings.map((x, j) => (j === i ? { ...x, subjects: x.subjects.filter((_, m) => m !== k) } : x)))}>×</Btn> : null}
                  </div>
                ))}
                {formOpen && s.subjects.length < 9 ? <Btn kind="ghost" onClick={() => setSittings(sittings.map((x, j) => (j === i ? { ...x, subjects: [...x.subjects, { subject: "", grade: "" }] } : x)))}>Add a subject</Btn> : null}
              </div>
            ))}
          </div>
          {formOpen ? (
            <div className="row row--inline mt-2">
              {!twoSittings && info.rules.maxSittings >= 2 ? <Btn kind="ghost" onClick={() => setSittings([...sittings, { exam_body: "NECO", exam_type: "SSCE", exam_number: "", exam_year: "", subjects: [{ subject: "", grade: "" }] }])}>Add a second sitting</Btn> : null}
              <Btn kind="primary" disabled={busy !== null} onClick={() => void call("ol", "PUT", "/me/preliminary/olevel", {
                sittings: sittings.map((s, i) => ({ sitting: i + 1, exam_body: s.exam_body, exam_type: s.exam_type, exam_number: s.exam_number.trim(), exam_year: s.exam_year,
                  subjects: s.subjects.filter((x) => x.subject.trim() || x.grade).map((x) => ({ subject: x.subject.trim(), grade: x.grade })) })),
              }, "Your O'Level saved")}>{busy === "ol" ? "Saving…" : "Save your O'Level"}</Btn>
            </div>
          ) : null}
          {elig.sittings ? (
            <div className="card mt-2" style={{ padding: 10 }}>
              <div className="row row--inline row--tight mb-1"><b>Your eligibility, on the results you gave</b><Pil kind={eligKind as "ok"}>{eligWord}</Pil></div>
              <DTable noPrint pageSize={0} cols={["Requirement", "Required|num", "Yours|num", ""]} rows={elig.checks.map((c) => [
                c.label, c.required == null ? "—" : `${c.atMost ? "at most " : ""}${c.required}`, c.held == null ? "—" : String(c.held),
                <Pil key="ok" kind={c.ok ? "ok" : "bad"}>{c.ok ? "Met" : "Not met"}</Pil>])} />
              {elig.reasons.length ? <ul className="sub2">{elig.reasons.map((r) => <li key={r}>{r}</li>)}</ul> : null}
              {p.remediation.status === "REQUIRED" ? <div className="mt-1">Remediation before completing the programme: <b>{remediationWords(p.remediation)}</b> ({labelOf(REMEDIATION, p.remediation.status)[0].toLowerCase()}).</div> : null}
              <div className="sub2 mt-1">The Preliminary Science Office verifies your results against your documents; the decision is the University&rsquo;s.</div>
            </div>
          ) : null}
        </>
      ))}

      {section(4, "Target programme", "PROGRAMME", (
        <>
          <div className="sub2 mb-2">{TARGET_NOTE}</div>
          <div className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
            <div style={{ minWidth: 320, flex: 1 }}>
              <SearchSelect id="ps-target" value={target} onChange={setTarget} disabled={!formOpen} placeholder="Choose the programme you intend to progress to"
                options={groups.flatMap((g) => info.targets.filter((t) => t.group === g).map((t) => ({ value: t.programmeCode, label: t.name, sub: g })))} />
            </div>
            {formOpen ? <Btn kind="primary" disabled={busy !== null || !target || target === p.targetProgramme} onClick={() => void call("target", "PUT", "/me/preliminary/target", { programmeCode: target }, "Target programme saved")}>{busy === "target" ? "Saving…" : "Save the target programme"}</Btn> : null}
          </div>
          {p.targetName ? <div className="mt-1">Chosen: <b>{info.targets.find((t) => t.programmeCode === p.targetProgramme)?.name ?? p.targetName}</b></div> : null}
        </>
      ))}

      {section(5, "Documents", "DOCUMENTS", (
        <DTable noPrint pageSize={0} cols={["Document", "Uploaded", "Checked by the Office", ""]} rows={docKinds.map((k) => {
          const d = doc(k.kind);
          return [
            <span key="k"><b>{k.label}</b>{k.required ? null : <span className="sub2"> (optional)</span>}<div className="sub2">{k.hint ?? (k.kind.startsWith("PASSPORT") ? "A recent JPEG photograph, plain background" : "PDF, JPEG or PNG · 2 MB at most")}</div></span>,
            d ? <span key="u">{d.filename}<div className="sub2">{when(d.uploadedAt)}</div></span> : <span key="u" className="sub2">not yet</span>,
            d ? <span key="s"><Pil kind={d.status === "ACCEPTED" ? "ok" : d.status === "REJECTED" ? "bad" : "grey"}>{d.status === "PENDING" ? "Not yet checked" : d.status === "ACCEPTED" ? "Accepted" : "Rejected — replace it"}</Pil>{d.reviewNote ? <div className="sub2">{d.reviewNote}</div> : null}</span> : <span key="s" />,
            formOpen ? <label key="x" className="btn btn--ghost btn--sm" style={{ cursor: "pointer" }}>{d ? "Replace" : "Upload"}
              <input type="file" hidden accept={k.kind.startsWith("PASSPORT") ? "image/jpeg" : "application/pdf,image/jpeg,image/png"} onChange={(e) => void upload(k.kind, e.target.files?.[0] ?? null)} /></label> : <span key="x" />,
          ];
        })} />
      ))}

      {editable ? (
        <Panel title={asked ? "6 · Send it back to the Office" : "6 · Declaration and submission"}>
          <PBody>
            <label className="row row--inline row--tight mb-2"><input type="checkbox" checked={declared} onChange={(e) => setDeclared(e.target.checked)} />
              I declare that the particulars I have given are true and that my O&rsquo;Level results are released results. I understand that a false statement or document ends the application, and any admission that follows from it.</label>
            <div className="row row--inline">
              <Btn kind="go" size="md" disabled={busy !== null || !declared || problems.length > 0} onClick={() => void call("submit", "POST", "/me/submit", { declaration: true }, asked ? "Your application is sent back to the Office" : "Your Preliminary Science application is submitted")}>
                {busy === "submit" ? "Sending…" : asked ? "Send it back to the Office" : "Submit my application"}</Btn>
              {problems.length ? <span className="sub2">{problems.length} thing{problems.length === 1 ? "" : "s"} still to do above.</span> : null}
            </div>
          </PBody>
        </Panel>
      ) : null}

      <Panel title="Your application form" right={<span className="row row--inline row--tight">
        <a className="btn btn--secondary btn--sm" href={FORM_PDF} target="_blank" rel="noopener">View or print</a>
        <a className="btn btn--ghost btn--sm" href={`${FORM_PDF}?download=1`}>Download PDF</a></span>}>
        <PBody><div className="sub2">The form carries your passport, details, O&rsquo;Level results, target programme, payment and documents. Print it and take it, with the photocopies asked for, to the Preliminary Science Office where the University asks for physical submission.</div></PBody>
      </Panel>

      <Panel title="What has happened">
        <DTable noPrint pageSize={0} cols={["When", "What"]} rows={p.events.map((e) => [
          <span key="w" className="tnum">{when(e.at)}</span>,
          <span key="a">{ACTION[e.action] ?? e.action}{e.note ? <div className="sub2">{e.note}</div> : null}</span>,
        ])} />
      </Panel>
      {["DRAFT", "SUBMITTED", "CORRECTION_REQUIRED"].includes(state) ? (
        <div className="row row--inline"><Btn kind="ghost" disabled={busy !== null} onClick={() => { if (window.confirm("Withdraw this application? It cannot be continued afterwards.")) void call("withdraw", "POST", "/me/preliminary/withdraw", { note: "Withdrawn by the applicant" }, "Your application is withdrawn"); }}>Withdraw my application</Btn></div>
      ) : null}
      <div className="sub2">Questions about your application go to the Preliminary Science Office, quoting {v.applicationNo}.</div>
    </>
  );
}
