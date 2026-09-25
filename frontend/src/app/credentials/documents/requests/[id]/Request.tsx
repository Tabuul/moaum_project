"use client";

/** One document request (V262): the student and what was asked; payment; the academic validation with its findings; the statement
 *  the document will carry, previewed course by course; generation as a versioned document; the quality check — approve, ask for a
 *  correction, reject; the Registrar's release; the deliveries recorded; the timeline. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Btn, KvGrid, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, Steps } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { DELIVERY_STATE, EVENT_WORDS, PAYMENT, STAGE, callDocs, dayOf, naira, parseStatement, semesterName, verifyPathFor, whenAt, type RequestFull, type Validation } from "@/lib/documents";

const OFFICE = ["academic", "registrar", "dregistrar", "records"];
const SIGNERS = ["registrar", "dregistrar", "academic"];

export function RequestScreen({ r, office, actor }: { r: RequestFull; office: string | null; actor: string | null }) {
  const router = useRouter();
  const may = !!office && OFFICE.includes(office);
  const signer = !!office && SIGNERS.includes(office);
  const [busy, setBusy] = useState(false);
  const [ask, setAsk] = useState<"qc" | "cancel" | "delivery" | null>(null);
  const [decision, setDecision] = useState("APPROVED");
  const [note, setNote] = useState("");
  const [dl, setDl] = useState<{ id: string; state: string; courier: string; tracking: string; note: string } | null>(null);
  const validation = r.validation ? (JSON.parse(r.validation) as Validation) : null;
  const preview = parseStatement(r.document?.statement ?? r.preview);
  const stageAt = ["AWAITING_PAYMENT", "READY", "PROCESSING", "GENERATED", "VERIFIED", "RELEASED", "DELIVERED", "COMPLETED"].indexOf(r.stage === "HELD_AT_CLEARANCE" ? "READY" : r.stage === "CORRECTION" ? "PROCESSING" : r.stage);
  const st = (i: number) => (r.stage === "REJECTED" || r.stage === "CANCELLED" ? (i < stageAt ? "done" : "todo") : i < stageAt ? "done" : i === stageAt ? "now" : "todo");

  async function run<T>(p: Promise<{ ok: true; data: T } | { ok: false; problem: import("@/lib/api").Problem }>, done: string): Promise<T | null> {
    setBusy(true);
    try { const x = await p; if (!x.ok) { notifyProblem(x.problem); return null; } notify(done); setAsk(null); setNote(""); router.refresh(); return x.data; } finally { setBusy(false); }
  }
  const start = () => run(callDocs("POST", `/documents/requests/${r.id}/start`, {}, `Start processing ${r.ref}`), "Validation recorded");
  const generate = () => run<{ number: string }>(callDocs("POST", `/documents/requests/${r.id}/generate`, {}, `Generate the document for ${r.ref}`), "Document generated");
  const qc = () => { if (decision !== "APPROVED" && !note.trim()) { notifyProblem({ status: 422, title: "Say why." }); return; } return run(callDocs("POST", `/documents/requests/${r.id}/qc`, { decision, note: note || null }, `Quality check ${r.ref}: ${decision}`), `Quality check: ${decision.toLowerCase()}`); };
  const release = () => run(callDocs("POST", `/documents/requests/${r.id}/release`, {}, `Release ${r.ref}`), "Released; the student is told");
  const cancel = () => run(callDocs("POST", `/documents/requests/${r.id}/cancel`, { reason: note || null }, `Cancel ${r.ref}`), "Request cancelled");
  const complete = () => run(callDocs("POST", `/documents/requests/${r.id}/complete`, {}, `Complete ${r.ref}`), "Request completed");
  const saveDelivery = () => { if (!dl) return; return run(callDocs("POST", `/documents/deliveries/${dl.id}`, { state: dl.state, courier: dl.courier || null, tracking: dl.tracking || null, note: dl.note || null }, `Delivery ${dl.state.toLowerCase()} for ${r.ref}`), "Delivery updated"); };
  const resend = (id: string) => run(callDocs("POST", `/documents/deliveries/${id}/resend`, {}, `Resend the secure link for ${r.ref}`), "Link resent");

  return (
    <>
      <div className="row row--tight sub2" style={{ gap: 6 }}><Link className="lnk" href="/credentials/documents">Documents office</Link><span>›</span><Link className="lnk" href="/credentials/documents/requests">Requests</Link><span>›</span><strong>{r.ref}</strong></div>
      <PageHead title={<>{r.ref} <Pil kind={STAGE[r.stage]?.[1] ?? "grey"}>{STAGE[r.stage]?.[0] ?? r.stage}</Pil>{r.breaching ? <Pil kind="bad">Breaching SLA</Pil> : null}</>} description={`${r.kind_label}${r.session ? ` · ${r.session}` : ""}${r.semester ? ` · ${semesterName(r.semester)}` : ""} for ${r.student_name} (${r.student_number}) · ${r.programme ?? "—"} · ${r.department ?? "—"} · ${r.faculty ?? "—"}. Requested ${whenAt(r.requested_at)}${r.sla_due_on ? `, due ${dayOf(r.sla_due_on)}` : ""}.`}
        actions={<>
          {may && ["READY", "HELD_AT_CLEARANCE", "CORRECTION"].includes(r.stage) ? <Btn kind="secondary" onClick={() => void start()} disabled={busy || !r.paid_at}>Validate the record</Btn> : null}
          {may && ["READY", "PROCESSING", "CORRECTION", "HELD_AT_CLEARANCE"].includes(r.stage) ? <Btn kind="primary" onClick={() => void generate()} disabled={busy || !r.paid_at || (validation ? !validation.ok : false)}>Generate the document</Btn> : null}
          {may && r.stage === "GENERATED" ? <Btn kind="primary" onClick={() => { setDecision("APPROVED"); setNote(""); setAsk("qc"); }}>Quality check</Btn> : null}
          {signer && r.stage === "VERIFIED" ? <Btn kind="primary" onClick={() => void release()} disabled={busy || r.produced_by === actor} title={r.produced_by === actor ? "The officer who produced a document does not release it" : undefined}>Authorise and release</Btn> : null}
          {may && ["RELEASED", "DELIVERED"].includes(r.stage) ? <Btn kind="secondary" onClick={() => void complete()} disabled={busy}>Mark completed</Btn> : null}
          {may && ["AWAITING_PAYMENT", "READY", "HELD_AT_CLEARANCE"].includes(r.stage) ? <Btn kind="ghost" onClick={() => { setNote(""); setAsk("cancel"); }}>Cancel</Btn> : null}
          {r.issued_id && r.document_status === "ACTIVE" ? <a className="btn btn--ghost btn--sm" href={`/credentials/documents/register/${r.issued_id}/pdf`} target="_blank" rel="noopener">Document PDF</a> : null}
          <LinkBtn kind="ghost" href={`/students/${r.student_id}`}>Student record</LinkBtn>
        </>} />

      <Steps list={[[st(0), "Payment", r.paid_at ? whenAt(r.paid_at) : r.fee ? naira(r.fee) : "No fee"], [st(1), "Ready", r.stage === "HELD_AT_CLEARANCE" ? "Held at clearance" : ""], [st(2), "Validation", r.validated_at ? whenAt(r.validated_at) : ""], [st(3), "Generated", r.produced_at ? whenAt(r.produced_at) : ""], [st(4), "Quality check", r.qc_at ? whenAt(r.qc_at) : ""], [st(5), "Released", r.released_at ? whenAt(r.released_at) : ""], [st(6), "Delivered", r.delivered_at ? whenAt(r.delivered_at) : ""], [st(7), "Completed", r.completed_at ? whenAt(r.completed_at) : ""]]} />

      {r.stage === "AWAITING_PAYMENT" ? <Note kind="info" title={`Awaiting payment of ${naira(r.fee)}`}>Reference {r.reference ?? "—"}; processing begins when the Bursary or the gateway confirms it.</Note> : null}
      {r.stage === "HELD_AT_CLEARANCE" ? <Note kind="bad" title="Held at clearance">A unit holds the student; the transcript is generated once every unit clears. The student&rsquo;s clearance screen names the unit.</Note> : null}
      {r.stage === "CORRECTION" ? <Note kind="bad" title="Correction asked at the quality check">{r.qc_note}. Put the record right, validate again, and generate a new version.</Note> : null}
      {r.stage === "REJECTED" || r.stage === "CANCELLED" ? <Note kind="bad" title={`${STAGE[r.stage]?.[0]}${r.closed_at ? ` on ${dayOf(r.closed_at)}` : ""}`}>{r.closed_reason ?? r.qc_note ?? ""}</Note> : null}
      {validation ? (
        <Note kind={validation.ok ? "ok" : "bad"} title={validation.ok ? `The record validates (${validation.published} published result(s)${validation.unpublished ? `, ${validation.unpublished} unpublished` : ""})` : "The record does not validate"}>
          {validation.findings.length ? validation.findings.map((f, i) => <span className="blk" key={i}><Pil kind={f.severity === "ERROR" ? "bad" : "warn"}>{f.severity.toLowerCase()}</Pil> {f.message}</span>) : "No finding."}
          <span className="blk sub2">Checked {whenAt(validation.checkedAt)}{validation.postgraduate ? " · postgraduate record" : ""}.</span>
        </Note>
      ) : null}

      <div className="grid grid--2">
        <Panel title="The request">
          <PBody>
            <KvGrid cls="grid--2" pairs={[["Document", `${r.kind_label} · ${r.copies} cop${r.copies === 1 ? "y" : "ies"}${r.express ? " · urgent" : ""}`], ["Delivery", `${r.delivery.toLowerCase()}${r.international ? " · international" : ""}`], ["Recipient", r.destination === "SELF" ? "The student" : `${r.destination.toLowerCase().replace("_", " ")}: ${r.destination_name ?? ""}`], ["Recipient contact", [r.recipient_name, r.recipient_department, r.recipient_email].filter(Boolean).join(" · ") || "—"], ["Address", r.recipient_address ?? "—"], ["Their reference", r.recipient_reference ?? "—"], ["Purpose", r.purpose ?? "—"], ["Fee", r.fee ? `${naira(r.fee)} · ${PAYMENT[r.payment_status]?.[0]}${r.receipt_no ? ` · receipt ${r.receipt_no}` : ""}${r.reference ? ` · ${r.reference}` : ""}` : "No fee"]]} />
          </PBody>
        </Panel>
        <Panel title="The document" right={r.document_number ? <span className="tnum">{r.document_number}{r.document_version && r.document_version > 1 ? ` v${r.document_version}` : ""}</span> : "Not yet generated"}>
          <PBody>
            {r.document ? <KvGrid cls="grid--2" pairs={[["Number", r.document_number ?? ""], ["Status", r.document_status ?? ""], ["Verification code", <Link key="v" className="lnk tnum" href={verifyPathFor(r.verification_code ?? "")}>{r.verification_code}</Link>], ["Issued", dayOf(r.document.issued_on)], ["Template", `version ${r.document.template_version ?? "—"}`], ["Versions", r.versions.map((v) => `v${v.version} ${v.status.toLowerCase()}`).join(", ")]]} /> : <div className="sub2">The statement below is what the document will carry once generated; it is read from the record at generation.</div>}
          </PBody>
        </Panel>
      </div>

      {preview ? (
        <Panel title={r.document ? "The generated statement, for the quality check" : "Preview of the record"} right={`${preview.holder} · ${preview.matricNo}`}>
          <PBody>
            <KvGrid cls="grid--4" pairs={[["Programme", preview.programme], ["Department", preview.department ?? "—"], ["Faculty", preview.faculty ?? "—"], ["Award", preview.award ?? "—"], ["Entry", `${preview.entrySession ?? ""} · ${preview.entryMode ?? ""}`], ["Standing", preview.standing ?? ""], ["CGPA", preview.cgpa !== undefined ? Number(preview.cgpa).toFixed(2) : "—"], ["Class", preview.classOfDegree ?? "—"], ["Graduation", preview.graduationSession ? `${preview.graduationSession}${preview.graduationMinute ? ` · ${preview.graduationMinute}` : ""}` : "—"], ["Scope", `${preview.scope ?? ""}${preview.session ? ` · ${preview.session}` : ""}`], ["Postgraduate", preview.postgraduate ? "Yes" : "No"], ["Research", preview.research?.topic ?? "—"]]} />
          </PBody>
          {(preview.sessions ?? []).map((ses) => ses.semesters.map((sem) => (
            <div key={`${ses.session}-${sem.semester}`}>
              <PBody><strong>{ses.session}</strong> · {semesterName(sem.semester)} <span className="sub2">· units {sem.units ?? "—"} · GPA {sem.gpa ?? "—"}{sem.cgpa !== undefined && sem.cgpa !== null ? ` · CGPA ${sem.cgpa}` : ""}</span></PBody>
              <DTable cols={["Code|mid", "Title", "Units|num", "Grade|mid", "Points|num", "Quality|num"]} rows={sem.courses.map((c) => [<span key="c" className="tnum b600">{c.code}</span>, c.title, <span key="u" className="tnum">{c.units}</span>, <strong key="g">{c.grade ?? c.outcome ?? ""}</strong>, <span key="p" className="tnum">{c.points ?? ""}</span>, <span key="q" className="tnum">{c.quality ?? ""}</span>])} />
            </div>
          )))}
        </Panel>
      ) : null}

      {r.deliveries.length ? (
        <Panel title="Deliveries">
          <DTable cols={["Kind|mid", "To", "State|mid", "Courier · tracking", "Link", "Updated|mid", "|num"]} rows={r.deliveries.map((x) => [<span key="k" className="sub2">{x.kind.toLowerCase()}</span>, <span key="t">{x.recipient ?? ""}{x.email ? <div className="sub2">{x.email}</div> : null}{x.address ? <div className="sub2">{x.address}</div> : null}</span>, <Pil key="s" kind={DELIVERY_STATE[x.state]?.[1] ?? "grey"}>{DELIVERY_STATE[x.state]?.[0] ?? x.state}</Pil>, <span key="c" className="sub2">{x.courier ?? ""}{x.tracking_no ? ` · ${x.tracking_no}` : ""}{x.dispatched_on ? ` · ${dayOf(x.dispatched_on)}` : ""}</span>, <span key="l" className="sub2 tnum">{x.token ? `${x.uses}/${x.max_uses} uses · to ${dayOf(x.expires_at)}` : "—"}</span>, <span key="u" className="tnum sub2">{whenAt(x.updated_at)}</span>, may ? <span key="a" className="row row--inline row--tight">{x.kind === "PHYSICAL" ? <Btn kind="ghost" onClick={() => { setDl({ id: x.id, state: x.state === "PROCESSING" ? "DISPATCHED" : x.state === "DISPATCHED" ? "IN_TRANSIT" : "DELIVERED", courier: x.courier ?? "", tracking: x.tracking_no ?? "", note: "" }); setAsk("delivery"); }}>Update</Btn> : x.email ? <Btn kind="ghost" onClick={() => void resend(x.id)}>Resend link</Btn> : <Btn kind="ghost" onClick={() => { setDl({ id: x.id, state: "DELIVERED", courier: "", tracking: "", note: "" }); setAsk("delivery"); }}>Mark</Btn>}</span> : <span key="a" />])} />
        </Panel>
      ) : null}

      <Panel title="Timeline" right={`${r.events.length} step(s)`}>
        <DTable cols={["When|mid", "Step", "Note", "By"]} rows={r.events.map((e) => [<span key="w" className="tnum sub2">{whenAt(e.at)}</span>, <strong key="a">{EVENT_WORDS[e.action] ?? e.action.toLowerCase()}{e.to_state && e.action === "QUALITY_CHECK" ? ` · ${e.to_state.toLowerCase()}` : ""}</strong>, <span key="n" className="sub2">{e.note ?? ""}</span>, <span key="b" className="sub2">{e.actor ?? e.actor_office ?? "portal"}</span>])} />
      </Panel>

      {ask === "qc" ? (
        <Modal title="Quality check" sub="Verify the name, ID, programme, courses, grades, GPA, CGPA, classification and graduation above" onClose={() => setAsk(null)} foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn><Btn kind={decision === "REJECTED" ? "urgent" : "primary"} onClick={() => void qc()} disabled={busy}>Record</Btn></>}>
          <Field id="qc-d" label="Decision"><select id="qc-d" className="ctl" value={decision} onChange={(e) => setDecision(e.target.value)}><option value="APPROVED">Approve — send for the Registrar&rsquo;s release</option><option value="CORRECTION">Request correction — regenerate after the record is put right</option><option value="REJECTED">Reject the request</option></select></Field>
          <Field id="qc-n" label={decision === "APPROVED" ? "Note" : "Reason"} required={decision !== "APPROVED"} full><textarea id="qc-n" className="ctl" rows={3} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
        </Modal>
      ) : ask === "cancel" ? (
        <Modal title={`Cancel ${r.ref}`} onClose={() => setAsk(null)} foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Keep it</Btn><Btn kind="urgent" onClick={() => void cancel()} disabled={busy}>Cancel the request</Btn></>}>
          <Field id="cn-n" label="Reason" full><textarea id="cn-n" className="ctl" rows={3} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
        </Modal>
      ) : ask === "delivery" && dl ? (
        <Modal title="Record the delivery" onClose={() => setAsk(null)} foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void saveDelivery()} disabled={busy}>Save</Btn></>}>
          <div className="grid grid--2">
            <Field id="dl-s" label="State"><select id="dl-s" className="ctl" value={dl.state} onChange={(e) => setDl({ ...dl, state: e.target.value })}>{Object.entries(DELIVERY_STATE).map(([k, v]) => <option key={k} value={k}>{v[0]}</option>)}</select></Field>
            <Field id="dl-c" label="Courier"><input id="dl-c" className="ctl" value={dl.courier} onChange={(e) => setDl({ ...dl, courier: e.target.value })} /></Field>
            <Field id="dl-t" label="Tracking number"><input id="dl-t" className="ctl" value={dl.tracking} onChange={(e) => setDl({ ...dl, tracking: e.target.value })} /></Field>
            <Field id="dl-n" label="Note"><input id="dl-n" className="ctl" value={dl.note} onChange={(e) => setDl({ ...dl, note: e.target.value })} /></Field>
          </div>
        </Modal>
      ) : null}
    </>
  );
}
