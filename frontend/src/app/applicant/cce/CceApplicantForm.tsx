"use client";

/**
 * The CCE application (V379), as the applicant works through it: the details the CCE list gave (read, not typed) and the rest of
 * the form; the O'Level in one sitting or two, each complete; the passport and the result of each sitting; the programme
 * confirmed; the CCE application fee; then the declaration and the submission, and an acknowledgement to print. Once submitted
 * the application is the Centre's: it is changed only when the Centre asks for documents or verification, and sent back to it.
 */
import { useEffect, useState, type ReactNode } from "react";
import Link from "next/link";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { esc, printDocument } from "@/lib/document/html";
import { confirmedReference, openReference, type Application } from "@/lib/applicant";
import { ACTION_LABEL, DOC_LABEL, REVIEW_LABEL, ccall, day, fileBase64, labelOf, naira, when } from "@/lib/cce";
import { PayByCard } from "../common";

interface Listed {
  session: string; jamb_reg_no: string; surname: string; first_name: string; middle_name: string | null; date_of_birth: string; sex: string | null;
  programme_code: string; programme: string; department: string | null; faculty: string | null; duration_years: number; study_mode: string;
  programme_admitting: boolean; centre: string | null; state: string; programme_confirmed_at: string | null; submitted_at: string | null;
  request_note: string | null; requested_at: string | null; published_at: string | null; decision_note: string | null;
}
interface Olevel { sitting: number; exam_body: string; exam_number: string; exam_year: number; subject: string; grade: string }
interface CceView extends Application {
  cce: { listed: Listed; fields: { field: string; required: boolean; label: string | null; value: string | null }[]; olevel: Olevel[];
         problems: { step: string; field: string; message: string }[]; events: { at: string; action: string; to_state: string | null; note: string | null }[] };
}
interface Sitting { exam_body: string; exam_number: string; exam_year: string; subjects: { subject: string; grade: string }[] }

const GRADES = ["A1", "B2", "B3", "C4", "C5", "C6", "D7", "E8", "F9"];
const BODIES: [string, string][] = [["WAEC", "WAEC (WASSCE)"], ["NECO", "NECO (SSCE)"], ["NABTEB", "NABTEB"], ["OTHER", "Another examination body"]];
const SUBJECTS = ["English Language", "Mathematics", "Biology", "Chemistry", "Physics", "Agricultural Science", "Economics", "Government", "Geography", "Literature in English",
  "Christian Religious Studies", "Islamic Religious Studies", "Civic Education", "Commerce", "Financial Accounting", "Further Mathematics", "Technical Drawing", "Data Processing",
  "Computer Studies", "History", "Tiv", "Hausa", "Yoruba", "Igbo", "French", "Fine Art", "Food and Nutrition", "Home Management", "Marketing", "Office Practice"];
const EDITABLE = new Set(["DRAFT", "DOCUMENTS_PENDING", "VERIFICATION_REQUIRED"]);

function sittingsOf(rows: Olevel[]): Sitting[] {
  const out: Sitting[] = [];
  for (const n of [1, 2]) {
    const r = rows.filter((o) => o.sitting === n);
    if (r.length) out.push({ exam_body: r[0].exam_body, exam_number: r[0].exam_number, exam_year: String(r[0].exam_year), subjects: r.map((o) => ({ subject: o.subject, grade: o.grade })) });
  }
  return out.length ? out : [{ exam_body: "WAEC", exam_number: "", exam_year: "", subjects: [{ subject: "English Language", grade: "" }, { subject: "Mathematics", grade: "" }] }];
}

export function CceApplicantForm() {
  const [v, setV] = useState<CceView | null>(null);
  const [tick, setTick] = useState(0);
  const [busy, setBusy] = useState<string | null>(null);
  const [fields, setFields] = useState<Record<string, string> | null>(null);
  const [sittings, setSittings] = useState<Sitting[] | null>(null);
  const [declared, setDeclared] = useState(false);
  useEffect(() => {
    let live = true;
    void ccall<CceView>("/api/v1/applicant/me/cce").then((r) => {
      if (!live) return;
      if (r.ok) {
        setV(r.data);
        setFields(Object.fromEntries(r.data.cce.fields.map((f) => [f.field, f.value ?? ""])));
        setSittings(sittingsOf(r.data.cce.olevel));
      } else notifyProblem(r.problem);
    });
    return () => { live = false; };
  }, [tick]);
  if (!v || !fields || !sittings) return <Note kind="info" title="Reading your CCE application…">One moment.</Note>;

  const l = v.cce.listed;
  const state = l.state;
  const editable = EDITABLE.has(state);
  const asked = state === "DOCUMENTS_PENDING" || state === "VERIFICATION_REQUIRED";
  const problems = v.cce.problems;
  const byStep = (s: string) => problems.filter((p) => p.step === s);
  const total = Number(v.fees.applicationFee ?? 0) + Number(v.fees.portalCharge ?? 0);
  const paid = confirmedReference(v, "APPLICATION");
  const open = openReference(v, "APPLICATION");
  const doc = (kind: string) => v.documents.find((d) => d.kind === kind) ?? null;
  const twoSittings = sittings.length === 2;

  async function call(key: string, method: "POST" | "PUT", path: string, body: unknown, reason: string) {
    setBusy(key);
    try {
      const r = await ccall<CceView>(`/api/v1/applicant${path}`, method, body, reason);
      if (!r.ok) { notifyProblem(r.problem); return false; }
      notify(reason);
      setTick((t) => t + 1);
      return true;
    } finally { setBusy(null); }
  }
  async function upload(kind: string, file: File | null) {
    if (!file) return;
    if (kind === "PASSPORT" && file.type !== "image/jpeg") { notifyProblem({ status: 422, title: "The passport photograph is a JPEG image (.jpg)" }); return; }
    if (file.size > 2 * 1024 * 1024) { notifyProblem({ status: 422, title: `The file is ${Math.round(file.size / 1024)} KB; 2 MB at most` }); return; }
    await call(`doc-${kind}`, "POST", "/me/documents", { kind, filename: file.name, contentType: file.type, contentBase64: await fileBase64(file) }, `${DOC_LABEL[kind] ?? kind} uploaded`);
  }
  function acknowledgement() {
    if (!v) return;
    const rows: [string, string][] = [
      ["Application number", v.applicationNo], ["JAMB number", l.jamb_reg_no], ["Name", `${l.surname}, ${l.first_name}${l.middle_name ? " " + l.middle_name : ""}`],
      ["Date of birth", day(l.date_of_birth)], ["Programme", l.programme], ["Faculty / department", `${l.faculty ?? "—"} / ${l.department ?? "—"}`],
      ["Centre", l.centre ?? "Centre for Continuing Education"], ["Study mode", "Part-time"], ["Session", l.session],
      ["Submitted", l.submitted_at ? when(l.submitted_at) : "not yet submitted"], ["Application fee", paid ? `${naira(paid.amount)} · ${paid.reference}` : "not paid"],
      ["O'Level", sittings!.map((s, i) => `Sitting ${i + 1}: ${s.exam_body} ${s.exam_year} ${s.exam_number} — ${s.subjects.map((x) => `${x.subject} ${x.grade}`).join(", ")}`).join(" | ")],
    ];
    void printDocument("FORM", {
      title: "CCE application acknowledgement", subtitle: `Centre for Continuing Education · ${l.session}`, reference: v.applicationNo,
      bodyHtml: `<table><tbody>${rows.map(([k, val]) => `<tr><th style="text-align:left;width:32%">${esc(k)}</th><td>${esc(val)}</td></tr>`).join("")}</tbody></table>
        <p style="margin-top:12px">This acknowledges the application above. It is not an offer of admission: the Centre reviews every application, and the outcome is published on the portal.</p>`,
    });
  }

  const head = (
    <>
      <Tiles cls="grid--4" items={[
        ["APPLICATION", v.applicationNo, null, `CCE ${l.session}`],
        ["STATE", labelOf(REVIEW_LABEL, state)[0], null, l.submitted_at ? `submitted ${day(l.submitted_at)}` : "not yet submitted"],
        ["PROGRAMME", l.programme_code, null, `${l.programme} · part-time`],
        ["STILL NEEDED", editable ? problems.length : 0, editable && problems.length ? "var(--amber-ink)" : null, editable ? (problems.length ? "before you can submit" : "ready to submit") : "with the Centre"],
      ]} />
      {asked ? (
        <Note kind="info" title={state === "DOCUMENTS_PENDING" ? "The Centre asks for documents" : "The Centre asks for verification"}>
          {l.request_note} Provide it below, then send the application back to the Centre.
        </Note>
      ) : null}
      {l.published_at ? (
        <Note kind={state === "ADMITTED" ? "ok" : "bad"} title={state === "ADMITTED" ? "The outcome of your application is published" : "The outcome of your application is published"}
          action={<LinkBtn kind="primary" href="/applicant/admission">Read it under Admission Status</LinkBtn>}>Open Admission Status to read the outcome and, if you are offered admission, accept it.</Note>
      ) : !editable ? (
        <Note kind="info" title="Your application is with the Centre for Continuing Education" action={<Btn kind="secondary" onClick={acknowledgement}>Print the acknowledgement</Btn>}>
          The Centre reviews it. You are told here and by email if anything more is needed, and when the outcome is published.
        </Note>
      ) : null}
    </>
  );

  const section = (n: number, title: string, step: string, body: ReactNode) => {
    const missing = byStep(step);
    return (
      <Panel title={`${n} · ${title}`} right={missing.length ? <Pil kind="warn">{missing.length} to do</Pil> : <Pil kind="ok">Done</Pil>}>
        <PBody>
          {missing.length && editable ? <div className="sub2 mb-2">{missing.map((p) => p.message).join("; ")}.</div> : null}
          {body}
        </PBody>
      </Panel>
    );
  };

  return (
    <>
      {head}
      {section(1, "Application fee", "PAYMENT", paid ? (
        <div>Paid <b>{naira(paid.amount)}</b> · <span className="tnum">{paid.reference}</span> · confirmed {when(paid.confirmedAt)}</div>
      ) : !v.fees.stated ? (
        <div className="sub2">The Bursary has not yet stated the CCE application fee for {l.session}. You pay before you submit.</div>
      ) : total === 0 ? <div className="sub2">No application fee is charged.</div> : (
        <>
          <div className="mb-2">CCE application fee <b>{naira(v.fees.applicationFee)}</b>{Number(v.fees.portalCharge) ? <> + portal charge {naira(v.fees.portalCharge)}</> : null} = <b>{naira(total)}</b>. No admission checking fee is charged to a CCE applicant.</div>
          {open ? <div className="mb-2">Your reference: <b className="tnum">{open.reference}</b> (expires {when(open.expiresAt)}). Pay it on the gateway, or at a bank quoting it.</div> : null}
          <div className="row row--inline row--tight">
            {open ? <PayByCard reference={open.reference} amount={total} /> : null}
            <Btn kind={open ? "ghost" : "primary"} disabled={busy !== null} onClick={() => void call("ref", "POST", "/me/fee-references", { kind: "APPLICATION" }, "CCE application fee reference generated")}>{busy === "ref" ? "Generating…" : open ? "A new reference" : `Generate a reference for ${naira(total)}`}</Btn>
          </div>
        </>
      ))}

      {section(2, "Your details", "PERSONAL", (
        <>
          <KvGrid cls="grid--4" pairs={[["Name (from the CCE list)", `${l.surname}, ${l.first_name}${l.middle_name ? " " + l.middle_name : ""}`], ["JAMB number", l.jamb_reg_no], ["Sex", l.sex === "F" ? "Female" : l.sex === "M" ? "Male" : "—"], ["Email (your account)", v.email]]} />
          <div className="grid grid--3 mt-2">
            {v.cce.fields.map((f) => (
              <Field key={f.field} id={`cce-${f.field}`} label={f.label ?? f.field.replace(/_/g, " ")} required={f.required}
                hint={f.field === "date_of_birth" ? "As on the CCE list; if the list is wrong, write to the Centre" : undefined}>
                {f.field === "date_of_birth"
                  ? <input id={`cce-${f.field}`} type="date" className="ctl" disabled={!editable} value={fields[f.field] ?? ""} onChange={(e) => setFields({ ...fields, [f.field]: e.target.value })} />
                  : f.field === "home_address" || f.field === "kin_address" || f.field === "postal_address"
                    ? <textarea id={`cce-${f.field}`} className="ctl" rows={2} disabled={!editable} value={fields[f.field] ?? ""} onChange={(e) => setFields({ ...fields, [f.field]: e.target.value })} />
                    : <input id={`cce-${f.field}`} className="ctl" disabled={!editable} value={fields[f.field] ?? ""} onChange={(e) => setFields({ ...fields, [f.field]: e.target.value })} />}
              </Field>
            ))}
          </div>
          {editable ? <Btn kind="primary" disabled={busy !== null} onClick={() => void call("bio", "PUT", "/me/cce/biodata", { fields }, "Your CCE details saved")}>{busy === "bio" ? "Saving…" : "Save your details"}</Btn> : null}
        </>
      ))}

      {section(3, "O'Level", "OLEVEL", (
        <>
          <div className="sub2 mb-2">One sitting or two; a second sitting must be complete. Credits in English Language and Mathematics are required.</div>
          <div className={`grid grid--${twoSittings ? "2" : "3"}`}>
            {sittings.map((s, i) => (
              <div key={i} className="card" style={{ padding: 10 }}>
                <div className="row row--inline row--tight mb-2" style={{ justifyContent: "space-between" }}><b>Sitting {i + 1}</b>
                  {editable && i === 1 ? <Btn kind="ghost" onClick={() => setSittings([sittings[0]])}>Remove the second sitting</Btn> : null}</div>
                <div className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
                  <Field id={`ol-b${i}`} label="Examination body"><select id={`ol-b${i}`} className="ctl" disabled={!editable} value={s.exam_body} onChange={(e) => setSittings(sittings.map((x, j) => (j === i ? { ...x, exam_body: e.target.value } : x)))}>{BODIES.map(([k, n]) => <option key={k} value={k}>{n}</option>)}</select></Field>
                  <Field id={`ol-n${i}`} label="Examination number"><input id={`ol-n${i}`} className="ctl tnum" disabled={!editable} value={s.exam_number} onChange={(e) => setSittings(sittings.map((x, j) => (j === i ? { ...x, exam_number: e.target.value } : x)))} /></Field>
                  <Field id={`ol-y${i}`} label="Year"><input id={`ol-y${i}`} className="ctl tnum" inputMode="numeric" maxLength={4} style={{ maxWidth: 90 }} disabled={!editable} value={s.exam_year} onChange={(e) => setSittings(sittings.map((x, j) => (j === i ? { ...x, exam_year: e.target.value.replace(/[^0-9]/g, "") } : x)))} /></Field>
                </div>
                <datalist id="ol-subjects">{SUBJECTS.map((x) => <option key={x} value={x} />)}</datalist>
                {s.subjects.map((g, k) => (
                  <div key={k} className="row row--inline row--tight mb-1">
                    <input className="ctl" list="ol-subjects" aria-label={`Sitting ${i + 1} subject ${k + 1}`} disabled={!editable} value={g.subject} style={{ flex: 1 }}
                      onChange={(e) => setSittings(sittings.map((x, j) => (j === i ? { ...x, subjects: x.subjects.map((y, m) => (m === k ? { ...y, subject: e.target.value } : y)) } : x)))} />
                    <select className="ctl" aria-label={`Sitting ${i + 1} grade ${k + 1}`} disabled={!editable} value={g.grade} style={{ width: 80 }}
                      onChange={(e) => setSittings(sittings.map((x, j) => (j === i ? { ...x, subjects: x.subjects.map((y, m) => (m === k ? { ...y, grade: e.target.value } : y)) } : x)))}>
                      <option value="">Grade</option>{GRADES.map((gr) => <option key={gr} value={gr}>{gr}</option>)}
                    </select>
                    {editable ? <Btn kind="ghost" aria-label="Remove the subject" onClick={() => setSittings(sittings.map((x, j) => (j === i ? { ...x, subjects: x.subjects.filter((_, m) => m !== k) } : x)))}>×</Btn> : null}
                  </div>
                ))}
                {editable && s.subjects.length < 9 ? <Btn kind="ghost" onClick={() => setSittings(sittings.map((x, j) => (j === i ? { ...x, subjects: [...x.subjects, { subject: "", grade: "" }] } : x)))}>Add a subject</Btn> : null}
              </div>
            ))}
          </div>
          {editable ? (
            <div className="row row--inline mt-2">
              {!twoSittings ? <Btn kind="ghost" onClick={() => setSittings([...sittings, { exam_body: "NECO", exam_number: "", exam_year: "", subjects: [{ subject: "", grade: "" }] }])}>Add a second sitting</Btn> : null}
              <Btn kind="primary" disabled={busy !== null} onClick={() => void call("ol", "PUT", "/me/cce/olevel", {
                sittings: sittings.map((s, i) => ({ sitting: i + 1, exam_body: s.exam_body, exam_number: s.exam_number.trim(), exam_year: s.exam_year, subjects: s.subjects.filter((x) => x.subject.trim() || x.grade).map((x) => ({ subject: x.subject.trim(), grade: x.grade })) })),
              }, "Your O'Level saved")}>{busy === "ol" ? "Saving…" : "Save your O'Level"}</Btn>
            </div>
          ) : null}
        </>
      ))}

      {section(4, "Documents and passport", "DOCUMENTS", (
        <DTable noPrint pageSize={0} cols={["Document", "Uploaded", "Checked by the Centre", ""]} rows={(["PASSPORT", "OLEVEL_STATEMENT", ...(twoSittings ? ["OLEVEL_STATEMENT_2"] : []), "BIRTH_CERT"] as string[]).map((kind) => {
          const d = doc(kind);
          return [
            <span key="k"><b>{DOC_LABEL[kind] ?? kind}</b>{kind === "BIRTH_CERT" ? <span className="sub2"> (optional)</span> : null}<div className="sub2">{kind === "PASSPORT" ? "A recent JPEG photograph, plain background" : "PDF, JPEG or PNG · 2 MB at most"}</div></span>,
            d ? <span key="u">{d.filename}<div className="sub2">{when(d.uploadedAt)}</div></span> : <span key="u" className="sub2">not yet</span>,
            d ? <span key="s"><Pil kind={d.status === "ACCEPTED" ? "ok" : d.status === "REJECTED" ? "bad" : "grey"}>{d.status === "PENDING" ? "Not yet checked" : d.status === "ACCEPTED" ? "Accepted" : "Rejected — replace it"}</Pil>{d.reviewNote ? <div className="sub2">{d.reviewNote}</div> : null}</span> : <span key="s" />,
            editable ? <label key="x" className="btn btn--ghost btn--sm" style={{ cursor: "pointer" }}>{d ? "Replace" : "Upload"}
              <input type="file" hidden accept={kind === "PASSPORT" ? "image/jpeg" : "application/pdf,image/jpeg,image/png"} onChange={(e) => void upload(kind, e.target.files?.[0] ?? null)} /></label> : <span key="x" />,
          ];
        })} />
      ))}

      {section(5, "Programme", "PROGRAMME", (
        <>
          <KvGrid cls="grid--3" pairs={[["Programme", `${l.programme} (${l.programme_code})`], ["Faculty", l.faculty ?? "—"], ["Department", l.department ?? "—"],
            ["Centre", l.centre ?? "Centre for Continuing Education"], ["Study mode", "Part-time · evening lectures"], ["Typical duration", `${l.duration_years} years`]]} />
          <div className="sub2 mt-1">The programme is the one on the CCE list. If it is wrong, write to the Centre before you submit.</div>
          {l.programme_confirmed_at ? <div className="mt-1"><Pil kind="ok">Confirmed {day(l.programme_confirmed_at)}</Pil></div>
            : editable ? <Btn kind="secondary" disabled={busy !== null} onClick={() => void call("prog", "POST", "/me/cce/programme", {}, "Programme confirmed")}>This is my programme</Btn> : null}
        </>
      ))}

      {editable ? (
        <Panel title={asked ? "6 · Send it back to the Centre" : "6 · Declaration and submission"}>
          <PBody>
            <label className="row row--inline row--tight mb-2"><input type="checkbox" checked={declared} onChange={(e) => setDeclared(e.target.checked)} />
              I declare that the particulars I have given are true. I understand that a false statement or document ends the application, and any admission that follows from it.</label>
            <div className="row row--inline">
              <Btn kind="go" size="md" disabled={busy !== null || !declared || problems.length > 0} onClick={() => void call("submit", "POST", "/me/submit", { declaration: true }, asked ? "Your CCE application is sent back to the Centre" : "Your CCE application is submitted")}>
                {busy === "submit" ? "Sending…" : asked ? "Send it back to the Centre" : "Submit my application"}</Btn>
              <Btn kind="ghost" onClick={acknowledgement}>Print a copy</Btn>
              {problems.length ? <span className="sub2">{problems.length} thing{problems.length === 1 ? "" : "s"} still to do above.</span> : null}
            </div>
          </PBody>
        </Panel>
      ) : null}

      <Panel title="What has happened">
        <DTable noPrint pageSize={0} cols={["When", "What"]} rows={v.cce.events.map((e) => [
          <span key="w" className="tnum">{when(e.at)}</span>,
          <span key="a">{ACTION_LABEL[e.action] ?? e.action}{e.note ? <div className="sub2">{e.note}</div> : null}</span>,
        ])} />
      </Panel>
      <div className="sub2">Questions about your application go to the Centre for Continuing Education, quoting {v.applicationNo}. <Link href="/applicant/admission">Admission Status</Link></div>
    </>
  );
}
