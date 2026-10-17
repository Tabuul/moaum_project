"use client";

/** tHanging — proto/part48.html: a payment that succeeded at the gateway has succeeded; the portal asks the gateway, not the student (V037).
 *  Oct 2026: a payment opened on Pay on Quickteller (PayDirect) cannot be asked about — Interswitch reports it to the portal, and the
 *  sweep leaves it alone; WebPAY's requery does not know it. Such a row says so, and sends the Bursary to the collections report import.
 *  V480: the receipts payers reported (Payment Log Id, day, amount, where) are listed, and the list Interswitch support is asked to
 *  re-send notifications for is taken as Excel. V490: each receipt says where it stands — waiting, seen short, seen against another
 *  reference, not found, confirmed — and the Bursary marks one Interswitch cannot find as not found, with a note the payer is told. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { OUTCOME, when, type PaymentsDesk } from "@/lib/bursary";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { ASK_HEADERS, CHANNEL_LABEL, CLAIM_STATE, askRows, paidDay, type AskRow, type ClaimChannel } from "@/lib/paydirect-claim";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { COLLECTIONS_REPORT_ANCHOR } from "../gateways/PayOnQuickteller";

/** a checkout on Pay on Quickteller: Interswitch reports it (PayDirect); nothing asks Interswitch about it */
const reportedOnly = (gateway: string | null | undefined) => gateway === "paydirect";
const IMPORT_HREF = `/finance/gateways#${COLLECTIONS_REPORT_ANCHOR}`;

export function Hanging({ d, actingOffice }: { d: PaymentsDesk; actingOffice: string | null }) {
  const router = useRouter();
  // V520: the Students Account Officer works the desk (asks the gateway, resolves an event, marks a receipt not found or reopens it);
  // the collections report is imported on the gateways screen, which stays the Bursary's and ICT's
  const may = ["bursar", "studentaccounts", "ict", "admin", "super"].includes(actingOffice ?? "");
  const mayImport = ["bursar", "ict", "admin", "super"].includes(actingOffice ?? "");
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [said, setSaid] = useState<string | null>(null);
  const settledBySweep = d.events.filter((e) => e.source === "SWEEP" && e.outcome === "SETTLED").length;
  const settledByVerify = d.events.filter((e) => e.source === "VERIFY" && e.outcome === "SETTLED").length;
  const needsPerson = d.events.filter((e) => ["UNKNOWN_REFERENCE", "SHORT_PAID", "GATEWAY_ERROR"].includes(e.outcome) && !e.resolved_at);
  const onQuickteller = d.hanging.filter((h) => reportedOnly(h.gateway)).length;
  const claims = d.claims ?? [];
  // V490: the receipts that wait on the Bursary — not confirmed, not marked not found
  const claimsOpen = claims.filter((c) => ["WAITING", "SEEN", "ELSEWHERE"].includes(c.state)).length;
  const [notFound, setNotFound] = useState<{ reference: string; log: string; note: string } | null>(null);
  const byWhom = (office: string | null) => !office || ["student", "applicant"].includes(office) ? "by the payer"
    : ["ictagent", "helpdeskhead"].includes(office) ? "by ICT Support" : `by ${office}`;

  /** V490: the Bursary's word on a receipt: not found at Interswitch (the payer told), or reopened */
  async function mark(reference: string, found: "NOT_FOUND" | "REOPEN", note?: string) {
    setBusy(`mark:${reference}`);
    setProblem(null);
    try {
      const path = found === "NOT_FOUND" ? "not-found" : "reopen";
      const r = await fetch(`/api/bff/api/v1/payments/claims/${encodeURIComponent(reference)}/${path}`, { method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(found === "NOT_FOUND" ? `Receipt for ${reference} not found at Interswitch` : `Receipt for ${reference} reopened`) },
        body: JSON.stringify(found === "NOT_FOUND" ? { note } : {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      notify(found === "NOT_FOUND" ? `${reference}: marked not found; the payer is told` : `${reference}: reopened`);
      setNotFound(null);
      router.refresh();
    } finally {
      setBusy(null);
    }
  }

  /** V480: what Interswitch support is asked to re-send, the last fourteen days, as Excel */
  async function askInterswitch() {
    setBusy("ask");
    setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/payments/paydirect/ask-list?days=14", { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      const rows = (j ?? []) as AskRow[];
      if (!rows.length) { notify("Nothing to ask Interswitch about: every Pay on Quickteller reference of the last 14 days is reported"); return; }
      const blob = await brandedXlsx("Payments to re-send: Pay on Quickteller", ASK_HEADERS, askRows(rows), {
        sheetName: "Ask Interswitch", serial: docSerial("PDX"),
        sub: "Please re-send the payment notification for each reference below, or confirm it was not paid.",
        meta: [["Period", "The last 14 days, opened over an hour before"], ["References", String(rows.length)], ["With the payer's receipt", String(rows.filter((x) => x.payment_log_id).length)]],
      });
      downloadBlob(blob, `ask-interswitch-${new Date().toISOString().slice(0, 10)}.xlsx`);
    } finally {
      setBusy(null);
    }
  }

  async function verify(reference: string) {
    setBusy(reference);
    setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/payments/verify", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Hanging payment ${reference} verified with the gateway`) }, body: JSON.stringify({ reference }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      setSaid(`${reference}: ${j.outcome}${j.said ? ` (${j.said})` : ""}`);
      notify(`${reference}: ${j.outcome}`);
      router.refresh();
    } finally {
      setBusy(null);
    }
  }

  return (
    <>
      <Note kind="info" title="A payment that succeeded at the gateway has succeeded">
        The gateway&rsquo;s record is the fact. The portal asks the gateway.
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title={said}>On the record; the student is told when a settlement posts.</Note> : null}
      <Tiles items={[
        ["Hanging now", String(d.hanging.length), d.hanging.length ? "var(--red-ink)" : null, "Checkout opened, nothing confirmed, last three days"],
        ["Resolved without a person", String(settledBySweep + settledByVerify), "var(--green-ink)", `${settledBySweep} by the sweep, ${settledByVerify} on request`],
        ["Needs a person", String(needsPerson.length), needsPerson.length ? "var(--red-ink)" : null, "Unknown reference, short paid, or the gateway silent"],
        ["The sweep", "Every 10 min", null, "Card checkouts; Pay on Quickteller waits for Interswitch's report"],
      ]} />
      {onQuickteller || claimsOpen ? (
        <Note kind="info" title={onQuickteller ? `${onQuickteller} opened on Pay on Quickteller — Interswitch reports these; the portal cannot ask` : `${claimsOpen} receipt${claimsOpen === 1 ? "" : "s"} reported by payers, not yet reported by Interswitch`}
          action={<div className="row row--tight">
            <Btn kind="ghost" disabled={busy !== null} onClick={() => void askInterswitch()}>{busy === "ask" ? "Preparing…" : "Ask Interswitch (Excel)"}</Btn>
            {mayImport ? <LinkBtn kind="primary" href={IMPORT_HREF}>Import the collections report</LinkBtn> : null}
          </div>}>
          A payment made at a bank or on Quickteller (PayDirect) reaches the portal only when Interswitch sends its payment notification. If the payer
          paid and nothing arrived, import Interswitch&rsquo;s collections report (each reference is matched and confirmed, a short payment kept open), or
          send Interswitch support the Excel list (every unreported reference of the last 14 days, with the Payment Log Id where the payer reported
          the receipt) and ask them to re-send the notifications. A reference that is not in the report was not paid.
        </Note>
      ) : null}
      <Panel title="Hanging at a gateway" right="Oldest first · a card checkout is asked about after five minutes, up to twelve times; Pay on Quickteller waits for Interswitch's report">
        {d.hanging.length ? (
          <DTable cols={["Opened|mid", "Payer", "Reference", "Gateway", "Amount|num", "Asked|mid", "|num"]} rows={d.hanging.map((h) => [
            <span className="sub2 tnum" key="o">{when(h.opened_at)}<div className="sub2">{h.minutes} min ago</div></span>,
            <Two key="p" a={h.payer ?? "—"} b={h.number ?? h.kind} />,
            <span className="tnum sub2" key="r">{h.reference}</span>,
            reportedOnly(h.gateway) ? <Two key="g" a="Pay on Quickteller" b="PayDirect" /> : <span key="g" style={{ textTransform: "capitalize" }}>{h.gateway}</span>,
            <b className="tnum" key="a">{h.amount == null ? "—" : money(Number(h.amount))}</b>,
            reportedOnly(h.gateway)
              ? <span className="sub2" key="c">Not asked: Interswitch reports it{h.receipt_log_id ? <div>Receipt <b className="tnum" style={{ whiteSpace: "nowrap" }}>{h.receipt_log_id}</b>{h.receipt_paid_on ? ` · paid ${paidDay(h.receipt_paid_on)}` : ""}</div> : null}</span>
              : <span className="sub2 tnum" key="c">{h.checks ? `${h.checks}× · last ${when(h.checked_at)}` : "not yet"}</span>,
            !may ? <span className="sub2" key="v">—</span>
              : reportedOnly(h.gateway) ? (mayImport ? <LinkBtn key="v" href={IMPORT_HREF}>Collections report</LinkBtn> : <span className="sub2" key="v">Bursary imports</span>)
              : <Btn key="v" kind="primary" disabled={busy !== null} onClick={() => void verify(h.reference)}>{busy === h.reference ? "Asking…" : "Ask the gateway"}</Btn>,
          ])} texts={d.hanging.map((h) => `${h.reference} ${h.payer ?? ""} ${h.number ?? ""}`)} />
        ) : <PBody><div className="sub2">Nothing is hanging in the last three days.</div></PBody>}
      </Panel>
      <Panel title="Receipts reported by payers" right="Pay on Quickteller · the last 30 days · those waiting on the Bursary first · a receipt confirms nothing until Interswitch reports the payment">
        {claims.length ? (
          <DTable cols={["Reported|mid", "Payer", "Reference", "Payment Log Id", "Paid|mid", "Amount|num", "Where", "State", "|num"]} rows={claims.map((c) => [
            <span className="sub2 tnum" key="w">{when(c.claimed_at)}<div className="sub2">{byWhom(c.claimed_office)}</div></span>,
            <Two key="p" a={c.payer ?? "—"} b={c.number ?? ""} />,
            <span className="tnum sub2" key="r">{c.reference}</span>,
            <b className="tnum" key="l" style={{ whiteSpace: "nowrap" }}>{c.payment_log_id}</b>,
            <span className="sub2 tnum" key="d" style={{ whiteSpace: "nowrap" }}>{paidDay(c.paid_on)}</span>,
            <span className="tnum" key="a">{c.amount == null ? "—" : money(Number(c.amount))}{c.due != null ? <div className="sub2">asks {money(Number(c.due))}</div> : null}</span>,
            <span className="sub2" key="c">{c.channel ? CHANNEL_LABEL[c.channel as ClaimChannel] ?? c.channel : "—"}{c.note ? <div>{c.note}</div> : null}</span>,
            <span key="s">
              <Pil kind={CLAIM_STATE[c.state]?.[1] ?? "grey"}>{c.state === "CONFIRMED" && c.confirmed_at ? `Confirmed ${when(c.confirmed_at)}` : CLAIM_STATE[c.state]?.[0] ?? c.state}</Pil>
              {c.state === "ELSEWHERE" ? <div className="sub2">Interswitch reported it against <b className="tnum">{c.seen_reference}</b>{c.seen_in === "COLLECTIONS" ? " in the collections report" : ""}: settle it to this payer</div>
                : c.state === "SEEN" ? <div className="sub2">Interswitch reported it here: {String(c.seen_outcome ?? "").toLowerCase().replace(/_/g, " ")}</div>
                : c.state === "NOT_FOUND" ? <div className="sub2">{c.not_found_note}</div> : null}
            </span>,
            // "not found" is for a receipt Interswitch has said nothing about; one it reported (here short, or elsewhere) is settled by the Bursary
            !may ? <span key="x" />
              : c.state === "NOT_FOUND" ? <Btn key="x" kind="ghost" disabled={busy !== null} onClick={() => void mark(c.reference, "REOPEN")}>Reopen</Btn>
              : c.state === "WAITING" ? <Btn key="x" kind="ghost" disabled={busy !== null} onClick={() => setNotFound({ reference: c.reference, log: c.payment_log_id, note: "" })}>Not found…</Btn>
              : <span key="x" />,
          ])} texts={claims.map((c) => `${c.reference} ${c.payer ?? ""} ${c.number ?? ""} ${c.payment_log_id} ${c.seen_reference ?? ""}`)} />
        ) : <PBody><div className="sub2">No payer has reported a receipt in the last 30 days.</div></PBody>}
      </Panel>
      <Panel title="Needs a person" right="What the sweep could not resolve on its own">
        {needsPerson.length ? (
          <DTable cols={["When|mid", "Gateway", "Reference", "Amount|num", "Why it hung", "|num"]} rows={needsPerson.map((e) => [
            <span className="sub2 tnum" key="w">{when(e.received_at)}</span>,
            <span key="g" style={{ textTransform: "capitalize" }}>{e.gateway}</span>,
            <span className="tnum sub2" key="r">{e.reference ?? "—"}</span>,
            <span className="tnum" key="a">{e.amount == null ? "—" : money(Number(e.amount))}</span>,
            <span key="o"><Pil kind={OUTCOME[e.outcome]?.[1] ?? "grey"}>{OUTCOME[e.outcome]?.[0] ?? e.outcome}</Pil><div className="sub2">{e.outcome === "UNKNOWN_REFERENCE" ? "Generated and abandoned, paid against another institution's code, or forged — the desk officer chooses; the portal does not guess." : e.outcome === "SHORT_PAID" ? "Less than the reference asks; applied as nothing, left open. A part payment needs a reference for the part." : "The gateway did not answer for this reference."}</div></span>,
            may ? <Btn key="x" kind="ghost" disabled={busy !== null} onClick={async () => { const why = window.prompt("How was it resolved? It goes on the record."); if (!why) return; const r = await fetch(`/api/bff/api/v1/payments/events/${e.id}/resolve`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Gateway event resolved: ${why}`) }, body: JSON.stringify({ resolution: why }) }); if (r.ok) { setSaid("Resolved"); notify("Gateway event resolved"); router.refresh(); } }}>Resolve</Btn> : <span className="sub2" key="x">—</span>,
          ])} />
        ) : <PBody><div className="sub2">Nothing waits on a person.</div></PBody>}
      </Panel>
      <Note kind="ok" title="The student is told">Every settlement sends the receipt by email and SMS.</Note>
      {notFound ? (
        <Modal title={`Not found at Interswitch: ${notFound.log}`} sub={<>For <b className="tnum">{notFound.reference}</b></>} onClose={() => setNotFound(null)}
          foot={<><Btn kind="ghost" onClick={() => setNotFound(null)}>Cancel</Btn>
            <Btn kind="primary" disabled={busy !== null || notFound.note.trim().length < 10} onClick={() => void mark(notFound.reference, "NOT_FOUND", notFound.note.trim())}>Mark not found and tell the payer</Btn></>}>
          <p>Say what Interswitch answered. The payer is told by e-mail and on the portal, and reads it where they pay; a corrected receipt from them reopens it.</p>
          <Field id="nf-note" label="What Interswitch said" required hint="At least ten characters">
            <textarea id="nf-note" className="ctl" rows={3} maxLength={500} value={notFound.note} onChange={(e) => setNotFound({ ...notFound, note: e.target.value })}
              placeholder="e.g. Interswitch has no payment with this Payment Log Id on our biller" />
          </Field>
        </Modal>
      ) : null}
    </>
  );
}
