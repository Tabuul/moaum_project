"use client";

/** My documents (V262): the certificates and transcripts issued to the student with their status, verification and download;
 *  the requests with payment, stage and delivery, each opening its timeline; and the wizard — document, delivery, recipient,
 *  fee, payment, submit — one step at a time. */
import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Btn, KvGrid, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, Steps } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { DELIVERY_STATE, DESTINATIONS, DOC_STATUS, EVENT_WORDS, KIND, PAYMENT, STAGE, callDocs, dayOf, naira, semesterName, verifyPathFor, whenAt, type DocEvent, type Delivery, type MyDocuments, type Policy, type RequestRow } from "@/lib/documents";
import { PayByCard } from "../common";

type Wizard = { kind: string; session: string; semester: string; delivery: string; destination: string; destinationName: string; department: string; recipientName: string; recipientEmail: string; recipientAddress: string; recipientReference: string; purpose: string; express: boolean; international: boolean; copies: string };
const EMPTY: Wizard = { kind: "TRANSCRIPT", session: "", semester: "", delivery: "DIGITAL", destination: "SELF", destinationName: "", department: "", recipientName: "", recipientEmail: "", recipientAddress: "", recipientReference: "", purpose: "", express: false, international: false, copies: "1" };

export function Documents({ d, open, wizard }: { d: MyDocuments; open: string; wizard: string }) {
  const router = useRouter();
  const [step, setStep] = useState(wizard ? 1 : 0);
  const [w, setW] = useState<Wizard>({ ...EMPTY, kind: wizard && KIND[wizard.toUpperCase()] ? wizard.toUpperCase() : "TRANSCRIPT" });
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState<{ ref: string; fee: number; reference: string | null; stage: string } | null>(null);
  const [timeline, setTimeline] = useState<(RequestRow & { events: DocEvent[]; deliveries: Delivery[] }) | null>(null);
  const [link, setLink] = useState<string | null>(null);
  const pol = (k: string) => d.policies.find((p) => p.kind === k);
  const chosen = pol(w.kind);
  const fee = (p: Policy | undefined) => {
    if (!p || !p.billable) return 0;
    const base = (p.fee_now ?? 0) * Math.max(1, Number(w.copies) || 1);
    return base + (w.express ? Number(p.urgent_fee) : 0) + (w.delivery !== "DIGITAL" ? Number(p.physical_fee) + (w.international ? Number(p.international_fee) : 0) : 0);
  };
  const thirdParty = w.destination !== "SELF";

  useEffect(() => {
    if (!open) return;
    let live = true;
    (async () => {
      const r = await callDocs<RequestRow & { events: DocEvent[]; deliveries: Delivery[] }>("GET", `/me/documents/requests/${open}`, undefined, "Open a request timeline");
      if (live && r.ok) setTimeline(r.data);
    })();
    return () => { live = false; };
  }, [open]);

  async function submit() {
    setBusy(true);
    try {
      const r = await callDocs<{ ref: string; fee: number; reference: string | null; stage: string }>("POST", "/me/documents/requests", {
        kind: w.kind, session: w.session || null, semester: w.semester ? Number(w.semester) : null, destination: w.destination, destinationName: w.destinationName || null, department: w.department || null,
        recipientName: w.recipientName || null, recipientEmail: w.recipientEmail || null, recipientAddress: w.recipientAddress || null, recipientReference: w.recipientReference || null, purpose: w.purpose || null,
        delivery: w.delivery, express: w.express, international: w.international, copies: Number(w.copies) || 1,
      }, `Document request: ${w.kind}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(`Request ${r.data.ref} submitted successfully.`); setDone(r.data); setStep(6); router.refresh();
    } finally { setBusy(false); }
  }
  async function openTimeline(r: RequestRow) {
    const x = await callDocs<RequestRow & { events: DocEvent[]; deliveries: Delivery[] }>("GET", `/me/documents/requests/${r.id}`, undefined, "Open a request timeline");
    if (!x.ok) { notifyProblem(x.problem); return; }
    setTimeline(x.data);
  }
  async function cancel(r: RequestRow) {
    const reason = window.prompt("Reason for cancelling (optional)") ?? "";
    const x = await callDocs("POST", `/me/documents/requests/${r.id}/cancel`, { reason: reason || null }, `Cancel document request ${r.ref}`);
    if (!x.ok) { notifyProblem(x.problem); return; }
    notify("Request cancelled"); setTimeline(null); router.refresh();
  }
  async function makeLink(id: string) {
    const x = await callDocs<{ path: string }>("POST", `/me/documents/${id}/link`, { days: 7 }, "Secure link for a document");
    if (!x.ok) { notifyProblem(x.problem); return; }
    setLink(`${window.location.origin}${x.data.path}`);
  }

  const active = d.documents.filter((x) => x.status === "ACTIVE");
  const pending = d.requests.filter((r) => !["COMPLETED", "REJECTED", "CANCELLED", "DELIVERED"].includes(r.stage));

  return (
    <>
      <PageHead title="My documents" description={`${d.student.name} · ${d.student.number} · ${d.student.programme ?? "—"}. Your official documents, each verifiable by its reference; your requests, each with its timeline.`}
        actions={<><Btn kind="primary" onClick={() => { setDone(null); setStep(1); }}>Request a document</Btn><LinkBtn kind="ghost" href="/verify/document">Verify a document</LinkBtn></>} />
      <Tiles items={[
        ["Certificates", String(d.counts.certificates), d.counts.certificates ? "var(--green-ink)" : null, "Issued and valid"],
        ["Transcripts & statements", String(d.counts.transcripts), null, "Valid documents"],
        ["Pending requests", String(d.counts.pending), d.counts.pending ? "var(--amber-ink)" : null, "In hand at the Registry"],
        ["Available downloads", String(d.counts.downloads), null, "Every valid document"],
      ]} cls="grid--4" />

      {pending.length ? (
        <Note kind="info" title={`${pending.length} request(s) in hand`}>
          {pending.map((r) => <span className="blk" key={r.id}><strong>{r.ref}</strong> · {r.kind_label} · <Pil kind={STAGE[r.stage]?.[1] ?? "grey"}>{STAGE[r.stage]?.[0] ?? r.stage}</Pil>{r.stage === "AWAITING_PAYMENT" && r.reference ? <> · pay {naira(r.fee)} against <span className="tnum">{r.reference}</span> <PayByCard reference={r.reference} amount={Number(r.fee)} /></> : null}{r.sla_due_on && !["AWAITING_PAYMENT"].includes(r.stage) ? <span className="sub2"> · expected by {dayOf(r.sla_due_on)}</span> : null}</span>)}
        </Note>
      ) : null}

      <Panel title="Documents issued to you" right={active.length ? `${active.length} valid` : "none yet"}>
        {d.documents.length ? (
          <DTable cols={["Document", "Number|mid", "Issued|mid", "Status|mid", "Verification|mid", "|num"]} rows={d.documents.map((x) => [
            <span key="d"><strong>{x.kind_label}</strong><div className="sub2">{x.award ?? x.programme ?? ""}{x.graduation_session ? ` · ${x.graduation_session}` : ""}{x.version > 1 ? ` · version ${x.version}` : ""}</div></span>,
            <span key="n" className="tnum">{x.number ?? "—"}</span>, <span key="i" className="tnum sub2">{dayOf(x.issued_on)}</span>,
            <Pil key="s" kind={DOC_STATUS[x.status]?.[1] ?? "grey"}>{DOC_STATUS[x.status]?.[0] ?? x.status}</Pil>,
            <Link key="v" className="lnk tnum" href={verifyPathFor(x.verification_code)}>{x.verification_code}</Link>,
            <span key="a" className="row row--inline row--tight">{x.status === "ACTIVE" ? <><a className="btn btn--primary btn--sm" href={`/student/documents/${x.id}/pdf`} target="_blank" rel="noopener">Download PDF</a><Btn kind="ghost" onClick={() => void makeLink(x.id)}>Secure link</Btn></> : <span className="sub2">{x.revoked_reason ?? "Superseded"}</span>}</span>,
          ])} />
        ) : <PBody><div className="sub2">No document has been issued to you yet. {d.student.status === "GRADUATED" ? "Your degree certificate appears here once the Registry issues it." : "Request a transcript, a sessional transcript, a mini-transcript or a statement of record above."}</div></PBody>}
      </Panel>

      <Panel title="My document requests" right={d.requests.length ? `${d.requests.length}` : "none yet"}>
        {d.requests.length ? (
          <DTable cols={["Request|mid", "Type", "Date|mid", "Payment|mid", "Status|mid", "Delivery|mid", "|num"]} rows={d.requests.map((r) => [
            <span key="r" className="tnum">{r.ref}</span>,
            <span key="t">{r.kind_label}{r.session ? <div className="sub2">{r.session}{r.semester ? ` · ${semesterName(r.semester)}` : ""}</div> : null}{r.destination !== "SELF" ? <div className="sub2">to {r.destination_name}</div> : null}</span>,
            <span key="d" className="tnum sub2">{dayOf(r.requested_at)}</span>,
            <span key="p"><Pil kind={PAYMENT[r.payment_status]?.[1] ?? "grey"}>{PAYMENT[r.payment_status]?.[0] ?? r.payment_status}</Pil>{r.fee ? <div className="sub2 tnum">{naira(r.fee)}</div> : null}</span>,
            <Pil key="s" kind={STAGE[r.stage]?.[1] ?? "grey"}>{STAGE[r.stage]?.[0] ?? r.stage}</Pil>,
            <span key="dl" className="sub2">{r.delivery.toLowerCase()}{r.deliveries_open ? ` · ${r.deliveries_open} open` : ""}</span>,
            <span key="a" className="row row--inline row--tight"><Btn kind="ghost" onClick={() => void openTimeline(r)}>Timeline</Btn>{r.issued_id && r.document_status === "ACTIVE" ? <a className="btn btn--primary btn--sm" href={`/student/documents/${r.issued_id}/pdf`} target="_blank" rel="noopener">Download</a> : null}</span>,
          ])} />
        ) : <PBody><div className="sub2">No request yet.</div></PBody>}
      </Panel>

      {step > 0 ? (
        <Modal title={step === 6 ? "Request submitted" : `Request a document · step ${step} of 5`} sub={step < 6 ? ["Select document", "Select delivery", "Recipient", "Review the fee", "Confirm and submit"][step - 1] : undefined} wide onClose={() => setStep(0)}
          foot={step < 6 ? <><Btn kind="ghost" onClick={() => setStep(Math.max(1, step - 1))} disabled={step === 1}>Back</Btn>{step < 5 ? <Btn kind="primary" onClick={() => setStep(step + 1)} disabled={(step === 1 && ((w.kind === "SESSIONAL_TRANSCRIPT" && !w.session) || !chosen)) || (step === 3 && thirdParty && !w.destinationName.trim()) || (step === 2 && w.delivery !== "DIGITAL" && step === 2 && false)}>Next</Btn> : <Btn kind="primary" onClick={() => void submit()} disabled={busy}>{busy ? "Submitting…" : "Submit request"}</Btn>}</> : <Btn kind="primary" onClick={() => setStep(0)}>Close</Btn>}>
          <Steps list={[[step > 1 ? "done" : "now", "Document", KIND[w.kind]?.[0] ?? ""], [step > 2 ? "done" : step === 2 ? "now" : "todo", "Delivery", w.delivery.toLowerCase()], [step > 3 ? "done" : step === 3 ? "now" : "todo", "Recipient", DESTINATIONS.find((x) => x[0] === w.destination)?.[1] ?? ""], [step > 4 ? "done" : step === 4 ? "now" : "todo", "Fee", naira(fee(chosen))], [step > 5 ? "done" : step === 5 ? "now" : "todo", "Submit", ""]]} />
          {step === 1 ? (
            <div className="grid grid--2">
              <Field id="wz-kind" label="Document" full><select id="wz-kind" className="ctl" value={w.kind} onChange={(e) => setW({ ...w, kind: e.target.value, session: "", semester: "" })}>{d.policies.filter((p) => p.kind !== "DEGREE_CERTIFICATE").map((p) => <option key={p.kind} value={p.kind}>{p.label}{p.billable ? ` · ${naira(p.fee_now)}` : " · free"}</option>)}</select></Field>
              {w.kind === "SESSIONAL_TRANSCRIPT" || (w.kind === "MINI_TRANSCRIPT" && (chosen?.includes === "SELECTED_SESSION" || chosen?.includes === "SELECTED_SEMESTER")) ? <Field id="wz-session" label="Academic session" required><select id="wz-session" className="ctl" value={w.session} onChange={(e) => setW({ ...w, session: e.target.value })}><option value="">Choose a session</option>{d.sessions.map((s) => <option key={s} value={s}>{s}</option>)}</select></Field> : null}
              {w.kind === "MINI_TRANSCRIPT" && chosen?.includes === "SELECTED_SEMESTER" ? <Field id="wz-sem" label="Semester"><select id="wz-sem" className="ctl" value={w.semester} onChange={(e) => setW({ ...w, semester: e.target.value })}><option value="">Choose</option><option value="1">First</option><option value="2">Second</option></select></Field> : null}
              <div className="sub2" style={{ gridColumn: "1 / -1" }}>
                {w.kind === "TRANSCRIPT" ? "The official full transcript records every session on the published record, the CGPA and, for a graduate, the class of degree. It is generated by Exams and Records, checked, and authorised by the Registrar." : w.kind === "SESSIONAL_TRANSCRIPT" ? "A sessional transcript records one academic session: its courses, units, grades, GPA and standing." : w.kind === "MINI_TRANSCRIPT" ? `A mini-transcript is a concise summary${chosen?.includes === "CUMULATIVE" ? " of your cumulative record" : chosen?.includes === "CURRENT_SEMESTER" ? " of the current semester" : ""}.` : "A statement of academic record is for a student still in study; it is not a transcript."}
                {chosen?.self_service && !chosen.billable ? " It is free and issued at once." : chosen?.billable ? ` Expected processing time: ${chosen.sla_days} working day(s)${chosen.urgent_fee ? `, or ${chosen.urgent_sla_days} urgent` : ""}.` : ""}
              </div>
            </div>
          ) : step === 2 ? (
            <div className="grid grid--2">
              <Field id="wz-dl" label="Delivery"><select id="wz-dl" className="ctl" value={w.delivery} onChange={(e) => setW({ ...w, delivery: e.target.value })}><option value="DIGITAL">Digital — secure download and verification code</option><option value="PHYSICAL">Physical — sealed copy dispatched</option><option value="BOTH">Both</option></select></Field>
              <Field id="wz-copies" label="Copies"><input id="wz-copies" type="number" min={1} max={10} className="ctl" value={w.copies} onChange={(e) => setW({ ...w, copies: e.target.value })} /></Field>
              <label className="row row--tight" style={{ gap: 6 }}><input type="checkbox" checked={w.express} onChange={(e) => setW({ ...w, express: e.target.checked })} /> Urgent processing{chosen?.urgent_fee ? ` (+${naira(chosen.urgent_fee)})` : ""}</label>
              {w.delivery !== "DIGITAL" ? <label className="row row--tight" style={{ gap: 6 }}><input type="checkbox" checked={w.international} onChange={(e) => setW({ ...w, international: e.target.checked })} /> International delivery{chosen?.international_fee ? ` (+${naira(chosen.international_fee)})` : ""}</label> : null}
            </div>
          ) : step === 3 ? (
            <div className="grid grid--2">
              <Field id="wz-dest" label="Send to"><select id="wz-dest" className="ctl" value={w.destination} onChange={(e) => setW({ ...w, destination: e.target.value })}>{DESTINATIONS.map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field>
              {thirdParty ? <Field id="wz-name" label="Institution / organisation" required><input id="wz-name" className="ctl" value={w.destinationName} onChange={(e) => setW({ ...w, destinationName: e.target.value })} /></Field> : null}
              {thirdParty ? <><Field id="wz-dep" label="Department / unit"><input id="wz-dep" className="ctl" value={w.department} onChange={(e) => setW({ ...w, department: e.target.value })} /></Field>
                <Field id="wz-rn" label="Recipient name"><input id="wz-rn" className="ctl" value={w.recipientName} onChange={(e) => setW({ ...w, recipientName: e.target.value })} /></Field>
                <Field id="wz-re" label="Recipient email" hint="A secure expiring link is sent here; the document itself is not attached"><input id="wz-re" type="email" className="ctl" value={w.recipientEmail} onChange={(e) => setW({ ...w, recipientEmail: e.target.value })} /></Field>
                <Field id="wz-rr" label="Their reference / application number"><input id="wz-rr" className="ctl" value={w.recipientReference} onChange={(e) => setW({ ...w, recipientReference: e.target.value })} /></Field></> : null}
              {w.delivery !== "DIGITAL" ? <Field id="wz-ra" label="Postal address for the sealed copy" required full><textarea id="wz-ra" className="ctl" rows={2} value={w.recipientAddress} onChange={(e) => setW({ ...w, recipientAddress: e.target.value })} /></Field> : null}
              <Field id="wz-purpose" label="Purpose" full><input id="wz-purpose" className="ctl" value={w.purpose} onChange={(e) => setW({ ...w, purpose: e.target.value })} placeholder="Further study, employment, professional registration…" /></Field>
            </div>
          ) : step === 4 ? (
            <>
              <KvGrid cls="grid--2" pairs={[["Document", KIND[w.kind]?.[0] ?? w.kind], ["Copies", w.copies], ["Delivery", w.delivery.toLowerCase()], ["Urgent", w.express ? "Yes" : "No"], ["Base fee", chosen?.billable ? `${naira(chosen.fee_now)} × ${w.copies}` : "Free"], ["Urgent fee", w.express && chosen ? naira(chosen.urgent_fee) : "—"], ["Delivery fee", w.delivery !== "DIGITAL" && chosen ? naira(Number(chosen.physical_fee) + (w.international ? Number(chosen.international_fee) : 0)) : "—"], ["Total", <strong key="t">{naira(fee(chosen))}</strong>]]} />
              <div className="sub2 mt-2">{fee(chosen) > 0 ? "An invoice and a payment reference are generated on submission; pay by card or at the bank from your Fees page. Processing begins when the Bursary or the gateway confirms it." : "No fee applies; processing begins at once."}</div>
            </>
          ) : step === 5 ? (
            <>
              <KvGrid cls="grid--2" pairs={[["Student", `${d.student.name} · ${d.student.number}`], ["Programme", d.student.programme ?? "—"], ["Document", `${KIND[w.kind]?.[0]}${w.session ? ` · ${w.session}` : ""}${w.semester ? ` · ${semesterName(Number(w.semester))}` : ""}`], ["Delivery", `${w.delivery.toLowerCase()} · ${w.copies} cop${w.copies === "1" ? "y" : "ies"}${w.express ? " · urgent" : ""}`], ["Recipient", thirdParty ? `${w.destinationName}${w.recipientName ? ` · ${w.recipientName}` : ""}${w.recipientEmail ? ` · ${w.recipientEmail}` : ""}` : "Myself"], ["Fee", naira(fee(chosen))]]} />
              <div className="sub2 mt-2">Your academic information is read from your record; the document is generated from the published results and cannot be edited by hand.</div>
            </>
          ) : done ? (
            <>
              <Note kind="ok" title={`Request ${done.ref} submitted successfully`}>{done.fee > 0 && done.reference ? <>Pay {naira(done.fee)} against reference <span className="tnum">{done.reference}</span>. <PayByCard reference={done.reference} amount={done.fee} /></> : done.stage === "RELEASED" ? "The document was issued at once and is under Documents issued to you." : "It is with Exams and Records; you will be told at each step."}</Note>
            </>
          ) : null}
        </Modal>
      ) : null}

      {timeline ? (
        <Modal title={`Request ${timeline.ref}`} sub={`${timeline.kind_label} · ${STAGE[timeline.stage]?.[0] ?? timeline.stage}`} wide onClose={() => { setTimeline(null); if (open) router.replace("/student/documents"); }}
          foot={<>{["AWAITING_PAYMENT", "READY", "HELD_AT_CLEARANCE"].includes(timeline.stage) ? <Btn kind="ghost" onClick={() => void cancel(timeline)}>Cancel request</Btn> : null}<Btn kind="primary" onClick={() => { setTimeline(null); if (open) router.replace("/student/documents"); }}>Close</Btn></>}>
          <KvGrid cls="grid--3" pairs={[["Requested", whenAt(timeline.requested_at)], ["Payment", timeline.fee ? `${naira(timeline.fee)} · ${PAYMENT[timeline.payment_status]?.[0] ?? timeline.payment_status}${timeline.receipt_no ? ` · receipt ${timeline.receipt_no}` : ""}` : "No fee"], ["Expected by", timeline.sla_due_on ? dayOf(timeline.sla_due_on) : "After payment"], ["Delivery", timeline.delivery.toLowerCase()], ["Recipient", timeline.destination === "SELF" ? "Myself" : timeline.destination_name ?? ""], ["Document", timeline.document_number ? `${timeline.document_number}${timeline.document_version && timeline.document_version > 1 ? ` v${timeline.document_version}` : ""}` : "Not yet generated"]]} />
          {timeline.stage === "AWAITING_PAYMENT" && timeline.reference ? <Note kind="info" title={`Pay ${naira(timeline.fee)} against ${timeline.reference}`}><PayByCard reference={timeline.reference} amount={Number(timeline.fee)} /></Note> : null}
          {timeline.stage === "HELD_AT_CLEARANCE" ? <Note kind="bad" title="Held at clearance">A unit holds you; the transcript moves when every unit clears you. Your clearance screen names the unit.</Note> : null}
          <Panel title="Timeline">
            <DTable cols={["When|mid", "Step", "Note"]} rows={timeline.events.map((e) => [<span key="w" className="tnum sub2">{whenAt(e.at)}</span>, <strong key="a">{EVENT_WORDS[e.action] ?? e.action.toLowerCase()}{e.to_state && e.action === "QUALITY_CHECK" ? ` · ${e.to_state.toLowerCase()}` : ""}</strong>, <span key="n" className="sub2">{e.note ?? ""}</span>])} />
          </Panel>
          {timeline.deliveries.length ? (
            <Panel title="Deliveries">
              <DTable cols={["Kind|mid", "To", "Status|mid", "Courier / tracking", "Updated|mid"]} rows={timeline.deliveries.map((x) => [<span key="k" className="sub2">{x.kind.toLowerCase()}</span>, <span key="t">{x.recipient ?? ""}{x.email ? <div className="sub2">{x.email}</div> : null}</span>, <Pil key="s" kind={DELIVERY_STATE[x.state]?.[1] ?? "grey"}>{DELIVERY_STATE[x.state]?.[0] ?? x.state}</Pil>, <span key="c" className="sub2">{x.courier ?? ""}{x.tracking_no ? ` · ${x.tracking_no}` : ""}{x.dispatched_on ? ` · dispatched ${dayOf(x.dispatched_on)}` : ""}</span>, <span key="u" className="tnum sub2">{whenAt(x.updated_at)}</span>])} />
            </Panel>
          ) : null}
        </Modal>
      ) : null}
      {link ? (
        <Modal title="Secure download link" sub="Valid for seven days; each use is logged" onClose={() => setLink(null)} foot={<Btn kind="primary" onClick={() => setLink(null)}>Close</Btn>}>
          <Field id="lk" label="Link" full><input id="lk" className="ctl tnum" readOnly value={link} onFocus={(e) => e.currentTarget.select()} /></Field>
          <div className="sub2">Share it with the recipient; the document opens as a PDF with its verification reference. The link stops working when the document is revoked or replaced.</div>
        </Modal>
      ) : null}
      <div className="sub2">The document verification page for third parties is public: <Link className="lnk" href="/verify/document">/verify/document</Link>.</div>
    </>
  );
}
