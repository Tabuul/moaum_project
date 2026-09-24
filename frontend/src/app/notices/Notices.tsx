"use client";

/** pNotify / tChannels — proto/part…: the outbox. A message is marked sent only when the
 *  provider acknowledges it; nothing is pretended. Failed notices can be put back in the queue. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { Btn, KvGrid, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface Recent { id: string; channel: string; recipient: string; subject: string; created_at: string; state: string; attempts: number; sent_at: string | null; last_error: string | null }
export interface Outbox { queued: number; sent: number; failed: number; sentToday: number; emailProvider: boolean; smsProvider: boolean; recent: Recent[] }

function when(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString("en-GB", { day: "2-digit", month: "short" }) + " " + d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
}

export function Notices({ d, actingOffice }: { d: Outbox; actingOffice: string | null }) {
  const router = useRouter();
  const may = ["ict", "admin", "super"].includes(actingOffice ?? "");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);
  const noProvider = !d.emailProvider && !d.smsProvider;

  async function retry(path: string, reason: string) {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/platform/notices${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: "{}" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      setSaid(`${(j as { requeued?: number })?.requeued ?? 0} notice(s) put back in the queue`);
      notify(`${(j as { requeued?: number })?.requeued ?? 0} notice(s) requeued`);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Note kind={noProvider ? "bad" : "info"} title={noProvider ? "No provider is wired, so nothing is being sent" : "A notice is marked sent only when the provider acknowledges it"}>
        Everything with a consequence — a result, a fee deadline, a registration close, a summons — is queued here and also posted in the portal, which is the channel of record. Nothing leaves until a provider is named, and nothing is marked sent unless the gateway confirms it, so a student who says they were not told is answered from this log, not from memory.
      </Note>

      {said ? <Note kind="ok" title={said}>The dispatcher tries the queue again within the minute.</Note> : null}
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Tiles items={[
        ["Waiting", String(d.queued), d.queued ? "var(--chrome)" : null, "In the outbox"],
        ["Sent today", String(d.sentToday), null, "Acknowledged by a provider"],
        ["Failed", String(d.failed), d.failed ? "var(--red-ink)" : "var(--green-ink)", d.failed ? "After five attempts" : "None"],
        ["Sent, all time", String(d.sent), null, "On the record"],
      ]} />

      <Panel title="Providers" right="Set as service variables on the API">
        <PBody>
          <KvGrid cls="grid--2" pairs={[
            ["Email provider", d.emailProvider ? <Pil kind="ok" key="e">Wired</Pil> : <span className="sub2" key="e">None — MOAUM_NOTICES_EMAIL_URL is not set</span>],
            ["SMS provider", d.smsProvider ? <Pil kind="ok" key="s">Wired</Pil> : <span className="sub2" key="s">None — MOAUM_NOTICES_SMS_URL is not set</span>],
          ]} />
          <div className="sub2 mt-2">A provider is an endpoint that takes a POST of the recipient, subject and body with a bearer token, one for email and one for SMS. Until one is named the outbox holds everything, on the record and shown to the student in the portal, and drops nothing.</div>
        </PBody>
      </Panel>

      <Panel title="The outbox" right={`${d.recent.length} most recent${may && d.failed ? "" : ""}`}>
        {may && d.failed ? <PBody style={{ borderBottom: "1px solid var(--line-2)" }}><Btn kind="ghost" disabled={busy} onClick={() => void retry("/retry-failed", "Requeue all failed notices")}>Put all {d.failed} failed back in the queue</Btn></PBody> : null}
        {d.recent.length ? (
          <DTable cols={["When|mid", "To", "Notice", "Channel|mid", "Attempts|mid", "State|num"]} rows={d.recent.map((n) => [
            <span className="tnum sub2" key="w">{when(n.created_at)}</span>,
            <span className="sub2" key="t">{n.recipient}</span>,
            <span key="s">{n.subject}</span>,
            <span className="sub2" key="c">{n.channel}</span>,
            <span className="tnum" key="a">{n.attempts}</span>,
            n.state === "SENT" ? <Pil kind="ok" key="x">Sent</Pil> : n.state === "FAILED" ? (
              <span key="x" className="row row--inline row--tight">
                <Pil kind="bad">Failed</Pil>{n.last_error ? <span className="sub2">{n.last_error}</span> : null}
                {may ? <Btn kind="ghost" disabled={busy} onClick={() => void retry(`/${n.id}/retry`, `Requeue notice to ${n.recipient}`)}>Requeue</Btn> : null}
              </span>
            ) : <Pil kind="info" key="x">Queued</Pil>,
          ])} texts={d.recent.map((n) => `${n.recipient} ${n.subject} ${n.state}`)} />
        ) : <PBody><div className="sub2">The outbox is empty. A notice appears here when the portal has something with a consequence to send.</div></PBody>}
      </Panel>

      <Note kind="info" title="Templates, quiet hours and per-channel routing are not invented here">
        This screen shows what the outbox actually holds and whether a provider is wired. It does not display message templates, delivery costs or quiet-hour rules the University has not configured, because a screen that shows a figure nobody set is worse than one that shows none.
      </Note>
    </>
  );
}
