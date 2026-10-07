"use client";
/** One payment in Payment Support (V346): what the gateway, the Bursary's ledger and the portal say — the diagnosis in four
 *  words and a sentence — and the acts this agent's postings allow, each through the existing services: Verify (the gateway
 *  asked again; the original reference settled or left as it is), Refresh entitlement (a confirmed payment's effects
 *  re-applied; nothing paid, nothing created), the receipt, and escalation to the Bursary or the Director of ICT on the
 *  student's ticket. There is no "mark as paid" here, by design. */
import Link from "next/link";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { OFFICE_WORD, PAY_WORD, type PaymentDiagnosis } from "@/lib/support";

const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
const naira = (v: unknown) => (v == null || v === "" ? "—" : `₦${Number(v).toLocaleString("en-NG", { minimumFractionDigits: 2 })}`);
const word = (v: string) => PAY_WORD[v] ?? [v.toLowerCase().replace(/_/g, " "), "grey" as const];
const yes = (v: unknown) => (v === true ? <Pil kind="ok">Yes</Pil> : v === false ? <Pil kind="warn">No</Pil> : <span className="sub2">—</span>);

export function PaymentCase({ data, ticket: ticketIn }: { data: PaymentDiagnosis; ticket: string }) {
  const router = useRouter();
  const p = data.payment;
  const can = new Set(data.actions);
  const [busy, setBusy] = useState<string | null>(null);
  const [ticket, setTicket] = useState(ticketIn || data.tickets[0]?.id || "");
  const [reason, setReason] = useState("");
  const [escalate, setEscalate] = useState<{ office: string; reason: string } | null>(null);
  const ref = encodeURIComponent(p.reference);

  async function post(path: string, body: unknown, label: string): Promise<Record<string, unknown> | null> {
    setBusy(label);
    try {
      const r = await fetch(`/api/bff/api/v1/helpdesk/support/${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(label) }, body: JSON.stringify(body) });
      const j = (await r.json().catch(() => null)) as Record<string, unknown> | null;
      if (!r.ok) { notifyProblem((j as unknown as Parameters<typeof notifyProblem>[0]) ?? { status: r.status, title: r.statusText }); return null; }
      return j;
    } finally { setBusy(null); }
  }
  const act = { reason: reason.trim() || null, ticket: ticket || null };
  async function verify() {
    const j = await post(`payments/${ref}/verify`, act, "Payment verified with the gateway");
    if (j) { notify(j.changed ? "The gateway confirmed the payment; the portal is synchronized and the student told." : `The gateway answered: ${String((j.gateway as Record<string, unknown>)?.outcome ?? "no change")}. Nothing changed.`); router.refresh(); }
  }
  async function refresh() {
    const j = await post(`payments/${ref}/refresh`, act, "Payment entitlement refreshed");
    if (j) { const problems = (j.problems as string[]) ?? []; notify(problems.length ? `Refreshed; for the Bursary: ${problems.join(" ")}` : "Payment verified. Portal entitlement synchronized. The student can continue."); router.refresh(); }
  }
  async function investigate() {
    const j = await post(`payments/${ref}/investigate`, act, "Payment investigated");
    if (j) { notify("The investigation is on the support ledger" + (ticket ? " and the ticket" : "") + "."); router.refresh(); }
  }
  async function receipt() {
    const j = await post(`payments/${ref}/receipt`, act, "Receipt regenerated");
    if (j) { notify(`Receipt ${String(j.receiptNo)} regenerated; the student is told it is ready.`); router.refresh(); }
  }
  async function sendEscalation() {
    if (!escalate) return;
    const j = await post(`students/${p.student_id}/escalate`, { ticket, office: escalate.office, reason: escalate.reason.trim(), paymentReference: p.reference }, `Escalated to ${OFFICE_WORD[escalate.office] ?? escalate.office}`);
    if (j) { notify(`The ticket is with ${OFFICE_WORD[escalate.office] ?? escalate.office}.`); setEscalate(null); router.refresh(); }
  }
  const actionButton = (a: string) => {
    switch (a) {
      case "VERIFY": return can.has("VERIFY") ? <Btn key={a} kind="primary" disabled={!!busy} onClick={() => void verify()}>Verify payment</Btn> : null;
      case "REFRESH": return can.has("REFRESH_ENTITLEMENT") ? <Btn key={a} kind="primary" disabled={!!busy} onClick={() => void refresh()}>Refresh payment entitlement</Btn> : null;
      case "ESCALATE_BURSARY": return <Btn key={a} kind="secondary" disabled={!!busy || !ticket} onClick={() => setEscalate({ office: "bursar", reason: "" })}>Escalate to Bursary</Btn>;
      case "VIEW_RECEIPT": return can.has("VIEW_RECEIPT") ? <a key={a} className="btn btn--secondary btn--sm" href={`/helpdesk/payments/${ref}/receipt`} target="_blank" rel="noopener">View receipt</a> : null;
      default: return null;
    }
  };
  const statusTile = (label: string, v: string) => (
    <div className="kv" key={label}><span className="k">{label}</span><span className="v"><Pil kind={word(v)[1]}>{word(v)[0]}</Pil></span></div>
  );

  return (
    <>
      <PageHead title={<span className="tnum">{p.reference}</span>} eyebrow={<>Payment Support · {p.student} · <span className="tnum">{p.number ?? ""}</span></>}
        description={`${p.purpose} · ${p.session} · ${naira(p.amount)}`}
        actions={<><LinkBtn href={`/helpdesk/students/${p.student_id}?tab=payments${ticket ? `&ticket=${encodeURIComponent(ticket)}` : ""}`}>The student</LinkBtn><LinkBtn href="/helpdesk/payments">Payment Support</LinkBtn></>} />

      <Panel title="Diagnosis" right="What each authority says about this payment, now">
        <PBody>
          <div className="grid grid--5">
            {statusTile("Current status", data.status.current)}
            {statusTile("Payment gateway", data.status.gateway)}
            {statusTile("Finance", data.status.finance)}
            {statusTile("Student entitlement", data.status.entitlement)}
            {statusTile("Verification", data.status.verification)}
          </div>
        </PBody>
        {data.advice.map((a) => (
          <PBody key={a.code}>
            <Note kind={a.code === "IN_ORDER" ? "ok" : ["ENTITLEMENT_STALE", "GATEWAY_PAID_PORTAL_NOT", "HANGING"].includes(a.code) ? "info" : "bad"} title={a.words}
              action={<span className="row row--inline row--tight">{actionButton(a.action)}</span>} />
          </PBody>
        ))}
      </Panel>

      <Panel title="Support actions" right="Only what your postings allow on this student; each act is on the support ledger and the ticket">
        <PBody>
          <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
            <Field id="pc-ticket" label="Support ticket" style={{ flex: "2 1 260px" }} hint={data.tickets.length ? "The act is filed on it" : "The student has no open ticket; raise one from the student's record to escalate"}>
              <select id="pc-ticket" className="ctl" value={ticket} onChange={(e) => setTicket(e.target.value)}>
                <option value="">No ticket</option>
                {data.tickets.map((t) => <option key={t.id} value={t.id}>{t.number} — {t.category}: {t.subject}</option>)}
              </select>
            </Field>
            <Field id="pc-reason" label="Reason" style={{ flex: "3 1 320px" }}><input id="pc-reason" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)} maxLength={2000} placeholder="e.g. the student reports a debit but the portal shows unpaid" /></Field>
          </div>
          <div className="row row--inline mt-2" style={{ flexWrap: "wrap", gap: "var(--s-2)" }}>
            <Btn kind="ghost" disabled={!!busy} onClick={() => void investigate()}>Record the investigation</Btn>
            {can.has("VERIFY") ? <Btn kind="primary" disabled={!!busy} onClick={() => void verify()}>Verify</Btn> : null}
            {can.has("RECHECK") ? <Btn kind="secondary" disabled={!!busy} onClick={() => void verify()} title="Asks the gateway again and settles what it confirms — the webhook's work, retried">Recheck / re-sync</Btn> : null}
            {can.has("REFRESH_ENTITLEMENT") ? <Btn kind="primary" disabled={!!busy} onClick={() => void refresh()}>Refresh entitlement</Btn> : null}
            {can.has("VIEW_RECEIPT") ? <a className="btn btn--secondary btn--sm" href={`/helpdesk/payments/${ref}/receipt`} target="_blank" rel="noopener">View receipt</a> : null}
            {can.has("REGENERATE_RECEIPT") ? <Btn kind="secondary" disabled={!!busy} onClick={() => void receipt()}>Regenerate receipt</Btn> : null}
            <Btn kind="secondary" disabled={!!busy || !ticket} onClick={() => setEscalate({ office: "bursar", reason: "" })}>Escalate to Bursary</Btn>
            <Btn kind="ghost" disabled={!!busy || !ticket} onClick={() => setEscalate({ office: "ict", reason: "" })}>Escalate to ICT Director</Btn>
          </div>
          <div className="sub2 mt-2">There is no &ldquo;mark as paid&rdquo;: a payment counts only when the gateway or the Bursary confirms the original reference. Refunds, amounts and fees stay with the Bursary.</div>
        </PBody>
      </Panel>

      <div className="grid grid--2">
        <Panel title="Payment information">
          <PBody>
            <KvGrid cls="grid--2" pairs={[
              ["Student", <Link key="s" className="lnk" href={`/helpdesk/students/${p.student_id}`}>{p.student}</Link>], ["Number", <span key="n" className="tnum">{p.number ?? "—"}</span>],
              ["Payment type", p.purpose], ["Session", p.session],
              ["Invoice number", <span key="i" className="tnum">{p.invoice}</span>], ["Payment reference", <span key="r" className="tnum">{p.reference}</span>],
              ["Gateway reference", <span key="g" className="tnum">{p.gatewayRef ?? "—"}</span>], ["Transaction reference", <span key="t" className="tnum">{p.transactionRef ?? "—"}</span>],
              ["Amount", <span key="a" className="tnum">{naira(p.amount)}</span>], ["Payment date", when(p.confirmed_at)],
              ["Generated", when(p.generated_at)], ["Expires", when(p.expires_at)],
              ["Channel", p.channel ?? "—"], ["Receipt", <span key="rc" className="tnum">{p.receipt_no ?? "—"}</span>],
            ]} />
          </PBody>
        </Panel>
        <Panel title="Entitlement and registration" right="Read from the confirmed payments, live">
          <PBody>
            <div className="mb-2">{data.entitlementWords}</div>
            <KvGrid cls="grid--2" pairs={[
              ["Due this session", <span key="d" className="tnum">{naira(data.entitlementState.due)}</span>], ["Paid this session", <span key="p" className="tnum">{naira(data.entitlementState.paid)}</span>],
              ["Balance", <span key="b" className="tnum">{naira(data.entitlementState.balance)}</span>], ["Arrears", yes(data.entitlementState.hasArrears)],
              ["Cleared for registration", yes(data.entitlementState.clearsRegistration)], ["First semester cleared", yes(data.entitlementState.semester1Cleared)],
              ["Second semester cleared", yes(data.entitlementState.semester2Cleared)], ["GST/EPS entitled", yes(data.entitlementState.gstEntitled)],
              [`Registration, semester ${data.registration.semester}`, <span key="r" className="sub2">{data.registration.status === "NONE" ? "not started" : data.registration.status.toLowerCase()}</span>],
              ["Registration window", data.registration.gate ? <span key="w" className="sub2">{data.registration.gate}</span> : <Pil key="w" kind="ok">Open</Pil>],
            ]} />
          </PBody>
        </Panel>
      </div>

      <Panel title="What the gateway said" right={`${data.events.length} answer${data.events.length === 1 ? "" : "s"} · ${data.attempts.length} attempt${data.attempts.length === 1 ? "" : "s"}`}>
        {data.events.length ? (
          <DTable pageSize={0} noPrint cols={["Received", "Gateway", "Source", "Gateway ref", "Amount|num", "Status", "Outcome|mid", "Signature|mid", "Resolved"]} rows={data.events.map((e, i) => [
            <span key={"w" + i} className="sub2">{when(e.received_at)}</span>, <span key={"g" + i}>{e.gateway}</span>, <span key={"s" + i} className="sub2">{e.source.toLowerCase()}</span>,
            <span key={"r" + i} className="tnum">{e.gateway_ref ?? "—"}</span>, <span key={"a" + i} className="tnum">{e.amount == null ? "—" : naira(e.amount)}</span>, <span key={"st" + i} className="sub2">{e.status ?? "—"}</span>,
            <Pil key={"o" + i} kind={e.outcome === "SETTLED" || e.outcome === "ALREADY_SETTLED" ? "ok" : e.outcome === "GATEWAY_ERROR" ? "warn" : "bad"}>{e.outcome.toLowerCase().replace(/_/g, " ")}</Pil>,
            e.signature_ok ? <Pil key={"sg" + i} kind="ok">valid</Pil> : <Pil key={"sg" + i} kind="bad">refused</Pil>, <span key={"rs" + i} className="sub2">{e.resolved_at ? `${when(e.resolved_at)} · ${e.resolution ?? ""}` : "—"}</span>,
          ])} />
        ) : <PBody><div className="sub2">No gateway has answered about this reference.</div></PBody>}
        {data.attempts.length ? (
          <DTable pageSize={0} noPrint cols={["Opened", "Gateway", "Kind", "Transaction ref", "Checks|mid", "Last checked"]} rows={data.attempts.map((a, i) => [
            <span key={"o" + i} className="sub2">{when(a.opened_at)}</span>, <span key={"g" + i}>{a.gateway}</span>, <span key={"k" + i} className="sub2">{a.kind}</span>,
            <span key={"t" + i} className="tnum">{a.txn_ref ?? "—"}</span>, <span key={"c" + i} className="tnum">{a.checks}</span>, <span key={"l" + i} className="sub2">{when(a.checked_at)}</span>,
          ])} />
        ) : null}
      </Panel>

      {data.related.length || data.refunds.length ? (
        <div className="grid grid--2">
          <Panel title="Other references for the same purpose" right="A second confirmed one may be a duplicate payment — the Bursary's to decide">
            {data.related.length ? <DTable pageSize={0} noPrint cols={["Reference|mid", "Amount|num", "Generated", "Confirmed", "Receipt|mid"]} rows={data.related.map((x) => [
              <Link key="r" className="lnk tnum" href={`/helpdesk/payments/${encodeURIComponent(x.reference)}${ticket ? `?ticket=${encodeURIComponent(ticket)}` : ""}`}>{x.reference}</Link>, <span key="a" className="tnum">{naira(x.amount)}</span>,
              <span key="g" className="sub2">{when(x.generated_at)}</span>, x.confirmed_at ? <Pil key="c" kind="ok">{when(x.confirmed_at)}</Pil> : <Pil key="c" kind="grey">not confirmed</Pil>, <span key="rc" className="tnum">{x.receipt_no ?? "—"}</span>,
            ])} /> : <PBody><div className="sub2">None.</div></PBody>}
          </Panel>
          <Panel title="Refunds" right="Tracked here; decided by the Bursary">
            {data.refunds.length ? <DTable pageSize={0} noPrint cols={["State|mid", "Amount|num", "Proposed", "Approved", "Paid"]} rows={data.refunds.map((x, i) => [
              <Pil key={"s" + i} kind={x.state === "PAID" ? "ok" : x.state === "REJECTED" ? "bad" : "warn"}>{x.state.toLowerCase()}</Pil>, <span key={"a" + i} className="tnum">{naira(x.amount)}</span>,
              <span key={"p" + i} className="sub2">{when(x.proposed_at)}</span>, <span key={"ap" + i} className="sub2">{when(x.approved_at)}</span>, <span key={"pd" + i} className="sub2">{when(x.paid_at)}</span>,
            ])} /> : <PBody><div className="sub2">No refund is recorded against this reference.</div></PBody>}
          </Panel>
        </div>
      ) : null}

      {escalate ? (
        <Modal title={`Escalate to ${OFFICE_WORD[escalate.office] ?? escalate.office}`} sub="The ticket goes to the office and waits on it; the payment's reference is named on the act" onClose={() => setEscalate(null)}
          foot={<><Btn kind="ghost" onClick={() => setEscalate(null)}>Cancel</Btn><Btn kind="primary" disabled={!!busy || escalate.reason.trim().length < 5 || !ticket} onClick={() => void sendEscalation()}>Escalate</Btn></>}>
          <div className="stack">
            <Field id="esc-office" label="To"><select id="esc-office" className="ctl" value={escalate.office} onChange={(e) => setEscalate({ ...escalate, office: e.target.value })}>
              <option value="bursar">The Bursary — a financial decision (short payment, duplicate, refund, bank evidence)</option>
              <option value="ict">The Director of ICT — a system-wide technical fault (gateway, callbacks)</option>
            </select></Field>
            <Field id="esc-reason" label="What the office should decide" required><textarea id="esc-reason" className="ctl" rows={4} value={escalate.reason} onChange={(e) => setEscalate({ ...escalate, reason: e.target.value })} maxLength={2000} /></Field>
          </div>
        </Modal>
      ) : null}
    </>
  );
}
