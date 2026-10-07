"use client";
/** One JUPEB record in support mode (V347). The banner says who is acting for whom and on which ticket; only what the agent's
 *  JUPEB postings carry is offered, and the server refuses the rest anyway. The contact details are corrected with a reason;
 *  the password is reset through the JUPEB portal's own one-hour link, or — on the candidate's ticket — a temporary password
 *  for one sign-in within 24 hours, shown here once and recorded nowhere; a JUPEB payment is asked of the gateway again through
 *  the payment service (never marked paid), and the activation a paid school fee earns is re-applied by the JUPEB rule.
 *  Identity details (name, date of birth, NIN, state) are the JUPEB Office's: the candidate asks from their portal, or the
 *  ticket is escalated. Nothing here admits, grades or refunds. */
import Link from "next/link";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tabs } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ACTION_WORD, RESULT_WORD } from "@/lib/support";
import { FEE_KIND, STATE_SHORT, day, feeCategoryLabel, fullName, naira, stateKind, streamLabel, when, type Candidate } from "@/lib/jupeb";

type Problem = Parameters<typeof notifyProblem>[0];
type Tab = "record" | "payments" | "tickets" | "history";
const TABS: Tab[] = ["record", "payments", "tickets", "history"];
const OFFICES: [string, string][] = [["jupeb", "The JUPEB Office"], ["bursar", "The Bursary"], ["ict", "The Director of ICT"]];

interface Payment {
  reference: string; kind: string; amount: number; session: string; semester: number | null; created_at: string; expires_at: string; confirmed_at: string | null; channel: string | null;
  state: string; gateway: string | null; gateway_ref: string | null; gateway_outcome: string | null; gateway_at: string | null; attempts: number; old_reference: string | null;
}
interface Action {
  id: string; at: string; action: string; module: string; field: string | null; old_value: string | null; new_value: string | null; reason: string; summary: string | null; outcome: string;
  method: string | null; payment_reference: string | null; agent: string; agent_office: string; ticket_id: string | null; ticket_number: string | null; result: string;
}
export interface JupebSupportData {
  record: Candidate; payments: Payment[]; capabilities: string[]; agent: string;
  account: { email: string; last_signed_in_at: string | null; locked: boolean | null; must_change_password: boolean; temporary: boolean };
  tickets: { id: string; number: string; subject: string; status: string; priority: string; category: string; created_at: string; updated_at: string; agent: string | null; escalated_office: string | null }[];
  actions: Action[];
  ticket: { id: string; number: string; subject: string; status: string; category: string; category_code: string } | null;
  categories: { code: string; name: string; fields: string }[];
}
interface TicketField { key: string; label: string; type?: string; required?: boolean; options?: string[] }

export function JupebSupport({ id, data, tab }: { id: string; data: JupebSupportData; tab: string }) {
  const router = useRouter();
  const go = useQueryNav();
  const c = data.record;
  const caps = new Set(data.capabilities);
  const ticket = data.ticket;
  const tabNow: Tab = (TABS as string[]).includes(tab) ? (tab as Tab) : "record";
  const [busy, setBusy] = useState(false);
  const [contact, setContact] = useState<Record<string, string> | null>(null);
  const [reset, setReset] = useState<{ method: "LINK" | "TEMPORARY"; reason: string; result: Record<string, unknown> | null } | null>(null);
  const [verify, setVerify] = useState<{ reference: string; reason: string; result: Record<string, unknown> | null } | null>(null);
  const [refresh, setRefresh] = useState<{ reason: string } | null>(null);
  const [raise, setRaise] = useState<{ subject: string; description: string; details: Record<string, string> } | null>(null);
  const [escalate, setEscalate] = useState<{ office: string; reason: string } | null>(null);
  const [resolve, setResolve] = useState<{ summary: string; details: string } | null>(null);

  async function call(method: "POST" | "PUT", path: string, body: unknown, reason: string, quiet = false): Promise<Record<string, unknown> | null> {
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/helpdesk/support/jupeb/${id}${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = (await r.json().catch(() => null)) as Record<string, unknown> | null;
      if (!r.ok) { notifyProblem(j ? (j as unknown as Problem) : ({ status: r.status, title: r.statusText } as Problem)); return null; }
      if (!quiet) notify(reason);
      return j;
    } finally { setBusy(false); }
  }
  const openTab = (t: Tab) => go(`/helpdesk/jupeb/${id}?tab=${t}${ticket ? `&ticket=${encodeURIComponent(ticket.id)}` : ""}`);

  function openContact() {
    setContact({ phone: c.phone ?? "", contactAddress: c.contact_address ?? "", permanentAddress: c.permanent_address ?? "", guardianName: c.guardian_name ?? "", guardianPhone: c.guardian_phone ?? "",
      guardianAddress: c.guardian_address ?? "", nextOfKinName: c.next_of_kin_name ?? "", nextOfKinPhone: c.next_of_kin_phone ?? "", nextOfKinRelationship: c.next_of_kin_relationship ?? "", reason: "" });
  }
  async function saveContact() {
    if (!contact) return;
    const body = Object.fromEntries(Object.entries(contact).map(([k, v]) => [k, v.trim() === "" ? null : v.trim()]));
    if (await call("PUT", "/contact", { ...body, ticket: ticket?.id ?? null }, "Contact details corrected")) { setContact(null); router.refresh(); }
  }
  async function confirmReset() {
    if (!reset) return;
    const j = await call("POST", "/password", { method: reset.method, reason: reset.reason.trim(), ticket: ticket?.id ?? null }, reset.method === "LINK" ? "Password reset link sent" : "Temporary password issued", true);
    if (j) { setReset({ ...reset, result: j }); router.refresh(); }
  }
  async function confirmVerify() {
    if (!verify) return;
    const j = await call("POST", `/payments/${encodeURIComponent(verify.reference)}/verify`, { reason: verify.reason.trim() || null, ticket: ticket?.id ?? null }, "Payment verified with the gateway", true);
    if (j) { setVerify({ ...verify, result: j }); notify(j.changed ? "Payment confirmed by the gateway" : "The gateway was asked; nothing changed"); router.refresh(); }
  }
  async function confirmRefresh() {
    if (!refresh) return;
    const j = await call("POST", "/refresh", { reason: refresh.reason.trim() || null, ticket: ticket?.id ?? null }, "Activation refreshed", true);
    if (j) { notify(j.activated ? "The studentship is activated" : `Nothing to re-apply: the record stands ${String(j.state).toLowerCase()}`); setRefresh(null); router.refresh(); }
  }
  const category = data.categories[0];
  const fields: TicketField[] = (() => { try { return category ? (JSON.parse(category.fields) as TicketField[]) : []; } catch { return []; } })();
  async function confirmRaise() {
    if (!raise) return;
    const j = await call("POST", "/tickets", { subject: raise.subject.trim(), description: raise.description.trim(), details: raise.details }, "Ticket raised for the candidate");
    if (j) { setRaise(null); go(`/helpdesk/jupeb/${id}?tab=tickets&ticket=${encodeURIComponent(String(j.id))}`); router.refresh(); }
  }
  async function confirmEscalate() {
    if (!escalate || !ticket) return;
    const j = await call("POST", "/escalate", { ticket: ticket.id, office: escalate.office, reason: escalate.reason.trim() }, `Escalated to ${OFFICES.find((o) => o[0] === escalate.office)?.[1] ?? escalate.office}`);
    if (j) { setEscalate(null); router.refresh(); }
  }
  async function confirmResolve() {
    if (!resolve || !ticket) return;
    setBusy(true);
    try {
      // a ticket still new or merely opened is moved to in progress first, as the ticket screen does
      for (const to of ticket.status === "SUBMITTED" ? ["OPENED", "IN_PROGRESS"] : ["OPENED", "REOPENED", "WAITING_FOR_STUDENT"].includes(ticket.status) ? ["IN_PROGRESS"] : []) {
        const st = await fetch(`/api/bff/api/v1/helpdesk/tickets/${ticket.id}/status`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${ticket.number}: worked from the JUPEB record`) }, body: JSON.stringify({ status: to, reason: "Worked from the JUPEB record" }) });
        if (!st.ok) { notifyProblem((await st.json().catch(() => null)) ?? { status: st.status, title: st.statusText }); return; }
      }
      const r = await fetch(`/api/bff/api/v1/helpdesk/tickets/${ticket.id}/resolve`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${ticket.number} resolved`) }, body: JSON.stringify({ summary: resolve.summary.trim(), details: resolve.details.trim() }) });
      if (!r.ok) { notifyProblem((await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }); return; }
      notify(`${ticket.number} resolved; the candidate is asked to confirm`);
      setResolve(null);
      router.refresh();
    } finally { setBusy(false); }
  }
  function openResolve() {
    if (!ticket) return;
    const acts = data.actions.filter((a) => a.ticket_id === ticket.id && a.action !== "TICKET_CREATED");
    const done = acts.map((a) => a.summary ?? ACTION_WORD[a.action] ?? a.action);
    setResolve({ summary: acts[0] ? (acts[0].summary ?? ACTION_WORD[acts[0].action] ?? acts[0].action).slice(0, 300) : "", details: done.length ? `Action taken:\n${done.map((d) => `- ${d}`).join("\n")}` : "" });
  }

  const nin = c.nin ? `${"•".repeat(Math.max(0, c.nin.length - 4))}${c.nin.slice(-4)}` : "—";
  const v = (x: string | null | undefined) => (x && String(x).trim() ? x : "—");
  const pending = data.payments.filter((p) => !p.confirmed_at);
  const sfPaid = data.payments.some((p) => p.confirmed_at && p.kind.startsWith("SCHOOL_"));
  return (
    <>
      <Note kind="info" title="SUPPORT MODE — you are acting on this JUPEB record on behalf of the candidate"
        action={ticket ? <span className="row row--inline row--tight">
          <Btn kind="secondary" disabled={busy} onClick={() => setEscalate({ office: "jupeb", reason: "" })}>Escalate</Btn>
          <Btn kind="primary" disabled={busy || ticket.status === "RESOLVED" || ticket.status === "CLOSED"} onClick={openResolve}>Resolve ticket</Btn>
        </span> : undefined}>
        <span className="row row--inline" style={{ gap: "var(--s-4)", flexWrap: "wrap" }}>
          <span><b>Agent</b> {data.agent}</span>
          <span><b>Candidate</b> {fullName(c)} · <span className="tnum">{c.application_no}</span></span>
          <span><b>Ticket</b> {ticket ? <Link href={`/helpdesk/tickets/${ticket.id}`} className="lnk tnum">{ticket.number}</Link> : <span className="sub2">none — give a reason with every change</span>}{ticket ? <span className="sub2"> · {ticket.status.toLowerCase().replace(/_/g, " ")}</span> : null}</span>
          <span><b>Reason for access</b> {ticket ? `${ticket.category}: ${ticket.subject}` : "JUPEB support"}</span>
        </span>
      </Note>
      <PageHead title={fullName(c)} eyebrow={<span className="tnum">{c.application_no}{c.exam_no ? ` · JUPEB ${c.exam_no}` : ""}{c.legacy_ref ? ` · Old portal ${c.legacy_ref}` : ""}</span>}
        description={<>JUPEB {c.session} · {streamLabel(c.stream)}{c.combination_code ? ` · ${c.combination_code}` : ""} · <Pil kind={stateKind(c.state)}>{STATE_SHORT[c.state] ?? c.state}</Pil></>}
        actions={<><LinkBtn href="/helpdesk/jupeb">JUPEB Student Support</LinkBtn>{ticket ? <LinkBtn href={`/helpdesk/tickets/${ticket.id}`}>Back to the ticket</LinkBtn> : null}<LinkBtn href="/helpdesk">Support Desk</LinkBtn></>} />

      <Panel title="Support actions" right={<span className="sub2">Only what your JUPEB postings carry is offered</span>}>
        <PBody>
          <div className="row" style={{ flexWrap: "wrap" }}>
            {caps.has("EDIT_CONTACT") ? <Btn kind="secondary" disabled={busy} onClick={openContact}>Correct contact details</Btn> : null}
            {caps.has("RESET_PASSWORD") ? <Btn kind="secondary" disabled={busy} onClick={() => setReset({ method: "LINK", reason: "", result: null })}>Reset password</Btn> : null}
            {caps.has("VERIFY_PAYMENT") || caps.has("VIEW_PAYMENTS") || caps.has("INVESTIGATE_PAYMENT") ? <Btn kind="secondary" onClick={() => openTab("payments")}>Payments</Btn> : null}
            {caps.has("SYNC_ENTITLEMENT") && c.state === "ADMITTED" ? <Btn kind="secondary" disabled={busy} onClick={() => setRefresh({ reason: "" })}>Refresh activation</Btn> : null}
            {caps.has("CREATE_TICKET") ? <Btn kind="secondary" disabled={busy || !category} onClick={() => setRaise({ subject: "", description: "", details: {} })}>Raise a ticket for the candidate</Btn> : null}
            <Btn kind="ghost" onClick={() => openTab("history")}>Support action history</Btn>
          </div>
          <p className="sub2 mt-2">Name, sex, date of birth, NIN, nationality, state and LGA are corrected only by the JUPEB Office: the candidate asks from My Profile on their portal, or escalate the ticket to the JUPEB Office.</p>
        </PBody>
      </Panel>

      <Tabs<Tab> look="line" value={tabNow} onChange={openTab} items={[
        { id: "record", label: "Record" }, { id: "payments", label: "Payments", count: data.payments.length }, { id: "tickets", label: "Tickets", count: data.tickets.length },
        { id: "history", label: "Support actions", count: data.actions.length },
      ]} />

      {tabNow === "record" ? (
        <div className="grid grid--2">
          <Panel title="Identity"><PBody><KvGrid cls="grid--2" pairs={[
            ["Surname", v(c.surname)], ["First name", v(c.first_name)], ["Middle name", v(c.middle_name)], ["Sex", c.sex === "F" ? "Female" : c.sex === "M" ? "Male" : v(c.sex)],
            ["Date of birth", c.date_of_birth ? day(c.date_of_birth) : "—"], ["NIN", nin], ["Nationality", v(c.nationality)], ["State / LGA", [c.state_of_origin, c.lga].filter(Boolean).join(" / ") || "—"],
          ]} /></PBody></Panel>
          <Panel title="Contact"><PBody><KvGrid cls="grid--2" pairs={[
            ["Email", v(c.email)], ["Phone", v(c.phone)], ["Contact address", v(c.contact_address)], ["Permanent address", v(c.permanent_address)],
            ["Guardian", [c.guardian_name, c.guardian_phone].filter(Boolean).join(" · ") || "—"], ["Next of kin", [c.next_of_kin_name, c.next_of_kin_phone, c.next_of_kin_relationship].filter(Boolean).join(" · ") || "—"],
          ]} /></PBody></Panel>
          <Panel title="Programme"><PBody><KvGrid cls="grid--2" pairs={[
            ["Session", c.session], ["Programme", streamLabel(c.stream)], ["Combination", c.combination_code ? `${c.combination_code}${c.combination_name ? ` — ${c.combination_name}` : ""}` : "—"],
            ["Class", v(c.class_name)], ["Subjects registered", c.subjects_registered_at ? day(c.subjects_registered_at) : "Not yet"], ["Studentship activated", c.activated_at ? day(c.activated_at) : "—"],
            ["Examination number", c.exam_no ?? "Not yet assigned"], ["From the old portal", c.legacy_source ? `Yes (${c.legacy_ref ?? "—"})` : "No"],
          ]} /></PBody></Panel>
          <Panel title="Sign-in account"><PBody><KvGrid cls="grid--2" pairs={[
            ["Sign-in email", data.account.email], ["Last signed in", when(data.account.last_signed_in_at)],
            ["Locked", data.account.locked ? <Pil key="l" kind="bad">Locked after failed sign-ins</Pil> : "No"],
            ["Password", data.account.temporary ? <Pil key="t" kind="warn">Temporary — to be changed at sign-in</Pil> : data.account.must_change_password ? <Pil key="t" kind="warn">To be changed at sign-in</Pil> : "Set by the candidate"],
          ]} />
            <p className="sub2 mt-2">The password itself is never shown or recorded. A reset is the JUPEB portal&rsquo;s own link, or a temporary password on the candidate&rsquo;s ticket.</p>
          </PBody></Panel>
        </div>
      ) : tabNow === "payments" ? (
        <>
          {c.fees ? (
            <Panel title="School fees (the Bursary's figures)"><PBody><KvGrid cls="grid--4" pairs={[
              ["Category", `${feeCategoryLabel(c.fees.category)} · ${c.fees.indigene ? "indigene" : "non-indigene"}`], ["School fee", naira(c.fees.total)], ["Paid", naira(c.fees.paid)], ["Outstanding", naira(c.fees.outstanding)],
            ]} /></PBody></Panel>
          ) : null}
          {c.state === "ADMITTED" && sfPaid && caps.has("SYNC_ENTITLEMENT") ? (
            <Note kind="info" title="A school fee is confirmed but the record is still Admitted" action={<Btn kind="primary" disabled={busy} onClick={() => setRefresh({ reason: "" })}>Refresh activation</Btn>}>
              The activation is re-applied by the JUPEB rule the payment applies; nothing is created or marked paid.</Note>
          ) : null}
          <Panel title="JUPEB payments">
            <PBody>
              {!data.payments.length ? <p className="sub2">{caps.has("VIEW_PAYMENTS") || caps.has("INVESTIGATE_PAYMENT") ? "No payment reference on the record." : "Your postings do not carry JUPEB payments."}</p> : (
                <DTable noPrint pageSize={0} cols={["Fee", "Reference", "Amount|num", "Generated", "Status", "Gateway", "Attempts|num", ""]} rows={data.payments.map((p) => [
                  FEE_KIND[p.kind] ?? p.kind,
                  <span key="r" className="tnum">{p.reference}{p.old_reference ? <div className="sub2">Old portal {p.old_reference}</div> : null}</span>,
                  naira(p.amount), day(p.created_at),
                  p.confirmed_at ? <Pil key="s" kind="ok">{`Confirmed ${day(p.confirmed_at)}${p.channel ? ` · ${p.channel}` : ""}`}</Pil> : <Pil key="s" kind={p.state === "EXPIRED" ? "grey" : "warn"}>{p.state === "EXPIRED" ? "Expired" : "Awaiting payment"}</Pil>,
                  p.gateway ? <span key="g" className="sub2">{p.gateway} · {p.gateway_outcome ?? "—"}{p.gateway_at ? ` · ${when(p.gateway_at)}` : ""}</span> : <span key="g" className="sub2">—</span>,
                  Number(p.attempts),
                  !p.confirmed_at && caps.has("VERIFY_PAYMENT") ? <Btn key="v" kind="secondary" size="sm" disabled={busy} onClick={() => setVerify({ reference: p.reference, reason: "", result: null })}>Verify with the gateway</Btn> : "",
                ])} />
              )}
              {pending.length && !caps.has("VERIFY_PAYMENT") ? <p className="sub2 mt-2">Your postings do not carry verifying payments; escalate the ticket to the Bursary.</p> : null}
              <p className="sub2 mt-2">A payment is confirmed only by the gateway or the Bursary. Support never marks one paid, changes an amount or refunds.</p>
            </PBody>
          </Panel>
        </>
      ) : tabNow === "tickets" ? (
        <Panel title="The candidate's tickets">
          {data.tickets.length ? (
            <DTable pageSize={0} cols={["Ticket", "Subject", "Category", "Status|mid", "Agent", "Updated", ""]} rows={data.tickets.map((t) => [
              <Link key="n" className="lnk tnum" href={`/helpdesk/tickets/${t.id}`}>{t.number}</Link>, t.subject, t.category,
              <Pil key="s" kind={t.status === "RESOLVED" || t.status === "CLOSED" ? "ok" : t.status === "WAITING_FOR_OFFICE" ? "warn" : "info"}>{t.status.toLowerCase().replace(/_/g, " ")}</Pil>,
              t.agent ?? "—", when(t.updated_at),
              ticket?.id === t.id ? <span key="w" className="sub2">Working on it</span> : <LinkBtn key="w" size="sm" href={`/helpdesk/jupeb/${id}?ticket=${t.id}`}>Work from here</LinkBtn>,
            ])} />
          ) : <PBody><p className="sub2">No ticket from this candidate.</p></PBody>}
        </Panel>
      ) : (
        <Panel title="Support action history">
          {data.actions.length ? (
            <DTable pageSize={25} cols={["When", "Act", "What was done", "Reason", "Agent", "Ticket", "Result|mid"]} rows={data.actions.map((a) => [
              when(a.at), ACTION_WORD[a.action] ?? a.action, a.summary ?? (a.field ? `${a.field}: ${a.old_value ?? "—"} → ${a.new_value ?? "—"}` : "—"), a.reason, a.agent,
              a.ticket_number ?? "—", <Pil key="r" kind={(RESULT_WORD[a.result] ?? [a.result, "grey"])[1]}>{(RESULT_WORD[a.result] ?? [a.result])[0]}</Pil>,
            ])} />
          ) : <PBody><p className="sub2">No support act on this record yet.</p></PBody>}
        </Panel>
      )}

      {contact ? (
        <Modal title="Correct the contact details" onClose={() => setContact(null)} wide
          foot={<><Btn kind="ghost" onClick={() => setContact(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || !/^0\d{10}$/.test(contact.phone.trim()) || contact.reason.trim().length < 5} onClick={() => void saveContact()}>{busy ? "Saving…" : "Save"}</Btn></>}>
          <div className="grid grid--3">
            {([["phone", "Phone"], ["guardianName", "Guardian"], ["guardianPhone", "Guardian's phone"], ["nextOfKinName", "Next of kin"], ["nextOfKinPhone", "Next of kin's phone"], ["nextOfKinRelationship", "Relationship"]] as const).map(([k, l]) => (
              <Field key={k} id={`jc-${k}`} label={l} required={k === "phone"}><input id={`jc-${k}`} className="ctl" value={contact[k]} maxLength={k.endsWith("Phone") || k === "phone" ? 11 : 120} onChange={(e) => setContact({ ...contact, [k]: e.target.value })} /></Field>
            ))}
          </div>
          <div className="grid grid--3">
            {([["contactAddress", "Contact address"], ["permanentAddress", "Permanent address"], ["guardianAddress", "Guardian's address"]] as const).map(([k, l]) => (
              <Field key={k} id={`jc-${k}`} label={l}><textarea id={`jc-${k}`} className="ctl" rows={2} maxLength={300} value={contact[k]} onChange={(e) => setContact({ ...contact, [k]: e.target.value })} /></Field>
            ))}
          </div>
          <Field id="jc-reason" label="Reason" required hint="What the candidate reported and how it was confirmed"><textarea id="jc-reason" className="ctl" rows={2} maxLength={2000} value={contact.reason} onChange={(e) => setContact({ ...contact, reason: e.target.value })} /></Field>
        </Modal>
      ) : null}

      {reset ? (
        <Modal title="Reset the JUPEB portal password" onClose={() => setReset(null)}
          foot={reset.result ? <Btn kind="primary" onClick={() => setReset(null)}>Done</Btn> : <><Btn kind="ghost" onClick={() => setReset(null)}>Cancel</Btn>
            <Btn kind="primary" disabled={busy || reset.reason.trim().length < 5 || (reset.method === "TEMPORARY" && !ticket)} onClick={() => void confirmReset()}>{reset.method === "LINK" ? "Send the link" : "Issue a temporary password"}</Btn></>}>
          {reset.result ? (
            reset.result.method === "TEMPORARY_PASSWORD" ? (
              <div className="stack">
                <Note kind="info" title="Give this to the candidate now — it is shown once and kept nowhere">It works for one sign-in, until {when(String(reset.result.expiresAt))}; the candidate chooses their own at once.</Note>
                <div className="tnum b700" style={{ fontSize: 24, letterSpacing: 2, textAlign: "center", padding: "var(--s-3)", border: "1px dashed var(--line-2)", borderRadius: "var(--r-sm)" }}>{String(reset.result.temporaryPassword)}</div>
              </div>
            ) : <Note kind="ok" title="The reset link is sent">{`A one-hour link went to ${String(reset.result.sentTo ?? "the candidate's email")}. The candidate chooses the new password; the desk never sees it.`}</Note>
          ) : (
            <>
              <Field id="jr-m" label="How">
                <div className="stack" style={{ gap: 4 }}>
                  <label className="row row--inline row--tight"><input type="radio" name="jr-m" checked={reset.method === "LINK"} onChange={() => setReset({ ...reset, method: "LINK" })} /> Email a one-hour reset link (the candidate sets the password)</label>
                  <label className="row row--inline row--tight"><input type="radio" name="jr-m" checked={reset.method === "TEMPORARY"} disabled={!ticket} onChange={() => setReset({ ...reset, method: "TEMPORARY" })} /> A temporary password at the desk — one sign-in within 24 hours{!ticket ? " (only on the candidate's ticket)" : ""}</label>
                </div>
              </Field>
              <Field id="jr-r" label="Reason" required hint="How the candidate's identity was confirmed"><textarea id="jr-r" className="ctl" rows={2} maxLength={2000} value={reset.reason} onChange={(e) => setReset({ ...reset, reason: e.target.value })} /></Field>
            </>
          )}
        </Modal>
      ) : null}

      {verify ? (
        <Modal title={`Verify ${verify.reference} with the gateway`} onClose={() => setVerify(null)}
          foot={verify.result ? <Btn kind="primary" onClick={() => setVerify(null)}>Done</Btn> : <><Btn kind="ghost" onClick={() => setVerify(null)}>Cancel</Btn><Btn kind="primary" disabled={busy} onClick={() => void confirmVerify()}>{busy ? "Asking the gateway…" : "Ask the gateway"}</Btn></>}>
          {verify.result ? (
            verify.result.changed ? <Note kind="ok" title="Confirmed">The gateway confirmed the payment; the original reference now stands paid and the candidate is told.</Note>
              : <Note kind="info" title="Nothing changed">{`The gateway answered: ${String((verify.result.gateway as Record<string, unknown> | undefined)?.outcome ?? "no confirmation")}. If the candidate holds a bank debit, escalate the ticket to the Bursary with the evidence.`}</Note>
          ) : (
            <>
              <p className="sub2">The payment service asks the gateway about this reference. Only the original reference can be settled; no payment is created and none is marked paid by hand.</p>
              <Field id="jv-r" label="Reason"><textarea id="jv-r" className="ctl" rows={2} maxLength={2000} value={verify.reason} placeholder="The candidate reported the payment as not reflected" onChange={(e) => setVerify({ ...verify, reason: e.target.value })} /></Field>
            </>
          )}
        </Modal>
      ) : null}

      {refresh ? (
        <Modal title="Refresh the activation" onClose={() => setRefresh(null)}
          foot={<><Btn kind="ghost" onClick={() => setRefresh(null)}>Cancel</Btn><Btn kind="primary" disabled={busy} onClick={() => void confirmRefresh()}>Re-apply the rule</Btn></>}>
          <p className="sub2">The JUPEB rule that activates a student on a confirmed school fee is applied again. It does nothing when no school fee is confirmed.</p>
          <Field id="jf-r" label="Reason"><textarea id="jf-r" className="ctl" rows={2} maxLength={2000} value={refresh.reason} placeholder="The school fee is paid but the studentship did not follow" onChange={(e) => setRefresh({ reason: e.target.value })} /></Field>
        </Modal>
      ) : null}

      {raise && category ? (
        <Modal title="Raise a ticket for the candidate" onClose={() => setRaise(null)}
          foot={<><Btn kind="ghost" onClick={() => setRaise(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || !raise.subject.trim() || !raise.description.trim()} onClick={() => void confirmRaise()}>Raise the ticket</Btn></>}>
          <Field id="jt-cat" label="Category"><input id="jt-cat" className="ctl" value={category.name} disabled /></Field>
          {fields.map((fl) => (
            <Field key={fl.key} id={`jt-${fl.key}`} label={fl.label} required={fl.required}>
              {fl.options ? <select id={`jt-${fl.key}`} className="ctl" value={raise.details[fl.key] ?? ""} onChange={(e) => setRaise({ ...raise, details: { ...raise.details, [fl.key]: e.target.value } })}>
                <option value="">—</option>{fl.options.map((o) => <option key={o}>{o}</option>)}</select>
                : <input id={`jt-${fl.key}`} className="ctl" value={raise.details[fl.key] ?? ""} onChange={(e) => setRaise({ ...raise, details: { ...raise.details, [fl.key]: e.target.value } })} />}
            </Field>
          ))}
          <Field id="jt-s" label="Subject" required><input id="jt-s" className="ctl" maxLength={200} value={raise.subject} onChange={(e) => setRaise({ ...raise, subject: e.target.value })} /></Field>
          <Field id="jt-d" label="Description" required><textarea id="jt-d" className="ctl" rows={4} maxLength={8000} value={raise.description} onChange={(e) => setRaise({ ...raise, description: e.target.value })} /></Field>
        </Modal>
      ) : null}

      {escalate && ticket ? (
        <Modal title={`Escalate ${ticket.number}`} onClose={() => setEscalate(null)}
          foot={<><Btn kind="ghost" onClick={() => setEscalate(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || escalate.reason.trim().length < 5} onClick={() => void confirmEscalate()}>Escalate</Btn></>}>
          <Field id="je-o" label="To"><select id="je-o" className="ctl" value={escalate.office} onChange={(e) => setEscalate({ ...escalate, office: e.target.value })}>{OFFICES.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></Field>
          <Field id="je-r" label="What the office must decide" required><textarea id="je-r" className="ctl" rows={3} maxLength={2000} value={escalate.reason} onChange={(e) => setEscalate({ ...escalate, reason: e.target.value })} /></Field>
        </Modal>
      ) : null}

      {resolve && ticket ? (
        <Modal title={`Resolve ${ticket.number}`} onClose={() => setResolve(null)}
          foot={<><Btn kind="ghost" onClick={() => setResolve(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || !resolve.summary.trim() || !resolve.details.trim()} onClick={() => void confirmResolve()}>Resolve</Btn></>}>
          <Field id="jz-s" label="Summary" required><input id="jz-s" className="ctl" maxLength={300} value={resolve.summary} onChange={(e) => setResolve({ ...resolve, summary: e.target.value })} /></Field>
          <Field id="jz-d" label="Details for the candidate" required><textarea id="jz-d" className="ctl" rows={5} maxLength={8000} value={resolve.details} onChange={(e) => setResolve({ ...resolve, details: e.target.value })} /></Field>
        </Modal>
      ) : null}
    </>
  );
}
