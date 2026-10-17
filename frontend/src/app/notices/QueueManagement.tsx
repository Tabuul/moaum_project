"use client";

/**
 * V436: the outbox paused, switched and cleared — the delivery switches (queue processing, e-mail, SMS, portal notices:
 * delivery only, the modules go on generating), the pending e-mail/SMS queue cancelled with a reason after a confirmation
 * (never deleted; sent and failed history untouched), the clearance on the record, and the jobs that would refill the queue.
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { Btn, KvGrid, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { SmtpPace } from "@/lib/mail-sending";
import { SmtpPaceBlock } from "./SmtpPaceBlock";

export interface Delivery {
  dispatch_enabled: boolean; email_delivery: boolean; sms_delivery: boolean; portal_delivery: boolean;
  dispatch_paused_at: string | null; dispatch_paused_by_name: string | null; updated_at: string | null; updated_office: string | null;
}
export interface Pending { channel: string; pending: number; oldest: string | null; newest: string | null }
export interface Clearance {
  id: string; cleared_at: string; cleared_office: string | null; cleared_by_name?: string | null; channels: string; reason: string;
  email_pending_before: number; sms_pending_before: number; email_cancelled: number; sms_cancelled: number; email_remaining: number; sms_remaining: number;
  email_sent: number; sms_sent: number; email_failed: number; sms_failed: number; jobs_open: number; campaigns_sending: number;
  verification?: { pending: Pending[]; processing: number; dispatch_enabled: boolean };
}
export interface OpenJob { id: string; kind: string; state: string; about: string; created_at: string; created_office: string | null; reached: number; queued: number; runs: number }
/** V438: a provider's delivery report as it came, and what was done with it */
export interface Receipt { id: string; provider: string; received_at: string; provider_id: string | null; status_word: string | null; notice_id: string | null; outcome: string; detail: string | null; channel: string | null; recipient: string | null; subject: string | null }

const DEFAULT_REASON = "Pending notification queue cancelled by the administrator before delivery";

function when(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString("en-GB", { day: "2-digit", month: "short" }) + " " + d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
}

export function QueueManagement({ delivery, pending, jobs, last, may, mayClear, receipts, receiptToken, smtpPace, smtp }: {
  delivery: Delivery; pending: Pending[]; jobs: OpenJob[]; last: Clearance | null; may: boolean; mayClear: boolean; receipts: Receipt[]; receiptToken: string | null;
  /** V532: the SMTP pace, and whether e-mail goes over SMTP now */
  smtpPace?: SmtpPace | null; smtp?: boolean;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [channels, setChannels] = useState({ EMAIL: true, SMS: true });
  const [reason, setReason] = useState(DEFAULT_REASON);
  const [confirming, setConfirming] = useState(false);
  const [report, setReport] = useState<Clearance | null>(null);
  const [showToken, setShowToken] = useState(false);
  const count = (c: string) => Number(pending.find((p) => p.channel === c)?.pending ?? 0);
  const chosen = (["EMAIL", "SMS"] as const).filter((c) => channels[c]);
  const toCancel = chosen.reduce((n, c) => n + count(c), 0);

  async function send(path: string, body: unknown, why: string, method: string = "POST"): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/platform/notices${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(why) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return null; }
      notify(why);
      router.refresh();
      return j;
    } finally {
      setBusy(false);
    }
  }

  const toggle = (key: "dispatch" | "email" | "sms" | "portal", label: string) => (e: React.ChangeEvent<HTMLInputElement>) =>
    void send("/delivery", { [key]: e.target.checked }, `${label} switched ${e.target.checked ? "on" : "off"}`, "PUT");

  return (
    <>
      <Panel title="Delivery" right="Delivery only: the modules go on generating, and the outbox holds what is not sent">
        <PBody>
          {problem ? <ProblemNotice problem={problem} /> : null}
          <div className="grid grid--2">
            <label className="row row--inline row--tight"><input type="checkbox" checked={delivery.dispatch_enabled} disabled={!may || busy} onChange={toggle("dispatch", "Queue processing")} /> Queue processing
              {delivery.dispatch_enabled ? <Pil kind="ok">running</Pil> : <Pil kind="warn">paused{delivery.dispatch_paused_at ? ` since ${when(delivery.dispatch_paused_at)}${delivery.dispatch_paused_by_name ? " by " + delivery.dispatch_paused_by_name : ""}` : ""}</Pil>}</label>
            <label className="row row--inline row--tight"><input type="checkbox" checked={delivery.email_delivery} disabled={!may || busy} onChange={toggle("email", "E-mail delivery")} /> E-mail delivery {delivery.email_delivery ? <Pil kind="ok">on</Pil> : <Pil kind="warn">held</Pil>}</label>
            <label className="row row--inline row--tight"><input type="checkbox" checked={delivery.sms_delivery} disabled={!may || busy} onChange={toggle("sms", "SMS delivery")} /> SMS delivery {delivery.sms_delivery ? <Pil kind="ok">on</Pil> : <Pil kind="warn">held</Pil>}</label>
            <label className="row row--inline row--tight"><input type="checkbox" checked={delivery.portal_delivery} disabled={!may || busy} onChange={toggle("portal", "Portal notices")} /> Portal notices {delivery.portal_delivery ? <Pil kind="ok">on</Pil> : <Pil kind="warn">not made</Pil>}</label>
          </div>
          <div className="sub2">
            While the portal is being tested, switch e-mail and SMS delivery off: every module still generates its messages, the templates can still be tested and
            previewed, and the outbox holds the messages unsent until delivery is switched on or the queue is cleared. A portal notice is delivered the moment it is
            made, so the portal switch keeps it from being made at all. Queue processing paused holds every channel.
          </div>
        </PBody>
        {smtpPace ? <SmtpPaceBlock pace={smtpPace} smtp={!!smtp} waiting={count("EMAIL")} may={may} /> : null}
        <PBody style={{ borderTop: "1px solid var(--line-2)" }}>
          <div className="row"><b>Delivery receipts</b>{receiptToken ? <Pil kind="ok">door open</Pil> : <Pil kind="grey">no token yet</Pil>}</div>
          <div className="sub2">
            A message is marked sent when the provider accepts it. A provider that reports further &mdash; delivered, bounced, undelivered &mdash; posts its report to the
            receipt door, and the word lands on the message without changing its state. Give the provider the door address with the token: Resend&rsquo;s webhooks to{" "}
            <code>/api/v1/notices/receipts/resend</code>, eBulkSMS&rsquo;s delivery reports to <code>/api/v1/notices/receipts/ebulksms</code>, anything else to{" "}
            <code>/api/v1/notices/receipts/generic</code> with <code>id</code>, <code>status</code> and <code>detail</code>; the token goes as <code>?token=</code> or the
            header <code>X-Receipt-Token</code>. Every report is kept below as it came, so what a provider actually sends is seen before it is trusted.
          </div>
          {may ? (
            <div className="row row--wrap row--tight mt-1">
              {receiptToken ? <Btn kind="ghost" size="sm" onClick={() => setShowToken(!showToken)}>{showToken ? "Hide the token" : "Show the token"}</Btn> : null}
              {showToken && receiptToken ? <code className="tnum" style={{ userSelect: "all" }}>{receiptToken}</code> : null}
              <Btn kind="secondary" size="sm" disabled={busy} onClick={() => { if (window.confirm(receiptToken ? "Generate a new token? The providers must be given the new one; reports with the old token are refused from now." : "Generate the receipt door's token?")) void send("/receipt-token", {}, "Delivery receipt token generated"); }}>{receiptToken ? "New token" : "Generate the token"}</Btn>
            </div>
          ) : null}
          {receipts.length ? (
            <DTable cols={["When|mid", "Provider", "Report", "Message", "Outcome|mid"]} rows={receipts.map((r) => [
              <span key="w" className="tnum sub2">{when(r.received_at)}</span>,
              r.provider,
              <span key="r"><span className="tnum">{r.provider_id ?? "\u2014"}</span> <span className="sub2">{r.status_word ?? ""}{r.detail ? ` · ${r.detail}` : ""}</span></span>,
              r.notice_id ? <span key="m" className="sub2">{r.channel} to {r.recipient}: {r.subject}</span> : <span key="m" className="sub2">no message of the portal&rsquo;s</span>,
              <Pil key="o" kind={r.outcome === "DELIVERED" ? "ok" : r.outcome === "BOUNCED" || r.outcome === "UNDELIVERED" ? "bad" : "grey"}>{r.outcome.toLowerCase().replace("_", " ")}</Pil>,
            ])} />
          ) : <div className="sub2 mt-1">No report has reached the door yet.</div>}
        </PBody>
      </Panel>

      <Panel title="Queue management" right={mayClear ? "Directorate of ICT and Super Administrator" : "Read by the offices; cleared by the Directorate of ICT"}>
        <PBody>
          <KvGrid cls="grid--2" pairs={[
            ["E-mail waiting", <span className="tnum" key="e">{count("EMAIL")}{pending.find((p) => p.channel === "EMAIL")?.oldest ? <span className="sub2"> · oldest {when(pending.find((p) => p.channel === "EMAIL")!.oldest!)}</span> : null}</span>],
            ["SMS waiting", <span className="tnum" key="s">{count("SMS")}{pending.find((p) => p.channel === "SMS")?.oldest ? <span className="sub2"> · oldest {when(pending.find((p) => p.channel === "SMS")!.oldest!)}</span> : null}</span>],
          ]} />
          {mayClear ? (
            <>
              <div className="row row--wrap row--tight mt-1">
                <label className="row row--inline row--tight"><input type="checkbox" checked={channels.EMAIL} disabled={busy} onChange={(e) => setChannels({ ...channels, EMAIL: e.target.checked })} /> E-mail</label>
                <label className="row row--inline row--tight"><input type="checkbox" checked={channels.SMS} disabled={busy} onChange={(e) => setChannels({ ...channels, SMS: e.target.checked })} /> SMS</label>
                <input className="ctl" aria-label="Reason" value={reason} onChange={(e) => setReason(e.target.value)} style={{ minWidth: 360 }} />
                {!confirming ? <Btn kind="secondary" size="sm" disabled={busy || !chosen.length || !reason.trim()} onClick={() => { setReport(null); setConfirming(true); }}>Clear pending queue…</Btn> : null}
              </div>
              {confirming ? (
                <Note kind="bad" title="Clear the pending queue">
                  <div>You are about to cancel {chosen.includes("EMAIL") ? <b>{count("EMAIL")} pending e-mail{count("EMAIL") === 1 ? "" : "s"}</b> : null}{chosen.length === 2 ? " and " : ""}{chosen.includes("SMS") ? <b>{count("SMS")} pending SMS</b> : null}.</div>
                  <div className="sub2 mt-1">
                    These messages have not been sent. Queue processing is paused first and the clearance runs under the dispatcher&rsquo;s own lock, so nothing is sent
                    meanwhile. Already sent, delivered and failed messages stay in the history; the cancelled ones stay too, marked cancelled with your reason. Queue
                    processing stays paused until you resume it below.
                  </div>
                  <div className="row row--tight mt-1">
                    <Btn kind="primary" size="sm" disabled={busy} onClick={async () => {
                      const j = await send("/clear", { channels: chosen, reason: reason.trim() }, `Pending notification queue cleared (${chosen.join(" + ")}): ${reason.trim()}`);
                      setConfirming(false);
                      if (j) setReport(j as unknown as Clearance);
                    }}>Cancel {toCancel} unsent message{toCancel === 1 ? "" : "s"}</Btn>
                    <Btn kind="ghost" size="sm" disabled={busy} onClick={() => setConfirming(false)}>Keep the queue</Btn>
                  </div>
                </Note>
              ) : null}
            </>
          ) : null}
          {report ? (
            <Note kind="ok" title="Notification queue clearance report">
              <KvGrid cls="grid--2" pairs={[
                ["E-mail: pending before", String(report.email_pending_before)], ["SMS: pending before", String(report.sms_pending_before)],
                ["E-mail: cancelled", String(report.email_cancelled)], ["SMS: cancelled", String(report.sms_cancelled)],
                ["E-mail: remaining pending", String(report.email_remaining)], ["SMS: remaining pending", String(report.sms_remaining)],
                ["E-mail: already sent (untouched)", String(report.email_sent)], ["SMS: already sent (untouched)", String(report.sms_sent)],
                ["E-mail: failed (untouched)", String(report.email_failed)], ["SMS: failed (untouched)", String(report.sms_failed)],
                ["Processing at the time", String(report.verification?.processing ?? 0)], ["Jobs still open", String(report.jobs_open)],
              ]} />
              <div className="sub2 mt-1">Verified after the clearance: {(report.verification?.pending ?? []).map((p) => `${p.channel === "EMAIL" ? "e-mail" : "SMS"} pending ${p.pending}`).join(", ")}. Queue processing is paused.</div>
              {may ? <Btn kind="primary" size="sm" disabled={busy || delivery.dispatch_enabled} onClick={() => void send("/delivery", { dispatch: true }, "Queue processing resumed after the clearance", "PUT")}>Resume queue processing</Btn> : null}
            </Note>
          ) : null}
          {last ? (
            <div className="sub2 mt-1">
              Last cleared {when(last.cleared_at)}{last.cleared_by_name ? ` by ${last.cleared_by_name}` : ""}{last.cleared_office ? ` (${last.cleared_office})` : ""}: {last.email_cancelled} e-mail
              and {last.sms_cancelled} SMS cancelled on {last.channels.toLowerCase().replace(",", " + ")} — &ldquo;{last.reason}&rdquo;.
            </div>
          ) : <div className="sub2 mt-1">The queue has never been cleared.</div>}
        </PBody>
        {jobs.length ? (
          <>
            <PBody style={{ borderTop: "1px solid var(--line-2)" }}>
              <b>Jobs still writing to the queue</b>
              <div className="sub2">A job left running refills the queue it just emptied. End it here if its messages are not wanted; a campaign&rsquo;s job cancels the campaign. The weekly biodata and staff contact reminders have their own switches on <a href="/notices/templates">Notification templates</a>.</div>
            </PBody>
            <DTable cols={["Job", "About", "State|mid", "Since|mid", "Reached|num", "Queued|num", "|mid"]} rows={jobs.map((j) => [
              <span key="k">{j.kind === "CAMPAIGN" ? "Campaign" : j.kind === "WINDOW" ? "Portal window" : j.kind.toLowerCase().replace("_", " ")}</span>,
              j.about,
              <Pil key="s" kind={j.state === "RUNNING" ? "info" : "grey"}>{j.state.toLowerCase()}</Pil>,
              <span key="w" className="tnum sub2">{when(j.created_at)}</span>,
              <span key="r" className="tnum">{j.reached}</span>,
              <span key="q" className="tnum">{j.queued}</span>,
              mayClear ? <Btn key="c" kind="ghost" size="sm" disabled={busy} onClick={() => { const why = window.prompt("Why is this job ended?", "Its messages are not wanted"); if (why !== null) void send(`/jobs/${j.id}/cancel`, { reason: why }, `Notification job ended: ${why}`); }}>End</Btn> : "",
            ])} />
          </>
        ) : null}
      </Panel>
    </>
  );
}
